local _ENV = ESAPP('mdt'); -- es_mdt 1.3.0 client: /911 and /311, the panic button, call / panic / announcement alerts, the mugshot camera,
-- and the OpenVehicle export. Loaded after client/main.lua (MDTC comes from there).
local DSP = Config.Dispatch or {}
local PAN = Config.Panic or {}
local myPanicAt = 0   -- my own panic: no card for it on my screen
local myBackupAt = -60000   -- 2.0.6: my own backup request: no card for it either

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
        notify('OFFICER DOWN sent. Units on duty have your location.', 'error', 6000)
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
    CreateThread(function()
        for _ = 1, times or 1 do PlaySoundFrontend(-1, name, set, true) Wait(gap or 250) end
    end)
end

-- ---------------------------------------------------------------- 1.3.2: call popup
-- A compact card (top right) for every new call while the MDT is closed: attend with one key (attaches your unit,
-- sets GPS), hide it, bring it back with /calls, leave with /detach. Closing a call clears its GPS.
local POP = DSP.popup or {}
local POP_ON = POP.enabled ~= false
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
            escalated = c.escalated, parentId = c.parentId },
        dist = dist, age = ageOf(c), left = math.max(0, hideAt - GetGameTimer()),
        more = math.max(0, #Queue - 1), state = f and f.state or nil, note = f and f.text or nil,
        keys = { attend = keyOf(CMD.attend, POP.attendKey), dismiss = keyOf(CMD.dismiss, POP.dismissKey), recall = '/' .. CMD.recall, detach = '/' .. CMD.detach } })
end

local function hide()
    shown, flash = nil, nil
    SendNUIMessage({ action = 'cpop', show = false })
end

--- show one call (the newest queued one when id is nil)
local function show(id, ms)
    if not POP_ON or MDTC.isOpen() then return end
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
    if t and t.x then
        local w = GetBlipInfoIdCoord(GetFirstBlipInfoId(8))
        if #(vector2(w.x, w.y) - vector2(t.x, t.y)) > 60.0 then return end
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
        if POP.sound ~= false then PlaySoundFrontend(-1, 'Menu_Accept', 'Phone_SoundSet_Default', true) end
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
RegisterCommand(CMD.dismiss, function() if shown then next_() end end, false)
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
    if c.kind ~= 'panic' and not mine and POP.sound ~= false then
        sound('Event_Message_Purple', 'GTAO_FM_Events_Soundset', c.priority == 1 and 2 or 1, 400)
    end
    if not MDTC.isOpen() then
        if POP_ON then
            if not mine then push(c) end
        elseif c.kind ~= 'panic' then
            notify(('%s #%d · %s%s'):format(c.kind == '311' and '311' or c.kind == '911' and '911' or 'Call', c.id,
                c.message ~= '' and c.message or c.title, c.street ~= '' and (' · ' .. c.street) or ''), c.priority == 1 and 'error' or 'inform', 9000)
        end
    elseif POP_ON and not mine then
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
    if shown == c.id then render(false) end
end)

RegisterNetEvent('es_mdt:client:callClosed', function(d)
    if type(d) ~= 'table' then return end
    local id = tonumber(d.id)
    local c = find(id)
    if c then c.closed, c.outcome = true, d.outcome end
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

RegisterNetEvent('es_mdt:client:panic', function(p)
    if type(p) ~= 'table' then return end
    lastPanic = p
    sound('Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', 6, 220)
    -- the call card shows it (attend = route + attach); without cards, the old notice
    if not POP_ON or MDTC.isOpen() then
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
    if lvl == 'urgent' then sound('Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', 3, 260)
    else sound('Text_Arrive_Tone', 'Phone_SoundSet_Default', 1) end
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
        notify(('Backup requested (P%d, call #%d)%s'):format(r.priority or 2, r.id, (r.units or 0) > 0 and '' or ' · no other units on duty'), 'success', 6000)
    end)
end
MDTC.askBackup = askBackup
if BKP.enabled ~= false then
    local BCMD = BKP.command or 'backup'
    RegisterCommand(BCMD, function() askBackup(myCall) end, false)
    RegisterKeyMapping(BCMD, 'Police: request backup', 'keyboard', BKP.key or '')
end

-- 2.0.6: an unanswered call went up a priority: a soft re-alert (one quiet tone and its card again, never over the MDT)
RegisterNetEvent('es_mdt:client:callEscalated', function(d)
    if type(d) ~= 'table' or not tonumber(d.id) then return end
    local id = tonumber(d.id)
    local c = find(id)
    if c then
        if c.closed then return end
        c.priority = d.priority
        c.escalated = d.from
    elseif POP_ON then
        c = { id = id, kind = d.kind, priority = d.priority, title = d.title, street = d.street, x = d.x, y = d.y, z = d.z, message = '', escalated = d.from }
    end
    SendNUIMessage({ action = 'callEscalated', call = { id = id, priority = d.priority, from = d.from, title = d.title, street = d.street } })
    if MDTC.isOpen() then return end
    if POP.sound ~= false then PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true) end
    if not POP_ON then
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
local SHOTS, THEFT = ALR.shots or {}, ALR.theft or {}
if SHOTS.enabled ~= false then
    local skip = {}
    for _, w in ipairs(ALR.ignoreWeapons or { 'WEAPON_STUNGUN', 'WEAPON_STUNGUN_MP', 'WEAPON_FIREEXTINGUISHER', 'WEAPON_PETROLCAN', 'WEAPON_HAZARDCAN',
        'WEAPON_FERTILIZERCAN', 'WEAPON_SNOWBALL', 'WEAPON_BALL', 'WEAPON_FLARE', 'WEAPON_FLAREGUN', 'WEAPON_RAYPISTOL' }) do skip[GetHashKey(w)] = true end
    local gap = math.max(5, tonumber(SHOTS.cooldown) or 45) * 1000
    CreateThread(function()
        local last = -gap
        while true do
            local ped = PlayerPedId()
            if IsPedArmed(ped, 4) then   -- 4 = guns: the per-frame check only while one is in hand
                Wait(0)
                if IsPedShooting(ped) and GetGameTimer() - last >= gap then
                    local _, w = GetCurrentPedWeapon(ped, true)
                    if not skip[w] and not (SHOTS.ignoreSuppressed ~= false and IsPedCurrentWeaponSilenced(ped)) then
                        last = GetGameTimer()
                        TriggerServerEvent('es_mdt:server:autoAlert', { kind = 'shots', street = streetHere() })
                    end
                end
            else
                Wait(500)
            end
        end
    end)
end
if THEFT.enabled ~= false then
    local LOCKED = { [2] = true, [3] = true, [7] = true, [10] = true }
    local gap = math.max(5, tonumber(THEFT.cooldown) or 90) * 1000
    CreateThread(function()
        local last, flagged = -gap, nil
        while true do
            Wait(400)
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
                        local model = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(v)))
                        if model == 'NULL' then model = GetDisplayNameFromVehicleModel(GetEntityModel(v)) end
                        TriggerServerEvent('es_mdt:server:autoAlert', { kind = 'theft', street = streetHere(),
                            plate = GetVehicleNumberPlateText(v), model = model })
                    end
                elseif trying == 0 and v ~= flagged then
                    flagged = nil   -- gave up
                end
            end
        end
    end)
end

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

MDTC.opsLoaded = true
