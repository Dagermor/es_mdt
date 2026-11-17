-- es_jail client: being cuffed (controls, animation, inventory lock), breaking out by shaking the mouse,
-- and the prompts: aim at a person (officers: cuff / uncuff / search; anyone: pick a lock) and the F1 wheel.

local wc, notify = JLC.wc, JLC.notify
local C, B, IT = Config.Cuffs, Config.Breakout, Config.Items
local BLOCK = 'es_jail:cuffed'

local Me = false         -- what the server says I wear: { mode, kind, escapes, max, canBreak, canPick } or false
local struggling = false
local Window = nil       -- the open cuffing window { token, lv, ends } (1.0.3)

local function stateOf(serverId)
    local v = serverId and Player(serverId).state.esCuffed
    if type(v) ~= 'string' then return nil end
    local mode, kind = v:match('^(%a+):(%a+)$')
    return mode and { mode = mode, kind = kind } or nil
end
JLC.stateOf = stateOf

local function animFor(mode)
    if mode == 'soft' then return 'anim@move_m@prisoner_cuffed', 'idle' end
    return 'mp_arresting', 'idle'
end

-- ---------------------------------------------------------------- being cuffed
local function applyBlocks()
    local groups = { 'combat', 'weaponWheel', 'driveBy' }
    if Me.mode == 'hard' then groups[#groups + 1] = 'move' end
    wc():BlockControls(BLOCK, { groups = groups, controls = C.blockControls, walk = true })
    wc():SetInventoryLocked(true)
    SetEnableHandcuffs(PlayerPedId(), true)
end

local function clearCuffs()
    wc():UnblockControls(BLOCK)
    wc():SetInventoryLocked(false)
    local ped = PlayerPedId()
    SetEnableHandcuffs(ped, false)
    for _, m in ipairs({ 'soft', 'hard' }) do
        local d, c = animFor(m)
        if IsEntityPlayingAnim(ped, d, c, 3) then StopAnimTask(ped, d, c, 2.0) end
    end
    JLC.ui({ t = 'cuffs', on = false })
end

-- 1.1.0: cuffs (or a zip tie) on the wrists, seen by everyone: a networked prop made by the cuffed player's own client
local Prop = nil
local function propOff()
    if Prop and DoesEntityExist(Prop) then DetachEntity(Prop, true, false) DeleteEntity(Prop) end
    Prop = nil
end
local function propOn(kind)
    propOff()
    local P = C.prop or {}
    if P.enabled == false then return end
    local model = kind == 'ziptie' and (P.ziptie or `hei_prop_zip_tie_positioned`) or (P.cuffs or `p_cs_cuffs_02_s`)
    if type(model) == 'string' then model = joaat(model) end
    if not IsModelInCdimage(model) then model = `p_cs_cuffs_02_s` end
    RequestModel(model)
    local t = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < t do Wait(50) end
    if not HasModelLoaded(model) or not Me then return end
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local o = CreateObject(model, c.x, c.y, c.z - 2.0, true, true, false)
    SetModelAsNoLongerNeeded(model)
    if o == 0 then return end
    SetEntityCollision(o, false, false)
    local off, rot = P.offset or vector3(-0.055, 0.06, 0.04), P.rot or vector3(265.0, 155.0, 80.0)
    AttachEntityToEntity(o, ped, GetPedBoneIndex(ped, P.bone or 60309), off.x, off.y, off.z, rot.x, rot.y, rot.z, true, true, false, true, 1, true)
    Prop = o
end

local loop = false
local function cuffLoop()
    if loop then return end
    loop = true
    CreateThread(function()
        while Me do
            local ped = PlayerPedId()
            local d, c = animFor(Me.mode)
            if not IsEntityDead(ped) and not IsPedRagdoll(ped) and not IsPedInAnyVehicle(ped, false) and not struggling
                and not IsEntityPlayingAnim(ped, d, c, 3) and not IsEntityPlayingAnim(ped, 'mp_arrest_paired', 'crook_p2_back_right', 3) and JLC.loadDict(d) then
                TaskPlayAnim(ped, d, c, 8.0, -8.0, -1, 49, 0.0, false, false, false)
            end
            if GetSelectedPedWeapon(ped) ~= `WEAPON_UNARMED` then SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true) end
            if Prop and (not DoesEntityExist(Prop) or not IsEntityAttachedToEntity(Prop, ped)) then propOn(Me.kind) end
            -- 1.1.0: someone cuffed cannot grab (escort) another person
            if wc():IsEscorting() then ExecuteCommand('escort_release') notify('You cannot hold anyone while restrained', 'error') end
            Wait(400)
        end
        loop = false
    end)
