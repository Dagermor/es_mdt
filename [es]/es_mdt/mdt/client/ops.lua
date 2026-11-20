local _ENV = ESAPP('mdt'); -- es_mdt 1.3.0 client: /911 and /311, the panic button, call / panic / announcement alerts, the mugshot camera,
-- and the OpenVehicle export. Loaded after client/main.lua (MDTC comes from there).
local DSP = Config.Dispatch or {}
local PAN = Config.Panic or {}
local myPanicAt = 0   -- my own panic: no card for it on my screen
local myBackupAt = -60000   -- 2.0.6: my own backup request: no card for it either
local Board = { open = false, poke = function() end, close = function() end }   -- 2.0.7: the call board (below)

local function wc() return exports.whip_core end
local function notify(text, kind, ms) wc():Notify(text, kind or 'inform', ms) end

--- "Strawberry Ave / Davis Ave, Davis"
local function streetHere()
    local p = GetEntityCoords(PlayerPedId())
    local s1, s2 = GetStreetNameAtCoord(p.x, p.y, p.z)
    local a = s1 and s1 ~= 0 and GetStreetNameFromHashKey(s1) or ''
    local b = s2 and s2 ~= 0 and GetStreetNameFromHashKey(s2) or ''
    local zone = GetLabelText(GetNameOfZone(p.x, p.y, p.z))
    local out = a
    if b ~= '' then out = out .. ' / ' .. b end
    if zone and zone ~= '' and zone ~= 'NULL' then out = (out ~= '' and (out .. ', ') or '') .. zone end
    return out:sub(1, 120)
end

-- ---------------------------------------------------------------- 911 / 311 (anyone)

local function cmdOf(kind)
    if kind == '311' then return DSP.nonEmergency or '311' elseif kind == 'medical' then return DSP.medical end
    return DSP.emergency or '911'
end
local function dial(kind, args)
    local msg = table.concat(args or {}, ' ')
    if #msg < 3 then return notify(('Type what is happening: /%s <message>'):format(cmdOf(kind)), 'error') end
    CreateThread(function()
        local r, why = wc():Callback('es_mdt:dial', { kind = kind, message = msg, street = streetHere() })
        if type(r) ~= 'table' then return notify(why or 'Dispatch did not answer', 'error') end
        if r.merged then return notify(('Dispatch already has this (#%d) · your report was added'):format(r.id), 'success', 7000) end
        notify(r.units > 0 and ('Dispatch has your call (#%d). Units are being told.'):format(r.id)
            or ('Dispatch has your call (#%d). No units are on duty right now.'):format(r.id), 'success', 7000)
    end)
end
RegisterCommand(DSP.emergency or '911', function(_, args) dial('911', args) end, false)
RegisterCommand(DSP.nonEmergency or '311', function(_, args) dial('311', args) end, false)
-- 2.0.6: an optional medical-only line (Config.Dispatch.medical = 'ems' gives /ems; '' = off)
local MED = type(DSP.medical) == 'string' and DSP.medical ~= '' and DSP.medical or nil
if MED then RegisterCommand(MED, function(_, args) dial('medical', args) end, false) end

-- ---------------------------------------------------------------- panic

-- 2.0.6: NO health, ragdoll, dead or downed check here (nor on the server: its callback is whileDead). A key mapping runs
-- through FiveM's command system, so the death screen's DisableControlAction lock does not stop it.
local panicSent = 0
local function pressPanic()
    if GetGameTimer() - panicSent < 1500 then return end   -- two bindings on one key: one press
    panicSent = GetGameTimer()
    myPanicAt = GetGameTimer()
    CreateThread(function()
        local r, why = wc():Callback('es_mdt:panic', { street = streetHere() })
        if type(r) ~= 'table' then return notify(why or 'Panic did not go through', 'error') end
        notify('Panic sent · units alerted', 'success', 6000)   -- 2.0.7: short (whip's toast cuts long text), success style
    end)
end
RegisterCommand(PAN.command or 'panic', pressPanic, false)
-- the old mapping stays for players who bound a key to it before 2.0.6
RegisterKeyMapping(PAN.command or 'panic', 'Police: panic button (old binding)', 'keyboard', '')
-- 2.0.6: a new mapping id, so the default key (Config.Panic.key, END) reaches players who already had the old unbound one
local PANIC_KEY_CMD = PAN.keyCommand or 'mdt_panic_key'
RegisterCommand(PANIC_KEY_CMD, pressPanic, false)
RegisterKeyMapping(PANIC_KEY_CMD, 'Police: PANIC · officer down', 'keyboard', PAN.key or 'END')
RegisterNUICallback('panicBtn', function(_, cb) pressPanic() cb({ ok = true }) end)

-- ---------------------------------------------------------------- alerts

local lastPanic
local function sound(name, set, times, gap)
    if (times or 1) <= 1 then PlaySoundFrontend(-1, name, set, true) return end
    CreateThread(function()
        for _ = 1, times or 1 do PlaySoundFrontend(-1, name, set, true) Wait(gap or 250) end
    end)
end
--- 2.0.7: an alert sound by tier ('routine', 'priority', 'critical', 'soft', 'ok', 'announce', 'urgent'), at the player's own
--- volume / mute (client/ui.lua EsAlertSound; the Aa popover). -> played
local function tone(tier)
    local es = rawget(_G, 'EsAlertSound')   -- client/ui.lua's (a real global, not a stub)
    if type(es) == 'function' then return es(tier) end
    -- client/ui.lua not loaded (should not happen): GTA's own sounds, the same as its 'game' engine
    if tier == 'critical' or tier == 'urgent' then sound('Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', 4, 220)
    elseif tier == 'soft' or tier == 'announce' then sound('Text_Arrive_Tone', 'Phone_SoundSet_Default', 1)
    elseif tier == 'ok' then sound('Menu_Accept', 'Phone_SoundSet_Default', 1)
    else sound('Event_Message_Purple', 'GTAO_FM_Events_Soundset', tier == 'priority' and 2 or 1, 400) end
    return true
end
local function tierOf(c) return (c.critical and 'critical') or (c.priority == 1 and 'priority') or 'routine' end

-- 2.0.7: a CRITICAL call's alarm repeats (Config.Dispatch.critical) until this unit acknowledges it (Respond / Hide on its
-- card, Ack on the board, attaching anywhere) or, with stopOnUnit, until any unit responds; and always when it closes.
local CRIT = DSP.critical or {}
local Alarm = {}   -- [callId] = { left = repeats still to play }
local function ack(id) if id then Alarm[tonumber(id)] = nil end end
MDTC.ackCall = ack
local function startAlarm(id)
    if CRIT.enabled == false then return end
    Alarm[id] = { left = math.max(0, math.floor(tonumber(CRIT.maxRepeats) or 8)) }
