local _ENV = ESAPP('mdt'); -- es_mdt 1.3.0: police radar + plate reader (ALPR), front and rear antennas.
-- Each antenna: on/off, Same / Opposite / Both directions, strongest target speed, fastest target speed, its own lock.
-- Patrol speed, fast-limit beep (and optional auto-lock), plate cameras with their own locks, checked against the MDT
-- (BOLO / stolen / owner warrant / unregistered). Only in configured police vehicles, only on duty in a law department.
-- Settings are each player's own (KVP). The display lives in the MDT page (html), the remote opens with focus.
-- 2.0.11: every server value is read live (/whip > Settings > MDT > Radar refills Config.Radar in place), and each player's
-- own choices (volume, mute, size, position, units, auto-on, lock sound, speed alert) are also rows of the pause menu's
-- Settings > Server Settings > Radar. 2.0.12: the radar shows only in police vehicles (the panel and the F7 remote), not in the MDT.
local R = Config.Radar or {}
local REMOTE = 'mdt_radar'
local KVP = 'es_mdt:radar'

local function wc() return exports.whip_core end
local function notify(text, kind, ms) wc():Notify(text, kind or 'inform', ms) end

-- ---------------------------------------------------------------- settings (per player)
local DEFAULTS = {
    shown = true,
    front = { on = true, mode = 'both' },   -- 'same' | 'opp' | 'both'
    rear  = { on = true, mode = 'both' },
    fast = nil,   -- 2.0.11: nil = the server's speed alert (Config.Radar.fastLimit), followed when an admin changes it
    beep = true, autoLock = false, volume = 0.6, plates = true,
    x = nil, y = nil, scale = 1.0,
    -- 2.0.11
    muted = false, lockSound = true, autoOn = true,
    pos = 'br',   -- 'br' | 'bl' | 'tr' | 'tl' | 'custom' (dragged: x, y)
    units = nil,  -- nil = the server's (Config.Radar.units), or 'mph' / 'kmh'
}
local POS = { br = true, bl = true, tr = true, tl = true, custom = true }
local S
local function copy(t) local o = {} for k, v in pairs(t) do o[k] = type(v) == 'table' and copy(v) or v end return o end
local function clean(s)
    local o = copy(DEFAULTS)
    if type(s) ~= 'table' then return o end
    if type(s.shown) == 'boolean' then o.shown = s.shown end
    for _, a in ipairs({ 'front', 'rear' }) do
        local x = type(s[a]) == 'table' and s[a] or {}
        if type(x.on) == 'boolean' then o[a].on = x.on end
        if x.mode == 'same' or x.mode == 'opp' or x.mode == 'both' then o[a].mode = x.mode end
    end
    local f = tonumber(s.fast) if f then o.fast = math.max(5, math.min(250, math.floor(f))) end
    for _, k in ipairs({ 'muted', 'lockSound', 'autoOn' }) do if type(s[k]) == 'boolean' then o[k] = s[k] end end
    if POS[s.pos] then o.pos = s.pos end
    if s.units == 'mph' or s.units == 'kmh' then o.units = s.units end
    if type(s.beep) == 'boolean' then o.beep = s.beep end
    if type(s.autoLock) == 'boolean' then o.autoLock = s.autoLock end
    if type(s.plates) == 'boolean' then o.plates = s.plates end
    local v = tonumber(s.volume) if v then o.volume = math.max(0, math.min(1, v)) end
    local sc = tonumber(s.scale) if sc then o.scale = math.max(0.6, math.min(1.6, sc)) end
    local x, y = tonumber(s.x), tonumber(s.y)
    if x and y then o.x, o.y = math.max(0, math.min(1, x)), math.max(0, math.min(1, y)) if not POS[s.pos] then o.pos = 'custom' end end
    if o.pos ~= 'custom' then o.x, o.y = nil, nil end
    return o
end
local function load()
    local raw = GetResourceKvpString(KVP)
    local ok, v = pcall(json.decode, raw or '')
    S = clean(ok and v or nil)
