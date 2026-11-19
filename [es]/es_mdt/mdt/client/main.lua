local _ENV = ESAPP('mdt'); -- es_mdt client: /mdt (and F6) opens the MDT page. ONE screen name for every SetScreenOpen call, the lesson from
-- /departments: opening under one name and closing under another left WHIP thinking a screen was open, so chat,
-- prompts and hotkeys stayed off.

local SCREEN = 'mdt'
local open, opening = false, false

local function wc() return exports.whip_core end
local function notify(text, kind) wc():Notify(text, kind or 'inform') end

--- Keyboard and mouse back, and WHIP told the screen is gone. Safe to call any number of times.
local function release()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    wc():SetScreenOpen(false, SCREEN)
end

-- ---------------------------------------------------------------- the tablet in hand
-- On while the MDT is open on foot: upper-body anim here, prop made by WHIP on the server (HoldProps, seen by all).
-- One flag, so opening twice never makes two; tabletOff is safe to call any number of times.
local tablet = false

local function tabletOff()
    if not tablet then return end
    tablet = false
    local T = Config.Tablet or {}
    local ped = PlayerPedId()
    if T.dict and T.anim and IsEntityPlayingAnim(ped, T.dict, T.anim, 3) then StopAnimTask(ped, T.dict, T.anim, 2.0) end
    pcall(function() wc():DropOwnHeldProp(T.prop or 'prop_cs_tablet', 'tablet') end)   -- gone here at once
    TriggerServerEvent('es_mdt:tablet', false)                                             -- and for everyone
end

local function tabletOn()
    local T = Config.Tablet
    if tablet or not (T and T.enabled) then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then return end   -- in a car the MDT just opens
    if wc():IsEmoting() then wc():CancelEmote() end
    if not T.dict or not T.anim or not wc():LoadAnimDict(T.dict) then return end
    if not open or tablet then return end   -- closed (or opened again) while the anim loaded
    tablet = true
    TaskPlayAnim(ped, T.dict, T.anim, 3.0, 3.0, -1, T.flag or 49, 0, false, false, false)
    RemoveAnimDict(T.dict)
    TriggerServerEvent('es_mdt:tablet', true)
    CreateThread(function()   -- keep holding it while open; put it away if they end up in a car or dead
        while tablet do
            Wait(500)
            if not tablet then break end
            local p = PlayerPedId()
            if not open or IsPedInAnyVehicle(p, false) or IsEntityDead(p) then tabletOff() break end
            if not IsEntityPlayingAnim(p, T.dict, T.anim, 3) and not IsPedRagdoll(p) and wc():LoadAnimDict(T.dict) then
                TaskPlayAnim(p, T.dict, T.anim, 3.0, 3.0, -1, T.flag or 49, 0, false, false, false)
                RemoveAnimDict(T.dict)
            end
        end
    end)
end

local function close()
    local was = open
    open = false
    release()
    tabletOff()
    if was then SendNUIMessage({ action = 'close' }) end
end

--- 1.10.0: the DOJ is part of the MDT: a DOJ member's MDT is the court side (es_doj's screen)
local function openCourt()
    if GetResourceState('es_doj') ~= 'started' then return notify('The court side of the MDT is not running', 'error') end
    TriggerEvent('es_doj:client:openTablet')
end

local function openScreen(after, opts)
    if open or opening then return end
    if wc():IsAnyScreenOpen() then return notify('Close what is open first', 'error') end
    opening = true
    local data, why = wc():Callback('es_mdt:open', type(opts) == 'table' and opts or {})
    opening = false
    if type(data) ~= 'table' then return notify(why or 'The MDT is not available', 'error') end
    if data.doj then return openCourt() end
    if open or wc():IsAnyScreenOpen() then return end
    open = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    wc():SetScreenOpen(true, SCREEN)
    SendNUIMessage({ action = 'open', data = data })
    if after then SendNUIMessage(after) end
    tabletOn()
end

-- 1.3.0: client/ops.lua and client/radar.lua use these
MDTC = {
    isOpen = function() return open end,
    open = openScreen,
    close = close,
    release = release,
    wc = wc,
    notify = notify,
    -- open the MDT on one page (or, when it is up, switch to it)
    goTo = function(view, arg)
        local msg = { action = 'go', view = view, arg = arg }
        if open then SendNUIMessage(msg) else CreateThread(function() openScreen(msg) end) end
    end,
}