end
CreateThread(function()
    while true do
        Wait(math.max(2, tonumber(CRIT.repeatSeconds) or 4) * 1000)   -- 2.0.8: read each round (live settings)
        for id, a in pairs(Alarm) do
            if a.left <= 0 then Alarm[id] = nil
            else a.left = a.left - 1 tone('critical') end
        end
    end
end)

-- ---------------------------------------------------------------- 1.3.2: call popup
-- A compact card (top right) for every new call while the MDT is closed: attend with one key (attaches your unit,
-- sets GPS), hide it, bring it back with /calls, leave with /detach. Closing a call clears its GPS.
local POP = DSP.popup or {}
local function popOn() return POP.enabled ~= false end   -- 2.0.8: read live
local Recent = {}   -- newest first: { id, kind, priority, title, message, street, x, y, z, callerName, at, units, closed, outcome }
local Queue = {}    -- ids still to show, newest first
local shown, hideAt, holdUntil, seq = nil, 0, 0, 0
local flash = nil   -- { id, state = 'attached' | 'closed' | 'error', text }
local myCall = nil  -- the call my GPS points at

local CMD = { attend = 'mdtcall_respond',   -- 1.3.3: new id so the new default (E) reaches players who had Y saved
     dismiss = 'mdtcall_dismiss', recall = POP.recallCommand or 'calls', detach = POP.detachCommand or 'detach' }

local function find(id) for i, c in ipairs(Recent) do if c.id == id then return c, i end end end
local function unqueue(id) for i = #Queue, 1, -1 do if Queue[i] == id then table.remove(Queue, i) end end end

--- what key a player bound to a command (falls back to the default)
local function keyOf(cmd, def)
    local ok, s = pcall(GetControlInstructionalButton, 0, GetHashKey(cmd) | 0x80000000, true)
    if ok and type(s) == 'string' and s:sub(1, 2) == 't_' then return s:sub(3) end
    if def and def ~= '' then return def end
    return '/' .. cmd
end

local function secsFor(c) return ((c.kind == 'panic' and (POP.panicSeconds or 30)) or (POP.seconds or 15)) * 1000 end

-- 1.3.4: distance and age are sent rounded, and only when what the card shows would change
local function distOf(c)
    if not c.x then return nil end
    local me = GetEntityCoords(PlayerPedId())
    local d = #(vector2(me.x, me.y) - vector2(c.x + 0.0, c.y + 0.0))
    if d < 1000 then return math.floor(d / 10 + 0.5) * 10 end
    return math.floor(d / 100 + 0.5) * 100
end
local function ageOf(c) return math.floor((GetGameTimer() - c.at) / 1000) end
local function ageBucket(a) if a < 30 then return 0 elseif a < 90 then return 1 end return math.floor(a / 60 + 0.5) end
local liveSent = { seq = -1, dist = false, age = false }

