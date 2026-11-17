local _ENV = ESAPP('mdt'); -- es_mdt 1.8.0: firearm permits for civilians. A prompt at each Config.Permits.desks spot and /permit open a small
-- application form (reason + a required photo: upload, drop, link or camera roll, with a live preview) and show
-- the status of their permit / latest application.
local function wc() return exports.whip_core end
local function notify(text, kind) wc():Notify(text, kind or 'inform') end
local SCREEN = 'es_mdt_permit'
local added, formOpen = {}, false

local function statusText(r)
    if not r then return 'No answer' end
    local lic, app = r.license, (r.apps or {})[1]
    local L = r.label or 'Firearm permit'
    if lic and lic.status == 'active' then return ('You hold an active %s%s.'):format(L, lic.origin == 'department' and ' (department issued)' or '') end
    if app and app.status == 'pending' then return ('Application #%d is waiting for review.'):format(app.id) end
    if app and app.status == 'denied' then return ('Application #%d was denied%s.'):format(app.id, app.decisionNote and (': ' .. app.decisionNote) or '') end
    if lic then return ('Your %s is %s.'):format(L, lic.status) end
    return ('You have no %s. Apply here (fee $%d when approved).'):format(L, r.fee or 0)
end

local function closeForm()
    if not formOpen then return end
    formOpen = false
    SetNuiFocus(false, false)
    wc():SetScreenOpen(false, SCREEN)
    SendNUIMessage({ action = 'permitAppClose' })
end

local function openForm(desk)
    if formOpen then return end
    if wc():IsAnyScreenOpen() then return notify('Close what is open first', 'error') end
    local st, why = wc():Callback('es_mdt:permitStatus')
    if not st then return notify(why or 'Permits are not available', 'error') end
    formOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    wc():SetScreenOpen(true, SCREEN)
    SendNUIMessage({ action = 'permitApp', data = { desk = desk or 0, status = st, text = statusText(st), roll = GetResourceState('es_evidence') == 'started' } })
end

RegisterNUICallback('permitSubmit', function(d, cb)
    if not formOpen then return cb({ ok = false, why = 'The form is closed' }) end
    CreateThread(function()
        d = type(d) == 'table' and d or {}
        local r, why = wc():Callback('es_mdt:permitApply', { reason = d.reason, desk = d.desk, mode = d.mode, image = d.image, url = d.url, photoId = d.photoId })
        if r then notify(('%s application #%d filed. You are told when it is decided.'):format('Permit', r.id), 'success') end
        cb(r and { ok = true, data = r } or { ok = false, why = why or 'Could not apply' })
    end)
end)
RegisterNUICallback('permitRoll', function(d, cb)
    if not formOpen then return cb({ ok = false }) end
    CreateThread(function()
        local r, why = wc():Callback('es_mdt:permitRoll', type(d) == 'table' and d or {})
        cb(r and { ok = true, data = r } or { ok = false, why = why })
    end)
end)
RegisterNUICallback('permitClose', function(_, cb) closeForm() cb({ ok = true }) end)

local function addDesks(D)
    for _, k in ipairs(added) do wc():RemoveAction(k) end
    added = {}
    if not D.enabled then return end
    for _, d in ipairs(D.desks or {}) do
        local key = 'es_mdt:permitdesk:' .. d.i
        local ok = wc():AddAction({
            id = key, at = { coords = vector3(d.x, d.y, d.z + 0.2) }, label = d.label or 'Front desk', icon = 'E',
            description = D.label, reach = 2.0, seeFrom = 6.0,
            options = {
                { id = 'apply', label = 'Apply for a ' .. (D.label or 'firearm permit'):lower(), onSelect = function() openForm(d.i) end },
                { id = 'status', label = 'My permit status', onSelect = function(ctx)
                    local r, why = wc():Callback('es_mdt:permitStatus')
                    if r then ctx.status(statusText(r), 6000) else ctx.refuse(why) end
                end },
            },
        })
        if ok then added[#added + 1] = key end
    end
end

local cmdOk = true
Whip.register(function()
    CreateThread(function()
        Wait(2000)
        -- 1.9.1: ask once a character is loaded (no refused calls from the character screen, and no 5-minute give-up)
        local tries = 0
        while tries < 20 do
            if wc():IsPlayerLoaded() then
                local D = wc():Callback('es_mdt:permitDesks')
                if D then cmdOk = D.command ~= false addDesks(D) return end
                tries = tries + 1
            end
            Wait(3000)
        end
    end)
end)

-- /permit: the form (when Config.Permits.command), else just the status
RegisterCommand('permit', function()
    if cmdOk then return openForm(0) end
    local r, why = wc():Callback('es_mdt:permitStatus')
    notify(r and statusText(r) or (why or 'No answer'), 'inform')
end, false)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    closeForm()
    for _, k in ipairs(added) do pcall(function() wc():RemoveAction(k) end) end
end)
