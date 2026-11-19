-- es_jobs: what both sides agree on. Spot types (what a station's spots can be), and the checks every value from a
-- page goes through on the server.
ESJ = ESJ or {}

-- Spot types. ped: a ped stands there by default. spawns: has spawn points (cars, helicopters, boats). phase: built in
-- a later update (the editor shows them greyed out until then).
ESJ.TYPES = {
    { key = 'duty',     label = 'Duty: clock on / off',   icon = '⏱', ped = true,  hint = 'Members clock on and off here.' },
    { key = 'armory',   label = 'Armory',                 icon = '🛡', ped = true,  stock = true, hint = 'Equipment by rank, issued free.' },
    { key = 'locker',   label = 'Locker room',            icon = '🗄', ped = false, hint = 'Personal lockers (uniforms come in the next update).' },
    { key = 'garage',   label = 'Garage (vehicles)',      icon = '🚓', ped = true,  spawns = 'car',  fleet = true, hint = 'Fleet vehicles by rank; put them back here.' },
    { key = 'helipad',  label = 'Helipad',                icon = '🚁', ped = false, spawns = 'heli', fleet = true, hint = 'Fleet helicopters by rank.' },
    { key = 'boatdock', label = 'Boat dock',              icon = '⚓', ped = true,  spawns = 'boat', fleet = true, hint = 'Fleet boats by rank.' },
    { key = 'impound',  label = 'Impound clerk',          icon = 'Ⓟ', ped = true,  spawns = 'car', phase = 2, hint = 'Owners get their impounded cars back (police update).' },
    { key = 'hospital', label = 'Hospital check-in',      icon = '✚', ped = true,  phase = 3, hint = 'Check in to be treated (EMS update).' },
    { key = 'court',    label = 'Courtroom',              icon = '⚖', ped = true,  phase = 4, hint = 'Court clerk and bench (DOJ update).' },
}
ESJ.TYPE = {}
for _, t in ipairs(ESJ.TYPES) do ESJ.TYPE[t.key] = t end
ESJ.PHASE = 1   -- the spot types built so far (phase <= this)

ESJ.LIMITS = { spots = 40, spawns = 20, stock = 60, vehicles = 40, name = 48, label = 40 }

function ESJ.trim(s) return (type(s) == 'string' and s:gsub('[%c]', ''):gsub('^%s+', ''):gsub('%s+$', '')) or '' end
function ESJ.num(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
    if lo and v < lo then return nil end
    if hi and v > hi then return nil end
    return v
end
function ESJ.int(v, lo, hi, def)
    v = ESJ.num(v)
    if not v then return def end
    v = math.floor(v + 0.5)
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    return v
end
--- a model or item name: letters, digits, _ (and - for items), 1-48 long
function ESJ.name(s, dash)
    s = ESJ.trim(s)
    if s == '' or #s > 48 then return nil end
    if dash then return s:match('^[%w_%-]+$') and s or nil end
    return s:match('^[%w_]+$') and s or nil
end
--- a point from a page: { x, y, z, h } inside the map
function ESJ.point(p)
    if type(p) ~= 'table' then return nil end
    local x, y, z = ESJ.num(p.x, -9000, 9000), ESJ.num(p.y, -9000, 11000), ESJ.num(p.z, -200, 2500)
    if not (x and y and z) then return nil end
    local h = (ESJ.num(p.h, -720, 720) or 0.0) % 360
    local r = function(n) return math.floor(n * 100 + 0.5) / 100 end
    return { x = r(x), y = r(y), z = r(z), h = r(h) }
end
function ESJ.dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