--- the whole card: only when a new call shows (restart) or what it says changes (attached, closed, units, queue)
local function render(restart)
    local c = shown and find(shown)
    if not c then SendNUIMessage({ action = 'cpop', show = false }) return end
    local dist = distOf(c)
    liveSent = { seq = seq, dist = dist, age = ageBucket(ageOf(c)) }
    local f = flash and flash.id == c.id and flash or nil
    SendNUIMessage({ action = 'cpop', show = true, restart = restart, seq = seq,
        call = { id = c.id, kind = c.kind, priority = c.priority, title = c.title, message = c.message, street = c.street,
            callerName = c.callerName, units = c.units, closed = c.closed, outcome = c.outcome, mine = myCall == c.id,
            escalated = c.escalated, parentId = c.parentId, backup = c.backup,
            critical = c.critical, icon = c.icon, reports = c.reports, radius = c.radius, details = c.details, alarm = Alarm[c.id] ~= nil },
        dist = dist, age = ageOf(c), left = math.max(0, hideAt - GetGameTimer()),
        more = math.max(0, #Queue - 1), state = f and f.state or nil, note = f and f.text or nil,
        keys = { attend = keyOf(CMD.attend, POP.attendKey), dismiss = keyOf(CMD.dismiss, POP.dismissKey), recall = '/' .. CMD.recall, detach = '/' .. CMD.detach,
            pad = type(ESPAD) == 'table' and ESPAD.button('es_mdt_call') or nil } })   -- 2.0.13: the controller's button (LB + D-Left unless moved)
end

local function hide()
    shown, flash = nil, nil
    SendNUIMessage({ action = 'cpop', show = false })
end

--- show one call (the newest queued one when id is nil)
local function show(id, ms)
    if not popOn() or MDTC.isOpen() then return end
    id = id or Queue[1]
    local c = id and find(id)
    if not c then return hide() end
    shown, flash = id, nil
    seq = seq + 1
    hideAt = GetGameTimer() + (ms or secsFor(c))
    render(true)
end

local function next_()
    if shown then unqueue(shown) end
    if Queue[1] then show(Queue[1]) else hide() end
end

local function setFlash(id, state, text, ms)
    flash = { id = id, state = state, text = text }
    holdUntil = GetGameTimer() + (ms or 2500)
    if state == 'error' then hideAt = math.max(hideAt, holdUntil) else hideAt = holdUntil end
    render(false)
end

-- 2.0.4: every waypoint this game set to a call (card, MDT "Set waypoint", attach, partner, /panicgps): [callId] = { x, y }.
-- When the call closes (any path) or I go off duty it is cleared, but only while the waypoint still points there
-- (a waypoint I put somewhere else since then stays).
local Routed = {}
local function noteRoute(id, x, y)
    id, x, y = tonumber(id), tonumber(x), tonumber(y)
    if id and x and y then Routed[id] = { x = x, y = y } end
end
local function waypointNear(x, y)
    if not IsWaypointActive() then return false end
    local w = GetBlipInfoIdCoord(GetFirstBlipInfoId(8))
    return #(vector2(w.x, w.y) - vector2(x + 0.0, y + 0.0)) <= 60.0
end
--- forget the waypoint I set to this call; true when it was still on my map and is gone now
local function dropRoute(id)
    local r = id and Routed[id]
    if not r then return false end
    Routed[id] = nil
    if waypointNear(r.x, r.y) then SetWaypointOff() return true end
    return false
end

local function routeTo(c)
    if c and c.x and c.y then SetNewWaypoint(c.x + 0.0, c.y + 0.0) noteRoute(c.id, c.x, c.y) return true end
    return false
end
-- 1.3.5: where my call is, for the arrival check: { id, x, y, r (radius, nil = off), arrived }
local Target = nil
local function onCall(id, x, y, r)
    myCall = id
    Target = { id = id, x = tonumber(x), y = tonumber(y), r = tonumber(r), arrived = false }
    noteRoute(id, x, y)
end
--- the waypoint is cleared only when it still points at the call (a waypoint the player set elsewhere stays)
local function dropCallWaypoint(t)
    if not IsWaypointActive() then return end
    -- 2.0.9: a call that follows its officer moves (t.x, t.y); the waypoint is where the route was last set (Routed)
    local w0 = t and (Routed[t.id] or (t.x and t))
    if w0 and w0.x then
        local w = GetBlipInfoIdCoord(GetFirstBlipInfoId(8))
        if #(vector2(w.x, w.y) - vector2(w0.x, w0.y)) > 60.0 then return end
    end
    SetWaypointOff()
end
local function clearRoute(id)
    if myCall and (id == nil or myCall == id) then
        myCall = nil
        local t = Target
        Target = nil
        if not (t and t.arrived) then dropCallWaypoint(t) end
        Routed[id or t and t.id or -1] = nil
        return true
    end
    return false
end
--- a call is over for me: my unit's route to it and any waypoint I set to it. true when something was on my map.
local function forgetCall(id)
    local a = clearRoute(id)
    local b = dropRoute(id)
    return a or b
end

-- 1.3.5: arrival: once a second, my distance to my call; inside the radius the server checks it and sets On scene
local arriveWaitUntil = 0
CreateThread(function()
    while true do
        Wait(1000)
        local t = Target
        if t and t.r and t.x and not t.arrived and GetGameTimer() >= arriveWaitUntil then
            local p = GetEntityCoords(PlayerPedId())
            if #(vector2(p.x, p.y) - vector2(t.x, t.y)) <= t.r then
                t.arrived = true
                local r, why = wc():Callback('es_mdt:callArrive', { id = t.id })
                if type(r) ~= 'table' then
                    if Target == t then t.arrived = false end
                    arriveWaitUntil = GetGameTimer() + 5000   -- the server said not yet: ask again in a bit
                    if why == 'That call is closed' and Target == t then clearRoute(t.id) end
                elseif not r.already then
                    dropCallWaypoint(t)
                    PlaySoundFrontend(-1, 'Menu_Accept', 'Phone_SoundSet_Default', true)
                    notify(('On scene · call #%d · GPS cleared'):format(t.id), 'success', 5000)
                end
            end
        end
    end
end)

--- distance / time-ago text only (the page changes those two in place), at most once a second, only on a change
local lastLive = 0
local function live()
    local now = GetGameTimer()
    if now - lastLive < 1000 then return end
    lastLive = now
    local c = shown and find(shown)
    if not c then return end
    local d, a = distOf(c), ageBucket(ageOf(c))
    if liveSent.seq == seq and liveSent.dist == d and liveSent.age == a then return end
    liveSent = { seq = seq, dist = d, age = a }
    SendNUIMessage({ action = 'cpopLive', seq = seq, dist = d, age = ageOf(c) })
end

-- the card loop: the card hides on time or when the MDT opens; the text ticks through live()
CreateThread(function()
    while true do
        if shown then
            Wait(250)
            if not shown then goto continue end
            if MDTC.isOpen() then hide()
            elseif GetGameTimer() >= hideAt then
                if flash and flash.state then next_() else unqueue(shown) Queue = {} hide() end   -- timed out: the rest wait for /calls
            else live() end
        else
            Wait(750)
        end
        ::continue::
    end
end)

local function push(c)
    c.at = GetGameTimer()
    c.units = c.units or {}
    table.insert(Recent, 1, c)
    while #Recent > (POP.keep or 6) do table.remove(Recent) end
    table.insert(Queue, 1, c.id)
    while #Queue > (POP.keep or 6) do table.remove(Queue) end
    show(c.id)
end

local attending = false
local function attend()
    -- only while a card is up and the game has the keyboard; nothing is blocked, so other E prompts still work.
    -- The server checks duty (an off-duty officer gets "Go on duty" on the card).
    if not shown or attending or MDTC.isOpen() or IsNuiFocused() or IsPauseMenuActive() then return end
    local c = find(shown)
    if not c then return end
    ack(c.id)   -- 2.0.7: pressing Respond acknowledges a critical alarm
    if c.closed then return setFlash(c.id, 'error', 'This call is closed') end
    if myCall == c.id then routeTo(c) return setFlash(c.id, 'attached', 'GPS set again') end
    attending = true
    CreateThread(function()
        local r, why = wc():Callback('es_mdt:callAttach', { id = c.id, route = false, from = 'popup' })
        attending = false
        if type(r) ~= 'table' then return setFlash(c.id, 'error', why or 'Could not attach') end
        if r.x then c.x, c.y, c.z = r.x, r.y, r.z end
        onCall(c.id, c.x, c.y, r.arrive)
        local routed = routeTo(c)
        if POP.sound ~= false then tone('ok') end
        setFlash(c.id, 'attached', (r.units or 1) > 1 and (routed and 'Attached with your partner · GPS set' or 'Attached with your partner')
            or (routed and 'Attached · GPS set' or 'Attached (no location on this call)'), 2500)
    end)
end

local function detach()
    if not myCall then return notify('You are not on a call', 'error') end
    local id = myCall
    CreateThread(function()
        local r, why = wc():Callback('es_mdt:callDetach', { id = id })
        if not r then return notify(why or 'Could not detach', 'error') end
        clearRoute(id)
        notify(('Detached from call #%d · GPS cleared'):format(id), 'inform')
        if shown == id then setFlash(id, 'closed', 'Detached', 1800) end
    end)
end

RegisterCommand(CMD.attend, attend, false)
RegisterKeyMapping(CMD.attend, 'Police: respond to the call on screen (attach + GPS)', 'keyboard', POP.attendKey or 'E')
RegisterCommand(CMD.dismiss, function() if shown then ack(shown) next_() end end, false)
RegisterKeyMapping(CMD.dismiss, 'Police: hide the call card', 'keyboard', POP.dismissKey or 'DELETE')
RegisterCommand(CMD.recall, function()
    if MDTC.isOpen() then return end
    -- open calls first, the newest on top
    Queue = {}
    for _, c in ipairs(Recent) do if not c.closed then Queue[#Queue + 1] = c.id end end
    if not Queue[1] then return notify('No recent open calls', 'inform') end
    show(Queue[1])
end, false)
RegisterKeyMapping(CMD.recall, 'Police: show the latest calls again', 'keyboard', POP.recallKey or '')
RegisterCommand(CMD.detach, detach, false)
RegisterKeyMapping(CMD.detach, 'Police: leave the call you are on', 'keyboard', POP.detachKey or '')

-- the MDT's own attach / detach (Dispatch tab) keeps the GPS state the same
MDTC.onCallAttach = function(id, r)
    id = tonumber(id)
    if not id then return end
    ack(id)
    local c = find(id)
    if c and type(r) == 'table' and r.x then c.x, c.y, c.z = r.x, r.y, r.z end
    r = type(r) == 'table' and r or {}
    onCall(id, r.x or (c and c.x), r.y or (c and c.y), r.arrive)
end
MDTC.onCallDetach = function(id) clearRoute(tonumber(id)) end
-- 2.0.4: the MDT's "Set waypoint" (the server set it; this remembers it so a closed call takes it off the map)
MDTC.onCallRouted = function(id, r) if type(r) == 'table' then noteRoute(r.id or id, r.x, r.y) end end

RegisterNetEvent('es_mdt:client:call', function(c)
    if type(c) ~= 'table' then return end
    local mine = (c.kind == 'panic' and GetGameTimer() - myPanicAt < 8000) or (c.kind == 'backup' and GetGameTimer() - myBackupAt < 8000)
    -- 2.0.7: three tiers (routine, P1, critical); a critical one repeats until acknowledged (never my own panic / backup)
    if not mine and POP.sound ~= false then
        tone(tierOf(c))
        if c.critical then startAlarm(tonumber(c.id)) end
    end
    if not MDTC.isOpen() then
        if popOn() then
            if not mine then push(c) end
        elseif c.kind ~= 'panic' then
            notify(('%s #%d · %s%s'):format(c.kind == '311' and '311' or c.kind == '911' and '911' or 'Call', c.id,
                c.message ~= '' and c.message or c.title, c.street ~= '' and (' · ' .. c.street) or ''), c.priority == 1 and 'error' or 'inform', 9000)
        end
    elseif popOn() and not mine then
        -- keep it for /calls after the MDT closes, but do not pop it now
        c.at = GetGameTimer() c.units = {}
        table.insert(Recent, 1, c)
        while #Recent > (POP.keep or 6) do table.remove(Recent) end
    end
    SendNUIMessage({ action = 'call', call = c })
end)

RegisterNetEvent('es_mdt:client:callUnits', function(d)
    if type(d) ~= 'table' then return end
    local c = find(tonumber(d.id))
    if not c then return end
    c.units = type(d.units) == 'table' and d.units or {}
    if CRIT.stopOnUnit ~= false and #c.units > 0 then ack(c.id) end
    if shown == c.id then render(false) end
    if Board.open then Board.poke() end
end)

-- 2.0.7: another report folded into a call: the count, its priority, the smaller search circle (the card updates quietly)
RegisterNetEvent('es_mdt:client:callMerged', function(d)
    if type(d) ~= 'table' or not tonumber(d.id) then return end
    local c = find(tonumber(d.id))
    if c then
        c.reports, c.priority = tonumber(d.reports) or c.reports, tonumber(d.priority) or c.priority
        if d.x then c.x, c.y, c.radius = d.x, d.y, tonumber(d.radius) end
        -- 2.2.2: UpdateCall (es_jobs: a wounded person is now down) changes the title and text too
        if type(d.title) == 'string' and d.title ~= '' then c.title = d.title end
        if type(d.message) == 'string' then c.message = d.message end
        if d.critical ~= nil then c.critical = d.critical end
        if shown == c.id then render(false) end
    end
    if d.upgraded and c then
        notify(('Call #%d upgraded: %s (P%d)'):format(c.id, c.title or 'call', c.priority or 1), 'error')
        tone((c.priority or 1) == 1 and 'urgent' or 'priority')
    end
    SendNUIMessage({ action = 'callMerged', call = d })
    if Board.open then Board.poke() end
end)

RegisterNetEvent('es_mdt:client:callClosed', function(d)
    if type(d) ~= 'table' then return end
    local id = tonumber(d.id)
    local c = find(id)
    if c then c.closed, c.outcome = true, d.outcome end
    ack(id)
    if forgetCall(id) then notify(('Call #%d closed%s · GPS cleared'):format(id, d.outcome and (' (' .. d.outcome .. ')') or ''), 'inform') end
    if shown == id then setFlash(id, 'closed', 'Closed' .. (d.outcome and (' · ' .. d.outcome) or ''), 2200)
    else unqueue(id) end
end)

-- 2.0.4: a call is gone (auto-closed, or closed on any path; this comes after callClosed for a closed one).
-- SILENT: no notice, sound or card. The waypoint I set to it goes (if it still points there), its card leaves the queue.
RegisterNetEvent('es_mdt:client:callGone', function(d)
    local id = tonumber(type(d) == 'table' and d.id)
    if not id then return end
    forgetCall(id)
    ack(id)
    if Board.open then Board.poke() end
    local c = find(id)
    if c and not c.closed then
        c.closed = true
        unqueue(id)
        if shown == id then hide() end
    end
end)
-- 2.0.4: I went off duty (or my unit was taken off its calls): GPS routes to calls go, the call cards go
RegisterNetEvent('es_mdt:client:offDuty', function()
    local any = false
    if myCall and clearRoute(myCall) then any = true end
    for id in pairs(Routed) do if dropRoute(id) then any = true end end
    Alarm = {}
    if Board.open then Board.close() end
    Queue = {}
    if shown then hide() end
    if any then notify('Off duty · call GPS cleared', 'inform') end
end)

-- my partner attached / detached our unit
RegisterNetEvent('es_mdt:client:attached', function(d)
    if type(d) ~= 'table' or not d.id then return end
    onCall(tonumber(d.id), d.x, d.y, d.arrive)
    if d.x and d.y then SetNewWaypoint(d.x + 0.0, d.y + 0.0) end
    notify(('%s attached your unit to call #%d%s'):format(d.by or 'Your partner', myCall, d.x and ' · GPS set' or ''), 'success', 6000)
end)
-- my partner got there first: our unit is On scene
RegisterNetEvent('es_mdt:client:arrived', function(d)
    if type(d) ~= 'table' or not d.id then return end
    local t = Target
    if t and t.id == tonumber(d.id) and not t.arrived then
        t.arrived = true
        dropCallWaypoint(t)
        notify(('On scene · call #%d (%s arrived) · GPS cleared'):format(t.id, d.by or 'your partner'), 'success', 5000)
    end
end)
RegisterNetEvent('es_mdt:client:detached', function(d)
    if type(d) ~= 'table' or not d.id then return end
    if clearRoute(tonumber(d.id)) then notify(('%s detached your unit from call #%d · GPS cleared'):format(d.by or 'Your partner', d.id), 'inform') end
end)

-- 2.0.9: a backup / panic call follows its officer: its spot moved. The card, the board and my arrival check use the new
-- spot at once; my GPS route follows at most every `gps` seconds, once the officer is `gpsMove` m from where it points,
-- and only while the waypoint still points at the call (one I put somewhere else stays). Never after I arrived.
local MovedAt = {}
RegisterNetEvent('es_mdt:client:callMoved', function(d)
    if type(d) ~= 'table' then return end
    local id, x, y = tonumber(d.id), tonumber(d.x), tonumber(d.y)
    if not id or not x or not y then return end
    local c = find(id)
    if c then c.x, c.y = x, y if shown == id then render(false) end end
    if lastPanic and tonumber(lastPanic.callId) == id then lastPanic.x, lastPanic.y = x, y end
    local t = Target
    local mine = t and t.id == id
    if mine then t.x, t.y = x, y end
    local r = Routed[id]
    if r and not (mine and t.arrived) then
        local gpsMs = math.max(3, tonumber(d.gps) or 10) * 1000
        local far = #(vector2(r.x, r.y) - vector2(x, y)) >= math.max(10, tonumber(d.gpsMove) or 35)
        if far and GetGameTimer() - (MovedAt[id] or -gpsMs) >= gpsMs and waypointNear(r.x, r.y) then
            SetNewWaypoint(x + 0.0, y + 0.0)
            Routed[id] = { x = x, y = y }
            MovedAt[id] = GetGameTimer()
        end
    end
    if Board.open then Board.poke() end
    SendNUIMessage({ action = 'callMoved', call = { id = id, x = x, y = y } })
end)
-- 2.0.9: my backup / panic: a unit is coming (its marker is on my map until it gets here) / it got here
RegisterNetEvent('es_mdt:client:followUnit', function(d)
    if type(d) ~= 'table' then return end
    local what = d.kind == 'panic' and 'your panic' or 'your backup request'
    if d.state == 'arrived' then notify(('%s is with you'):format(d.cs or 'A unit'), 'success', 5000)
    else notify(('%s is responding to %s · marker on your map'):format(d.cs or 'A unit', what), 'success', 6000) end
end)

RegisterNetEvent('es_mdt:client:panic', function(p)
    if type(p) ~= 'table' then return end
    lastPanic = p
    -- 2.0.7: the sound is the panic CALL's (es_mdt:client:call, critical tier, repeating until acknowledged)
    -- the call card shows it (attend = route + attach); without cards, the old notice
    if not popOn() or MDTC.isOpen() then
        notify(('PANIC · %s %s (%s) · %s · /panicgps for a route'):format(p.callsign or '', p.name or '', p.deptShort or '', p.street or ''), 'error', 15000)
    end
    SendNUIMessage({ action = 'panic', panic = p })
end)
RegisterCommand('panicgps', function()
    if not lastPanic or not lastPanic.x then return notify('No panic to route to', 'error') end
    SetNewWaypoint(lastPanic.x + 0.0, lastPanic.y + 0.0)
    noteRoute(lastPanic.callId, lastPanic.x, lastPanic.y)
    notify('GPS set to the panic', 'success')
end, false)

RegisterNetEvent('es_mdt:client:announce', function(a)
    if type(a) ~= 'table' then return end
    -- 2.0.4: Important / Urgent say so; Urgent is red, stays longer and has its own tone
    local lvl = a.level
    tone(lvl == 'urgent' and 'urgent' or 'announce')
    if not MDTC.isOpen() then
        notify(('%sAnnouncement (%s) · %s, by %s'):format(lvl == 'urgent' and 'URGENT · ' or lvl == 'important' and 'Important · ' or '',
            a.deptShort or '', a.title or '', a.by or ''), lvl == 'urgent' and 'error' or 'inform', lvl == 'urgent' and 20000 or 9000)
    end
    SendNUIMessage({ action = 'announce', announce = a })
end)

-- ---------------------------------------------------------------- 2.0.6: request backup
-- /backup: a backup call at my position, linked to the call I am on (or on its own when I am on none)
local BKP = DSP.backup or {}
local function askBackup(id)
    myBackupAt = GetGameTimer()
    CreateThread(function()
        local r, why = wc():Callback('es_mdt:callBackup', { id = id, street = streetHere() })
        if type(r) ~= 'table' then return notify(why or 'Backup request did not go through', 'error') end
        if r.merged then   -- 2.0.15: onto the call I am on
            return notify(('Backup %s on call #%d (P%d)%s'):format(r.again and 'requested again' or 'requested', r.id, r.priority or 2,
                (r.units or 0) > 0 and ' · its units were alerted' or ' · no other units on duty'), 'success', 6000)
        end
        notify(('Backup requested (P%d, call #%d)%s'):format(r.priority or 2, r.id, (r.units or 0) > 0 and '' or ' · no other units on duty'), 'success', 6000)
    end)
end
MDTC.askBackup = askBackup
-- 2.0.8: always registered (the name and key are read at start); backup.enabled is read when it is used, so it changes live
do
    local BCMD = BKP.command or 'backup'
    RegisterCommand(BCMD, function()
        if BKP.enabled == false then return notify('Backup requests are turned off', 'error') end
        askBackup(myCall)
    end, false)
    RegisterKeyMapping(BCMD, 'Police: request backup', 'keyboard', BKP.key or '')
end

-- 2.0.15: an officer on a call asked for backup on it: the call again, with its "Backup requested" banner (card and sound,
-- like a new call; the asking officer never gets this)
RegisterNetEvent('es_mdt:client:callBackup', function(d)
    if type(d) ~= 'table' or not tonumber(d.id) then return end
    local id = tonumber(d.id)
    local c = find(id)
    if c then
        if c.closed then return end
        c.priority, c.backup = tonumber(d.priority) or c.priority, d.backup
        if d.x then c.x, c.y, c.z, c.radius = d.x, d.y, d.z, tonumber(d.radius) end
    else
        c = d
    end
    SendNUIMessage({ action = 'callBackup', call = { id = id, priority = c.priority, backup = d.backup } })
    if Board.open then Board.poke() end
    if POP.sound ~= false then
        tone(tierOf(c))
        if c.critical then startAlarm(id) end
    end
    if MDTC.isOpen() then return end
    if not popOn() then
        return notify(('Backup requested on #%d · %s%s'):format(id, d.backup and d.backup.by or 'an officer', c.street and c.street ~= '' and (' · ' .. c.street) or ''), 'error', 9000)
    end
    if not find(id) then push(c) return end
    unqueue(id)
    table.insert(Queue, 1, id)
    show(id)
end)

-- 2.0.6: an unanswered call went up a priority: a soft re-alert (one quiet tone and its card again, never over the MDT)
RegisterNetEvent('es_mdt:client:callEscalated', function(d)
    if type(d) ~= 'table' or not tonumber(d.id) then return end
    local id = tonumber(d.id)
    local c = find(id)
    if c then
        if c.closed then return end
        c.priority = d.priority
        c.escalated = d.from
    elseif popOn() then
        c = { id = id, kind = d.kind, priority = d.priority, title = d.title, street = d.street, x = d.x, y = d.y, z = d.z, message = '', escalated = d.from, radius = d.radius }
    end
    SendNUIMessage({ action = 'callEscalated', call = { id = id, priority = d.priority, from = d.from, title = d.title, street = d.street } })
    if MDTC.isOpen() then return end
    if POP.sound ~= false then tone('soft') end
    if not popOn() then
        return notify(('Call #%d now P%d · no unit yet%s'):format(id, d.priority or 2, d.street and d.street ~= '' and (' · ' .. d.street) or ''), 'inform', 7000)
    end
    if shown == id then render(false) return end
    if not find(id) then push(c) return end
    unqueue(id)
    table.insert(Queue, 1, id)
    if not shown then show(id) end
end)

-- ---------------------------------------------------------------- 2.0.6: shots fired / vehicle theft (Config.Dispatch.alerts)
-- The game only says "it happened, here"; the server decides (on-duty law exempt, chance, cooldowns, one call per area)
-- and reads the position itself.
local ALR = DSP.alerts or {}
-- 2.0.8: every detector runs from the start and reads Config each time, so /whip > Settings > MDT turns them on and off
-- live (whip_core refills these tables in place). Off, a detector only sleeps.
local function alertCfg(k) local t = ALR[k] return type(t) == 'table' and t or {} end
local function vehModel(v)
    local model = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(v)))
    if model == 'NULL' then model = GetDisplayNameFromVehicleModel(GetEntityModel(v)) end
    return model
