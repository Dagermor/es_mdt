-- es_jail 1.0.8 client: the jail timer on screen, teleports in and out, the job board and the job spots.

local wc, notify = JLC.wc, JLC.notify
local PR, JB = Config.Prison, Config.Jobs

local St = false          -- { remaining, total, cut, jobs, job = { key, label, verb, spot } | false } or false
local stAt = 0            -- GetGameTimer() when St came in
local boardAdded, spotKey = false, nil
local blip

RegisterNetEvent('es_jail:teleport', function(p, why)
    local ped = PlayerPedId()
    DoScreenFadeOut(500)
    local t = GetGameTimer() + 1500
    while not IsScreenFadedOut() and GetGameTimer() < t do Wait(10) end
    if IsPedInAnyVehicle(ped, false) then TaskLeaveVehicle(ped, GetVehiclePedIsIn(ped, false), 16) Wait(300) end
    DetachEntity(ped, true, false)
    RequestCollisionAtCoord(p.x, p.y, p.z)
    SetEntityCoords(ped, p.x + 0.0, p.y + 0.0, p.z + 0.0, false, false, false, false)
    SetEntityHeading(ped, (p.w or 0.0) + 0.0)
    t = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < t do Wait(20) end
    Wait(300)
    DoScreenFadeIn(700)
    if why == 'out' then SetNewWaypoint(PR.release.x + 60.0, PR.release.y) end
end)

local function removeBoard()
    if boardAdded then pcall(function() wc():RemoveAction('es_jail:board') end) boardAdded = false end
end
local function removeSpot()
    if spotKey then pcall(function() wc():RemoveAction('es_jail:spot') end) spotKey = nil end
end

local function addBoard()
    if boardAdded then return end
    local opts = {}
    for key, j in pairs(JB) do
        if type(j) == 'table' and j.spots then
            opts[#opts + 1] = { id = key, label = ('%s (−%ds a task)'):format(j.label, j.cut or 0),
                onSelect = function() TriggerServerEvent('es_jail:job', key) end }
        end
    end
    table.sort(opts, function(a, b) return a.id < b.id end)
    opts[#opts + 1] = { id = 'stop', label = 'Stop working', canInteract = function() return St and St.job and true or false end,
        onSelect = function() TriggerServerEvent('es_jail:jobStop') end }
    local ok = wc():AddAction({ id = 'es_jail:board', at = { coords = PR.board }, label = 'Prison jobs', icon = 'E', reach = 2.5, options = opts })
    boardAdded = ok and true or false
end

-- 1.0.6: every job's spot gets the same treatment: a GPS route blip, a ground ring snapped to the real ground and a
-- bobbing arrow above it you can see across the yard.
local spotBlip, groundZ = nil, nil
local function clearSpotBlip()
    if spotBlip then RemoveBlip(spotBlip) spotBlip = nil end
end
local function groundAt(p)
    RequestCollisionAtCoord(p.x, p.y, p.z)
    local ok, z = GetGroundZFor_3dCoord(p.x + 0.0, p.y + 0.0, p.z + 2.0, false)
    if ok and math.abs(z - p.z) < 4.0 then return z end
    return p.z - 0.98                                  -- spots are stored at standing height (ground + ~1 m)
end

-- kitchen grills: the stock canteen can not be entered, so each yard cooking spot gets a grill (local, this game only).
-- 1.0.8: no more guessing which way the model faces. Each grill stands at a fixed station (as in 1.0.7, where its back
-- already sat against the wall); its long axis is the model's X, so its front is +Y or -Y. A short ray each way from
-- the grill finds the wall: the open side is the front. The cook's point is then 0.9 m out from the front centre
-- (GetOffsetFromEntityInWorldCoords), the marker and the prompt sit there, and E walks you to it facing the grill.
local placeSpotFn          -- placeSpot, set below (jailgrill re-places the prompt)
local grills = {}          -- [spotIndex] = { obj, front = vector3 cook point, face = heading to the grill }
local grillTurn = 0.0      -- F8 jailgrill: extra degrees on every grill (this game only, for tuning)
local FRONT_GAP = 0.9

local function stationOf(j, i)
    local v, h = j.spots[i], j.faces[i] or 0.0
    local r = math.rad(h)
    local d = j.station.dist or 0.8
    return vector3(v.x - math.sin(r) * d, v.y + math.cos(r) * d, v.z), (h + 90.0 + (j.station.turn or 0.0) + grillTurn) % 360.0
end