-- 1.3.1: say so in F8 when the newer client files were not sent (the server needs `refresh` after files are added)
CreateThread(function()
    Wait(5000)
    if not MDTC.opsLoaded or not MDTC.radarLoaded then
        print('^1[es_mdt] client/ops.lua or client/radar.lua did not load. An admin should run `refresh` then `ensure es_mdt`.^7')
    end
end)

RegisterCommand(Config.Command, function() CreateThread(function() openScreen() end) end, false)
-- 1.10.0: es_doj's "Police MDT" button (a member of both the DOJ and a police department)
AddEventHandler('es_mdt:client:openLaw', function() CreateThread(function() openScreen(nil, { law = true }) end) end)
RegisterKeyMapping(Config.Command, 'Open the MDT', 'keyboard', Config.Key)

-- Page -> server. Only these names pass; each becomes the SecureCallback 'es_mdt:<name>'.
local CALLS = {}
for _, n in ipairs({ 'open', 'pickDept', 'dashboard', 'units', 'setStatus', 'people', 'person', 'profileSave', 'vehicles', 'vehicle',
    'vehicleSave', 'penal', 'penalSave', 'reports', 'report', 'reportSave', 'reportDelete', 'fineReport', 'fineCustom', 'fineAct',
    'warrants', 'warrantSave', 'warrantAct', 'bolos', 'boloSave', 'boloClose', 'dept', 'hire', 'setRank', 'fire', 'memberInfo',
    'stats', 'activity', 'loaMine', 'loaList', 'loaFile', 'loaAct', 'trainees', 'ftoSessions', 'ftoAssign', 'ftoLog', 'ftoSignOff',
    'ftoHome', 'ftoFile', 'ftoStats', 'ftoProgramSave', 'ftoStart', 'ftoSign', 'ftoComplete',
    'recommend', 'recs', 'recAct', 'badges', 'unitGps', 'onlinePlayers', 'officer', 'warrantCounts',
    'unitInvite', 'unitCancel', 'unitAnswer', 'unitLeave', 'rideLog', 'rideSkip',
    'weaponTypes', 'weaponOverview', 'weapons', 'weapon', 'weaponRegister', 'weaponAct', 'licenseAct',
    'calls', 'call', 'callCreate', 'callAttach', 'callDetach', 'callRoute', 'callNote', 'callClose', 'callBackup', 'mapData', 'callLink', 'board',
    'mugshots', 'mugshot', 'mugshotLink', 'mugshotProfile', 'announcements', 'announceSave', 'announceAct',
    'templates', 'templateSave', 'templateDelete', 'jailStatus', 'sendToJail',
    'evStatus', 'evList', 'evGet', 'evForReport', 'evLink', 'evUnlink', 'evNote', 'evDestroy', 'evRoll', 'evRollPhoto', 'evPhoto', 'evLockers', 'mugshotRoll',
    'cases', 'caseFind', 'case', 'caseSave', 'caseStatus', 'casePerson', 'caseLink', 'reportCase', 'evSources', 'evAttachMany', 'evImage', 'casePurge',
    'officerProfile', 'officerPhoto', 'personnelAdd', 'personnelRemove', 'certs', 'certsSave', 'certGrant', 'certRevoke',
    'permits', 'permitRecheck', 'permitDecide', 'permitPhoto', 'editing', 'testData', 'testClear',
    -- 1.11.2: the whip_evidence locker (server/whipev.lua); missing in 1.11.0/1.11.1, so the page got "Unknown call"
    'wevStatus', 'wevList', 'wevUpload', 'wevPhoto', 'wevLocker', 'wevReport', 'wevReportLink',
    -- 1.11.2: also had server handlers but were never let through (Jail tab, booking prints, weapon release)
    'jailList', 'jailRelease', 'evPrintsOf', 'evPrintsTake', 'evRelease',
    -- 2.1.0: tickets, contests (the officer's statement), impound and the lot
    'tickets', 'ticket', 'tkStatement', 'tkVoid', 'impForm', 'impSave', 'impList', 'impGet', 'impVehicle', 'impHold', 'impRelease' }) do CALLS[n] = true end

RegisterNUICallback('call', function(d, cb)
    local name = type(d) == 'table' and d.name
    if not CALLS[name] then return cb({ ok = false, why = 'Unknown call' }) end
    CreateThread(function()
        local data = type(d.data) == 'table' and d.data or {}
        local res, why = wc():Callback('es_mdt:' .. name, data)
        if res == false or res == nil then cb({ ok = false, why = why or 'That did not work' }) else cb({ ok = true, data = res }) end
        -- 1.3.2: the call card's GPS follows attach / detach made in the Dispatch tab
        if res and name == 'callAttach' and MDTC.onCallAttach then MDTC.onCallAttach(data.id, res)
        elseif res and name == 'callDetach' and MDTC.onCallDetach then MDTC.onCallDetach(data.id)
        elseif res and name == 'callRoute' and MDTC.onCallRouted then MDTC.onCallRouted(data.id, res) end
    end)
end)

RegisterNUICallback('close', function(_, cb) close() cb({ ok = true }) end)
-- 2.0.7: a case's whip_evidence locker from the MDT. whip_core will not open a stash while another screen (the MDT) is up,
-- so: close the MDT, wait until whip_core sees no screen, then ask the server once. The stash opens on its own; a refusal
-- (not at a locker, no permission) is a notice, and the MDT stays closed (it never reopens by itself).
local lockerBusy = false
RegisterNUICallback('wevLockerOpen', function(d, cb)
    local caseId = tonumber(type(d) == 'table' and d.caseId)
    if not caseId then return cb({ ok = false, why = 'No case' }) end
    if lockerBusy then return cb({ ok = true, busy = true }) end   -- a second press while the first is on its way
    lockerBusy = true
    cb({ ok = true })
    close()
    CreateThread(function()
        local t0 = GetGameTimer()
        Wait(100)   -- the focus and the screen claim let go this frame
        while wc():IsAnyScreenOpen() and GetGameTimer() - t0 < 1500 do Wait(50) end
        local r, why = wc():Callback('es_mdt:wevLocker', { caseId = caseId })
        if r ~= true and type(r) ~= 'table' then notify(why or 'The locker did not open', 'error') end
        SetTimeout(1500, function() lockerBusy = false end)
    end)
end)
-- 1.10.0: Court (DOJ) in the nav, or the DOJ department picked in the switcher: the court side opens in its place
RegisterNUICallback('toCourt', function(_, cb)
    cb({ ok = true })
    close()
    CreateThread(function() Wait(150) openCourt() end)
end)

-- GPS: mark a unit's position (the server sends where they are)
RegisterNUICallback('waypoint', function(d, cb)
    local x, y = tonumber(type(d) == 'table' and d.x), tonumber(type(d) == 'table' and d.y)
    if not x or not y then return cb({ ok = false, why = 'No position' }) end
    SetNewWaypoint(x + 0.0, y + 0.0)
    cb({ ok = true })
end)

-- Department logos come from es_departments (cached there by version)
RegisterNUICallback('logo', function(d, cb)
    CreateThread(function()
        local ok, data = pcall(function() return exports.es_departments:GetLogo(tonumber(d.id), tonumber(d.ver)) end)
        cb({ ok = ok and data and true or false, data = ok and data or nil })
    end)
end)

-- Something others changed (a unit's status, a warrant): the page reloads what it shows
RegisterNetEvent('es_mdt:client:refresh', function(what)
    if open then SendNUIMessage({ action = 'refresh', what = what }) end
end)
-- A ride-along this FTO led just ended: the page asks for the notes (if the MDT is closed, Training lists it)
RegisterNetEvent('es_mdt:client:ride', function(ride)
    if open and type(ride) == 'table' then SendNUIMessage({ action = 'ride', ride = ride }) end
end)
RegisterNetEvent('es_departments:client:changed', function()
    if open then SendNUIMessage({ action = 'refresh', what = 'dept' }) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    open = false
    SetNuiFocus(false, false)   -- whip_core drops the screen claim and our held props itself
    local T = Config.Tablet or {}
    if tablet and T.dict and T.anim then StopAnimTask(PlayerPedId(), T.dict, T.anim, 2.0) end
    tablet = false
end)

-- The page went away while we think it is up: never leave the game without keys
CreateThread(function()
    local misses = 0
    while true do
        Wait(1000)
        misses = (open and not IsNuiFocused()) and misses + 1 or 0
        if misses >= 2 then misses = 0 close() end
    end
end)
AddEventHandler('whip_core:player:died', function() close() end)
AddEventHandler('whip_core:player:logout', function() close() end)