end
do
    local skip
    local function skipList()
        local key = ALR.ignoreWeapons
        if skip and skip.src == key then return skip.set end
        local set = {}
        for _, w in ipairs(type(key) == 'table' and key or { 'WEAPON_STUNGUN', 'WEAPON_STUNGUN_MP', 'WEAPON_FIREEXTINGUISHER', 'WEAPON_PETROLCAN', 'WEAPON_HAZARDCAN',
            'WEAPON_FERTILIZERCAN', 'WEAPON_SNOWBALL', 'WEAPON_BALL', 'WEAPON_FLARE', 'WEAPON_FLAREGUN', 'WEAPON_RAYPISTOL' }) do set[GetHashKey(w)] = true end
        skip = { src = key, set = set }
        return set
    end
    -- 2.0.10: no per-frame check any more. Four times a second while a gun is in hand it compares the gun's ammo with the
    -- last look: less ammo while aiming / pulling the trigger is a shot (a reload never lowers the total). The game's
    -- "is shooting" flag still counts when it is caught (guns with endless ammo). On-duty law is skipped here too
    -- (asked once a minute and again on any clock on / off); the server still makes the final call.
    local law, lawAt, asking = false, -1e9, false
    for _, ev in ipairs({ 'whip_core:job:clockedOn', 'whip_core:job:clockedOff', 'whip_core:client:jobClockState' }) do
        AddEventHandler(ev, function() lawAt = -1e9 end)
        RegisterNetEvent(ev)
    end
    local function isLaw()
        if ALR.exemptLaw == false then return false end
        if not asking and GetGameTimer() - lawAt > 60000 then
            asking, lawAt = true, GetGameTimer()
            CreateThread(function()
                local ok, r = pcall(function() return wc():Callback('es_mdt:radarAllowed', {}) end)
                law = ok and r == true
                asking = false
            end)
        end
        return law
    end
    CreateThread(function()
        local last, seenW, seenClip, seenTotal = -1e9, nil, -1, -1
        while true do
            local SHOTS = alertCfg('shots')
            local ped = PlayerPedId()
            if SHOTS.enabled ~= false and IsPedArmed(ped, 4) then   -- 4 = guns
                Wait(250)
                local _, w = GetCurrentPedWeapon(ped, true)
                local _, clip = GetAmmoInClip(ped, w)
                local total = GetAmmoInPedWeapon(ped, w)
                clip, total = tonumber(clip) or 0, tonumber(total) or 0
                local fewer = w == seenW and (total < seenTotal or (clip < seenClip and total <= seenTotal))
                local trigger = IsPedShooting(ped) or IsControlPressed(0, 24) or IsDisabledControlPressed(0, 24) or IsPlayerFreeAiming(PlayerId())
                local shot = IsPedShooting(ped) or (fewer and trigger)
                seenW, seenClip, seenTotal = w, clip, total
                local gap = math.max(5, tonumber(SHOTS.cooldown) or 45) * 1000
                if shot and GetGameTimer() - last >= gap and not skipList()[w]
                    and not (SHOTS.ignoreSuppressed ~= false and IsPedCurrentWeaponSilenced(ped)) and not isLaw() then
                    last = GetGameTimer()
                    local veh = GetVehiclePedIsIn(ped, false)
                    TriggerServerEvent('es_mdt:server:autoAlert', { kind = 'shots', street = streetHere(), model = veh ~= 0 and vehModel(veh) or nil })
                end
            else
                seenW = nil
                Wait(SHOTS.enabled ~= false and 500 or 2000)
            end
        end
    end)
