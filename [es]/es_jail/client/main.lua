-- es_jail client: the overlay page (shake meter, jail timer), the cuffing animations. The server checks everything.

JLC = JLC or {}
local function wc() return exports.whip_core end
JLC.wc = wc
function JLC.notify(text, kind) wc():Notify(text, kind or 'info') end
function JLC.ui(msg) SendNUIMessage(msg) end

function JLC.loadDict(d)
    if HasAnimDictLoaded(d) then return true end
    RequestAnimDict(d)
    local t = GetGameTimer() + 3000
    while not HasAnimDictLoaded(d) and GetGameTimer() < t do Wait(10) end
    return HasAnimDictLoaded(d)
end

local function pedOf(serverId)
    local p = GetPlayerFromServerId(serverId)
    if p == -1 then return nil end
    local ped = GetPlayerPed(p)
    return ped ~= 0 and ped or nil
end
JLC.pedOf = pedOf

-- the paired cuffing animation: the officer from behind, the suspect held in front of them for a moment
RegisterNetEvent('es_jail:anim', function(role, other)
    local ped = PlayerPedId()
    if role == 'stop' then
        DetachEntity(ped, true, false)
        ClearPedSecondaryTask(ped)
        return
    end
    if not JLC.loadDict('mp_arrest_paired') then return end
    if role == 'cop' then
        TaskPlayAnim(ped, 'mp_arrest_paired', 'cop_p2_back_right', 8.0, -8.0, 3800, 33, 0.0, false, false, false)
    elseif role == 'crook' then
        local cop = pedOf(other)
        if not cop then return end
        AttachEntityToEntity(ped, cop, 11816, -0.1, 0.45, 0.0, 0.0, 0.0, 20.0, false, false, false, false, 20, false)
        TaskPlayAnim(ped, 'mp_arrest_paired', 'crook_p2_back_right', 8.0, -8.0, 3800, 32, 0.0, false, false, false)
        SetTimeout(2600, function() DetachEntity(PlayerPedId(), true, false) end)
    end
end)

AddEventHandler('onResourceStop', function(r)
    if r ~= GetCurrentResourceName() then return end
    DetachEntity(PlayerPedId(), true, false)
end)

-- F8 helper for setting up spots: prints where you stand
RegisterCommand('jailpos', function()
    local p, h = GetEntityCoords(PlayerPedId()), GetEntityHeading(PlayerPedId())
    print(('vector4(%.2f, %.2f, %.2f, %.1f)'):format(p.x, p.y, p.z, h))
    JLC.notify(('Printed in F8: %.2f, %.2f, %.2f'):format(p.x, p.y, p.z), 'info')
end, false)