end

RegisterNetEvent('es_jail:cuffs', function(inf)
    local was = Me
    Me = inf or false
    if not Me then
        if not Window then struggling = false JLC.ui({ t = 'shake', on = false }) end
        if was then clearCuffs() end
        propOff()
        return
    end
    applyBlocks()
    cuffLoop()
    if not was or was.kind ~= Me.kind or not Prop then CreateThread(function() propOn(Me.kind) end) end
    JLC.ui({ t = 'cuffs', on = true, mode = Me.mode, kind = Me.kind, canBreak = Me.canBreak, canPick = Me.canPick,
        escapes = Me.escapes, max = Me.max, key = Me.key })
end)

AddEventHandler('onResourceStop', function(r)
    if r ~= GetCurrentResourceName() then return end
    if Me then clearCuffs() end
    propOff()
end)

-- ---------------------------------------------------------------- breaking out (1.0.3: only while the cuffs go on)
-- The server opens a window when someone starts cuffing you (es_jail:cuffWindow). Press the key and shake the mouse
-- before it ends; once the cuffs lock there is no shaking out of them.
local WBLOCK = 'es_jail:window'

local function closeWindowUi(keepResult)
    Window = nil
    wc():UnblockControls(WBLOCK)
    if not keepResult then JLC.ui({ t = 'shake', on = false }) end
end

RegisterNetEvent('es_jail:cuffWindow', function(token, lv)
    if not token then
        local was = struggling
        struggling = false
        closeWindowUi(was)
        return
    end
    Window = { token = token, lv = lv, ends = GetGameTimer() + (lv.ms or 6000) }
    -- held still while the cuffs go on: break free or wear them
    wc():BlockControls(WBLOCK, { groups = { 'move', 'combat', 'weaponWheel' }, controls = { 21, 22 } })
    JLC.ui({ t = 'shake', on = true, ready = true, attempt = lv.attempt, max = lv.max, key = lv.key, kind = lv.kind,
        pct = 0, left = (lv.ms or 6000) / 1000 })
    CreateThread(function()   -- the countdown until they press the key
        local w = Window
        while Window == w and not struggling do
            local left = (w.ends - GetGameTimer()) / 1000
            if left <= 0 then break end
            JLC.ui({ t = 'shake', on = true, ready = true, left = left })
            Wait(100)
        end
    end)
end)

RegisterNetEvent('es_jail:struggle', function(token)
    local w = Window
    if struggling or not w or w.token ~= token then return end
    struggling = true
    local lv = w.lv
    CreateThread(function()
        local meter, need = 0.0, (lv.need or 100) + 0.0
        local K = 2.4
        -- never faster than the server allows: at best the meter fills in lv.fastest seconds
        local cap = need / math.max(0.5, lv.fastest or 3) + (lv.decay or 10)
        local last = GetGameTimer()
        local won = false
        wc():BlockControls('es_jail:struggle', { groups = { 'look' } })
        local ped = PlayerPedId()
        if JLC.loadDict('random@rescue_hostage') then
            TaskPlayAnim(ped, 'random@rescue_hostage', 'girl_struggle_loop', 8.0, -8.0, -1, 49, 0.0, false, false, false)
        end
        JLC.ui({ t = 'shake', on = true, ready = false, attempt = lv.attempt, max = lv.max, pct = 0 })
        local sent = 0
        while struggling and Window == w do
            Wait(0)
            local t = GetGameTimer()
            local dt = math.max(0.001, (t - last) / 1000)
            last = t
            local dx = math.abs(GetDisabledControlNormal(0, 1))
            local dy = math.abs(GetDisabledControlNormal(0, 2))
            local speed = math.min(30.0, (dx + dy) / dt)
            local rise = math.min(speed * K * (lv.gain or 1), cap)
            meter = math.max(0.0, math.min(need, meter + (rise - (lv.decay or 10)) * dt))
            if t - sent > 50 then
                sent = t
                JLC.ui({ t = 'shake', on = true, pct = meter / need * 100, left = math.max(0, (w.ends - t) / 1000) })
            end
            if meter >= need then won = true break end
            if t >= w.ends then break end
        end
        wc():UnblockControls('es_jail:struggle')
        StopAnimTask(PlayerPedId(), 'random@rescue_hostage', 'girl_struggle_loop', 2.0)
        local mine = struggling
        struggling = false
        if mine then JLC.ui({ t = 'shake', on = false, won = won }) else JLC.ui({ t = 'shake', on = false }) end
        if mine then TriggerServerEvent('es_jail:struggleEnd', w.token, won) end
        if won then closeWindowUi(true) end
    end)
end)