end
do
    local LOCKED = { [2] = true, [3] = true, [7] = true, [10] = true }
    CreateThread(function()
        local last, flagged = -1e9, nil
        while true do
            local THEFT = alertCfg('theft')
            if THEFT.enabled == false then
                flagged = nil
                Wait(2000)
            else
                Wait(400)
                local gap = math.max(5, tonumber(THEFT.cooldown) or 90) * 1000
                local ped = PlayerPedId()
                local trying = GetVehiclePedIsTryingToEnter(ped)
                if trying ~= 0 and DoesEntityExist(trying) and GetSeatPedIsTryingToEnter(ped) == -1 then
                    local drv = GetPedInVehicleSeat(trying, -1)
                    if IsPedJacking(ped) or LOCKED[GetVehicleDoorLockStatus(trying)] or IsVehicleNeedsToBeHotwired(trying)
                        or (drv ~= 0 and drv ~= ped) then flagged = trying end
                end
                local v = GetVehiclePedIsIn(ped, false)
                if flagged then
                    if v == flagged and GetPedInVehicleSeat(v, -1) == ped then
                        flagged = nil
                        if GetGameTimer() - last >= gap then
                            last = GetGameTimer()
                            TriggerServerEvent('es_mdt:server:autoAlert', { kind = 'theft', street = streetHere(),
                                plate = GetVehicleNumberPlateText(v), model = vehModel(v) })
                        end
                    elseif trying == 0 and v ~= flagged then
                        flagged = nil   -- gave up
                    end
                end
            end
        end
    end)
