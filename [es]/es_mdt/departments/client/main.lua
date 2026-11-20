local _ENV = ESAPP('departments'); -- es_departments client: the /departments screen, and department logos for anyone who asks.

local open = false
local opening = false
-- One name for this screen, used by EVERY SetScreenOpen call: open with one key and close with another and WHIP
-- keeps the screen "open" for good (chat, prompts and hotkeys stay away until the resource stops). Fixed 1.1.1.
local SCREEN = 'departments'
local Logos = {}   -- [deptId] = { ver = n, data = 'data:image/...' }
local fetching = {}

local function wc() return exports.whip_core end

local function notify(text, kind) wc():Notify(text, kind or 'inform') end

--- A department's logo (data URL), fetched part by part and kept until its version changes. Waits.
local function getLogo(id, ver)
    local have = Logos[id]
    if have and (ver == nil or have.ver == ver) then return have.data, have.ver end
    while fetching[id] do Wait(50) end
    have = Logos[id]
    if have and (ver == nil or have.ver == ver) then return have.data, have.ver end
    fetching[id] = true
    local first, why = wc():Callback('es_departments:logo', id, 1)
    if type(first) ~= 'table' then fetching[id] = nil return false, why end
    if (first.total or 0) == 0 then
        Logos[id] = { ver = first.ver, data = false }
        fetching[id] = nil
        return false, 'No logo'
    end
    local parts = { first.part }
    for i = 2, first.total do
        local p = wc():Callback('es_departments:logo', id, i)
        if type(p) ~= 'table' or p.ver ~= first.ver then fetching[id] = nil return false, 'The logo changed while loading' end
        parts[i] = p.part
    end
    Logos[id] = { ver = first.ver, data = table.concat(parts) }
    fetching[id] = nil
    return Logos[id].data, first.ver
end

exports('GetLogo', function(id, ver)
    local data, v = getLogo(id, ver)
    if not data then return false, v end
    return data, v
end)

--- Give the keyboard and mouse back and tell WHIP the screen is gone. Safe to call any number of times.
local function release()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    wc():SetScreenOpen(false, SCREEN)
    wc():SetScreenOpen(false)   -- 1.1.0 claimed under SCREEN but released 'default'; harmless either way
end

local function close()
    local was = open
    open = false
    release()
    if was then SendNUIMessage({ action = 'close' }) end
end

local function openScreen()
    if open or opening then return end
    if wc():IsAnyScreenOpen() then return notify('Close what is open first', 'error') end
    opening = true
    local data, why = wc():Callback('es_departments:open')
    opening = false
    if type(data) ~= 'table' then return notify(why or 'Departments are not available', 'error') end
    if open or wc():IsAnyScreenOpen() then return end   -- something else opened while we waited
    open = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    wc():SetScreenOpen(true, SCREEN)
    SendNUIMessage({ action = 'open', data = data })
end

RegisterCommand(Config.Command, function()
    CreateThread(openScreen)
end, false)

-- Page -> game. Each answers { ok, data } or { ok = false, why }.
local function answer(cb, ok, why)
    if ok == false or ok == nil then cb({ ok = false, why = why or 'That did not work' }) else cb({ ok = true, data = ok }) end
end

local function ask(name, ...)
    local args = table.pack(...)
    return function(cb)
        CreateThread(function()
            local res, why = wc():Callback(name, table.unpack(args, 1, args.n))
            answer(cb, res, why)
        end)
    end
end

RegisterNUICallback('close', function(_, cb) close() cb({ ok = true }) end)

-- 2.2.0: "Set up locations": the job pack's station editor (whip_jobs; es_jobs before 0.5.0), on this department
RegisterNUICallback('jobsLocations', function(d, cb)
    local res = EsSuite.jobsRes(true)
    if not res then return cb({ ok = false, why = 'The job pack (whip_jobs) is not running on this server' }) end
    close()
    cb({ ok = true })
    local jobId = type(d) == 'table' and tonumber(d.jobId) or nil
    local starter = type(d) == 'table' and d.starter == true   -- 2.4.0: a new department: its usual spots, placed one after another
    CreateThread(function() Wait(200) exports[res]:OpenStations({ jobId = jobId, starter = starter or nil }) end)
end)

-- 2.4.0: the spots (and their peds) a department of this type gets on New department, from the job pack
RegisterNUICallback('jobsStarter', function(d, cb)
    local res = EsSuite.jobsRes(true)
    if not res then return cb({ ok = true, data = false }) end
    local ok, list = pcall(function() return exports[res]:GetStarter(type(d) == 'table' and tostring(d.type or '') or '') end)
    cb({ ok = true, data = ok and type(list) == 'table' and list or false })
end)

RegisterNUICallback('reload', function(_, cb)
    CreateThread(function()
        local data, why = wc():Callback('es_departments:open')
        answer(cb, data, why)
    end)
end)

