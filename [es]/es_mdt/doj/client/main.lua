local _ENV = ESAPP('doj'); -- es_doj client: /doj (the DOJ tablet) and /court (the public portal; also the clerk's window at the courthouse).
-- ONE screen name for every SetScreenOpen call. The page asks the server through the allow-listed names below.
local SCREEN = 'es_doj'
local open, opening, mode = false, false, nil   -- mode: 'tablet' | 'portal'

local function wc() return exports.whip_core end
local function notify(text, kind) wc():Notify(text, kind or 'inform') end

local function release()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    wc():SetScreenOpen(false, SCREEN)
end

local function close()
    local was = open
    open, mode = false, nil
    release()
    if was then SendNUIMessage({ action = 'close' }) end
end

--- What the page needs to draw forms (the shared config)
local function lists()
    return {
        caseKinds = Config.CaseKinds, stages = Config.Stages, hearingKinds = Config.HearingKinds, filingKinds = Config.FilingKinds,
        rooms = Config.Courthouse.rooms, courthouse = Config.Courthouse.label, bondPercent = (Config.Bail or {}).bondPercent or 10,
        bailMax = (Config.Bail or {}).max or 1000000, sentence = Config.Sentence, fees = Config.Fees, portal = Config.PortalCommand, tablet = Config.Command,
        maxImage = (Config.Images or {}).maxBytes or 420000, judgeOnly = (Config.Warrants or {}).judgeOnly == true,
    }
end

local function openScreen(which, extra)
    if open or opening then
        if open and mode ~= which then notify('Close the other window first', 'error') end
        return
    end
    if wc():IsAnyScreenOpen() then return notify('Close what is open first', 'error') end
    opening = true
    local data, why
    if which == 'tablet' then data, why = wc():Callback('es_doj:dashboard', {})
    else data, why = wc():Callback('es_doj:pub:home', {}) end
    opening = false
    if type(data) ~= 'table' then return notify(why or 'Not available', 'error') end
    if open or wc():IsAnyScreenOpen() then return end
    open, mode = true, which
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    wc():SetScreenOpen(true, SCREEN)
    SendNUIMessage({ action = 'open', mode = which, data = data, lists = lists(), extra = extra })
end

RegisterCommand(Config.Command or 'doj', function() CreateThread(function() openScreen('tablet') end) end, false)
if Config.Key and Config.Key ~= '' then RegisterKeyMapping(Config.Command or 'doj', 'Open the DOJ tablet', 'keyboard', Config.Key) end
RegisterCommand(Config.PortalCommand or 'court', function() CreateThread(function() openScreen('portal') end) end, false)

-- 1.1.0: the DOJ is part of the MDT. es_mdt opens this (its Court page, the DOJ department picked, or /mdt for a
-- DOJ member); "Police MDT" here goes back for someone who is in a police department too.
AddEventHandler('es_doj:client:openTablet', function() CreateThread(function() openScreen('tablet') end) end)
exports('OpenTablet', function() CreateThread(function() openScreen('tablet') end) end)
RegisterNUICallback('toMdt', function(_, cb)
    cb({ ok = true })
    if mode ~= 'tablet' then return end
    close()
    if GetResourceState('es_mdt') ~= 'started' then return notify('The MDT is not running', 'error') end
    CreateThread(function() Wait(150) TriggerEvent('es_mdt:client:openLaw') end)
end)

-- Page -> server. Only these names pass: 'es_doj:<name>' (tablet) and 'es_doj:pub:<name>' (portal).
local TABLET, PUB = {}, {}
for _, n in ipairs({ 'people', 'person', 'roll', 'rollImage', 'recordSeal', 'fees', 'feeCreate', 'feeVoid', 'petitions', 'petition', 'petitionDecide',
    'businesses', 'businessAct', 'businessCreate', 'noticeSend', 'dashboard', 'calendar', 'judges', 'penal', 'penalSave', 'permits', 'permitPhoto',
    'permitCheck', 'permitDecide', 'activity', 'bar', 'barIssue', 'barAct', 'clients', 'clientAdd', 'clientEnd', 'cases', 'case', 'reportLookup',
    'caseCreate', 'caseUpdate', 'caseCharges', 'hearingSave', 'hearingAct', 'transcript', 'transcriptAdd', 'filingSave', 'filingImage', 'evidenceImage',
    'filingRule', 'pleaOffer', 'pleaAct', 'verdict', 'sentence', 'caseClose', 'caseReopen', 'bail', 'appealFile', 'appealRule', 'caseSeal',
    'subpoenaSave', 'subpoenaAct', 'benchWarrant', 'warrants', 'warrant', 'warrantDecide', 'warrantIssue', 'warrantRecall' }) do TABLET[n] = true end
for _, n in ipairs({ 'home', 'case', 'filingImage', 'noticeRead', 'pay', 'payFine', 'people', 'billsFor', 'plea', 'petition', 'myRecords', 'civil',
    'appeal', 'lawyers', 'hire', 'fire', 'publicDefender', 'records' }) do PUB[n] = true end

RegisterNUICallback('call', function(d, cb)
    local name = type(d) == 'table' and d.name
    if not open then return cb({ ok = false, why = 'Closed' }) end
    local full
    if mode == 'tablet' and TABLET[name] then full = 'es_doj:' .. name
    elseif mode == 'portal' and PUB[name] then full = 'es_doj:pub:' .. name end
    if not full then return cb({ ok = false, why = 'Unknown call' }) end
    CreateThread(function()
        local res, why = wc():Callback(full, type(d.data) == 'table' and d.data or {})
        if res == false or res == nil then cb({ ok = false, why = why or 'That did not work' }) else cb({ ok = true, data = res }) end
    end)
end)

RegisterNUICallback('close', function(_, cb) close() cb({ ok = true }) end)
RegisterNUICallback('waypoint', function(d, cb)
    local x, y = tonumber(type(d) == 'table' and d.x), tonumber(type(d) == 'table' and d.y)
    if x and y then SetNewWaypoint(x + 0.0, y + 0.0) end
    cb({ ok = x ~= nil })
end)
RegisterNUICallback('logo', function(d, cb)
    CreateThread(function()
        local ok, data = pcall(function() return exports.es_departments:GetLogo(tonumber(d.id), tonumber(d.ver)) end)
        cb({ ok = ok and data and true or false, data = ok and data or nil })
    end)
end)

RegisterNetEvent('es_doj:client:refresh', function(what)
    if open then SendNUIMessage({ action = 'refresh', what = what }) end
end)
RegisterNetEvent('es_doj:client:notices', function()
    if open and mode == 'portal' then SendNUIMessage({ action = 'refresh', what = 'notices' }) end
end)

-- ---------------------------------------------------------------- the courthouse window
local added = {}
local function addDesks(P)
    for _, k in ipairs(added) do pcall(function() wc():RemoveAction(k) end) end
    added = {}
    for _, d in ipairs(P.desks or {}) do
        local key = 'es_doj:desk:' .. d.i
        local ok = wc():AddAction({
            id = key, at = { coords = vector3(d.x, d.y, d.z + 0.2) }, label = d.label or 'Court clerk', icon = 'E',
            description = P.label, reach = 2.0, seeFrom = 6.0,
            options = {
                { id = 'portal', label = 'Court services (cases, payments, petitions)', onSelect = function() openScreen('portal', { desk = d.i }) end },
                { id = 'pay', label = 'Pay a fine, fee or bail', onSelect = function() openScreen('portal', { desk = d.i, view = 'pay' }) end },
            },
        })
        if ok then added[#added + 1] = key end
    end
end

Whip.register(function()
    CreateThread(function()
        Wait(2500)
        -- 1.1.0: ask once a character is loaded (no refused calls from the character screen, and no 5-minute give-up)
        local tries = 0
        while tries < 20 do
            if wc():IsPlayerLoaded() then
                local P = wc():Callback('es_doj:pub:places')
                if P then addDesks(P) return end
                tries = tries + 1
            end
            Wait(3000)
        end
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if open then SetNuiFocus(false, false) end
    open = false
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