end

-- 2.0.7: fights (a melee hit with someone watching), a person down, speeding (off by default). The server decides
-- (on-duty units exempt, chance, cooldowns, per-kind rate, merging) and reads position, weapon, plate and speed itself.
local function witnesses(range, need)
    local me = PlayerPedId()
    local p = GetEntityCoords(me)
    local n = 0
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= me and not IsPedAPlayer(ped) and not IsPedDeadOrDying(ped, true) and #(GetEntityCoords(ped) - p) <= range then
            n = n + 1
            if n >= need then return true end
        end
    end
    return false
end
do
    local last = -1e9
    AddEventHandler('gameEventTriggered', function(name, args)
        if name ~= 'CEventNetworkEntityDamage' then return end
        local FIGHT = alertCfg('fight')
        if FIGHT.enabled == false then return end
        local gap = math.max(5, tonumber(FIGHT.cooldown) or 60) * 1000
        if GetGameTimer() - last < gap then return end
        local victim, attacker, weapon = args[1], args[2], args[7]
        local me = PlayerPedId()
        if attacker ~= me or victim == me or not victim or not DoesEntityExist(victim) or not IsEntityAPed(victim) then return end
        -- melee only (fists, bats, knives): damage type 2
        if not weapon or GetWeaponDamageType(weapon) ~= 2 then return end
        if not witnesses(tonumber(FIGHT.witnessRange) or 30.0, math.max(1, math.floor(tonumber(FIGHT.witnesses) or 1))) then return end
        last = GetGameTimer()
        TriggerServerEvent('es_mdt:server:autoAlert', { kind = 'fight', street = streetHere() })
    end)
