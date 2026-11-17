-- es_jail 1.0.5: the stock Bolingbroke's own ambient inmates and guards (GTA's PRISONER / SECURITY_GUARD peds) attack
-- anyone who walks in. While a player is near the prison (inmate, officer, visitor) this keeps them calm:
--   Config.Prison.ambient = 'friendly'  their groups respect the player (and anyone already fighting stands down)
--                           'remove'    no prison ambient peds spawn there; the ones about are cleared
--                           'off'       GTA's normal behaviour
-- Everything is put back the moment the player leaves the area. Client only; whip_core is not touched.

local PR = Config.Prison
local MODE = PR.ambient or 'friendly'
if MODE == 'off' then return end

local RADIUS = PR.ambientRadius or 320.0
local MODELS = { `s_m_y_prisoner_01`, `s_m_y_prismuscl_01`, `u_m_y_prisoner_01`, `g_m_m_prisoners_01`, `s_m_m_prisguard_01` }
local IS_MODEL = {}
for _, m in ipairs(MODELS) do IS_MODEL[m] = true end
local GROUPS = { `PRISONER`, `SECURITY_GUARD`, `COP` }   -- the prison's own ped groups (inmates, guards, towers)
local PLAYER_G = `PLAYER`
local RESPECT = 1

local _, CALM = AddRelationshipGroup('ES_JAIL_CALM')        -- prison peds we take charge of: never on the player
SetRelationshipBetweenGroups(RESPECT, CALM, PLAYER_G)
SetRelationshipBetweenGroups(RESPECT, PLAYER_G, CALM)

local inside = false
local saved = nil       -- { [group] = { theirs, ours } } relationships before we changed them

local function enter()
    inside = true
    if MODE == 'friendly' then
        saved = {}
        for _, g in ipairs(GROUPS) do
            saved[g] = { GetRelationshipBetweenGroups(g, PLAYER_G), GetRelationshipBetweenGroups(PLAYER_G, g) }
            SetRelationshipBetweenGroups(RESPECT, g, PLAYER_G)
            SetRelationshipBetweenGroups(RESPECT, PLAYER_G, g)
        end
    else
        for _, m in ipairs(MODELS) do SetPedModelIsSuppressed(m, true) end
    end
end

local function leave()
    inside = false
    if saved then
        for g, r in pairs(saved) do
            SetRelationshipBetweenGroups(r[1], g, PLAYER_G)
            SetRelationshipBetweenGroups(r[2], PLAYER_G, g)
        end
        saved = nil
    end
    if MODE == 'remove' then
        for _, m in ipairs(MODELS) do SetPedModelIsSuppressed(m, false) end
    end
end

--- a prison ped near us: calm it (friendly) or clear it (remove). Only peds no script owns, and only ones we control.
local function handle(ped, me)
    if IsPedAPlayer(ped) or not IS_MODEL[GetEntityModel(ped)] then return end
    if IsEntityAMissionEntity(ped) then return end                       -- someone's script ped (or our test NPC): leave it
    if NetworkGetEntityIsNetworked(ped) and not NetworkHasControlOfEntity(ped) then return end
    if MODE == 'remove' then
        if not IsEntityOnScreen(ped) or #(GetEntityCoords(ped) - GetEntityCoords(me)) > 25.0 or IsPedInCombat(ped, me) then
            SetEntityAsMissionEntity(ped, true, true)
            DeletePed(ped)
        end
        return
    end
    if GetPedRelationshipGroupHash(ped) ~= CALM then
        SetPedRelationshipGroupHash(ped, CALM)
        SetPedRelationshipGroupDefaultHash(ped, CALM)
    end
    if IsPedInCombat(ped, me) then
        ClearPedTasks(ped)
        TaskWanderStandard(ped, 10.0, 10)
    end
end

CreateThread(function()
    while true do
        local me = PlayerPedId()
        local near = #(GetEntityCoords(me) - PR.center) <= RADIUS
        if near and not inside then enter()
        elseif not near and inside then leave() end
        if inside then
            for _, ped in ipairs(GetGamePool('CPed')) do handle(ped, me) end
            StopAlarm('PRISON_ALARMS', true)
            Wait(1000)
        else
            Wait(2500)
        end
    end
end)

AddEventHandler('onResourceStop', function(r)
    if r == GetCurrentResourceName() and inside then leave() end
end)