local function tryStruggle()
    if Window and not struggling then TriggerServerEvent('es_jail:struggleStart') return end
    if Me and not struggling then
        notify(Me.canPick and 'The cuffs are locked. Pick the lock (F1) to get out.' or 'The cuffs are locked. You can not get out of these.', 'error')
    end
end
RegisterCommand('+es_jail_struggle', tryStruggle, false)
RegisterCommand('-es_jail_struggle', function() end, false)
RegisterKeyMapping('+es_jail_struggle', 'Struggle while being cuffed', 'keyboard', B.key or 'X')

AddEventHandler('onResourceStop', function(r)
    if r == GetCurrentResourceName() and Window then wc():UnblockControls(WBLOCK) end
end)

-- ---------------------------------------------------------------- prompts
local function nearestPlayer(range)
    local me = PlayerPedId()
    local at = GetEntityCoords(me)
    local best, bestD
    for _, p in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(p)
        if ped ~= me and ped ~= 0 then
            local d = #(GetEntityCoords(ped) - at)
            if d <= range and (not bestD or d < bestD) then best, bestD = GetPlayerServerId(p), d end
        end
    end
    return best
end
JLC.nearestPlayer = nearestPlayer

local function officerReq() return { onDuty = true, jobPermission = Config.Perms.cuff } end
local function sid(ctx) return ctx and ctx.player and ctx.player.serverId end

local PED_ID = 'es_jail:ped'
local pedAdded = false
local function addPedPrompt()
    if pedAdded then return end
    local ok = wc():AddAction({
        id = PED_ID, at = { aimBox = 'ped' }, label = 'Restrain', icon = 'E',
        reach = (C.range or 2.0) + 0.5,
        canInteract = function(ctx) return sid(ctx) ~= nil and not Me end,
        options = {
            -- 1.1.0: the three ways to restrain sit in one "Cuff ›" menu, so the prompt stays short (no cut-off labels)
            { id = 'cuffm', label = 'Cuff ›', canInteract = function(ctx) return not stateOf(sid(ctx)) end,
                options = {
                    { id = 'soft', label = 'Cuff (can walk)', require = officerReq(), onSelect = function(ctx) TriggerServerEvent('es_jail:cuff', sid(ctx), 'soft', 'cuffs') end },
                    { id = 'hard', label = 'Hard cuff (held still)', require = officerReq(), onSelect = function(ctx) TriggerServerEvent('es_jail:cuff', sid(ctx), 'hard', 'cuffs') end },
                    { id = 'zip', label = 'Zip-tie', require = C.zipAnyone and { item = IT.ziptie } or { onDuty = true, jobPermission = Config.Perms.cuff, item = IT.ziptie },
                        onSelect = function(ctx) TriggerServerEvent('es_jail:cuff', sid(ctx), 'soft', 'ziptie') end },
                } },
            { id = 'uncuff', label = function(ctx) local s = stateOf(sid(ctx)) return s and s.kind == 'ziptie' and 'Cut ties' or 'Uncuff' end,
                canInteract = function(ctx) return stateOf(sid(ctx)) ~= nil end,
                onSelect = function(ctx) TriggerServerEvent('es_jail:uncuff', sid(ctx)) end },
            { id = 'tohard', label = 'Hold still', require = officerReq(),
                canInteract = function(ctx) local s = stateOf(sid(ctx)) return s and s.mode == 'soft' end,
                onSelect = function(ctx) TriggerServerEvent('es_jail:mode', sid(ctx), 'hard') end },
            { id = 'tosoft', label = 'Let walk', require = officerReq(),
                canInteract = function(ctx) local s = stateOf(sid(ctx)) return s and s.mode == 'hard' end,
                onSelect = function(ctx) TriggerServerEvent('es_jail:mode', sid(ctx), 'soft') end },
            { id = 'search', label = 'Search', require = officerReq(),
                canInteract = function(ctx) return stateOf(sid(ctx)) ~= nil or (ctx.player and ctx.player.isDead) end,
                onSelect = function(ctx) TriggerServerEvent('es_jail:search', sid(ctx)) end },
            { id = 'pick', label = 'Pick cuffs', require = { item = IT.lockpick },
                canInteract = function(ctx) local s = stateOf(sid(ctx)) return Config.Lockpick.enabled ~= false and Config.Lockpick.others ~= false and s and (s.kind == 'cuffs' or Config.Lockpick.zipties) end,
                onSelect = function(ctx) TriggerServerEvent('es_jail:pick', sid(ctx)) end },
        },
    })
    pedAdded = ok and true or false