end
-- down for `delay` seconds (a quick revive sends nothing); the server checks whip's own death state again
CreateThread(function()
    local since, sent = nil, false
    while true do
        Wait(2000)
        local DOWN = alertCfg('down')
        if DOWN.enabled == false then since, sent = nil, false
        else
            local dead = false
            local okd, v = pcall(function() return wc():IsPlayerDead() end)
            if okd then dead = v == true else dead = IsEntityDead(PlayerPedId()) end
            if dead then
                since = since or GetGameTimer()
                if not sent and GetGameTimer() - since >= math.max(5, tonumber(DOWN.delay) or 20) * 1000 then
                    sent = true
                    TriggerServerEvent('es_mdt:server:autoAlert', { kind = 'down', street = streetHere() })
                end
            else since, sent = nil, false end
        end
    end
end)
-- 2.0.8: speeding over the admin's limit (city / highway, mph or km/h: mdt/shared/speed.lua) for `seconds`. Off by default.
CreateThread(function()
    local over, last, peak = nil, -1e9, 0
    while true do
        local SPEED = alertCfg('speeding')
        if SPEED.enabled ~= true then
            over = nil
            Wait(3000)
        else
            local ped = PlayerPedId()
            local v = GetVehiclePedIsIn(ped, false)
            if v ~= 0 and GetPedInVehicleSeat(v, -1) == ped and GetVehicleClass(v) ~= 18 then
                local street = streetHere()
                local _, _, limitMs = EsSpeedLimit(street, SPEED)
                local ms = GetEntitySpeed(v)
                if ms > limitMs then
                    if not over then over, peak = GetGameTimer(), 0 end
                    if ms > peak then peak = ms end
                    local gap = math.max(10, tonumber(SPEED.cooldown) or 120) * 1000
                    if GetGameTimer() - over >= math.max(1, tonumber(SPEED.seconds) or 4) * 1000 and GetGameTimer() - last >= gap then
                        last = GetGameTimer()
                        TriggerServerEvent('es_mdt:server:autoAlert', { kind = 'speeding', street = street, model = vehModel(v), speed = peak })
                    end
                    Wait(500)
                else
                    over = nil
                    Wait(1000)
                end
            else
                over = nil
                Wait(v ~= 0 and 1000 or 2500)
            end
        end
    end
end)

-- ---------------------------------------------------------------- 2.0.7: the quick call board
-- A compact overlay of the active calls (hotkey, Config.Dispatch.board.key, O by default; players can rebind it): respond
-- (attach + GPS), waypoint, ack, detach. It has the mouse while open; Esc or the key again closes it. Live: it re-reads the
-- list when calls change (throttled).
local BRD = DSP.board or {}
local BOARD_SCREEN = 'mdtboard'
local boardKeyCmd = BRD.command or 'callboard'
local function boardKey()
    local ok, s = pcall(GetControlInstructionalButton, 0, GetHashKey(boardKeyCmd) | 0x80000000, true)
    if ok and type(s) == 'string' and s:sub(1, 2) == 't_' then return s:sub(3) end
    return BRD.key or ''
end
local boardSeq, boardAt, boardPending = 0, 0, false
local function boardLoad()
    if not Board.open then return end
    boardAt = GetGameTimer()
    boardSeq = boardSeq + 1
    local my = boardSeq
    CreateThread(function()
        local r, why = wc():Callback('es_mdt:board', {})
        if not Board.open or my ~= boardSeq then return end
        if type(r) ~= 'table' then
            SendNUIMessage({ action = 'board', show = true, error = why or 'The board did not load' })
            return
        end
        for _, c in ipairs(r.calls or {}) do c.alarm = Alarm[c.id] ~= nil end
        SendNUIMessage({ action = 'board', show = true, calls = r.calls, now = r.now, myCall = myCall, key = boardKey() })
    end)
end
Board.poke = function()
    if not Board.open or boardPending then return end
    local wait = math.max(0, 1200 - (GetGameTimer() - boardAt))   -- at most one reload a second and a bit
    boardPending = true
    SetTimeout(wait, function() boardPending = false boardLoad() end)
