local _ENV = ESAPP('mdt'); -- es_mdt 2.1.0: at the roadside, without the MDT.
--   /ticket (Config.Tickets.command, or the "Write a ticket" controller button): the ticket form. People and vehicles
--     close by are offered (the server checks each again), the charges come from the penal code.
--   /mdtimpound (Config.Impound.command, or the "Impound vehicle" button): the impound form for the vehicle the officer
--     stands by (the same form as the MDT's vehicle page). A car nobody owns is towed instead (a small payout).
--   The recipient of a citation is asked to sign (an overlay with the ticket; WHIP's Confirm when another screen is up).
--   Using the paper ticket item shows the ticket.
-- One screen name while any of these is up (SCREEN); nothing runs while none is.
local SCREEN = 'es_mdt_roadside'
local function wc() return exports.whip_core end
local function notify(text, kind) wc():Notify(text, kind or 'inform') end
local up = false        -- our overlay holds the focus
local signing = nil     -- the token we are asked to sign

local function TK() return type(Config.Tickets) == 'table' and Config.Tickets or {} end
local function IC() return type(Config.Impound) == 'table' and Config.Impound or {} end

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

--- networked vehicles within range, nearest first (at most 12)
local function vehiclesNear(range)
    local me = GetEntityCoords(PlayerPedId())
    local list = {}
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if NetworkGetEntityIsNetworked(veh) then
            local d = #(GetEntityCoords(veh) - me)
            if d <= range then list[#list + 1] = { veh = veh, d = d } end
        end
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    local out = {}
    for i = 1, math.min(12, #list) do out[i] = NetworkGetNetworkIdFromEntity(list[i].veh) end
    return out
end

--- the vehicle the officer means: the one they sit in, else the one in front of them, else the nearest
local function vehicleHere(range)
    local ped = PlayerPedId()
    local inVeh = GetVehiclePedIsIn(ped, false)
    if inVeh ~= 0 then return NetworkGetEntityIsNetworked(inVeh) and NetworkGetNetworkIdFromEntity(inVeh) or nil end
    local from = GetEntityCoords(ped)
    local to = GetOffsetFromEntityInWorldCoords(ped, 0.0, range, 0.0)
    local ray = StartShapeTestCapsule(from.x, from.y, from.z, to.x, to.y, to.z, 1.2, 2, ped, 7)
    local _, hit, _, _, ent = GetShapeTestResult(ray)
    if hit == 1 and ent ~= 0 and GetEntityType(ent) == 2 and NetworkGetEntityIsNetworked(ent) then return NetworkGetNetworkIdFromEntity(ent) end
    return vehiclesNear(range)[1]
end

local function show(msg)
    if not up then
        up = true
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false)
        wc():SetScreenOpen(true, SCREEN)
    end
    msg.action = 'roadside'
    SendNUIMessage(msg)
end

local function hide()
    if not up then return end
    up = false
    SetNuiFocus(false, false)
    wc():SetScreenOpen(false, SCREEN)
    SendNUIMessage({ action = 'roadsideClose' })
end

-- ---------------------------------------------------------------- the ticket form
local busy = false
local function openTicket()
    if busy or up then return end
    if TK().enabled == false then return notify('Roadside tickets are turned off', 'error') end
    if wc():IsAnyScreenOpen() then return notify('Close what is open first', 'error') end
    busy = true
    local data, why = wc():Callback('es_mdt:tkForm', { netIds = vehiclesNear((tonumber(TK().range) or 12.0) + 2.0) })
    busy = false
    if type(data) ~= 'table' then return notify(why or 'You cannot write tickets', 'error') end
    if wc():IsAnyScreenOpen() then return end
    show({ mode = 'ticket', data = data, location = streetHere() })
end

local function openImpound()
    if busy or up then return end
    if IC().enabled == false then return notify('Impounding is turned off', 'error') end
    if wc():IsAnyScreenOpen() then return notify('Close what is open first', 'error') end
    local nid = vehicleHere(tonumber(IC().range) or 8.0)
    if not nid then return notify('Stand by the vehicle first', 'error') end
    busy = true
    local data, why = wc():Callback('es_mdt:impForm', { netId = nid })
    busy = false
    if type(data) ~= 'table' then return notify(why or 'You cannot impound vehicles', 'error') end
    if wc():IsAnyScreenOpen() then return end
    show({ mode = 'impound', data = data, location = streetHere() })
end

RegisterCommand(TK().command or 'ticket', function() CreateThread(openTicket) end, false)
RegisterCommand(IC().command or 'mdtimpound', function() CreateThread(openImpound) end, false)
MDTC = MDTC or {}
MDTC.roadside = { ticket = function() CreateThread(openTicket) end, impound = function() CreateThread(openImpound) end }

-- ---------------------------------------------------------------- page -> server
local function relay(name, server, guard)
    RegisterNUICallback(name, function(d, cb)
        if guard and not guard() then return cb({ ok = false, why = 'The form is closed' }) end
        CreateThread(function()
            local r, why = wc():Callback('es_mdt:' .. server, type(d) == 'table' and d or {})
            if r == false or r == nil then cb({ ok = false, why = why or 'That did not work' }) else cb({ ok = true, data = r }) end
        end)
    end)
end
local function isUp() return up end
relay('rsIssue', 'tkIssue', isUp)
relay('rsStatus', 'tkStatus', isUp)
relay('rsImpSave', 'impSave', isUp)
relay('rsRefresh', 'tkForm', isUp)
RegisterNUICallback('rsNearby', function(_, cb) cb({ ok = true, data = { netIds = vehiclesNear((tonumber(TK().range) or 12.0) + 2.0), location = streetHere() } }) end)
RegisterNUICallback('rsClose', function(_, cb)
    if signing then
        local tok = signing
        signing = nil
        CreateThread(function() wc():Callback('es_mdt:tkSignAnswer', { token = tok, signed = false }) end)
    end
    hide()
    cb({ ok = true })
end)

-- the officer's form hears how the signature went
RegisterNetEvent('es_mdt:client:tkSigned', function(r)
    if up then SendNUIMessage({ action = 'roadsideSigned', data = r }) end
    if type(r) == 'table' then
        notify(r.sign == 'signed' and 'The ticket was signed' or ('Filed unsigned' .. (r.why and (' (' .. r.why .. ')') or '')), r.sign == 'signed' and 'success' or 'inform')
    end
end)

-- ---------------------------------------------------------------- signing (the recipient)
RegisterNetEvent('es_mdt:client:tkSign', function(d)
    if type(d) ~= 'table' or type(d.token) ~= 'string' then return end
    signing = d.token
    if up or not wc():IsAnyScreenOpen() then
        show({ mode = 'sign', data = d })
        return
    end
    -- another screen is up (their phone, a menu): WHIP's own confirm
    CreateThread(function()
        local t = d.ticket or {}
        local ok = wc():Confirm(('%s %s'):format(t.kindLabel or 'Ticket', t.number or ''),
            ('%s from %s. Sign it (you accept and will pay), or refuse (filed unsigned%s).'):format(t.total and t.total > 0 and ('$' .. t.total) or 'A ticket',
                t.officerName or 'an officer', d.contests and ': you may contest it' or ''), 'Sign', 'Refuse')
        if signing ~= d.token then return end
        signing = nil
        wc():Callback('es_mdt:tkSignAnswer', { token = d.token, signed = ok == true })
    end)
end)
RegisterNetEvent('es_mdt:client:tkSignClose', function(token)
    if signing == token then signing = nil end
    if up then SendNUIMessage({ action = 'roadsideSignGone', token = token }) end
end)
RegisterNUICallback('rsSign', function(d, cb)
    local tok = type(d) == 'table' and d.token
    if not tok or tok ~= signing then return cb({ ok = false, why = 'That ticket is no longer waiting for you' }) end
    signing = nil
    CreateThread(function()
        local r, why = wc():Callback('es_mdt:tkSignAnswer', { token = tok, signed = d.signed == true })
        cb(r and { ok = true } or { ok = false, why = why })
    end)
end)

-- ---------------------------------------------------------------- the paper (the item)
RegisterNetEvent('es_mdt:client:tkPaper', function(t)
    if type(t) ~= 'table' then return end
    if not up and wc():IsAnyScreenOpen() then return notify('Close what is open first', 'error') end
    show({ mode = 'paper', data = t })
end)

AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() and up then hide() end end)
