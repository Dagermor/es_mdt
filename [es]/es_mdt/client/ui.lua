-- es_mdt 2.0.2: the display size of every es_mdt page (MDT, Departments, DOJ), each player's own.
-- Saved in this player's KVP (survives restarts and cache clears); the server owner sets the default and the range in
-- mdt/config.lua (Config.UI). html/shell.js scales the pages; the size popover (the Aa button in each page's header)
-- and /mdtscale both end here.

local KVP = 'es_mdt:ui_scale'

local function range()
    local C = (ESPART('mdt') or {}).Config or {}
    local U = type(C.UI) == 'table' and C.UI or {}
    local lo = math.min(1.0, math.max(0.5, tonumber(U.minScale) or 0.7))
    local hi = math.max(1.0, math.min(2.0, tonumber(U.maxScale) or 1.5))
    local def = math.min(hi, math.max(lo, tonumber(U.defaultScale) or 1.0))
    return lo, hi, def
end

local function clamp(v)
    local lo, hi = range()
    v = tonumber(v)
    if not v or v ~= v then return nil end
    v = math.floor(v * 100 + 0.5) / 100
    return math.min(hi, math.max(lo, v))
end

local function state()
    local lo, hi, def = range()
    local mine = clamp(GetResourceKvpString(KVP))
    return { scale = mine or def, min = lo, max = hi, def = def, custom = mine ~= nil }
end

local function push()
    local s = state()
    s.__shell = 'scale'
    SendNUIMessage(s)
    return s
end

local function set(v)
    v = clamp(v)
    if not v then return nil end
    SetResourceKvp(KVP, tostring(v))
    return v
end

local function reset() DeleteResourceKvp(KVP) end

-- the shell asks once it has loaded (and again when a page opens, if the first ask came too early)
RegisterNUICallback('esui_scale_get', function(_, cb) cb(state()) end)
-- the popover: { scale = 1.15 } saves, { reset = true } goes back to the server's default
RegisterNUICallback('esui_scale', function(d, cb)
    d = type(d) == 'table' and d or {}
    if d.reset then reset() else set(d.scale) end
    cb(state())
end)

CreateThread(function() Wait(1500) push() end)

local function notify(text, kind) pcall(function() exports.whip_core:Notify(text, kind or 'inform') end) end

-- /mdtscale 120   /mdtscale 85%   /mdtscale reset   /mdtscale (shows the size)
RegisterCommand('mdtscale', function(_, args)
    local a = (args[1] or ''):lower():gsub('%%', '')
    local lo, hi = range()
    if a == '' then
        local s = state()
        notify(('MDT size: %d%% (%d-%d%%). /mdtscale <percent> or /mdtscale reset'):format(math.floor(s.scale * 100 + 0.5), math.floor(lo * 100 + 0.5), math.floor(hi * 100 + 0.5)))
        return
    end
    if a == 'reset' or a == 'default' then
        reset()
        local s = push()
        notify(('MDT size reset to %d%%'):format(math.floor(s.scale * 100 + 0.5)), 'success')
        return
    end
    local n = tonumber(a)
    if not n then notify('Use /mdtscale <percent>, for example /mdtscale 120', 'error') return end
    if n <= 3 then n = n * 100 end   -- /mdtscale 1.2 means 120%
    local v = set(n / 100)
    push()
    notify(('MDT size: %d%%'):format(math.floor(v * 100 + 0.5)), 'success')
end, false)

TriggerEvent('chat:addSuggestion', '/mdtscale', 'MDT, Departments and DOJ display size', {
    { name = 'percent', help = 'for example 120, or reset' },
})
