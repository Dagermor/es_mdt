-- es_mdt 2.0.0: taking over from the separate es_departments and es_doj resources (once per server, harmless after).
--  1. whip_core records a table's migrations per resource ('es_departments:fto_test_1'): copy those records to this
--     resource's name, so nothing runs again.
--  2. Resource KVPs belong to a resource, and es_departments kept its "done once" marks in its own (seeded, backfills,
--     rank adds, permission grants and mirrors, starter certifications, duty tracked since). On a server that already
--     ran es_departments those jobs are done: mark them done here too. A new server has no departments yet and is
--     left alone, so everything runs there as it should.
local ADOPTED = 'es_suite:adopted'

local function tableExists(name)
    return MySQL.scalar.await('SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ? LIMIT 1', { name }) ~= nil
end

local function copyMigrations()
    if not tableExists('schema_migrations') then return end
    for _, old in ipairs({ 'es_departments', 'es_doj' }) do
        local n = MySQL.update.await(("INSERT IGNORE INTO `schema_migrations` (`id`) SELECT CONCAT(?, SUBSTRING(`id`, %d)) FROM `schema_migrations` WHERE `id` LIKE ?")
            :format(#old + 2), { GetCurrentResourceName() .. ':', old .. ':%' })
        if (tonumber(n) or 0) > 0 then print(('[es_mdt] took over %d migration record(s) of %s'):format(n, old)) end
    end
end

local function adoptKvps()
    if GetResourceKvpString(ADOPTED) == '1' then return end
    local had = tableExists('es_departments') and (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM `es_departments`')) or 0) > 0
    if had then
        local C = ESPART('departments') and ESPART('departments').Config or {}
        local set = function(k, v) if GetResourceKvpString(k) == nil then SetResourceKvp(k, v) end end
        local want = 1
        for _, s in ipairs(C.Seed or {}) do want = math.max(want, s.since or 1) end
        set('es_departments:seeded', tostring(want))
        set('es_departments:ftoBackfill', '1')
        set('es_departments:pers_backfill_1', '1')
        for _, a in ipairs(C.RankAdds or {}) do set('es_departments:rankadd:' .. a.id, '1') end
        for _, g in ipairs(C.PermissionGrants or {}) do set('es_departments:grant:' .. g.id, '1') end
        for _, g in ipairs(C.PermissionMirrors or {}) do set('es_departments:mirror:' .. g.id, '1') end
        for _, r in ipairs(MySQL.query.await('SELECT `id` FROM `es_departments`') or {}) do set('es_departments:certs_seed:' .. r.id, '1') end
        if tableExists('es_duty_sessions') then
            local t = MySQL.scalar.await('SELECT UNIX_TIMESTAMP(MIN(`startedAt`)) FROM `es_duty_sessions`')
            if tonumber(t) then set('es_departments:dutySince', tostring(math.floor(tonumber(t)))) end
        end
        print('[es_mdt] took over from es_departments: its one-time setup is marked done')
    end
    SetResourceKvp(ADOPTED, '1')
end

Whip.register(function()
    local ok, err = pcall(copyMigrations)
    if not ok then print('^1[es_mdt] could not copy migration records: ' .. tostring(err) .. '^7') end
    ok, err = pcall(adoptKvps)
    if not ok then print('^1[es_mdt] could not take over es_departments marks: ' .. tostring(err) .. '^7') end
end)