end
local function removePedPrompt()
    if not pedAdded then return end
    pcall(function() wc():RemoveAction(PED_ID) end)
    pedAdded = false
end

-- the ped prompt costs a ray every frame: only while it means something
CreateThread(function()
    while true do
        Wait(1500)
        local want = false
        if not Me then
            local job = LocalPlayer.state.whipJob
            if job and job ~= false then want = true
            else
                local me = GetEntityCoords(PlayerPedId())
                for _, p in ipairs(GetActivePlayers()) do
                    local s = GetPlayerServerId(p)
                    if p ~= PlayerId() and stateOf(s) and #(GetEntityCoords(GetPlayerPed(p)) - me) < 15.0 then want = true break end
                end
                if not want and (wc():HasItem(IT.cuffs) or wc():HasItem(IT.ziptie)) then want = true end
            end
        end
        if want then addPedPrompt() else removePedPrompt() end
    end
end)

-- the F1 wheel
CreateThread(function()
    Wait(1000)
    wc():AddAction({ id = 'es_jail:struggle', at = { radial = true }, label = 'Struggle free', icon = 'hand',
        description = 'While the cuffs go on: shake your mouse to slip free',
        canInteract = function() return Window ~= nil and not struggling end,
        onSelect = function() tryStruggle() end })
    wc():AddAction({ id = 'es_jail:pickself', at = { radial = true }, label = 'Pick your cuffs', icon = 'key',
        require = { item = IT.lockpick, alive = true },
        canInteract = function() return Me and Me.canPick end,
        onSelect = function() TriggerServerEvent('es_jail:pick', GetPlayerServerId(PlayerId())) end })
    wc():AddAction({ id = 'es_jail:cuffnear', at = { radial = true }, label = 'Cuff nearest person', icon = 'lock',
        require = officerReq(),
        canInteract = function() local s = nearestPlayer(C.range or 2.0) return s and not stateOf(s) and not Me end,
        onSelect = function() local s = nearestPlayer(C.range or 2.0) if s then TriggerServerEvent('es_jail:cuff', s, 'soft', 'cuffs') end end })
    wc():AddAction({ id = 'es_jail:uncuffnear', at = { radial = true }, label = 'Uncuff nearest person', icon = 'unlock',
        canInteract = function() local s = nearestPlayer(C.range or 2.0) return s and stateOf(s) and not Me end,
        onSelect = function() local s = nearestPlayer(C.range or 2.0) if s then TriggerServerEvent('es_jail:uncuff', s) end end })
    wc():AddAction({ id = 'es_jail:searchnear', at = { radial = true }, label = 'Search nearest person', icon = 'search',
        require = officerReq(),
        canInteract = function() local s = nearestPlayer(C.searchRange or 2.5) return s and stateOf(s) and not Me end,
        onSelect = function() local s = nearestPlayer(C.searchRange or 2.5) if s then TriggerServerEvent('es_jail:search', s) end end })
end)