end
local function save() SetResourceKvp(KVP, json.encode(S)) end
load()

-- 2.0.11: what is in force now (the player's own choice, else the server's)
local function unitsNow() return S.units or (R.units == 'kmh' and 'kmh' or 'mph') end
local function mult() return unitsNow() == 'kmh' and 3.6 or 2.236936 end
local function fastNow() return S.fast or math.floor(tonumber(R.fastLimit) or 70) end
local function autoLockOn() return S.autoLock and R.autoLockAllowed ~= false end
local function sound(name, set)
    if S.muted or (S.volume or 0) <= 0 then return end
    PlaySoundFrontend(-1, name, set, true)
end
local function lockSound() if S.lockSound ~= false then sound('TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET') end end

-- ---------------------------------------------------------------- state
local allowed, allowedAt, allowedVeh = false, 0, 0
local live = false                 -- display up right now
local remoteOpen = false
local L = {                        -- locks
    front = { speed = nil, fast = nil, plate = nil },
    rear  = { speed = nil, fast = nil, plate = nil },
}
local plates = { front = nil, rear = nil }   -- last read
local checked = {}                 -- [plate] = { at, res }
local asking = false
local lastBeep = 0
local hits = {}                    -- last plate hits, newest first (remote shows them)

-- 2.0.11: the vehicle classes and models, read live (Config.Radar.classList / models; classes before 2.0.11)
local vehSets = { sig = nil, classes = {}, models = {} }
local function sets()
    local cl, md = R.classList, R.models or {}
    local sig = (type(cl) == 'table' and table.concat(cl, ',') or 'map') .. '|' .. table.concat(md, ',')
    if sig ~= vehSets.sig then
        local c, m = {}, {}
        if type(cl) == 'table' then for _, x in ipairs(cl) do c[math.floor(tonumber(x) or -1)] = true end
        else for k, v in pairs(R.classes or { [18] = true }) do if v then c[k] = true end end end
        for _, x in ipairs(md) do m[type(x) == 'number' and x or joaat(x)] = true end
        vehSets = { sig = sig, classes = c, models = m }
    end
    return vehSets
end

local function policeCar(veh)
    if veh == 0 then return false end
    local ped = PlayerPedId()
    if GetPedInVehicleSeat(veh, -1) ~= ped and GetPedInVehicleSeat(veh, 0) ~= ped then return false end
    local vs = sets()
    return vs.classes[GetVehicleClass(veh)] == true or vs.models[GetEntityModel(veh)] == true
end

local function key(p) return (p or ''):upper():gsub('[^A-Z0-9]', '') end

local function send(msg) SendNUIMessage(msg) end
--- the page gets the player's settings with what is in force filled in (speed alert, units) and the server's switches
local function view()
    local o = copy(S)
    o.fast = fastNow()
    o.unitsNow = unitsNow()
    o.autoLockAllowed = R.autoLockAllowed ~= false
    o.hitSound = R.hitSound ~= false
    return o
end
local function pushSettings() send({ action = 'radarSettings', settings = view(), units = unitsNow() == 'kmh' and 'KMH' or 'MPH' }) end