end
Board.close = function()
    if not Board.open then return end
    Board.open = false
    SetNuiFocus(false, false)
    wc():SetScreenOpen(false, BOARD_SCREEN)
    SendNUIMessage({ action = 'board', show = false })
end
local function boardOpen()
    if Board.open then return Board.close() end
    if BRD.enabled == false or MDTC.isOpen() then return end
    if wc():IsAnyScreenOpen() then return notify('Close what is open first', 'error') end
    Board.open = true
    if shown then hide() end
    wc():SetScreenOpen(true, BOARD_SCREEN)
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'board', show = true, loading = true, key = boardKey(), pad = type(ESPAD) == 'table' and ESPAD.button('es_mdt_board') or nil })
    boardLoad()
end
-- 2.0.8: always registered; board.enabled is read on each press (boardOpen), so it changes live
RegisterCommand(boardKeyCmd, boardOpen, false)
RegisterKeyMapping(boardKeyCmd, 'Police: call board (active calls)', 'keyboard', BRD.key or 'O')
AddEventHandler('es_mdt:client:refresh', function(what) if Board.open and (what == 'calls' or what == 'units') then Board.poke() end end)
RegisterNUICallback('boardClose', function(_, cb) Board.close() cb({ ok = true }) end)
--- { id, act = 'respond' | 'route' | 'detach' | 'ack' }
RegisterNUICallback('boardAct', function(d, cb)
    d = type(d) == 'table' and d or {}
    local id = tonumber(d.id)
    if not id then return cb({ ok = false, why = 'No call' }) end
    ack(id)
    if d.act == 'ack' then cb({ ok = true }) Board.poke() return end
    CreateThread(function()
        if d.act == 'respond' then
            local r, why = wc():Callback('es_mdt:callAttach', { id = id, route = false, from = 'board' })
            if type(r) ~= 'table' then return cb({ ok = false, why = why or 'Could not attach' }) end
            local c = find(id)
            if c then c.x, c.y, c.z = r.x or c.x, r.y or c.y, r.z or c.z end
            onCall(id, r.x, r.y, r.arrive)
            if r.x and r.y then SetNewWaypoint(r.x + 0.0, r.y + 0.0) end
            tone('ok')
            cb({ ok = true, units = r.units, gps = r.x ~= nil })
        elseif d.act == 'route' then
            local r, why = wc():Callback('es_mdt:callRoute', { id = id })
            if type(r) ~= 'table' then return cb({ ok = false, why = why or 'No location' }) end
            noteRoute(id, r.x, r.y)
            cb({ ok = true })
        elseif d.act == 'detach' then
            local r, why = wc():Callback('es_mdt:callDetach', { id = id })
            if not r then return cb({ ok = false, why = why or 'Could not detach' }) end
            clearRoute(id)
            cb({ ok = true })
        else cb({ ok = false, why = 'Unknown action' }) end
        Board.poke()
    end)
end)
AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() and Board.open then Board.close() end end)

-- 2.0.6: chat suggestions (whip_chat / stock chat)
if DSP.chatSuggestions ~= false then
    CreateThread(function()
        Wait(2000)
        local msg = { { name = 'message', help = 'What is happening (your street and location are added)' } }
        TriggerEvent('chat:addSuggestion', '/' .. (DSP.emergency or '911'), 'Emergency call: police and EMS get your location', msg)
        TriggerEvent('chat:addSuggestion', '/' .. (DSP.nonEmergency or '311'), 'Non-emergency call to the police', msg)
        if MED then TriggerEvent('chat:addSuggestion', '/' .. MED, 'Medical emergency: EMS get your location', msg) end
        TriggerEvent('chat:addSuggestion', '/' .. (PAN.command or 'panic'), 'Officers on duty: PANIC · officer down at your location')
        if BKP.enabled ~= false then TriggerEvent('chat:addSuggestion', '/' .. (BKP.command or 'backup'), 'Officers on duty: request backup at your location') end
        if (DSP.board or {}).enabled ~= false then TriggerEvent('chat:addSuggestion', '/' .. ((DSP.board or {}).command or 'callboard'), 'Units on duty: the call board (active calls)') end
    end)
end

-- ---------------------------------------------------------------- mugshot camera
-- A scripted camera in front of the suspect's face, then WHIP RequestScreenshot (game only, no MDT) on the server.
local shooting = false
RegisterNUICallback('mugshotCam', function(d, cb)
    if shooting then return cb({ ok = false, why = 'Already taking one' }) end
    local charId = tonumber(type(d) == 'table' and d.charId)
    if not charId then return cb({ ok = false, why = 'Pick a person' }) end
    shooting = true
    CreateThread(function()
        local prep, why = wc():Callback('es_mdt:mugshotPrep', { charId = charId })
        if type(prep) ~= 'table' then shooting = false return cb({ ok = false, why = why or 'Not possible right now' }) end
        local me = GetPlayerServerId(PlayerId())
        local ped = prep.source == me and PlayerPedId() or GetPlayerPed(GetPlayerFromServerId(prep.source))
        if not ped or ped == 0 or not DoesEntityExist(ped) then shooting = false return cb({ ok = false, why = 'They are too far away to see' }) end
        local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
        local f = GetEntityForwardVector(ped)
        local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', head.x + f.x * 0.95, head.y + f.y * 0.95, head.z + 0.05, 0.0, 0.0, 0.0, 38.0, false, 0)
        PointCamAtCoord(cam, head.x, head.y, head.z + 0.02)
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 0, true, true)
        Wait(450)
        local res, err = wc():Callback('es_mdt:mugshotTake', { charId = charId, reportId = tonumber(d.reportId) })
        RenderScriptCams(false, false, 0, true, true)
        SetCamActive(cam, false)
        DestroyCam(cam, false)
        shooting = false
        if type(res) ~= 'table' then return cb({ ok = false, why = err or 'The camera did not work' }) end
        cb({ ok = true, data = res })
    end)
end)

-- ---------------------------------------------------------------- other scripts

--- exports.es_mdt:OpenVehicle('ABC123'): the MDT opens on that plate
exports('OpenVehicle', function(plate)
    if type(plate) ~= 'string' or plate == '' then return false end
    MDTC.goTo('vehicles', plate)
    return true
end)

-- 2.0.13: the commands client/pad.lua puts on WHIP's controller buttons (each keeps its own checks), and whether a call card is up
MDTC.padCmds = { attend = CMD.attend, dismiss = CMD.dismiss, backup = BKP.command or 'backup', board = boardKeyCmd, panic = PANIC_KEY_CMD }
MDTC.callShown = function() return shown ~= nil end
MDTC.opsLoaded = true
