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
local function applyFocus()
    local f, c = false, false
    for _, st in pairs(Focus) do f = f or st[1] c = c or st[2] end
    SetNuiFocus(f, c)
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
            Focus[app] = on and { hasFocus and true or false, hasCursor and true or false } or nil
            applyFocus()
            SendNUIMessage({ __shell = 'focus', app = app, on = on })
        end
    end
    envs[app] = e
    return e
end

--- Another part's globals (read only by convention): ESPART('departments').Config
function ESPART(app) return envs[app] end
