local _ENV = ESAPP('mdt'); -- es_mdt 2.0.8: the speeding alert's limit (Config.Dispatch.alerts.speeding), read live on both sides
-- units 'mph' | 'kmh'; limit = the speed that counts as speeding; highwayLimit = the same on a highway (0 = use limit). GTA has
-- no speed zones, so a highway is a street whose name has one of highwayWords in it ("Del Perro Fwy", "Route 68", ...).
-- Before 2.0.8 the setting was `mph` (a single limit in mph); a config that still has only that keeps working.

local FACTOR = { mph = 2.236936, kmh = 3.6 }
local DEF_WORDS = { 'Fwy', 'Freeway', 'Hwy', 'Highway', 'Route', 'Interstate' }

local function speedCfg()
    local D = type(Config.Dispatch) == 'table' and Config.Dispatch or {}
    local A = type(D.alerts) == 'table' and D.alerts or {}
    return type(A.speeding) == 'table' and A.speeding or {}
end

--- Is this street a highway (by its name)?
function EsSpeedHighway(street, cfg)
    cfg = cfg or speedCfg()
    if type(street) ~= 'string' or street == '' then return false end
    -- only the road itself: "Del Perro Fwy / Palomino Ave, Little Seoul" -> "Del Perro Fwy" (a cross street or the
    -- zone, e.g. the Route 68 zone around a side road, does not make it a highway)
    local s = (street:match('^([^,/]+)') or street):lower()
    for _, w in ipairs(type(cfg.highwayWords) == 'table' and cfg.highwayWords or DEF_WORDS) do
        if type(w) == 'string' and w ~= '' and s:find(w:lower(), 1, true) then return true end
    end
    return false
end

--- The limit for this street -> limit (in units), units ('mph' | 'kmh'), metres per second, highway
function EsSpeedLimit(street, cfg)
    cfg = cfg or speedCfg()
    local units = cfg.units == 'kmh' and 'kmh' or 'mph'
    local limit = tonumber(cfg.limit)
    if not limit then limit, units = tonumber(cfg.mph) or 120, 'mph' end   -- a pre-2.0.8 config
    local hwy = EsSpeedHighway(street, cfg)
    local hl = tonumber(cfg.highwayLimit) or 0
    if hwy and hl > 0 then limit = hl end
    limit = math.max(10, limit)
    return limit, units, limit / FACTOR[units], hwy
end

--- metres per second -> a whole number in these units
function EsSpeedIn(ms, units) return math.floor((tonumber(ms) or 0) * (FACTOR[units] or FACTOR.mph) + 0.5) end
