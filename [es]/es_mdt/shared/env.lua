-- es_mdt 2.0.0: one resource for the MDT, Departments and the DOJ (they were es_mdt, es_departments and es_doj).
-- Each part keeps its own globals: every file of a part starts with `local _ENV = ESAPP('<part>')`, a table of its
-- own that reads through to the real globals (natives, exports, Whip, MySQL, json...). So the three `Config`s and
-- the three `Fetch`es never meet, and the code of each part is the code it was.
--
-- What each part sees differently from the real globals:
--   exports('Name', fn)          also answers as exports.es_departments:Name / exports.es_doj:Name (the old names
--                                keep working for other resources, e.g. es_jail, and for the parts themselves)
--   GetResourceState(old name)   'es_departments' / 'es_doj' read as this resource
--   RegisterNUICallback(name)    departments -> 'dept_<name>', doj -> 'doj_<name>' (their pages post to those)
--   SendNUIMessage(msg)          goes to that part's page only (html/index.html hands it to the right frame)
--   SetNuiFocus(a, b)            per part; the game's focus is on while any part wants it
--   SetNuiFocusKeepInput(k)      2.0.13: left to the pad layer (client/pad.lua) while a controller drives a screen

local SELF = GetCurrentResourceName()
local REAL = _G
local OLD = { departments = 'es_departments', doj = 'es_doj' }
local PREFIX = { departments = 'dept_', doj = 'doj_', mdt = '' }
local ALIAS = { es_departments = true, es_doj = true }
local SERVER = IsDuplicityVersion()

local function resourceState(name)
    if ALIAS[name] then name = SELF end
    return GetResourceState(name)
end

-- NUI focus: one per part, the game's is the OR of them
local Focus = {}
local focusOrder = 0
local function applyFocus()
    local f, c, top, topAt = false, false, nil, -1
    for app, st in pairs(Focus) do
        f = f or st[1] c = c or st[2]
        if st[3] > topAt then top, topAt = app, st[3] end
    end
    -- 2.0.13: with controller support on, client/pad.lua (Whip.padScreen) owns the focus while any part has it: the
    -- cursor goes while a pad drives and comes back with the mouse. Off (or no pad layer): as before.
    if type(ESPAD) == 'table' and ESPAD.focus(f, top) then return end
    SetNuiFocus(f, c)
end
--- 2.0.13: is a part's screen up (the pad layer re-applies the focus when a setting changes)
function ESFocusState()
    local f, top, topAt = false, nil, -1
    for app, st in pairs(Focus) do
        f = f or st[1]
        if st[3] > topAt then top, topAt = app, st[3] end
    end
    return f, top, applyFocus
end

local envs = {}
function ESAPP(app)
    local e = envs[app]
    if e then return e end
    e = setmetatable({ ES_PART = app }, { __index = REAL })
    e.GetResourceState = resourceState
    local old = OLD[app]
    e.exports = setmetatable({}, {
        __index = function(_, k) return REAL.exports[k] end,
        __newindex = function() error('cannot set values on exports', 2) end,
        __call = function(_, name, fn)
            REAL.exports(name, fn)
            if old then
                AddEventHandler(('__cfx_export_%s_%s'):format(old, name), function(setCB) setCB(fn) end)
            end
        end,
    })
    if not SERVER then
        local pfx = PREFIX[app] or ''
        e.RegisterNUICallback = function(name, fn) return RegisterNUICallback(pfx .. name, fn) end
        e.SendNUIMessage = function(msg) return SendNUIMessage({ __app = app, m = msg }) end
        e.SetNuiFocus = function(hasFocus, hasCursor)
            local on = (hasFocus or hasCursor) and true or false
            local was = Focus[app]
            if on and not was then focusOrder = focusOrder + 1 end
            Focus[app] = on and { hasFocus and true or false, hasCursor and true or false, was and was[3] or focusOrder } or nil
            applyFocus()
            SendNUIMessage({ __shell = 'focus', app = app, on = on })
        end
        -- 2.0.13: while a pad drives a screen, the pad layer decides (the game keeps its input, so the pad can be read;
        -- walking, looking and fighting are held off). Otherwise as the part asks.
        e.SetNuiFocusKeepInput = function(keep)
            if type(ESPAD) == 'table' and ESPAD.owns() then return end
            return SetNuiFocusKeepInput(keep)
        end
    end
    envs[app] = e
    return e
end

--- Another part's globals (read only by convention): ESPART('departments').Config
function ESPART(app) return envs[app] end
