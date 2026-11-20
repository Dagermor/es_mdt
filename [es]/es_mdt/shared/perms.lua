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
-- 2.1.1: re-run once for servers where 2.1.0's grant was skipped on ranks holding not-yet-started permissions (adds missing only)
D.PermissionGrants[#D.PermissionGrants + 1] = { id = 'mdt211_tickets_impound_retry', perms = g.perms }

-- 2.5.0: the EMS side of the MDT. EMS departments get these (Ranks); new EMS departments: incident reports from EMT,
-- death records and waiving bills from Captain (80) only (the stock rule gave every permission from level 30);
-- existing EMS ranks get them once, by level.
local EMS_NEW = {
    { key = 'medical_records', label = 'Medical records', level = 10 },
    { key = 'ems_reports',     label = 'EMS: write incident reports after a call', level = 10 },
    { key = 'ems_deaths',      label = 'EMS supervisor: record and undo deaths', level = 80 },
    { key = 'ems_bills_waive', label = 'EMS supervisor: waive medical bills', level = 80 },
}
local SUPER = { ems_deaths = true, ems_bills_waive = true }
local elist = D.Permissions.ems
if type(elist) == 'table' then
    local have = {}
    for _, p in ipairs(elist) do if type(p) == 'table' then have[p.key] = true end end
    for _, p in ipairs(EMS_NEW) do if not have[p.key] then elist[#elist + 1] = { key = p.key, label = p.label } end end
    local erules = type(D.DefaultRankPermissions) == 'table' and D.DefaultRankPermissions.ems
    if type(erules) == 'table' then
        local top = false
        for _, rule in ipairs(erules) do
            if type(rule) == 'table' and rule.perms == 'all' and (tonumber(rule.min) or 0) >= 80 then top = true end
        end
        for _, rule in ipairs(erules) do
            if type(rule) == 'table' then
                local min = tonumber(rule.min) or 0
                if rule.perms == 'all' and min < 80 then
                    -- every EMS permission but the supervisor ones
                    local list = {}
                    for _, p in ipairs(elist) do if type(p) == 'table' and not SUPER[p.key] then list[#list + 1] = p.key end end
                    rule.perms = list
                elseif type(rule.perms) == 'table' then
                    local h = {}
                    for _, k in ipairs(rule.perms) do h[k] = true end
                    for _, p in ipairs(EMS_NEW) do if min >= p.level and not h[p.key] then rule.perms[#rule.perms + 1] = p.key end end
                end
            end
        end
        if not top then table.insert(erules, 1, { min = 80, perms = 'all' }) end
        -- EMTs (level 10) write incident reports and look patients up
        local ten = false
        for _, rule in ipairs(erules) do if type(rule) == 'table' and tonumber(rule.min) == 10 then ten = true end end
        if not ten then
            for i, rule in ipairs(erules) do
                if type(rule) == 'table' and (tonumber(rule.min) or 0) < 10 then
                    table.insert(erules, i, { min = 10, perms = { 'mdt_view', 'medical_records', 'ems_reports' } })
                    break
                end
            end
        end
    end
    local eg = { id = 'mdt250_ems', perms = {} }
    for _, p in ipairs(EMS_NEW) do eg.perms[p.key] = p.level end
    D.PermissionGrants[#D.PermissionGrants + 1] = eg
end
