-- es_mdt 2.0.13: controller (gamepad) support for every es_mdt screen and action, the way WHIP's own menus do it.
--
-- WHIP reads the pad in Lua (FiveM pad key mappings never fire and the browser cannot see a gamepad), so:
--   * actions go on WHIP's controller buttons with RegisterPadAction (LB + Y, LB + D-pad: the buttons WHIP leaves free).
--     Players move them on the pause menu's Controller screen. Holds (panic, hide a call, the radar remote) are timed
--     here, from the press to the release WHIP reports, so a tap can never send a panic.
--   * screens: ONE Whip.padScreen for the whole resource. shared/env.lua hands it the NUI focus while any part (MDT,
--     Departments, DOJ, call board, permits, radar remote) is up; presses go to the part on top as { action = 'pad' },
--     the sticks and triggers as { action = 'padAxes' } (only while they move, at most 20 a second), and html/pad.js moves
--     a highlight, picks, goes back, switches tabs, scrolls and drives the Live map.
--   * typing: A on a text box asks for WHIP's on-screen keyboard (OpenKeyboard), GTA's own if whip_core has none.
--
-- 2.0.10's rule holds: nothing here runs a frame loop while no es_mdt screen is open. WHIP reads the LB combos itself; a
-- hold runs a 50 ms timer only between its press and its release; the pad screen reads the pad only while a screen is up.

local KVP_ON, KVP_SENS, KVP_HINTS = 'es_mdt:pad_on', 'es_mdt:pad_sens', 'es_mdt:pad_hints'

local function mdtPart() return ESPART('mdt') or {} end
local function CC()
    local c = mdtPart().Config
    c = type(c) == 'table' and c.Controller or nil
    return type(c) == 'table' and c or {}
end
--- an admin switch (Config.Controller.<k>; nil = the master switch alone)
local function adminOn(k)
    local c = CC()
    if c.enabled == false then return false end
    return k == nil or c[k] ~= false
end

-- ---------------------------------------------------------------- each player's own (pause menu > Server Settings > Controller)
local function mineOn() return GetResourceKvpInt(KVP_ON) ~= 1 end   -- 1 = this player turned it off
local function sens()
    local v = GetResourceKvpInt(KVP_SENS)
    if v < 25 or v > 300 then return 100 end
    return v
end
local STYLES = { xbox = true, playstation = true, off = true }
local function hintStyle()
    local v = GetResourceKvpString(KVP_HINTS)
    return STYLES[v] and v or 'xbox'
end

local function navOn() return adminOn('navigation') and mineOn() end
local function kbOn() return adminOn('keyboard') and mineOn() end
local function hintsOf() if not (adminOn('hints') and mineOn()) then return 'off' end return hintStyle() end

local function holdMs(key, def)
    local v = math.floor(tonumber(CC()[key]) or def)
    return math.max(300, math.min(5000, v))
end

local function wcall(name, ...)
    local ok, a, b = pcall(function(...) return exports.whip_core[name](exports.whip_core, ...) end, ...)
    if not ok then return nil, a end
    return a, b
end

-- the real SendNUIMessage, addressed to one part's frame (html/shell.js hands it over)
local function send(app, m) if app then SendNUIMessage({ __app = app, m = m }) end end

-- ---------------------------------------------------------------- the device (event driven: whip_core says when it swaps)
local padActive = false
AddEventHandler('whip_core:pad:deviceChanged', function(e)
    padActive = type(e) == 'table' and e.pad == true
    -- the call card and the radar panel (not focused) swap their key hints too
    send('mdt', { action = 'padDevice', pad = padActive, hud = true, hints = hintsOf() })
end)

-- ---------------------------------------------------------------- one pad screen for the whole resource
local cur = { app = nil, owned = false }
local screen
local LT, RT = { 207, 25, 72 }, { 208, 24, 71 }   -- whip_core's trigger controls (frontend, on foot, in a car)
local AX = { t = 0, live = false }
local function dz(v) if v > -0.15 and v < 0.15 then return 0.0 end return math.floor(v * 100 + 0.5) / 100 end
local function trig(list)
    local v = 0.0
    for i = 1, #list do local n = GetDisabledControlNormal(0, list[i]) if n > v then v = n end end
    return v > 0.08 and math.floor(v * 100 + 0.5) / 100 or 0.0
