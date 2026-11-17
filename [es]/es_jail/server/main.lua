-- es_jail server: shared helpers, the items, who counts as an officer. Cuffs live in server/cuffs.lua, the jail in
-- server/jail.lua. Every client message is a SecureEvent / SecureCallback; the server decides everything.

local WC = exports.whip_core
JL = JL or {}
JL.WC = WC

local function str(v, n) v = type(v) == 'string' and v or (v ~= nil and tostring(v) or '') return v:sub(1, n or 255) end
JL.str = str

function JL.names(ids)
    local list, uniq = {}, {}
    for _, x in ipairs(ids) do x = tonumber(x) if x and not uniq[x] then uniq[x] = true list[#list + 1] = x end end
    if #list == 0 then return {} end
    local out = {}
    for k, v in pairs(WC:GetCharacterNames(list) or {}) do out[tonumber(k) or k] = v end
    return out
end
function JL.nameOf(cid) return cid and (JL.names({ cid })[tonumber(cid)] or ('#' .. cid)) or 'Unknown' end

function JL.notify(source, text, kind, ms) if source then WC:NotifyPlayer(source, text, kind or 'info', ms or 7000) end end

function JL.pedCoords(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

function JL.onlineByChar()
    local out = {}
    for _, s in ipairs(GetPlayers()) do
        local cid = WC:GetCharId(tonumber(s))
        if cid then out[cid] = tonumber(s) end
    end
    return out
end

function JL.log(charId, what, detail, byCharId)
    if not charId then return end
    MySQL.insert('INSERT INTO `es_jail_log` (`charId`,`what`,`detail`,`byCharId`) VALUES (?,?,?,?)',
        { charId, str(what, 20), detail and str(detail, 255) or nil, byCharId })
end

function JL.activity(source, what, detail)
    CreateThread(function() pcall(function() WC:LogActivity(source or 0, 'es_jail_' .. what, { detail = str(detail, 200) }) end) end)
end

-- 1.1.1: es_departments is part of es_mdt since es_mdt 2.0.0 (its exports keep the es_departments name)
local function ED() return (GetResourceState('es_mdt') == 'started' or GetResourceState('es_departments') == 'started') and exports.es_departments or nil end

function JL.isStaff(source)
    if IsPlayerAceAllowed(source, Config.Jail.staffAce or 'es_jail.admin') then return true end
    local ed = ED()
    if not ed then return false end
    local ok, v = pcall(function() return ed:IsStaff(source) end)
    return ok and v == true
end

--- The officer behind a source when they are on duty in a department whose rank holds `perm`, or false, why
local OffCache = {}
function JL.officer(source, perm)
    perm = perm or Config.Perms.cuff
    local key = source .. ':' .. perm
    local hit = OffCache[key]
    if hit and GetGameTimer() - hit.at < 4000 then return hit.v, hit.why end
    local v, why = false, nil
    local charId = WC:GetCharId(source)
    local ed = ED()
    if not charId then why = 'No character'
    elseif not ed then why = 'The departments system is not running'
    else
        local staff = JL.isStaff(source)
        local duty = false
        for _, d in ipairs(ed:GetPlayerDepartments(source) or {}) do
            if d.onDuty then
                duty = true
                if staff or WC:HasJobPermission(source, d.jobId, perm, { onDuty = true }) == true then
                    v = { source = source, charId = charId, dept = d, staff = staff }
                    break
                end
            end
        end
        if not v then why = duty and 'Your rank cannot do that' or 'Go on duty first' end
    end
    OffCache[key] = { at = GetGameTimer(), v = v, why = why }
    return v, why
end
AddEventHandler('playerDropped', function()
    local s = source
    for k in pairs(OffCache) do if k:find('^' .. s .. ':') then OffCache[k] = nil end end
end)

--- On-duty officers (any cuff-capable rank) within `range` of coords (nil = everywhere): { source, ... }
function JL.officersNear(coords, range)
    local out = {}
    local list = coords and WC:GetPlayersInRange(coords, range or 40.0) or GetPlayers()
    for _, s in ipairs(list) do
        s = tonumber(s)
        if s and JL.officer(s, Config.Perms.cuff) then out[#out + 1] = s end
    end
    return out
end

-- ---------------------------------------------------------------- items
local IT = Config.Items
function JL.registerItems()
    WC:RegisterItem(IT.cuffs, {
        name = 'Handcuffs', desc = 'Steel police handcuffs. Aim at someone (or use the F1 wheel) to cuff them. Opened with a cuff key.',
        weight = 0.4, stack = true, maxStack = 5, type = 'tool',
    })
    WC:RegisterItem(IT.key, {
        name = 'Cuff Key', desc = 'Opens any standard handcuffs.',
        weight = 0.02, stack = true, maxStack = 5, type = 'tool',
    })
    WC:RegisterItem(IT.ziptie, {
        name = 'Zip Ties', desc = 'Single-use plastic restraints. Cut off, not unlocked; they cannot be picked.',
        weight = 0.05, stack = true, maxStack = 20, type = 'tool',
    })
    CreateThread(function()
        Wait(3000)
        local want = {}
        for _, n in ipairs(Config.Shops or {}) do want[n:lower()] = true end
        for _, sh in ipairs(WC:GetShops() or {}) do
            if sh.name and want[sh.name:lower()] and (sh.mode == 'infinite' or sh.mode == 'npc') then
                local cat = WC:GetShopCatalog(sh.shopId) or {}
                for _, item in ipairs({ IT.cuffs, IT.key, IT.ziptie }) do
                    if cat[item] == nil then
                        local ok, err = WC:AddCatalogItem(sh.shopId, item, (Config.ShopPrices or {})[item] or 1)
                        print(('[es_jail] %s %s the shop "%s" (#%d)%s'):format(item, ok and 'added to' or 'NOT added to', sh.name, sh.shopId, ok and '' or (': ' .. tostring(err))))
                    end
                end
            end
        end
    end)
end
