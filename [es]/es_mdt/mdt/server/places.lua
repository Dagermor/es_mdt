local _ENV = ESAPP('mdt'); -- es_mdt 2.0.8: named places for robbery alerts (Config.Dispatch.places)
-- StoreRobbery / BankRobbery / JewelryRobbery (and Alert('store' ...)) are titled with the place's name, e.g.
-- "24/7 Supermarket, Innocence Blvd", instead of a number. Order: the caller's own name (data.storeName / data.label),
-- then a store id or number (data.store / data.storeId / data.id: a place id below, or Config.Dispatch.places.ids), then
-- the nearest place of that kind within its radius, else "Store, <street>". The built-in list is GTA V's stock shops,
-- banks and Vangelico; add your own (or override one by its id) in Config.Dispatch.places.extra or /whip > Settings > MDT.
-- Positions are each place's front door / counter, a few metres either way.

local P = {}
local function add(kind, id, name, x, y, z, radius) P[#P + 1] = { kind = kind, id = id, name = name, x = x, y = y, z = z, radius = radius } end

-- 24/7 Supermarket
add('store', '247_innocence',  '24/7 Supermarket, Innocence Blvd',      25.7,  -1347.3,  29.5)
add('store', '247_clinton',    '24/7 Supermarket, Clinton Ave',        373.8,    325.8, 103.6)
add('store', '247_palomino',   '24/7 Supermarket, Palomino Fwy',      2557.4,    382.3, 108.6)
add('store', '247_barbareno',  '24/7 Supermarket, Barbareno Rd',     -3038.7,    585.9,   7.9)
add('store', '247_ineseno',    '24/7 Supermarket, Ineseno Road',     -3241.9,   1001.5,  12.8)
add('store', '247_route68',    '24/7 Supermarket, Route 68',           547.4,   2671.7,  42.2)
add('store', '247_niland',     '24/7 Supermarket, Niland Ave',        1961.5,   3740.7,  32.3)
add('store', '247_senora',     '24/7 Supermarket, Senora Fwy',        2678.9,   3280.7,  55.2)
add('store', '247_paleto',     '24/7 Supermarket, Great Ocean Hwy',   1729.2,   6414.1,  35.0)
-- LTD Gasoline
add('store', 'ltd_grove',      'LTD Gasoline, Grove St',               -48.5,  -1757.5,  29.4)
add('store', 'ltd_mirror',     'LTD Gasoline, Mirror Park Blvd',      1163.4,   -323.8,  69.2)
add('store', 'ltd_seoul',      'LTD Gasoline, Little Seoul',          -707.5,   -914.3,  19.2)
add('store', 'ltd_banham',     'LTD Gasoline, Banham Canyon Dr',     -1820.5,    792.5, 138.1)
add('store', 'ltd_grapeseed',  'LTD Gasoline, Grapeseed Main St',     1698.4,   4924.4,  42.1)
-- Rob's Liquor
add('store', 'robs_prosperity','Rob\'s Liquor, Prosperity St',       -1487.5,   -379.1,  40.2)
add('store', 'robs_sanandreas','Rob\'s Liquor, San Andreas Ave',     -1222.9,   -906.9,  12.3)
add('store', 'robs_elrancho',  'Rob\'s Liquor, El Rancho Blvd',       1135.8,   -982.3,  46.4)
add('store', 'robs_chumash',   'Rob\'s Liquor, Great Ocean Hwy',     -2968.2,    390.9,  15.0)
add('store', 'scoops_route68', 'Scoops Liquor Barn, Route 68',        1166.0,   2708.9,  38.2)
-- Ammu-Nation
add('store', 'ammu_pillbox',   'Ammu-Nation, Adam\'s Apple Blvd',       22.0,  -1107.3,  29.8)
add('store', 'ammu_cypress',   'Ammu-Nation, Popular St',              810.2,  -2157.3,  29.6)
add('store', 'ammu_seoul',     'Ammu-Nation, Little Seoul',           -662.1,   -935.3,  21.8)
add('store', 'ammu_hawick',    'Ammu-Nation, Hawick',                  252.3,    -50.0,  69.9)
add('store', 'ammu_morningwood','Ammu-Nation, Morningwood',          -1305.9,   -394.5,  36.7)
add('store', 'ammu_chumash',   'Ammu-Nation, Chumash',               -3172.0,   1088.0,  20.8)
add('store', 'ammu_zancudo',   'Ammu-Nation, Route 68',              -1117.6,   2698.6,  18.6)
add('store', 'ammu_sandy',     'Ammu-Nation, Sandy Shores',           1693.4,   3759.5,  34.7)
add('store', 'ammu_paleto',    'Ammu-Nation, Paleto Bay',             -330.2,   6083.8,  31.5)
add('store', 'ammu_tataviam',  'Ammu-Nation, Palomino Fwy',           2567.6,    294.3, 108.7)
add('store', 'ammu_lamesa',    'Ammu-Nation, La Mesa',                 842.4,  -1033.4,  28.2)
-- clothing
add('store', 'binco_strawberry','Binco, Strawberry',                    72.3,  -1399.1,  29.4)
add('store', 'binco_canals',   'Binco, Vespucci Canals',              -822.4,  -1073.7,  11.3)
add('store', 'binco_textile',  'Binco, Textile City',                  427.0,   -806.3,  29.5)
add('store', 'suburban_hawick','Suburban, Hawick',                     125.8,   -223.8,  54.6)
add('store', 'suburban_delperro','Suburban, Del Perro',              -1193.4,   -772.3,  17.3)
add('store', 'suburban_chumash','Suburban, Chumash',                 -3172.5,   1048.1,  20.9)
add('store', 'suburban_route68','Suburban, Route 68',                  614.2,   2761.9,  42.1)
add('store', 'ponsonbys_rockford','Ponsonbys, Rockford Hills',        -708.7,   -152.1,  37.4)
add('store', 'ponsonbys_burton','Ponsonbys, Burton',                  -164.6,   -302.0,  39.7)
add('store', 'ponsonbys_morningwood','Ponsonbys, Morningwood',       -1450.4,   -237.3,  49.8)
add('store', 'discount_harmony','Discount Store, Route 68',           1196.4,   2710.0,  38.2)
add('store', 'discount_grapeseed','Discount Store, Grapeseed',        1693.5,   4822.3,  42.1)
add('store', 'discount_paleto', 'Discount Store, Paleto Bay',            5.9,   6511.4,  31.9)
-- barbers
add('store', 'barber_davis',   'Herr Kutz Barber, Davis',              136.8,  -1708.4,  29.3)
add('store', 'barber_mirror',  'Herr Kutz Barber, Mirror Park',       1212.8,   -472.9,  66.2)
add('store', 'barber_paleto',  'Herr Kutz Barber, Paleto Bay',        -278.1,   6228.5,  31.7)
add('store', 'barber_hawick',  'Hair on Hawick, Hawick',               -32.9,   -152.3,  57.1)
add('store', 'barber_vespucci','Beachcombover Barbers, Vespucci',    -1282.6,  -1116.8,   7.0)
add('store', 'barber_sandy',   'O\'Sheas Barber Shop, Sandy Shores',  1931.5,   3729.7,  32.8)
add('store', 'barber_rockford','Bob Mulét, Rockford Hills',           -814.3,   -183.8,  37.6)
-- banks (a bit wider: the alarm can come from the vault)
add('bank', 'fleeca_legion',   'Fleeca Bank, Legion Square',           149.9,  -1040.5,  29.4, 50)
add('bank', 'fleeca_alta',     'Fleeca Bank, Hawick Ave',              314.2,   -278.6,  54.2, 50)
add('bank', 'fleeca_burton',   'Fleeca Bank, Burton',                 -351.5,    -49.5,  49.0, 50)
add('bank', 'fleeca_delperro', 'Fleeca Bank, Blvd Del Perro',        -1212.9,   -330.8,  37.8, 50)
add('bank', 'fleeca_chumash',  'Fleeca Bank, Great Ocean Hwy',       -2962.6,    482.6,  15.7, 50)
add('bank', 'fleeca_route68',  'Fleeca Bank, Route 68',               1175.0,   2706.6,  38.1, 50)
add('bank', 'paleto',          'Blaine County Savings, Paleto Bay',   -104.9,   6477.0,  31.6, 60)
add('bank', 'pacific',         'Pacific Standard Bank, Vinewood Blvd', 235.0,    216.4, 106.3, 80)
-- jewelry
add('jewelry', 'vangelico',    'Vangelico Jewelry, Rockford Hills',   -630.4,   -236.7,  38.2, 50)

local BUILTIN = P
local LABEL = { store = 'Store', bank = 'Bank', jewelry = 'Jewelry store' }
-- BankRobbery's 'paleto' / 'pacific' name their bank without coords near it
local BANK_PRESET = { bank_paleto = 'paleto', bank_pacific = 'pacific' }

local function cfg()
    local D = type(Config.Dispatch) == 'table' and Config.Dispatch or {}
    return type(D.places) == 'table' and D.places or {}
end
local function num(v) return tonumber(v) end
local function coordsOfPlace(p)
    local c = p.coords
    if type(c) == 'table' or type(c) == 'vector3' then return num(c.x or c[1]), num(c.y or c[2]), num(c.z or c[3]) end
    return num(p.x), num(p.y), num(p.z)
end

--- Every place in force: the built-in ones, with Config.Dispatch.places.extra added (an extra with a built-in's id replaces it)
local function all()
    local C = cfg()
    local byId, out = {}, {}
    for _, p in ipairs(C.builtin == false and {} or BUILTIN) do out[#out + 1] = p byId[p.id] = #out end
    for _, e in ipairs(type(C.extra) == 'table' and C.extra or {}) do
        if type(e) == 'table' and type(e.name) == 'string' and e.name ~= '' then
            local x, y, z = coordsOfPlace(e)
            local p = { kind = LABEL[e.kind] and e.kind or 'store', id = type(e.id) == 'string' and e.id ~= '' and e.id or nil,
                name = e.name, x = x, y = y, z = z, radius = num(e.radius) }
            if p.id and byId[p.id] then out[byId[p.id]] = p else out[#out + 1] = p if p.id then byId[p.id] = #out end end
        end
    end
    return out
end

local function byId(id)
    if id == nil then return nil end
    id = tostring(id):lower()
    for _, p in ipairs(all()) do if p.id and p.id:lower() == id then return p end end
    return nil
end

local function clean(s, n)
    if type(s) ~= 'string' then return nil end
    s = s:gsub('%c', ''):match('^%s*(.-)%s*$')
    if s == '' then return nil end
    return s:sub(1, n or 80)
end

--- The place a robbery alert is at -> name, how ('caller' | 'id' | 'near' | 'fallback'), placeId
---@param kind string 'store' | 'bank' | 'jewelry'
---@param pos table|nil { x, y, z }
---@param data table|nil the caller's data
---@param street string|nil
---@param preset string|nil
function EsPlaceName(kind, pos, data, street, preset)
    data = type(data) == 'table' and data or {}
    local named = clean(data.storeName, 80) or clean(data.placeName, 80) or clean(data.label, 80)
    if named then return named, 'caller' end
    -- a store id or number from the robbery script
    local C = cfg()
    local ids = type(C.ids) == 'table' and C.ids or {}
    for _, k in ipairs({ 'store', 'storeId', 'id', 'shop', 'bankId' }) do
        local v = data[k]
        if v ~= nil and (type(v) == 'string' or type(v) == 'number') then
            local mapped = ids[v] or ids[tostring(v)] or (tonumber(v) and ids[tonumber(v)])
            if type(mapped) == 'string' then
                local p = byId(mapped)
                if p then return p.name, 'id', p.id end
                local n = clean(mapped, 80)
                if n then return n, 'id' end
            end
            local p = byId(v)
            if p then return p.name, 'id', p.id end
        end
    end
    -- the nearest of this kind
    local x, y = pos and num(pos.x), pos and num(pos.y)
    if x and y then
        local def = math.max(5, num(C.radius) or 40)
        local best, bestD
        for _, p in ipairs(all()) do
            if p.kind == kind and p.x and p.y then
                local d = math.sqrt((p.x - x) ^ 2 + (p.y - y) ^ 2)
                local r = p.radius and math.max(def, p.radius) or def
                if d <= r and (not bestD or d < bestD) then best, bestD = p, d end
            end
        end
        if best then return best.name, 'near', best.id end
    end
    if BANK_PRESET[preset] then local p = byId(BANK_PRESET[preset]) if p then return p.name, 'id', p.id end end
    local base = LABEL[kind] or 'Store'
    street = clean(street, 70)
    return street and (base .. ', ' .. street) or base, 'fallback'
end

--- for tests and admins: the place list in force
function EsPlaces() return all() end