end

local function stateMsg(open)
    return { action = 'padState', open = open, nav = navOn(), keyboard = kbOn(), hints = hintsOf(), sens = sens(),
        pad = (cur.owned and screen and screen:isPad()) or padActive }
end

if Whip and Whip.padScreen then
    screen = Whip.padScreen({
        buttons = { 'up', 'down', 'left', 'right', 'a', 'b', 'x', 'y', 'lb', 'rb', 'menu' },
        stick = false,   -- the page steps with the stick itself (padAxes), so on the Live map the stick moves the map
        onButton = function(cmd, down, rep)
            if down then send(cur.app, { action = 'pad', cmd = cmd, rep = rep }) end
        end,
        onDevice = function(pad)
            padActive = pad
            send(cur.app, { action = 'padDevice', pad = pad, hints = hintsOf() })
        end,
        onFrame = function()
            local lx, ly = dz(GetDisabledControlNormal(0, 30)), dz(GetDisabledControlNormal(0, 31))
            local rx, ry = dz(GetDisabledControlNormal(0, 1)), dz(GetDisabledControlNormal(0, 2))
            local lt, rt = trig(LT), trig(RT)
            local any = lx ~= 0 or ly ~= 0 or rx ~= 0 or ry ~= 0 or lt ~= 0 or rt ~= 0
            if not any and not AX.live then return end
            local now = GetGameTimer()
            if any and AX.live and now - AX.t < 50 then return end
            AX.t, AX.live = now, any
            send(cur.app, { action = 'padAxes', lx = lx, ly = ly, rx = rx, ry = ry, lt = lt, rt = rt })
        end,
    })
end

ESPAD = {}

--- shared/env.lua: the parts' focus changed. f: any part wants the focus; top: the part on top. Returns true when the pad
--- screen took the focus (env then leaves SetNuiFocus alone).
function ESPAD.focus(f, top)
    if f then
        if cur.app ~= top then
            if cur.app then send(cur.app, { action = 'padState', open = false }) end
            cur.app = top
        end
    else
        if cur.app then send(cur.app, { action = 'padState', open = false }) end
        cur.app = nil
    end
    local want = f and screen ~= nil and navOn()
    if want then
        if not cur.owned then cur.owned = true screen:open() end
    elseif cur.owned then
        cur.owned = false
        AX.live = false
        screen:close()
    end
    if f then send(top, stateMsg(true)) end
    return want and true or false
end
--- is the pad screen holding the focus (env leaves keep-input to it)
function ESPAD.owns() return cur.owned end
--- the controller button an action is on now, for a hint ('lb_dpad_left'), or nil
function ESPAD.button(id)
    if not (adminOn('buttons') and mineOn()) then return nil end
    local slot = wcall('GetPadActionButton', id)
    return type(slot) == 'string' and slot or nil
end
function ESPAD.isPad() return padActive end

--- a setting changed: hand the focus again (the screen may be up) and tell the page
local function refresh()
    if type(ESFocusState) == 'function' then
        local f, _, apply = ESFocusState()
        if f then apply() end
    end
    send('mdt', { action = 'padDevice', pad = padActive, hud = true, hints = hintsOf() })
end

-- ---------------------------------------------------------------- the on-screen keyboard
local kbBusy = false
--- GTA's own keyboard, when whip_core has no OpenKeyboard. The NUI focus is let go while it is up (it reads the game's input).
local function gtaKeyboard(o)
    if screen and cur.owned then screen:pause(true) end
    SetNuiFocus(false, false)
    DisplayOnscreenKeyboard(1, 'FMMC_KEY_TIP8', '', o.value or '', '', '', '', o.maxLength or 255)
    local status = 0
    repeat Wait(0) status = UpdateOnscreenKeyboard() until status ~= 0
    local text = status == 1 and GetOnscreenKeyboardResult() or nil
    if screen and cur.owned then screen:pause(false)
    elseif type(ESFocusState) == 'function' then local f, _, apply = ESFocusState() if f then apply() end end
    return text
end