--- how far the ray from the grill's centre reaches along its own +Y / -Y before something (a wall) stops it
local function openness(o, sign)
    local c = GetOffsetFromEntityInWorldCoords(o, 0.0, 0.0, 0.8)
    local e = GetOffsetFromEntityInWorldCoords(o, 0.0, sign * 3.0, 0.8)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(c.x, c.y, c.z, e.x, e.y, e.z, 1 + 16, o, 4)
    local _, hit, at = GetShapeTestResult(ray)
    if hit == 1 and at then return #(vector3(at.x, at.y, at.z) - c) end
    return 3.0
end

local function frontOf(o, j)
    local mn, mx = GetModelDimensions(GetEntityModel(o))
    local sign
    local plus, minus = openness(o, 1.0), openness(o, -1.0)
    if math.abs(plus - minus) > 0.4 then sign = plus > minus and 1.0 or -1.0
    else sign = (j.station.frontSign or -1.0) end          -- nothing either side: the config's guess (-Y)
    local depth = sign > 0 and mx.y or -mn.y                -- from the centre to that face
    local p = GetOffsetFromEntityInWorldCoords(o, 0.0, sign * (depth + FRONT_GAP), 0.0)
    local g = GetEntityCoords(o)
    return vector3(p.x, p.y, g.z), GetHeadingFromVector_2d(g.x - p.x, g.y - p.y), sign
end

local function removeGrills()
    for _, o in pairs(grills) do if DoesEntityExist(o.obj) then DeleteObject(o.obj) end end
    grills = {}
end
local function placeGrills()
    if next(grills) then return end
    local j = JB.kitchen
    if not (j and j.station and j.spots and j.faces) then return end
    local model = joaat(j.station.model)
    RequestModel(model)
    local t = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < t do Wait(20) end
    if not HasModelLoaded(model) then return end
    for i in ipairs(j.spots) do
        local at, h = stationOf(j, i)
        RequestCollisionAtCoord(at.x, at.y, at.z)
        local o = CreateObject(model, at.x, at.y, at.z - 0.9, false, false, false)
        SetEntityHeading(o, h)
        PlaceObjectOnGroundProperly(o)
        FreezeEntityPosition(o, true)
        SetEntityInvincible(o, true)
        local front, face, sign = frontOf(o, j)
        grills[i] = { obj = o, front = front, face = face, sign = sign }
    end
    SetModelAsNoLongerNeeded(model)
end

--- the kitchen station for a job spot, or nil
local function stationFor(job)
    if not job or job.key ~= 'kitchen' then return nil end
    local j = JB.kitchen
    for i, v in ipairs(j.spots) do
        if #(vector2(v.x, v.y) - vector2(job.spot.x, job.spot.y)) < 0.2 then return grills[i] end
    end
end

--- walk to the grill's front, turn to it, and only then start the bar; hold the heading while cooking
local cooking = false
local function cookAt(st)
    if cooking then return end
    cooking = true
    CreateThread(function()
        local ped = PlayerPedId()
        local p = st.front
        if #(GetEntityCoords(ped).xy - p.xy) > 0.25 then
            TaskGoStraightToCoord(ped, p.x, p.y, p.z, 1.0, 4000, st.face, 0.05)
            local t = GetGameTimer() + 4000
            while #(GetEntityCoords(ped).xy - p.xy) > 0.3 and GetGameTimer() < t do Wait(50) end
            ClearPedTasks(ped)
            if #(GetEntityCoords(ped).xy - p.xy) > 0.3 then
                local z = GetEntityCoords(ped).z
                SetEntityCoords(ped, p.x, p.y, z - 0.98, false, false, false, false)
            end
        end
        TaskAchieveHeading(ped, st.face, 800)
        local t = GetGameTimer() + 1200
        while math.abs(((GetEntityHeading(ped) - st.face + 540.0) % 360.0) - 180.0) > 8.0 and GetGameTimer() < t do Wait(30) end
        SetEntityHeading(ped, st.face)
        TriggerServerEvent('es_jail:jobDo')
        -- the bar's anim does not turn you, but hold the heading anyway while it runs
        local stop = GetGameTimer() + math.floor(((JB.kitchen.seconds or 9) + 1.5) * 1000)
        while GetGameTimer() < stop do
            Wait(150)
            local d = math.abs(((GetEntityHeading(ped) - st.face + 540.0) % 360.0) - 180.0)
            if d > 12.0 and #(GetEntityCoords(ped).xy - p.xy) < 0.8 then SetEntityHeading(ped, st.face) end
        end
        cooking = false
    end)
end