-- ---------------------------------------------------------------- plate checks
local function checkPlates(list, pos, ants)
    if asking or #list == 0 then return end
    asking = true
    CreateThread(function()
        local res = wc():Callback('es_mdt:radarPlates', { plates = list })
        asking = false
        if type(res) ~= 'table' then return end
        for k, r in pairs(res) do
            local first = not checked[k] or not checked[k].res
            checked[k] = { at = GetGameTimer(), res = r }
            if first and r.level == 'high' then
                local why = {}
                for _, h in ipairs(r.hits or {}) do if h.level == 'high' then why[#why + 1] = h.text end end
                table.insert(hits, 1, { plate = k, text = table.concat(why, ' · '), at = GetCloudTimeAsInt(),
                    x = pos and pos.x or nil, y = pos and pos.y or nil, ownerCharId = r.ownerCharId, vehicleId = r.vehicleId, boloId = r.boloId })
                while #hits > 8 do table.remove(hits) end
                if R.hitSound ~= false then sound('Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS') end
                notify(('ALPR HIT %s · %s · /radaropen to look it up'):format(k, table.concat(why, ' · ')), 'error', 10000)
                -- lock the plate on whichever camera read it
                for _, a in ipairs({ 'front', 'rear' }) do
                    if plates[a] and key(plates[a]) == k and not L[a].plate then L[a].plate = plates[a] end
                end
                send({ action = 'radarHit', hit = hits[1] })
            end
        end
    end)
end

local function plateInfo(p)
    if not p then return nil end
    local c = checked[key(p)]
    if not c or not c.res then return { plate = p } end
    return { plate = p, level = c.res.level, hits = c.res.hits, done = true }
end

-- ---------------------------------------------------------------- the scan
local function scan(veh)
    local myPos = GetEntityCoords(veh)
    local fwd = GetEntityForwardVector(veh)
    local out = {
        front = { strong = nil, fast = nil, plate = nil, pd = 1e9, sd = 1e9 },
        rear  = { strong = nil, fast = nil, plate = nil, pd = 1e9, sd = 1e9 },
    }
    local range, pr = tonumber(R.range) or 110.0, tonumber(R.plateRange) or 30.0
    local COS, MULT = math.cos(math.rad(tonumber(R.angle) or 18.0)), mult()   -- 2.0.11: live
    for _, v in ipairs(GetGamePool('CVehicle')) do
        if v ~= veh then
            local p = GetEntityCoords(v)
            local dx, dy, dz = p.x - myPos.x, p.y - myPos.y, p.z - myPos.z
            local d = math.sqrt(dx * dx + dy * dy + dz * dz)
            if d > 1.0 and d <= range then
                local dot = (dx * fwd.x + dy * fwd.y) / d
                local ant = (dot >= COS and 'front') or (dot <= -COS and 'rear') or nil
                if ant and S[ant].on and HasEntityClearLosToEntity(veh, v, 17) then
                    local of = GetEntityForwardVector(v)
                    local same = (of.x * fwd.x + of.y * fwd.y) > 0
                    local mode = S[ant].mode
                    if mode == 'both' or (mode == 'same' and same) or (mode == 'opp' and not same) then
                        local spd = GetEntitySpeed(v) * MULT
                        local o = out[ant]
                        if spd >= 2 then
                            if d < o.sd then o.sd = d o.strong = spd end
                            if not o.fast or spd > o.fast then o.fast = spd end
                        end
                        if d <= pr and d < o.pd then o.pd = d o.plate = GetVehicleNumberPlateText(v) end
                    end
                end
            end
        end
    end
    return out
end

local function round(x) return x and math.floor(x + 0.5) or nil end

local lastSig, lastSent, lastPrune = nil, -1e9, 0   -- 2.0.10

local function tick(veh)
    local o = scan(veh)
    local patrol = round(GetEntitySpeed(veh) * mult())
    local ask, ants = {}, {}
    local FAST = fastNow()
    local overLimit = false
    local data = { patrol = patrol, front = {}, rear = {} }
    for _, a in ipairs({ 'front', 'rear' }) do
        local x, lk = o[a], L[a]
        local strong, fast = round(x.strong), round(x.fast)
        if fast and strong and fast <= strong then fast = nil end   -- only show "fast" when it is a different, faster car
        if S[a].on and autoLockOn() and not lk.speed and (fast or strong or 0) >= FAST then
            lk.speed, lk.fast = strong, fast
            lockSound()
        end
        if S[a].on and (fast or strong or 0) >= FAST then overLimit = true end
        if x.plate then plates[a] = x.plate end
        local shownPlate = lk.plate or (S.plates and S[a].on and x.plate or nil)
        if S.plates and shownPlate then
            local k = key(shownPlate)
            local c = checked[k]
            if k ~= '' and (not c or GetGameTimer() - c.at > (R.recheckSec or 60) * 1000) then
                checked[k] = checked[k] or { at = GetGameTimer() }
                checked[k].at = GetGameTimer()
                ask[#ask + 1] = shownPlate
                ants[k] = a
            end
        end
        data[a] = { on = S[a].on, mode = S[a].mode, speed = S[a].on and strong or nil, fast = S[a].on and fast or nil,
            lockSpeed = lk.speed, lockFast = lk.fast, locked = lk.speed ~= nil or lk.fast ~= nil,
            plate = plateInfo(shownPlate), plateLocked = lk.plate ~= nil }
    end
    if overLimit and S.beep and not S.muted and GetGameTimer() - lastBeep > 2500 then
        lastBeep = GetGameTimer()
        data.beep = true
    end
    data.over = overLimit or nil
    if #ask > 0 then local p = GetEntityCoords(veh) checkPlates(ask, { x = p.x, y = p.y }, ants) end
    -- 2.0.10: the screen only gets the readout when something on it changed (at least every 2 s to be safe)
    local now = GetGameTimer()
    local sig = json.encode(data)
    if sig ~= lastSig or now - lastSent > 2000 then
        lastSig, lastSent = sig, now
        send({ action = 'radar', data = data })
    end
    -- 2.0.10: plates looked up more than 10 minutes ago are forgotten (checked again if they come back)
    if now - lastPrune > 60000 then
        lastPrune = now
        for k, c in pairs(checked) do if now - (c.at or 0) > 600000 then checked[k] = nil end end
    end
end

-- ---------------------------------------------------------------- may it run here?
local function refreshAllowed(veh)
    if GetGameTimer() - allowedAt < 15000 and allowedVeh == veh then return end
    allowedAt, allowedVeh = GetGameTimer(), veh
    CreateThread(function()
        local ok = wc():Callback('es_mdt:radarAllowed', {})
        allowed = ok == true
    end)
end
for _, ev in ipairs({ 'whip_core:job:clockedOn', 'whip_core:job:clockedOff', 'whip_core:client:jobClockState' }) do
    AddEventHandler(ev, function() allowedAt = 0 end)
    RegisterNetEvent(ev)
end

local function setLive(on)
    if live == on then return end
    live = on
    lastSig = nil   -- 2.0.10: a fresh readout right away
    if on then pushSettings() end
    send({ action = 'radarShow', show = on })
end

local function closeRemote()
    if not remoteOpen then return end
    remoteOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    wc():SetScreenOpen(false, REMOTE)
    -- the block stays a moment longer, so the Esc that closed it does not open the pause menu
    SetTimeout(400, function() if not remoteOpen then wc():UnblockControls(REMOTE) end end)
    send({ action = 'radarRemote', open = false })
end

CreateThread(function()
    local lastVeh = 0
    while true do
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if R.enabled == false then   -- 2.0.11: turned off in /whip: nothing runs
            if live then setLive(false) end
            if remoteOpen then closeRemote() end
            Wait(2000)
        elseif policeCar(veh) then
            refreshAllowed(veh)
            -- 2.0.11: getting into a radar vehicle turns the radar on (pause menu: Radar > Turn on in a police vehicle)
            if veh ~= lastVeh and S.autoOn and not S.shown then S.shown = true save() end
            lastVeh = veh
            if allowed and S.shown then
                setLive(true)
                tick(veh)
                -- 2.0.10: parked (and no remote open) it looks half as often; 2.0.11: both rates are settings
                local parked = GetEntitySpeed(veh) < 1.0 and not remoteOpen
                local ms = parked and (tonumber(R.parkedScanMs) or 500) or (tonumber(R.scanMs) or 250)
                Wait(math.max(100, math.min(5000, math.floor(ms))))
            else
                setLive(false)
                Wait(500)
            end
        else
            lastVeh = 0
            if live then setLive(false) end
            if remoteOpen then closeRemote() end
            Wait(1000)
        end
    end
end)

-- ---------------------------------------------------------------- controls
local function inCar() return policeCar(GetVehiclePedIsIn(PlayerPedId(), false)) and allowed end

-- look LR/UD (1, 2), attack / aim (24, 25), vehicle mouse look (106), weapon wheel (37, 12-17), pause (199, 200, 322),
-- vehicle aim / attack / passenger attack (68, 69, 70, 91, 92), melee (140-142, 257, 263, 264)
local REMOTE_BLOCK = { 1, 2, 3, 4, 5, 6, 24, 25, 106, 37, 12, 13, 14, 15, 16, 17, 199, 200, 322, 68, 69, 70, 91, 92, 140, 141, 142, 257, 263, 264 }

--- the key a player bound to the remote command (F7 by default), so the page can close on it too
local function remoteKey()
    local ok, s = pcall(GetControlInstructionalButton, 0, GetHashKey('radarremote') | 0x80000000, true)
    if ok and type(s) == 'string' and s:sub(1, 2) == 't_' then return s:sub(3) end
    return (R.keys or {}).remote or 'F7'
end

local function cmd(name, label, def, fn)
    RegisterCommand(name, function() if inCar() then fn() end end, false)
    RegisterKeyMapping(name, 'Police radar: ' .. label, 'keyboard', def or '')
end
local K = R.keys or {}

cmd('radar', 'show / hide', K.toggle, function()
    S.shown = not S.shown save()
    notify(S.shown and 'Radar on' or 'Radar off', 'inform', 1500)
end)
local function lockSpeed(a)
    local lk = L[a]
    if lk.speed or lk.fast then lk.speed, lk.fast = nil, nil
    else
        local ped = PlayerPedId()
        local o = scan(GetVehiclePedIsIn(ped, false))[a]
        lk.speed, lk.fast = round(o.strong), round(o.fast)
        if not lk.speed and not lk.fast then notify('Nothing to lock on the ' .. a .. ' antenna', 'error', 1500) return false end
    end
    lockSound()
    lastSig = nil
    return true
end
local function lockPlate(a)
    local lk = L[a]
    if lk.plate then lk.plate = nil
    elseif plates[a] then lk.plate = plates[a]
    else notify('No ' .. a .. ' plate to lock', 'error', 1500) return false end
    lockSound()
    lastSig = nil
    return true
end
cmd('radarfs', 'lock front speed', K.frontSpeed, function() lockSpeed('front') end)
cmd('radarrs', 'lock rear speed', K.rearSpeed, function() lockSpeed('rear') end)
cmd('radarfp', 'lock front plate', K.frontPlate, function() lockPlate('front') end)
cmd('radarrp', 'lock rear plate', K.rearPlate, function() lockPlate('rear') end)
cmd('radarreset', 'reset locks', K.reset, function()
    for _, a in ipairs({ 'front', 'rear' }) do L[a] = { speed = nil, fast = nil, plate = nil } end
    plates = { front = nil, rear = nil }
    notify('Radar locks cleared', 'inform', 1500)
end)
cmd('radarremote', 'remote', K.remote, function()
    if remoteOpen then return closeRemote() end
    if wc():IsAnyScreenOpen() then return notify('Close what is open first', 'error') end
    remoteOpen = true
    lastSig = nil   -- 2.0.10: the remote shows the readout at once
    wc():SetScreenOpen(true, REMOTE)
    -- 1.3.2: the remote takes the mouse and keyboard; the game gets none (the mouse turned the camera before).
    -- Set after SetScreenOpen, so nothing that runs on the screen claim can leave keep-input on.
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    pushSettings()
    send({ action = 'radarRemote', open = true, hits = hits, closeKey = remoteKey() })
    -- belt and braces while it is open: if any other layer keeps game input, look / aim / attack / weapon wheel /
    -- pause / vehicle aim and shoot stay off (WHIP's shared block), so the mouse and Esc only reach the remote.
    -- Steering and throttle are not in it.
    wc():BlockControls(REMOTE, { groups = { 'look', 'combat', 'vehicleCombat', 'weaponWheel' }, controls = REMOTE_BLOCK })
    CreateThread(function()
        while remoteOpen do Wait(500) if remoteOpen then SetNuiFocusKeepInput(false) end end
    end)
end)
RegisterCommand('radaropen', function()
    local p = (hits[1] and hits[1].plate) or (L.front.plate and key(L.front.plate)) or (L.rear.plate and key(L.rear.plate))
    if not p then return notify('No plate hit or locked plate to look up', 'error') end
    MDTC.goTo('vehicles', p)
end, false)

-- ---------------------------------------------------------------- from the page
--- 2.0.11: settings from a page: the speed alert equal to the server's is not kept (the player follows the server)
local function fromPage(t)
    -- 2.0.12: laid over what the player has now, so a key the page leaves out (e.g. auto-on, set in the pause menu) is kept
    local m = copy(S)
    for k, v in pairs(type(t) == 'table' and t or {}) do
        if (k == 'front' or k == 'rear') and type(v) == 'table' then for a, b in pairs(v) do m[k][a] = b end else m[k] = v end
    end
    if type(t) == 'table' and t.fast == nil then m.fast = S.fast end
    local n = clean(m)
    if n.fast and n.fast == math.floor(tonumber(R.fastLimit) or 70) then n.fast = nil end
    if not (R.autoLockAllowed ~= false) then n.autoLock = S.autoLock end
    return n
end
RegisterNUICallback('radarSave', function(d, cb)
    S = fromPage(type(d) == 'table' and d.settings or nil)
    save()
    lastSig = nil
    pushSettings()
    cb({ ok = true, data = view() })
end)
RegisterNUICallback('radarClose', function(_, cb) closeRemote() cb({ ok = true }) end)
RegisterNUICallback('radarReset', function(_, cb)
    for _, a in ipairs({ 'front', 'rear' }) do L[a] = { speed = nil, fast = nil, plate = nil } end
    lastSig = nil
    cb({ ok = true })
end)
RegisterNUICallback('radarLock', function(d, cb)
    d = type(d) == 'table' and d or {}
    local a = d.antenna == 'rear' and 'rear' or 'front'
    if not inCar() then return cb({ ok = false, why = 'Get in a police vehicle, on duty' }) end
    local ok = d.what == 'plate' and lockPlate(a) or (d.what ~= 'plate' and lockSpeed(a))
    cb({ ok = ok == true, why = ok ~= true and ('Nothing to lock on the ' .. a .. ' antenna') or nil })
end)
RegisterNUICallback('radarOpenPlate', function(d, cb)
    local p = key(type(d) == 'table' and d.plate or '')
    if p == '' then return cb({ ok = false, why = 'No plate' }) end
    closeRemote()
    MDTC.goTo('vehicles', p)
    cb({ ok = true })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if remoteOpen then SetNuiFocus(false, false) end
end)

-- ---------------------------------------------------------------- 2.0.11: the pause menu (Settings > Server Settings > Radar)
-- Each player's own radar choices as rows of WHIP's Server Settings page (Whip.playerSetting). They are the same values as
-- the remote (F7) (KVP es_mdt:radar), so both always agree: the page reads `get` each time.
-- The speed alert and the units follow the server's default until the player picks their own.
local function changed() save() lastSig = nil pushSettings() end
local function declareRows()
    if not (Whip and Whip.playerSetting) then return end
    local G = 'Radar'
    local unitTxt = function() return unitsNow() == 'kmh' and 'km/h' or 'mph' end
    Whip.playerSetting({ key = 'es_mdt.radarAutoOn', group = G, type = 'toggle', label = 'Turn the radar on in a police vehicle', default = true,
        help = 'On duty, as you get in. Turn it off for a ride with F5 (rebind in GTA Settings > Key Bindings > FiveM).',
        get = function() return S.autoOn ~= false end, set = function(v) S.autoOn = v == true changed() end })
    Whip.playerSetting({ key = 'es_mdt.radarVolume', group = G, type = 'slider', label = 'Radar volume', unit = '%', min = 0, max = 100, step = 5, default = 60,
        help = 'Speed alert beeps, locks and plate hits.',
        get = function() return math.floor((S.volume or 0.6) * 100 + 0.5) end,
        set = function(v) v = tonumber(v) if not v then return end S.volume = math.max(0, math.min(100, v)) / 100 changed() end })
    Whip.playerSetting({ key = 'es_mdt.radarMute', group = G, type = 'toggle', label = 'Mute the radar', default = false,
        help = 'No radar sounds at all (the display still flashes on a hit).',
        get = function() return S.muted == true end, set = function(v) S.muted = v == true changed() end })
    Whip.playerSetting({ key = 'es_mdt.radarLockSound', group = G, type = 'toggle', label = 'Sound when a target is locked', default = true,
        get = function() return S.lockSound ~= false end, set = function(v) S.lockSound = v == true changed() end })
    Whip.playerSetting({ key = 'es_mdt.radarBeep', group = G, type = 'toggle', label = 'Beep over my speed alert', default = true,
        get = function() return S.beep ~= false end, set = function(v) S.beep = v == true changed() end })
    local def = math.floor(tonumber(R.fastLimit) or 70)
    Whip.playerSetting({ key = 'es_mdt.radarFast', group = G, type = 'slider', label = 'My speed alert', unit = unitTxt(), min = 10, max = 200, step = 1, default = def,
        help = 'Targets over this speed beep (and lock, with auto-lock on in the remote). The server\'s default is ' .. def .. '.',
        get = function() return fastNow() end,
        set = function(v) v = tonumber(v) if not v then return end v = math.floor(v + 0.5) S.fast = (v ~= math.floor(tonumber(R.fastLimit) or 70)) and math.max(5, math.min(250, v)) or nil changed() end })
    Whip.playerSetting({ key = 'es_mdt.radarUnits', group = G, type = 'choice', label = 'Show speeds in', default = 'server',
        options = { { value = 'server', label = 'The server\'s unit (' .. ((R.units == 'kmh') and 'km/h' or 'mph') .. ')' }, { value = 'mph', label = 'mph' }, { value = 'kmh', label = 'km/h' } },
        get = function() return S.units or 'server' end,
        set = function(v) S.units = (v == 'mph' or v == 'kmh') and v or nil changed() end })
    Whip.playerSetting({ key = 'es_mdt.radarScale', group = G, type = 'slider', label = 'Radar panel size', unit = '%', min = 60, max = 160, step = 5, default = 100,
        get = function() return math.floor((S.scale or 1) * 100 + 0.5) end,
        set = function(v) v = tonumber(v) if not v then return end S.scale = math.max(60, math.min(160, v)) / 100 changed() end })
    Whip.playerSetting({ key = 'es_mdt.radarPos', group = G, type = 'choice', label = 'Radar panel position', default = 'br',
        help = 'Or drag it anywhere with the remote (F7) open: that is "Where I dragged it".',
        options = { { value = 'br', label = 'Bottom right' }, { value = 'bl', label = 'Bottom left' }, { value = 'tr', label = 'Top right' },
            { value = 'tl', label = 'Top left' }, { value = 'custom', label = 'Where I dragged it' } },
        get = function() return S.pos or 'br' end,
        set = function(v)
            if not POS[v] then return end
            if v == 'custom' and not S.x then return end   -- nowhere dragged yet: stays where it is
            S.pos = v
            if v ~= 'custom' then S.x, S.y = nil, nil end
            changed()
        end })
end
declareRows()
-- an admin changed the radar's defaults (/whip > Settings > MDT > Radar): the rows, the display and the tab follow
if Whip and Whip.onConfigChanged then
    local queued = false
    Whip.onConfigChanged('Radar', function()
        if queued then return end
        queued = true
        SetTimeout(0, function() queued = false lastSig = nil pushSettings() declareRows() end)
    end)
end

MDTC.radarLoaded = true
