local _ENV = ESAPP('doj'); -- es_mdt 2.3.0: the court portal as a whip_phone app ("Court").
-- whip_phone loads html/phone/court.js from this resource; its requests are es_doj:pub:<action>, the portal's own
-- SecureCallbacks (doj/server/civ.lua, contests.lua), so the phone app checks exactly what /court checks.
-- Nothing in whip_phone changes: this only calls its RegisterModule export. Config.PhoneApp = false: no app.
local ID, SCRIPT, NS = 'court', 'html/phone/court.js', 'es_doj:pub'

local function register()
    if Config.PhoneApp == false or GetResourceState('whip_phone') ~= 'started' then return end
    local ok, done, why = pcall(function() return exports.whip_phone:RegisterModule({ id = ID, script = SCRIPT, ns = NS }) end)
    if not ok or done == false then print(('^3[es_doj] Court phone app not registered: %s^7'):format(tostring(ok and why or done))) end
end

CreateThread(register)
AddEventHandler('onResourceStart', function(res) if res == 'whip_phone' then CreateThread(function() Wait(500) register() end) end end)