--- { title, value, placeholder, maxLength, numeric, predict } -> { ok, text }
RegisterNUICallback('esui_padKeyboard', function(d, cb)
    d = type(d) == 'table' and d or {}
    if not kbOn() then return cb({ ok = false, why = 'off' }) end
    if kbBusy then return cb({ ok = false, why = 'busy' }) end
    local o = {
        title = tostring(d.title or 'Type'):sub(1, 80),
        value = tostring(d.value or ''):sub(1, 2000),
        placeholder = tostring(d.placeholder or ''):sub(1, 120),
        maxLength = math.max(1, math.min(2000, math.floor(tonumber(d.maxLength) or 255))),
        numeric = d.numeric == true,
        predict = d.predict ~= false,
    }
    kbBusy = true
    CreateThread(function()
        local text
        local ok, r = pcall(function() return exports.whip_core:OpenKeyboard(o) end)
        if ok then text = r else text = gtaKeyboard(o) end
        kbBusy = false
        cb({ ok = type(text) == 'string', text = type(text) == 'string' and text or nil })
    end)
end)

-- ---------------------------------------------------------------- the buttons (WHIP's RegisterPadAction)
local function mdt() return mdtPart().MDTC or {} end
local function cmds() return mdt().padCmds or {} end
local function run(name) if type(name) == 'string' and name ~= '' then ExecuteCommand(name) end end

--- the hold ring on the HUD (html/mdt: works over any screen, and while down)
local function ring(id, label, ms, kind) send('mdt', { action = 'padHold', id = id, label = label, ms = ms, kind = kind }) end
local function ringOff(id, done) send('mdt', { action = 'padHold', id = id, stop = true, done = done == true }) end

local ACTIONS = {
    { id = 'es_mdt_tablet', label = 'MDT / tablet', slot = 'lb_y',
      tap = function() run((mdtPart().Config or {}).Command or 'mdt') end },
    -- works under any screen and while down or dead (menus = true: WHIP sends it over its own screens too)
    { id = 'es_mdt_panic', label = 'PANIC (hold)', slot = 'lb_dpad_up', menus = true,
      hold = 'panicHoldMs', holdDef = 1500, ringLabel = 'PANIC · keep holding', kind = 'panic', ringNow = true,
      onHold = function() run(cmds().panic or 'mdt_panic_key') end },
    { id = 'es_mdt_call', label = 'Respond / hide call (hold)', slot = 'lb_dpad_left',
      tap = function() run(cmds().attend or 'mdtcall_respond') end,
      hold = 'dismissHoldMs', holdDef = 600, ringLabel = 'Hide call card',
      holdIf = function() local f = mdt().callShown return f and f() end,
      onHold = function() run(cmds().dismiss or 'mdtcall_dismiss') end },
    { id = 'es_mdt_backup', label = 'Request backup', slot = 'lb_dpad_right',
      tap = function() run(cmds().backup or 'backup') end },
    { id = 'es_mdt_board', label = 'Call board (hold: radar)', slot = 'lb_dpad_down',
      tap = function() run(cmds().board or 'callboard') end,
      hold = 'remoteHoldMs', holdDef = 600, ringLabel = 'Radar remote',
      holdIf = function() local f = mdt().radarInCar return f and f() end,
      onHold = function() run('radarremote') end },
    -- on no button by default (WHIP has none free): players put it where they like
    { id = 'es_mdt_radar', label = 'Radar on / off', where = 'car', tap = function() run('radar') end },
    -- 2.1.0: the roadside forms (no default button either)
    { id = 'es_mdt_ticket', label = 'Write a ticket', tap = function() run(((mdtPart().Config or {}).Tickets or {}).command or 'ticket') end },
    { id = 'es_mdt_impound', label = 'Impound / tow vehicle', tap = function() run(((mdtPart().Config or {}).Impound or {}).command or 'mdtimpound') end },
}

local holds = {}   -- [id] = the hold going on

local function press(a)
    if not a.hold then return a.tap() end
    local canHold = not a.holdIf or a.holdIf()
    if not canHold then return a.tap and a.tap() end
    local ms = holdMs(a.hold, a.holdDef)
    local h = { t0 = GetGameTimer(), done = false, up = false, ringed = false }
    holds[a.id] = h
    if a.ringNow then h.ringed = true ring(a.id, a.ringLabel, ms, a.kind) end
    CreateThread(function()
        while holds[a.id] == h and not h.up and not h.done do
            Wait(50)
            if holds[a.id] ~= h or h.up then return end
            local held = GetGameTimer() - h.t0
            -- a tap shows nothing: the ring comes once it is clearly a hold
            if not h.ringed and held >= 150 then h.ringed = true ring(a.id, a.ringLabel, ms - held, a.kind) end
            if held >= ms then
                h.done = true
                holds[a.id] = nil
                ringOff(a.id, true)
                a.onHold()
            end
        end
    end)
end

local function release(a)
    local h = holds[a.id]
    if not h then return end
    holds[a.id] = nil
    h.up = true
    if h.done then return end
    if h.ringed then ringOff(a.id, false) end
    -- let go early: a tap (respond, the board), or nothing (panic)
    if a.tap and GetGameTimer() - h.t0 < holdMs(a.hold, a.holdDef) then a.tap() end
end

local registered = {}
local function register()
    local want = adminOn('buttons')
    for _, a in ipairs(ACTIONS) do
        if want then
            local def = { label = a.label, slot = a.slot, where = a.where, menus = a.menus,
                onPress = function() press(a) end }
            if a.hold then def.onRelease = function() release(a) end end
            local ok, why = wcall('RegisterPadAction', a.id, def)
            if ok == true then
                registered[a.id] = true
                wcall('SetPadActionReady', a.id, mineOn())
            elseif why then
                print(('[es_mdt] no %s on the controller: %s'):format(a.id, tostring(why)))
            end
        elseif registered[a.id] then
            wcall('RemovePadAction', a.id)
            registered[a.id] = nil
        end
    end
end

if Whip and Whip.register then
    Whip.register(function()
        registered = {}
        register()
        local p = wcall('IsControllerActive')
        padActive = p == true
    end)
end
if Whip and Whip.onConfigChanged then
    Whip.onConfigChanged('Controller', function() register() refresh() end)
end

-- ---------------------------------------------------------------- pause menu > Settings > Server Settings > Controller
if Whip and Whip.playerSetting then
    local G = 'Controller'
    Whip.playerSetting({ key = 'es_mdt.padOn', group = G, type = 'toggle', label = 'MDT: controller support', default = true,
        help = 'The MDT, Departments, DOJ, call board and radar remote on a controller, and the MDT\'s LB buttons.',
        get = function() return mineOn() end,
        set = function(v)
            if v == false then SetResourceKvpInt(KVP_ON, 1) else DeleteResourceKvp(KVP_ON) end
            for id in pairs(registered) do wcall('SetPadActionReady', id, mineOn()) end
            refresh()
        end })
    Whip.playerSetting({ key = 'es_mdt.padSens', group = G, type = 'slider', label = 'MDT: stick speed', unit = '%',
        min = 25, max = 300, step = 25, default = 100,
        help = 'How fast the sticks move the highlight, scroll and move the Live map.',
        get = function() return sens() end,
        set = function(v)
            v = math.floor(tonumber(v) or 100)
            if v == 100 then DeleteResourceKvp(KVP_SENS) else SetResourceKvpInt(KVP_SENS, math.max(25, math.min(300, v))) end
            refresh()
        end })
    Whip.playerSetting({ key = 'es_mdt.padHints', group = G, type = 'choice', label = 'MDT: button hints', default = 'xbox',
        options = { { value = 'xbox', label = 'Xbox (A B X Y)' }, { value = 'playstation', label = 'PlayStation (✕ ○ □ △)' }, { value = 'off', label = 'Off' } },
        help = 'The button hints at the bottom of es_mdt screens and on call cards.',
        get = function() return hintStyle() end,
        set = function(v)
            if v == 'xbox' or not STYLES[v] then DeleteResourceKvp(KVP_HINTS) else SetResourceKvp(KVP_HINTS, v) end
            refresh()
        end })
end

-- the page asks for its pad state when it loads late (the first open)
RegisterNUICallback('esui_padState', function(_, cb) local m = stateMsg(cur.app ~= nil) m.action = nil cb(m) end)
