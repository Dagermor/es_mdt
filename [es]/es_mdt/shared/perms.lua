-- es_mdt 2.1.0: the new law permissions (roadside tickets, impound), added here at start rather than in
-- departments/config.lua, so a server's own edited departments config keeps working untouched. Each law department type
-- (police, sheriff, state) gets them in /departments > Ranks; new departments' ranks get them by level; existing ranks
-- get them ONCE by level (Config.PermissionGrants, remembered per server: a rank an admin later unticks stays unticked).
local D = (ESPART('departments') or {}).Config
if type(D) ~= 'table' then return end

local NEW = {
    { key = 'tickets_issue',    label = 'Tickets: write roadside citations, parking tickets and warnings', level = 30 },
    { key = 'impound_vehicle',  label = 'Impound: impound and tow vehicles', level = 30 },
    { key = 'impound_hold',     label = 'Impound: put a hold on a vehicle (N days or until released)', level = 60 },
    { key = 'impound_lot',      label = 'Impound lot: release vehicles, charge or waive fees', level = 60 },
    { key = 'impound_override', label = 'Impound: release early (override a hold, logged)', level = 80 },
}

D.Permissions = type(D.Permissions) == 'table' and D.Permissions or {}
local done = {}
for _, t in ipairs({ 'police', 'sheriff', 'state' }) do
    local list = D.Permissions[t]
    if type(list) == 'table' and not done[list] then
        done[list] = true   -- the stock config shares one LAW list between the three
        local have = {}
        for _, p in ipairs(list) do if type(p) == 'table' then have[p.key] = true end end
        for _, p in ipairs(NEW) do if not have[p.key] then list[#list + 1] = { key = p.key, label = p.label } end end
    end
end

-- new departments: by level (the law rules below 'all')
local rules = type(D.DefaultRankPermissions) == 'table' and D.DefaultRankPermissions.law
if type(rules) == 'table' then
    for _, rule in ipairs(rules) do
        if type(rule) == 'table' and type(rule.perms) == 'table' then
            local have = {}
            for _, k in ipairs(rule.perms) do have[k] = true end
            for _, p in ipairs(NEW) do
                if (tonumber(rule.min) or 0) >= p.level and not have[p.key] then rule.perms[#rule.perms + 1] = p.key end
            end
        end
    end
end

-- existing ranks: once, by level
D.PermissionGrants = type(D.PermissionGrants) == 'table' and D.PermissionGrants or {}
local g = { id = 'mdt210_tickets_impound', perms = {} }
for _, p in ipairs(NEW) do g.perms[p.key] = p.level end
D.PermissionGrants[#D.PermissionGrants + 1] = g