-- F8 tuning: `jailgrill 90` turns every grill 90 degrees more (this game only); the cook's point follows the grill
RegisterCommand('jailgrill', function(_, args)
    local v = tonumber(args[1])
    if not v then
        for i, g in pairs(grills) do
            print(('[es_jail] grill %d: heading %.0f, front %s (%.2f, %.2f), turn %d'):format(i, GetEntityHeading(g.obj), g.sign > 0 and '+Y' or '-Y', g.front.x, g.front.y, math.floor(grillTurn)))
        end
        print('[es_jail] jailgrill <degrees>: turn every grill (0 = as placed). Put a good value in Config.Jobs.kitchen.station.turn')
        return
    end
    grillTurn = v % 360.0
    removeGrills()
    CreateThread(function()
        placeGrills()
        local job = St and St.job
        spotKey = nil
        if job then placeSpotFn(job) end
        print(('[es_jail] grills turned %d degrees'):format(math.floor(grillTurn)))
    end)
end, false)

local function placeSpot(job)
    local key = job and (job.key .. ':' .. ('%.1f:%.1f'):format(job.spot.x, job.spot.y)) or nil
    local st = stationFor(job)
    if key == spotKey then return end
    removeSpot()
    clearSpotBlip()
    groundZ = nil
    if not job then return end
    local at = st and vector3(st.front.x, st.front.y, job.spot.z + 0.6) or vector3(job.spot.x, job.spot.y, job.spot.z + 0.6)
    local ok = wc():AddAction({ id = 'es_jail:spot', at = { coords = at }, label = job.verb, icon = 'E', reach = 2.0,
        onSelect = function()
            local s2 = stationFor(job)
            if s2 then cookAt(s2) else TriggerServerEvent('es_jail:jobDo') end
        end })
    if ok then spotKey = key end
    spotBlip = AddBlipForCoord(job.spot.x, job.spot.y, job.spot.z)
    SetBlipSprite(spotBlip, 1)
    SetBlipColour(spotBlip, 5)
    SetBlipScale(spotBlip, 0.85)
    SetBlipRoute(spotBlip, true)
    SetBlipRouteColour(spotBlip, 5)
    BeginTextCommandSetBlipName('STRING') AddTextComponentString(('Prison job: %s'):format(job.label or job.verb or 'task')) EndTextCommandSetBlipName(spotBlip)
end

placeSpotFn = placeSpot
local gAt

-- marker on the job spot (the grill's front for the kitchen)
CreateThread(function()
    while true do
        if St and St.job then
            local st = stationFor(St.job)
            local s = st and vector3(st.front.x, st.front.y, St.job.spot.z) or St.job.spot
            if gAt ~= s then gAt, groundZ = s, nil end
            groundZ = groundZ or groundAt(s)
            local me = GetEntityCoords(PlayerPedId())
            local d = #(vector2(me.x, me.y) - vector2(s.x, s.y))
            if d < 150.0 then
                DrawMarker(25, s.x, s.y, groundZ + 0.03, 0, 0, 0, 0, 0, 0, 1.4, 1.4, 1.0, 255, 170, 60, 170, false, false, 2, false, nil, nil, false)
                DrawMarker(2, s.x, s.y, groundZ + 1.6 + math.sin(GetGameTimer() / 300) * 0.12, 0, 0, 0, 180.0, 0, 0, 0.45, 0.45, 0.45,
                    255, 170, 60, 210, false, true, 2, false, nil, nil, false)
                Wait(0)
            else
                Wait(400)
            end
        else
            Wait(500)
        end
    end
end)

local function showBlip(on)
    if on and not blip then
        blip = AddBlipForCoord(PR.center.x, PR.center.y, PR.center.z)
        SetBlipSprite(blip, PR.blip.sprite or 188)
        SetBlipColour(blip, PR.blip.color or 1)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING') AddTextComponentString(PR.blip.label or 'Prison') EndTextCommandSetBlipName(blip)
    elseif not on and blip then
        RemoveBlip(blip) blip = nil
    end
end

RegisterNetEvent('es_jail:state', function(st)
    St, stAt = st or false, GetGameTimer()
    if not St then
        removeBoard() removeSpot() clearSpotBlip() removeGrills() showBlip(false)
        JLC.ui({ t = 'jail', on = false })
        return
    end
    addBoard() showBlip(true)
    placeGrills()
    placeSpot(St.job or nil)
    JLC.ui({ t = 'jail', on = true, remaining = St.remaining, total = St.total, cut = St.cut, jobs = St.jobs,
        job = St.job and St.job.label or nil, verb = St.job and St.job.verb or nil })
end)

AddEventHandler('onResourceStop', function(r)
    if r ~= GetCurrentResourceName() then return end
    removeBoard() removeSpot() clearSpotBlip() removeGrills() showBlip(false)
end)
