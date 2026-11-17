-- es_jail 1.0.2 client: staff test mode (the test suspect NPC, the TEST MODE tag) and /jaildebug (draws the fence,
-- spawns, job board, job spots and release point). The server decides who may; this only acts and draws.

local wc, notify = JLC.wc, JLC.notify
local PR, JB, IT = Config.Prison, Config.Jobs, Config.Items

local Peds = {}          -- [netId] = { mode = 'soft'|'hard'|nil, escort = bool }
local ACT = 'es_jail:testped'
local actAdded = false

local function entOf(net)
    local t = GetGameTimer() + 2000
    while not NetworkDoesNetworkIdExist(net) and GetGameTimer() < t do Wait(50) end
    if not NetworkDoesNetworkIdExist(net) then return nil end
    local ent = NetworkGetEntityFromNetworkId(net)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
    NetworkRequestControlOfEntity(ent)
    t = GetGameTimer() + 1500
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() < t do Wait(25) NetworkRequestControlOfEntity(ent) end
    return ent
end

-- Cuffed poses (checked against the game's anim list): hard = hands behind, soft = hands in front.
local POSE = {
    hard = { 'mp_arresting', 'idle' },
    soft = { 'anim@move_m@prisoner_cuffed', 'idle' },
}
local BUSY = { -- one-off anims the keep-pose loop must not cut short
    { 'mp_arrest_paired', 'crook_p2_back_right' },
    { 'random@rescue_hostage', 'girl_struggle_loop' },
}
local Frozen = {}         -- [ent] = true while we hold a hard-cuffed NPC in place

local function cuffAnim(ent, mode)
    local a = POSE[mode] or POSE.hard
    if JLC.loadDict(a[1]) then
        -- 49 = loop + upper body + keep moving: the arms hold the pose while escorted or walking
        TaskPlayAnim(ent, a[1], a[2], 8.0, -8.0, -1, 49, 0.0, false, false, false)
        SetPedKeepTask(ent, true)
    end
end
local function stopCuffAnim(ent)
    for _, a in pairs(POSE) do StopAnimTask(ent, a[1], a[2], 2.0) end
    SetEnableHandcuffs(ent, false)
    if Frozen[ent] then FreezeEntityPosition(ent, false) Frozen[ent] = nil end
end

local function letGo(ent, net)
    if IsEntityAttached(ent) then DetachEntity(ent, true, false) end
    if Peds[net] then Peds[net].escort = false end
end

-- ---------------------------------------------------------------- what the server asks of the NPC
RegisterNetEvent('es_jail:npcDo', function(net, what, extra)
    local ent = entOf(net)
    if not ent then return end
    Peds[net] = Peds[net] or {}
    local p = Peds[net]
    if what == 'setup' then
        SetBlockingOfNonTemporaryEvents(ent, true)
        SetPedFleeAttributes(ent, 0, false)
        SetPedCombatAttributes(ent, 17, true)
        SetEntityInvincible(ent, true)
        SetPedCanRagdollFromPlayerImpact(ent, false)
        TaskStandStill(ent, -1)
    elseif what == 'crook' then
        local cop = JLC.pedOf(extra) or PlayerPedId()
        if JLC.loadDict('mp_arrest_paired') then
            letGo(ent, net)
            AttachEntityToEntity(ent, cop, 11816, -0.1, 0.45, 0.0, 0.0, 0.0, 20.0, false, false, false, false, 20, false)
            TaskPlayAnim(ent, 'mp_arrest_paired', 'crook_p2_back_right', 8.0, -8.0, 3800, 32, 0.0, false, false, false)
            SetTimeout(2600, function() if DoesEntityExist(ent) then DetachEntity(ent, true, false) end end)
        end
    elseif what == 'cuffed' then
        p.mode = extra
        ClearPedTasks(ent)
        SetBlockingOfNonTemporaryEvents(ent, true)
        SetEnableHandcuffs(ent, true)
        cuffAnim(ent, extra)
    elseif what == 'idle' then
        p.mode = nil
        letGo(ent, net)
        stopCuffAnim(ent)
        TaskStandStill(ent, -1)
    elseif what == 'struggle' then
        if not IsEntityAttached(ent) and not IsPedInAnyVehicle(ent, false) and JLC.loadDict('random@rescue_hostage') then
            TaskPlayAnim(ent, 'random@rescue_hostage', 'girl_struggle_loop', 8.0, -8.0, 3500, 49, 0.0, false, false, false)
        end
    elseif what == 'flee' then
        p.mode = nil
        letGo(ent, net)
        stopCuffAnim(ent)
        FreezeEntityPosition(ent, false)
        if IsPedInAnyVehicle(ent, false) then TaskLeaveVehicle(ent, GetVehiclePedIsIn(ent, false), 256) Wait(1500) end
        TaskSmartFleePed(ent, PlayerPedId(), 120.0, -1, false, false)
    elseif what == 'jail' then
        p.mode = nil
        letGo(ent, net)
        stopCuffAnim(ent)
        FreezeEntityPosition(ent, false)
        ClearPedTasksImmediately(ent)
        SetEntityCoords(ent, extra.x + 0.0, extra.y + 0.0, extra.z - 0.95, false, false, false, false)
        SetEntityHeading(ent, (extra.w or 0.0) + 0.0)
        TaskStandStill(ent, -1)
    end
end)

-- Keep cuffed test NPCs in their pose. Driven by the entity's own state (esTest = its tester, esCuffed = 'mode:kind'),
-- so it holds even if an event was missed or the NPC streamed in late. Control is asked for every pass, not assumed.
local function cuffedMode(ent)
    local v = Entity(ent).state.esCuffed
    return type(v) == 'string' and v:match('^(%a+):') or nil
end
local function busy(ent)
    for _, a in ipairs(BUSY) do if IsEntityPlayingAnim(ent, a[1], a[2], 3) then return true end end
    return false
end
CreateThread(function()
    local me
    while true do
        Wait(400)
        me = me or GetPlayerServerId(PlayerId())
        for ent in pairs(Frozen) do
            if not DoesEntityExist(ent) then Frozen[ent] = nil end
        end
        for _, ent in ipairs(GetGamePool('CPed')) do
            if not IsPedAPlayer(ent) and Entity(ent).state.esTest == me then
                local mode = cuffedMode(ent)
                if not NetworkHasControlOfEntity(ent) then
                    NetworkRequestControlOfEntity(ent)
                elseif mode then
                    SetBlockingOfNonTemporaryEvents(ent, true)
                    SetPedKeepTask(ent, true)
                    SetEnableHandcuffs(ent, true)
                    SetPedCanPlayGestureAnims(ent, false)
                    local inCar, attached = IsPedInAnyVehicle(ent, false), IsEntityAttached(ent)
                    -- hard cuffs: planted where they stand (unless escorted or seated)
                    local hold = mode == 'hard' and not attached and not inCar
                    if hold and not Frozen[ent] then FreezeEntityPosition(ent, true) Frozen[ent] = true
                    elseif not hold and Frozen[ent] then FreezeEntityPosition(ent, false) Frozen[ent] = nil end
                    if not inCar and not busy(ent) then
                        local a = POSE[mode] or POSE.hard
                        if not IsEntityPlayingAnim(ent, a[1], a[2], 3) then
                            local other = POSE[mode == 'soft' and 'hard' or 'soft']
                            StopAnimTask(ent, other[1], other[2], 1.0)
                            cuffAnim(ent, mode)
                        end
                    end
                elseif Frozen[ent] then
                    FreezeEntityPosition(ent, false)
                    Frozen[ent] = nil
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------- escort / car (client only: WHIP's escort is for players)
local function escort(ent, net)
    local me = PlayerPedId()
    if IsPedInAnyVehicle(me, false) then return notify('Get out of the car first', 'error') end
    NetworkRequestControlOfEntity(ent)
    if Frozen[ent] then FreezeEntityPosition(ent, false) Frozen[ent] = nil end
    AttachEntityToEntity(ent, me, 11816, 0.54, 0.54, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    Peds[net] = Peds[net] or {}
    Peds[net].escort = true
end

local function nearestCar(at, range)
    local best, bd
    for _, v in ipairs(GetGamePool('CVehicle')) do
        local d = #(GetEntityCoords(v) - at)
        if d <= range and (not bd or d < bd) then best, bd = v, d end
    end
    return best
end

local function seat(ent, net)
    local veh = nearestCar(GetEntityCoords(PlayerPedId()), 7.0)
    if not veh then return notify('No car within 7 m', 'error') end
    if GetVehicleDoorLockStatus(veh) == 2 then return notify('That car is locked', 'error') end
    local seatIx
    for _, s in ipairs({ 1, 2, 0 }) do if IsVehicleSeatFree(veh, s) then seatIx = s break end end
    if not seatIx then return notify('No free seat', 'error') end
    letGo(ent, net)
    NetworkRequestControlOfEntity(ent)
    if Frozen[ent] then FreezeEntityPosition(ent, false) Frozen[ent] = nil end
    TaskWarpPedIntoVehicle(ent, veh, seatIx)
    notify('[TEST] Seated in the car', 'success')
end

local function takeOut()
    local me = GetEntityCoords(PlayerPedId())
    for net in pairs(Peds) do
        if NetworkDoesNetworkIdExist(net) then
            local ent = NetworkGetEntityFromNetworkId(net)
            if ent ~= 0 and IsPedInAnyVehicle(ent, false) and #(GetEntityCoords(ent) - me) < 6.0 then
                NetworkRequestControlOfEntity(ent)
                local veh = GetVehiclePedIsIn(ent, false)
                local out = GetOffsetFromEntityInWorldCoords(veh, -2.2, -0.6, 0.0)
                ClearPedTasksImmediately(ent)
                SetEntityCoords(ent, out.x, out.y, out.z, false, false, false, false)
                Wait(200)
                escort(ent, net)
                notify('[TEST] Pulled out and escorting', 'success')
                return
            end
        end
    end
    notify('No test suspect in a car near you', 'error')
end

-- ---------------------------------------------------------------- the prompt on a test NPC
local function testNet(ctx)
    local e = ctx and ctx.entity
    if not e or ctx.player or not DoesEntityExist(e) or not IsEntityAPed(e) then return nil end
    if not Entity(e).state.esTest then return nil end
    return NetworkGetNetworkIdFromEntity(e)
end
local function stOf(ctx)
    local e = ctx.entity
    local v = e and Entity(e).state.esCuffed
    if type(v) ~= 'string' then return nil end
    local mode, kind = v:match('^(%a+):(%a+)$')
    return mode and { mode = mode, kind = kind } or nil
end
local function send(action) return function(ctx) local n = testNet(ctx) if n then TriggerServerEvent('es_jail:testNpc', n, action) end end end

local function addAct()
    if actAdded then return end
    local ok = wc():AddAction({
        id = ACT, at = { aimBox = 'ped' }, icon = 'E', reach = 3.0,
        label = 'Test suspect',
        canInteract = function(ctx) return testNet(ctx) ~= nil end,
        options = {
            -- 1.1.0: short prompt: the cuff kinds under "Cuff ›", the rarer actions under "More ›"
            { id = 'cuffm', label = 'Cuff ›', canInteract = function(ctx) return not stOf(ctx) end,
                options = {
                    { id = 'soft', label = 'Cuff (can walk)', require = { item = IT.cuffs }, onSelect = send('soft') },
                    { id = 'hard', label = 'Hard cuff (held still)', require = { item = IT.cuffs }, onSelect = send('hard') },
                    { id = 'zip', label = 'Zip-tie', require = { item = IT.ziptie }, onSelect = send('zip') },
                } },
            { id = 'uncuff', label = function(ctx) local s = stOf(ctx) return s and s.kind == 'ziptie' and 'Cut ties' or 'Uncuff' end,
                canInteract = function(ctx) return stOf(ctx) ~= nil end, onSelect = send('uncuff') },
            { id = 'escort', label = function(ctx) return ctx.entity and IsEntityAttached(ctx.entity) and 'Stop escort' or 'Escort' end,
                canInteract = function(ctx) return stOf(ctx) ~= nil end,
                onSelect = function(ctx)
                    local n = testNet(ctx)
                    if not n then return end
                    if IsEntityAttached(ctx.entity) then letGo(ctx.entity, n) else escort(ctx.entity, n) end
                end },
            { id = 'seat', label = 'Put in car', canInteract = function(ctx) return stOf(ctx) ~= nil end,
                onSelect = function(ctx) local n = testNet(ctx) if n then seat(ctx.entity, n) end end },
            { id = 'more', label = 'More ›', canInteract = function(ctx) return stOf(ctx) ~= nil end,
                options = {
                    { id = 'tohard', label = 'Hold still', canInteract = function(ctx) local s = stOf(ctx) return s and s.mode == 'soft' end, onSelect = send('tohard') },
                    { id = 'tosoft', label = 'Let walk', canInteract = function(ctx) local s = stOf(ctx) return s and s.mode == 'hard' end, onSelect = send('tosoft') },
                    { id = 'search', label = 'Search', onSelect = send('search') },
                } },
            { id = 'jail', label = 'Send to jail', canInteract = function(ctx) return stOf(ctx) ~= nil end, onSelect = send('jail') },
        },
    })
    actAdded = ok and true or false
end
local function removeAct()
    if not actAdded then return end
    pcall(function() wc():RemoveAction(ACT) end)
    actAdded = false
end

local testOn = false
RegisterNetEvent('es_jail:testTag', function(on)
    testOn = on and true or false
    JLC.ui({ t = 'test', on = testOn })
    if testOn then addAct() else removeAct() end
end)

-- the F1 wheel while testing: let go of the escorted suspect, pull them out of a car
CreateThread(function()
    Wait(1200)
    wc():AddAction({ id = 'es_jail:test_letgo', at = { radial = true }, label = 'Stop escort', icon = 'hand',
        canInteract = function() for _, p in pairs(Peds) do if p.escort then return true end end return false end,
        onSelect = function() for net, p in pairs(Peds) do if p.escort and NetworkDoesNetworkIdExist(net) then letGo(NetworkGetEntityFromNetworkId(net), net) end end end })
    wc():AddAction({ id = 'es_jail:test_out', at = { radial = true }, label = 'Take out of car', icon = 'car',
        canInteract = function()
            if not testOn then return false end
            local me = GetEntityCoords(PlayerPedId())
            for net in pairs(Peds) do
                if NetworkDoesNetworkIdExist(net) then
                    local ent = NetworkGetEntityFromNetworkId(net)
                    if ent ~= 0 and IsPedInAnyVehicle(ent, false) and #(GetEntityCoords(ent) - me) < 6.0 then return true end
                end
            end
            return false
        end,
        onSelect = function() takeOut() end })
end)

-- an escorted test NPC is let go when you get in a car or die
CreateThread(function()
    while true do
        Wait(500)
        local me = PlayerPedId()
        if IsPedInAnyVehicle(me, false) or IsEntityDead(me) then
            for net, p in pairs(Peds) do if p.escort and NetworkDoesNetworkIdExist(net) then letGo(NetworkGetEntityFromNetworkId(net), net) end end
        end
    end
end)

-- ---------------------------------------------------------------- /jaildebug
local debugOn = false
local function txt(x, y, z, s)
    local on, sx, sy = World3dToScreen2d(x, y, z)
    if not on then return end
    SetTextScale(0.32, 0.32) SetTextFont(4) SetTextCentre(true) SetTextOutline() SetTextColour(255, 255, 255, 230)
    BeginTextCommandDisplayText('STRING') AddTextComponentSubstringPlayerName(s) EndTextCommandDisplayText(sx, sy)
end
local function pin(v, r, g, b, label)
    DrawMarker(28, v.x, v.y, v.z + 0.2, 0, 0, 0, 0, 0, 0, 0.35, 0.35, 0.35, r, g, b, 170, false, false, 2, false, nil, nil, false)
    DrawLine(v.x, v.y, v.z - 1.0, v.x, v.y, v.z + 6.0, r, g, b, 220)
    txt(v.x, v.y, v.z + 1.2, label)
end
local function insideZone(p)
    if p.z < (PR.zoneMinZ or -1000) or p.z > (PR.zoneMaxZ or 3000) then return false end
    local poly, x, y, inn = PR.zone, p.x, p.y, false
    local j = #poly
    for i = 1, #poly do
        local xi, yi, xj, yj = poly[i][1], poly[i][2], poly[j][1], poly[j][2]
        if ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi) then inn = not inn end
        j = i
    end
    return inn
end

RegisterNetEvent('es_jail:debug', function(on)
    debugOn = on and true or false
    if not debugOn then JLC.ui({ t = 'debug', on = false }) return end
    CreateThread(function()
        local lastIn, tick = nil, 0
        while debugOn do
            Wait(0)
            local me = GetEntityCoords(PlayerPedId())
            if #(me - PR.center) < 600.0 then
                local lo, hi = 44.0, 58.0
                local poly = PR.zone
                for i = 1, #poly do
                    local a, b = poly[i], poly[i % #poly + 1]
                    DrawLine(a[1], a[2], lo, b[1], b[2], lo, 255, 60, 60, 255)
                    DrawLine(a[1], a[2], hi, b[1], b[2], hi, 255, 60, 60, 255)
                    DrawLine(a[1], a[2], lo, a[1], a[2], hi, 255, 60, 60, 255)
                    -- extra rails every ~10 m so the wall reads from the ground
                    local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
                    for k = 1, math.floor(len / 10) do
                        local f = k * 10 / len
                        local x, y = a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f
                        DrawLine(x, y, lo, x, y, lo + 4.0, 255, 90, 90, 160)
                    end
                    txt(a[1], a[2], hi + 1.0, ('fence %d'):format(i))
                end
                for i, v in ipairs(PR.arrive) do pin(v, 80, 220, 120, 'spawn ' .. i) end
                pin(PR.board, 80, 150, 255, 'job board')
                pin(PR.release, 255, 255, 255, 'release (must be OUTSIDE)')
                for key, j in pairs(JB) do
                    if type(j) == 'table' and j.spots then for i, v in ipairs(j.spots) do pin(v, 255, 200, 60, ('%s %d'):format(j.label, i)) end end
                end
            end
            tick = tick + 1
            if tick % 15 == 0 then
                local inn = insideZone(me)
                if inn ~= lastIn then
                    lastIn = inn
                    JLC.ui({ t = 'debug', on = true, inside = inn, x = me.x, y = me.y, z = me.z })
                end
            end
        end
    end)
end)

AddEventHandler('onResourceStop', function(r)
    if r ~= GetCurrentResourceName() then return end
    removeAct()
end)