RegisterNUICallback('get', function(d, cb) ask('es_departments:get', tonumber(d.id))(cb) end)
RegisterNUICallback('health', function(_, cb) ask('es_departments:health')(cb) end)
RegisterNUICallback('create', function(d, cb) ask('es_departments:create', d.data)(cb) end)
RegisterNUICallback('update', function(d, cb) ask('es_departments:update', tonumber(d.id), d.data)(cb) end)
RegisterNUICallback('rankSave', function(d, cb) ask('es_departments:rankSave', tonumber(d.id), tonumber(d.roleId) or 0, d.data, d.perms or {})(cb) end)
RegisterNUICallback('hire', function(d, cb) ask('es_departments:hire', tonumber(d.id), tonumber(d.target), tonumber(d.roleId))(cb) end)
RegisterNUICallback('setRank', function(d, cb) ask('es_departments:setRank', tonumber(d.id), tonumber(d.charId), tonumber(d.roleId))(cb) end)
RegisterNUICallback('member', function(d, cb) ask('es_departments:member', tonumber(d.id), tonumber(d.charId), d.data)(cb) end)

-- Asked first in a WHIP dialog over the screen, then focus comes back to the page
local function confirmThen(title, text, name, ...)
    local args = table.pack(...)
    return function(cb)
        CreateThread(function()
            local yes = wc():Confirm(title, text, 'Yes', 'Cancel')
            if not open then return cb({ ok = false, why = 'closed', quiet = true }) end   -- closed during the dialog: never grab focus back
            SetNuiFocus(true, true)
            if yes ~= true then return cb({ ok = false, why = 'cancelled', quiet = true }) end
            local res, why = wc():Callback(name, table.unpack(args, 1, args.n))
            answer(cb, res, why)
        end)
    end
end

RegisterNUICallback('delete', function(d, cb)
    local alsoJob = d.alsoJob == true
    confirmThen('Delete department', alsoJob
        and 'Delete this department AND its WHIP job (ranks and staff list go too)?'
        or 'Delete this department? Its WHIP job, ranks and staff stay.', 'es_departments:delete', tonumber(d.id), alsoJob)(cb)
end)
RegisterNUICallback('rankDelete', function(d, cb)
    confirmThen('Delete rank', 'Delete this rank? Nobody may hold it.', 'es_departments:rankDelete', tonumber(d.id), tonumber(d.roleId))(cb)
end)
RegisterNUICallback('fire', function(d, cb)
    confirmThen('Remove from department', 'Remove this person from the department?', 'es_departments:fire', tonumber(d.id), tonumber(d.charId))(cb)
end)

-- A logo the page has already made 256 px webp/png: sent in parts
RegisterNUICallback('logo', function(d, cb)
    CreateThread(function()
        local id, dataUrl = tonumber(d.id), d.dataUrl
        if type(dataUrl) ~= 'string' or not id then return cb({ ok = false, why = 'No picture' }) end
        local size = 15000
        local total = math.ceil(#dataUrl / size)
        if total > 24 then return cb({ ok = false, why = 'That logo is too big' }) end
        local res, why
        for i = 1, total do
            res, why = wc():Callback('es_departments:logoPart', id, i, total, dataUrl:sub((i - 1) * size + 1, i * size))
            if not res then return cb({ ok = false, why = why }) end
        end
        if type(res) == 'table' and res.done then
            Logos[id] = { ver = res.logoVer, data = dataUrl }
            return cb({ ok = true, data = res })
        end
        cb({ ok = false, why = 'The logo did not arrive whole' })
    end)
end)

-- A picture from a link that the page could not read itself: the server fetches it, the page shrinks it
RegisterNUICallback('urlFetch', function(d, cb)
    CreateThread(function()
        local head, why = wc():Callback('es_departments:urlFetch', tonumber(d.id) or 0, tostring(d.url or ''))
        if type(head) ~= 'table' then return cb({ ok = false, why = why or 'That link did not load' }) end
        local parts = {}
        for i = 1, head.total do
            local part, pwhy = wc():Callback('es_departments:urlPart', i)
            if type(part) ~= 'string' then return cb({ ok = false, why = pwhy or 'The picture stopped loading' }) end
            parts[i] = part
        end
        cb({ ok = true, data = table.concat(parts) })
    end)
end)

RegisterNUICallback('logoFetch', function(d, cb)
    CreateThread(function()
        local data = getLogo(tonumber(d.id), tonumber(d.ver))
        cb({ ok = data and true or false, data = data or nil })
    end)
end)

RegisterNetEvent('es_departments:client:changed', function(id)
    if open then SendNUIMessage({ action = 'changed', id = id }) end
end)

-- Every way out: the resource stopping, and whip_core taking the screen away
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        open = false
        SetNuiFocus(false, false)   -- whip_core drops this resource's screen claims by itself
    end
end)

-- If the page ever goes away while we think it is up (an error in it), the game is never left without keys
CreateThread(function()
    local misses = 0
    while true do
        Wait(1000)
        misses = (open and not IsNuiFocused()) and misses + 1 or 0
        if misses >= 2 then misses = 0 close() end   -- two in a row: a dialog handing focus back is never this slow
    end
end)
AddEventHandler('whip_core:player:died', function() close() end)
AddEventHandler('whip_core:player:logout', function() close() end)
