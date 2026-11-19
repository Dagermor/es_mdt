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

-- ---------------------------------------------------------------- 2.0.7: alert sound volume / mute (each player's own)
-- Saved in KVP like the size. The Aa popover shows it; html/shell.js plays the tones (WebAudio) at this volume.
local KVP_VOL, KVP_MUTE = 'es_mdt:alert_volume', 'es_mdt:alert_mute'
local function sndCfg()
    local C = (ESPART('mdt') or {}).Config or {}
    local D = type(C.Dispatch) == 'table' and C.Dispatch or {}
    return type(D.sounds) == 'table' and D.sounds or {}
end
local function volState()
    local def = math.floor(math.min(100, math.max(0, tonumber(sndCfg().defaultVolume) or 70)))
    local v = GetResourceKvpInt(KVP_VOL)            -- 0 when never set: stored as volume + 1
    local vol = v > 0 and math.min(100, v - 1) or def
    return { volume = vol, muted = GetResourceKvpInt(KVP_MUTE) == 1, def = def, engine = sndCfg().engine == 'game' and 'game' or 'nui' }
end
local function pushVol()
    local s = volState()
    s.__shell = 'volume'
    SendNUIMessage(s)
    return s
end
RegisterNUICallback('esui_volume_get', function(_, cb) cb(volState()) end)
-- { volume = 0-100 } and / or { muted = true|false }, or { reset = true }
RegisterNUICallback('esui_volume', function(d, cb)
    d = type(d) == 'table' and d or {}
    if d.reset then DeleteResourceKvp(KVP_VOL) DeleteResourceKvp(KVP_MUTE)
    else
        local v = tonumber(d.volume)
        if v then SetResourceKvpInt(KVP_VOL, math.floor(math.min(100, math.max(0, v))) + 1) end
        if d.muted ~= nil then SetResourceKvpInt(KVP_MUTE, d.muted == true and 1 or 0) end
    end
    cb(volState())
end)
CreateThread(function() Wait(1600) pushVol() end)

local GAME_SOUND = {   -- the 'game' engine (volume cannot be set there; mute still works)
    routine  = { 'Event_Message_Purple', 'GTAO_FM_Events_Soundset', 1, 400 },
    priority = { 'Event_Message_Purple', 'GTAO_FM_Events_Soundset', 2, 400 },
    critical = { 'Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', 4, 220 },
    soft     = { 'Text_Arrive_Tone', 'Phone_SoundSet_Default', 1, 250 },
    ok       = { 'Menu_Accept', 'Phone_SoundSet_Default', 1, 250 },
}
--- EsAlertSound('routine' | 'priority' | 'critical' | 'soft' | 'ok' | 'announce' | 'urgent') -> played (false when muted / volume 0)
function EsAlertSound(tier)
    local s = volState()
    if s.muted or s.volume <= 0 then return false end
    if s.engine == 'game' then
        local g = GAME_SOUND[tier] or (tier == 'urgent' and GAME_SOUND.critical) or GAME_SOUND.soft
        CreateThread(function() for _ = 1, g[3] do PlaySoundFrontend(-1, g[1], g[2], true) Wait(g[4]) end end)
        return true
    end
    SendNUIMessage({ __shell = 'tone', tier = tier })
    return true
end

-- /mdtvolume 50   /mdtvolume mute   /mdtvolume unmute
RegisterCommand('mdtvolume', function(_, args)
    local a = (args[1] or ''):lower():gsub('%%', '')
    if a == 'mute' or a == 'off' then SetResourceKvpInt(KVP_MUTE, 1)
    elseif a == 'unmute' or a == 'on' then SetResourceKvpInt(KVP_MUTE, 0)
    elseif tonumber(a) then SetResourceKvpInt(KVP_VOL, math.floor(math.min(100, math.max(0, tonumber(a)))) + 1) SetResourceKvpInt(KVP_MUTE, 0)
    elseif a ~= '' then return notify('Use /mdtvolume <0-100>, mute or unmute', 'error') end
    local s = pushVol()
    notify(s.muted and 'MDT alert sounds: muted' or ('MDT alert sounds: %d%%'):format(s.volume), 'success')
    if not s.muted then EsAlertSound('priority') end
end, false)
TriggerEvent('chat:addSuggestion', '/mdtvolume', 'Dispatch alert volume (0-100), or mute / unmute', { { name = 'volume', help = '0-100, mute or unmute' } })

-- ---------------------------------------------------------------- 2.0.8: the pause menu (Settings > Server > MDT)
-- Each player's size, alert volume and mute as rows of WHIP's Server Settings page (Whip.playerSetting). The values stay
-- where they always were (the KVPs above), so the page, the Aa popover, /mdtscale and /mdtvolume always agree: the page
-- reads `get` each time it opens. A value equal to the server's default is not kept (the KVP is deleted), so that player
-- follows the default, also when an admin changes it later (/whip > Settings > MDT). Rows are declared again when the
-- server's range or defaults change.
local KEYS_HELP = 'Keys (MDT, panic, call board ...) are rebound in GTA Settings > Key Bindings > FiveM.'
local function pct(v) return math.floor((tonumber(v) or 1) * 100 + 0.5) end
local function declareRows()
    if not (Whip and Whip.playerSetting) then return end
    local lo, hi, def = range()
    Whip.playerSetting({
        key = 'es_mdt.scale', group = 'MDT', type = 'slider', label = 'MDT display size', unit = '%',
        min = pct(lo), max = pct(hi), step = 5, default = pct(def),
        help = 'MDT, Departments and DOJ pages. Also the Aa button in their header, or /mdtscale. ' .. KEYS_HELP,
        get = function() return pct(state().scale) end,
        set = function(v)
            v = tonumber(v)
            if not v then return end
            local _, _, d = range()
            if math.abs(v - pct(d)) < 0.5 then reset() else set(v / 100) end
            push()
        end,
    })
    local vs = volState()
    Whip.playerSetting({
        key = 'es_mdt.alertVolume', group = 'MDT', type = 'slider', label = 'Dispatch alert volume', unit = '%',
        min = 0, max = 100, step = 5, default = vs.def,
        help = 'New calls, critical alarms and announcements. Also the Aa button, or /mdtvolume.',
        get = function() return volState().volume end,
        set = function(v)
            v = tonumber(v)
            if not v then return end
            v = math.floor(math.min(100, math.max(0, v)) + 0.5)
            if v == volState().def then DeleteResourceKvp(KVP_VOL) else SetResourceKvpInt(KVP_VOL, v + 1) end
            pushVol()
        end,
    })
    Whip.playerSetting({
        key = 'es_mdt.alertMute', group = 'MDT', type = 'toggle', label = 'Mute dispatch alerts', default = false,
        help = 'No alert sounds at all (cards and blips still show).',
        get = function() return volState().muted end,
        set = function(v)
            if v == true then SetResourceKvpInt(KVP_MUTE, 1) else DeleteResourceKvp(KVP_MUTE) end
            pushVol()
        end,
    })
end
declareRows()

-- an admin changed the size range / default or the sound defaults: the pages and the rows follow at once
if Whip and Whip.onConfigChanged then
    local queued = false
    local function again()
        if queued then return end
        queued = true
        SetTimeout(0, function()   -- never from inside whip_core's settings call
            queued = false
            push()
            pushVol()
            declareRows()
        end)
    end
    Whip.onConfigChanged('UI', again)
    Whip.onConfigChanged('Dispatch.sounds', again)
end
