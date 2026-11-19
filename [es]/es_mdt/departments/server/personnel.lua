local _ENV = ESAPP('departments'); -- es_departments 1.5.0: personnel files. Everything a department keeps on its people beyond the roster:
--   career log      hires, rank changes (who and why), departures, inactivity warnings, certifications
--   entries         commendations, written warnings, suspensions and notes (supervisors; officer-visible or private)
--   certifications  each department's own list (FTO, SWAT, K9 ...), granted per officer with expiry and history
-- The MDT's officer profile reads it all through GetPersonnelFile; nothing here trusts the caller beyond `who`.

local WC = exports.whip_core
Pers = Pers or {}
local ctx, up = nil, false
local CC = Config.Certs or {}
-- 2.0.10: read each time (/whip > Settings > MDT > Departments: training and certifications)
local function soon() return math.max(1, tonumber((Config.Certs or {}).alertDays) or 14) * 86400 end
local TEST_BASE = 900000000

-- ---------------------------------------------------------------- tables

function Pers.tables()
    local defs = {
        { 'es_dept_career', [[CREATE TABLE IF NOT EXISTS `es_dept_career` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `deptId` INT UNSIGNED NOT NULL,
            `charId` INT UNSIGNED NOT NULL,
            `kind` VARCHAR(16) NOT NULL,
            `fromRole` VARCHAR(60) NULL,
            `toRole` VARCHAR(60) NULL,
            `fromLevel` INT NULL,
            `toLevel` INT NULL,
            `byCharId` INT UNSIGNED NULL,
            `reason` VARCHAR(500) NULL,
            `detail` VARCHAR(200) NULL,
            `backfill` TINYINT(1) NOT NULL DEFAULT 0,
            `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_es_car_char` (`charId`, `at`),
            KEY `idx_es_car_dept` (`deptId`, `at`),
            CONSTRAINT `fk_es_car_dept` FOREIGN KEY (`deptId`) REFERENCES `es_departments` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
        { 'es_dept_personnel', [[CREATE TABLE IF NOT EXISTS `es_dept_personnel` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `deptId` INT UNSIGNED NOT NULL,
            `charId` INT UNSIGNED NOT NULL,
            `kind` VARCHAR(12) NOT NULL,
            `title` VARCHAR(100) NOT NULL,
            `body` VARCHAR(1000) NULL,
            `visibility` VARCHAR(12) NOT NULL DEFAULT 'officer',
            `days` SMALLINT UNSIGNED NULL,
            `byCharId` INT UNSIGNED NULL,
            `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `removedAt` DATETIME NULL,
            `removedBy` INT UNSIGNED NULL,
            PRIMARY KEY (`id`),
            KEY `idx_es_pers_char` (`charId`, `deptId`),
            CONSTRAINT `fk_es_pers_dept` FOREIGN KEY (`deptId`) REFERENCES `es_departments` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
        { 'es_dept_certs', [[CREATE TABLE IF NOT EXISTS `es_dept_certs` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `deptId` INT UNSIGNED NOT NULL,
            `name` VARCHAR(40) NOT NULL,
            `icon` VARCHAR(16) NULL,
            `color` CHAR(7) NOT NULL DEFAULT '#3b82f6',
            `months` SMALLINT UNSIGNED NULL,
            `minLevel` INT NULL,
            `prereqs` VARCHAR(200) NULL,
            `auto` VARCHAR(12) NULL,
            `sort` INT NOT NULL DEFAULT 0,
            `active` TINYINT(1) NOT NULL DEFAULT 1,
            `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_es_cert_dept` (`deptId`, `active`),
            CONSTRAINT `fk_es_cert_dept` FOREIGN KEY (`deptId`) REFERENCES `es_departments` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
        { 'es_dept_cert_holders', [[CREATE TABLE IF NOT EXISTS `es_dept_cert_holders` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `deptId` INT UNSIGNED NOT NULL,
            `certId` INT UNSIGNED NOT NULL,
            `charId` INT UNSIGNED NOT NULL,
            `grantedBy` INT UNSIGNED NULL,
            `grantedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `expiresAt` DATETIME NULL,
            `note` VARCHAR(300) NULL,
            `auto` VARCHAR(12) NULL,
            `revokedAt` DATETIME NULL,
            `revokedBy` INT UNSIGNED NULL,
            `revokeNote` VARCHAR(300) NULL,
            `alerted` TINYINT UNSIGNED NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_es_ch_char` (`deptId`, `charId`),
            KEY `idx_es_ch_cert` (`certId`),
            CONSTRAINT `fk_es_ch_cert` FOREIGN KEY (`certId`) REFERENCES `es_dept_certs` (`id`) ON DELETE CASCADE,
            CONSTRAINT `fk_es_ch_dept` FOREIGN KEY (`deptId`) REFERENCES `es_departments` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
        { 'es_dept_pers_flags', [[CREATE TABLE IF NOT EXISTS `es_dept_pers_flags` (
            `jobId` INT UNSIGNED NOT NULL,
            `charId` INT UNSIGNED NOT NULL,
            `level` TINYINT UNSIGNED NOT NULL,
            `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`jobId`, `charId`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    }
    for _, t in ipairs(defs) do
        local ok, why = EsSchema.ensure(t[1], t[2], {})
        if not ok then return false, t[1] .. ': ' .. tostring(why) end
    end
    return true
end

-- ---------------------------------------------------------------- helpers

local function trim(s) return (type(s) == 'string' and (s:gsub('^%s+', ''):gsub('%s+$', ''))) or '' end
local function clean(s, max) return (trim(type(s) == 'string' and s or ''):gsub('[%c]', ' ')):sub(1, max) end
local function charOf(who) if type(who) == 'table' then return who.charId end return WC:GetCharId(who) end
local function isStaffWho(who) return type(who) == 'number' and ctx.isStaff(who) end
local function isTest(cid) return (tonumber(cid) or 0) >= TEST_BASE end
local function nowT() return os.time() end

local function may(who, d, perm)
    if isStaffWho(who) then return true end
    return WC:HasJobPermission(who, d.jobId, perm, { onDuty = false }) == true
end
local function mayPers(who, d) return may(who, d, 'personnel_manage') end
local function mayCertEdit(who, d) return may(who, d, 'personnel_manage') or may(who, d, 'canManage') end

local function levelOfChar(d, charId)
    local job = WC:GetJob(d.jobId)
    if job and job.ownerCharId == charId then return 1e9 end
    local r = WC:GetPlayerRole({ charId = charId }, d.jobId)
    return r and r.level or nil, r
end
local function myLevel(who, d)
    if isStaffWho(who) then return 1e9 end
    return levelOfChar(d, charOf(who)) or 0
end
--- may `who` act on charId's file at d? (personnel_manage, and they rank below you; staff always)
local function canActOn(who, d, charId)
    if not mayPers(who, d) then return false, 'Your rank cannot manage personnel files' end
    if isStaffWho(who) then return true end
    if charOf(who) == charId then return false, 'Another supervisor handles your own file' end
    local theirs = levelOfChar(d, charId)
    if not theirs then return false, 'They are not in this department' end
    if theirs >= myLevel(who, d) then return false, 'You can only manage people below your rank' end
    return true
end
Pers.canActOn = canActOn

local function rolesById(d)
    local out = {}
    for _, r in ipairs(WC:GetJobRoles(d.jobId) or {}) do out[r.roleId] = r end
    return out
end

local function career(deptId, charId, kind, f)
    f = f or {}
    MySQL.insert.await([[INSERT INTO `es_dept_career` (`deptId`,`charId`,`kind`,`fromRole`,`toRole`,`fromLevel`,`toLevel`,`byCharId`,`reason`,`detail`,`backfill`,`at`)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,COALESCE(FROM_UNIXTIME(?), CURRENT_TIMESTAMP))]],
        { deptId, charId, kind, f.fromRole, f.toRole, f.fromLevel, f.toLevel, f.by, f.reason and tostring(f.reason):sub(1, 500) or nil,
          f.detail and tostring(f.detail):sub(1, 200) or nil, f.backfill and 1 or 0, tonumber(f.at) })
end
Pers.career = career

local function onlineSrc(charId)
    for src, p in pairs(WC:GetPlayers({ light = true }) or {}) do if p.charId == charId then return tonumber(src) end end
end
local function notifyChar(charId, text, kind)
    local src = onlineSrc(charId)
    if src then WC:NotifyPlayer(src, text, kind or 'info', 9000) end
end
--- online people at d who hold personnel_manage (supervisors)
local function supervisorsOnline(d)
    local out = {}
    for src, p in pairs(WC:GetPlayers({ light = true }) or {}) do
        local s = tonumber(src)
        if s and p.charId and WC:HasJobPermission(s, d.jobId, 'personnel_manage', { onDuty = false }) == true then out[#out + 1] = s end
    end
    return out
end
local function mdtRefresh(what) TriggerClientEvent('es_mdt:client:refresh', -1, what or 'personnel') end

-- ---------------------------------------------------------------- who did it (rank changes come in as WHIP events)

local Expect = {}   -- ['jobId:charId'] = { by, reason, until }
function Pers.expect(jobId, charId, by, reason)
    Expect[jobId .. ':' .. charId] = { by = by, reason = reason, ['until'] = GetGameTimer() + 15000 }
end
local function takeExpect(jobId, charId)
    local k = jobId .. ':' .. charId
    local e = Expect[k]
    Expect[k] = nil
    if e and GetGameTimer() <= e['until'] then return e end
    return {}
end

AddEventHandler('whip_core:job:hired', function(e)
    if not up or type(e) ~= 'table' or not e.jobId or not e.charId then return end
    local d = ctx.byJob(e.jobId)
    if not d then return end
    local x = takeExpect(e.jobId, e.charId)
    local role = rolesById(d)[e.roleId] or {}
    career(d.id, e.charId, 'hired', { toRole = e.role or role.name, toLevel = role.level, by = e.by or x.by, reason = x.reason })
    mdtRefresh()
end)

AddEventHandler('whip_core:job:roleChanged', function(e)
    if not up or type(e) ~= 'table' or not e.jobId or not e.charId then return end
    local d = ctx.byJob(e.jobId)
    if not d then return end
    local x = takeExpect(e.jobId, e.charId)
    local roles = rolesById(d)
    local new, old = roles[e.roleId] or { name = e.role }, roles[e.oldRoleId] or {}
    local kind = 'rank'
    if new.level and old.level then kind = new.level > old.level and 'promoted' or new.level < old.level and 'demoted' or 'rank' end
    career(d.id, e.charId, kind, { fromRole = old.name, toRole = new.name or e.role, fromLevel = old.level, toLevel = new.level, by = x.by, reason = x.reason })
    mdtRefresh()
end)

AddEventHandler('whip_core:job:fired', function(e)
    if not up or type(e) ~= 'table' or not e.jobId or not e.charId then return end
    local d = ctx.byJob(e.jobId)
    if not d then return end
    local x = takeExpect(e.jobId, e.charId)
    local last = MySQL.single.await("SELECT `toRole`,`toLevel` FROM `es_dept_career` WHERE `deptId` = ? AND `charId` = ? AND `toRole` IS NOT NULL ORDER BY `at` DESC, `id` DESC LIMIT 1", { d.id, e.charId }) or {}
    career(d.id, e.charId, 'left', { fromRole = last.toRole, fromLevel = last.toLevel, by = x.by, reason = x.reason })
    mdtRefresh()
end)

-- ---------------------------------------------------------------- backfill (once per person: their hire, from WHIP's employee row)

local function backfill()
    local seen = {}
    for _, r in ipairs(MySQL.query.await('SELECT DISTINCT `deptId`,`charId` FROM `es_dept_career`') or {}) do seen[r.deptId .. ':' .. r.charId] = true end
    for _, d in ipairs(ctx.sortedDepts()) do
        local created = MySQL.single.await('SELECT UNIX_TIMESTAMP(`createdAt`) AS `t` FROM `es_departments` WHERE `id` = ?', { d.id })
        local emp = {}
        for _, r in ipairs(MySQL.query.await('SELECT `charId`,`hiredBy`,UNIX_TIMESTAMP(`hiredAt`) AS `t` FROM `job_employees` WHERE `jobId` = ?', { d.jobId }) or {}) do emp[r.charId] = r end
        for _, m in ipairs(ctx.rosterOf(d)) do
            if not seen[d.id .. ':' .. m.charId] then
                local e = emp[m.charId] or {}
                career(d.id, m.charId, 'hired', { toRole = m.roleName, toLevel = m.roleLevel, by = e.hiredBy, backfill = true,
                    detail = m.owner and not emp[m.charId] and 'Department owner' or nil, at = e.t or (created and created.t) })
            end
        end
    end
    -- rank changes and departures the MDT / panel logged before 1.5.0 (WHIP activity log)
    if GetResourceKvpString('es_departments:pers_backfill_1') ~= '1' then
        for _, r in ipairs(MySQL.query.await([[SELECT `ts`,`charId`,`event`,`detail` FROM `activity_log`
            WHERE `event` IN ('es_departments_set_rank','es_departments_fired') ORDER BY `id`]]) or {}) do
            local short, cid, roleId = tostring(r.detail or ''):match('^(%w+): char (%d+) %-> role (%d+)')
            local d = short and ctx.resolve(short)
            if d and r.event == 'es_departments_set_rank' then
                local role = rolesById(d)[tonumber(roleId)] or {}
                career(d.id, tonumber(cid), 'rank', { toRole = role.name, toLevel = role.level, by = r.charId, backfill = true, at = r.ts })
            elseif r.event == 'es_departments_fired' then
                local s2, c2 = tostring(r.detail or ''):match('^(%w+): char (%d+)')
                local d2 = s2 and ctx.resolve(s2)
                if d2 then career(d2.id, tonumber(c2), 'left', { by = r.charId, backfill = true, at = r.ts }) end
            end
        end
        SetResourceKvp('es_departments:pers_backfill_1', '1')
    end
end

-- ---------------------------------------------------------------- certifications

local DEFAULT_CERTS = {
    { 'FTO', '🎓', '#f2c230', nil, 30, nil, 'fto' },
    { 'SWAT', '🛡', '#ef4444', 12, 30 },
    { 'K9', '🐕', '#b45309', 12, 30 },
    { 'Air Unit', '🚁', '#38bdf8', 12, 30 },
    { 'Marine', '⚓', '#0ea5e9', 12, 30 },
    { 'Traffic/Motor', '🏍', '#f97316', 12, 30 },
    { 'Detective/CID', '🕵', '#8b5cf6', nil, 30 },
    { 'Crisis Negotiator', '🗣', '#14b8a6', 24, 30 },
    { 'Firearms Instructor', '🎯', '#dc2626', 24, 30 },
    { 'EVOC/Pursuit', '🚓', '#3b82f6', 24, nil, nil, 'graduate' },
    { 'Medical/First Aid', '⛑', '#22c55e', 24 },
    { 'Supervisor', '⭐', '#eab308', nil, 60 },
}
local LAWTYPES = { police = true, sheriff = true, state = true }

local function seedCerts()
    for _, d in ipairs(ctx.sortedDepts()) do
        local kvp = 'es_departments:certs_seed:' .. d.id
        if GetResourceKvpString(kvp) ~= '1' then
            local n = MySQL.single.await('SELECT COUNT(*) AS `n` FROM `es_dept_certs` WHERE `deptId` = ?', { d.id })
            if LAWTYPES[d.type] and n and tonumber(n.n) == 0 then
                for i, c in ipairs(DEFAULT_CERTS) do
                    MySQL.insert.await('INSERT INTO `es_dept_certs` (`deptId`,`name`,`icon`,`color`,`months`,`minLevel`,`prereqs`,`auto`,`sort`) VALUES (?,?,?,?,?,?,?,?,?)',
                        { d.id, c[1], c[2], c[3], c[4], c[5], c[6], c[7], i })
                end
            end
            SetResourceKvp(kvp, '1')
        end
    end
end

local function idsOf(s)
    local out = {}
    for x in tostring(s or ''):gmatch('%d+') do out[#out + 1] = tonumber(x) end
    return out
end

local function certDefs(d, all)
    local rows = MySQL.query.await(('SELECT `id`,`name`,`icon`,`color`,`months`,`minLevel`,`prereqs`,`auto`,`sort`,`active` FROM `es_dept_certs` WHERE `deptId` = ?%s ORDER BY `sort`,`id`')
        :format(all and '' or ' AND `active` = 1'), { d.id }) or {}
    for _, r in ipairs(rows) do r.prereqs = idsOf(r.prereqs) r.active = r.active == 1 or r.active == true end
    return rows
end

local function stateOf(exp, t)
    if not exp then return 'valid' end
    if exp <= t then return 'expired' end
    if exp - t <= soon() then return 'expiring' end
    return 'valid'
end

--- every holder row (active only unless opts.history) at d, optionally for one person
local function holders(d, charId, history)
    local q = [[SELECT h.`id`,h.`certId`,h.`charId`,h.`grantedBy`,UNIX_TIMESTAMP(h.`grantedAt`) AS `grantedAt`,UNIX_TIMESTAMP(h.`expiresAt`) AS `expiresAt`,
        h.`note`,h.`auto`,UNIX_TIMESTAMP(h.`revokedAt`) AS `revokedAt`,h.`revokedBy`,h.`revokeNote`,c.`name`,c.`icon`,c.`color`
        FROM `es_dept_cert_holders` h JOIN `es_dept_certs` c ON c.`id` = h.`certId` WHERE h.`deptId` = ?]]
    local args = { d.id }
    if charId then q = q .. ' AND h.`charId` = ?' args[#args + 1] = charId end
    if not history then q = q .. ' AND h.`revokedAt` IS NULL AND c.`active` = 1' end
    q = q .. ' ORDER BY c.`sort`, h.`grantedAt` DESC'
    local rows = MySQL.query.await(q, args) or {}
    local t = nowT()
    for _, r in ipairs(rows) do r.state = r.revokedAt and 'revoked' or stateOf(r.expiresAt, t) end
    return rows
end

local function hasCert(d, charId, certId)
    local r = MySQL.single.await([[SELECT 1 AS `x` FROM `es_dept_cert_holders` WHERE `deptId` = ? AND `charId` = ? AND `certId` = ? AND `revokedAt` IS NULL
        AND (`expiresAt` IS NULL OR `expiresAt` > NOW()) LIMIT 1]], { d.id, charId, certId })
    return r ~= nil
end
local function certByName(d, name)
    return MySQL.single.await('SELECT `id`,`name` FROM `es_dept_certs` WHERE `deptId` = ? AND `active` = 1 AND LOWER(`name`) = LOWER(?) LIMIT 1', { d.id, tostring(name or '') })
end
function Pers.hasCertNamed(d, charId, name)
    local c = certByName(d, name)
    if not c then return true end   -- no such cert in this department: nothing to require
    return hasCert(d, charId, c.id)
end

--- grant (or renew) a cert. f: { by (charId), note, expiresAt (unix) | nil = from months, auto, skipChecks }
local function grant(d, charId, cert, f)
    f = f or {}
    if not f.skipChecks then
        if cert.minLevel then
            local lv = levelOfChar(d, charId)
            if not lv or lv < cert.minLevel then
                local need
                for _, r in ipairs(WC:GetJobRoles(d.jobId) or {}) do if (r.level or 0) >= cert.minLevel and (not need or r.level < need.level) then need = r end end
                return false, ('%s needs the rank of %s or higher'):format(cert.name, need and need.name or ('level ' .. cert.minLevel))
            end
        end
        for _, pid in ipairs(cert.prereqs or {}) do
            if not hasCert(d, charId, pid) then
                local p = MySQL.single.await('SELECT `name` FROM `es_dept_certs` WHERE `id` = ?', { pid })
                return false, ('%s needs a valid %s certification first'):format(cert.name, p and p.name or 'other')
            end
        end
    end
    local exp = tonumber(f.expiresAt)   -- 1.5.1: only a real unix time; false/'' meant "no expiry" and broke FROM_UNIXTIME
    if exp == nil and not f.noMonths and cert.months and cert.months > 0 then exp = nowT() + cert.months * 30 * 86400 end
    if exp and exp <= nowT() then return false, 'The expiry date has to be in the future' end
    local okDb, dbWhy = pcall(function()
    local cur = MySQL.single.await('SELECT `id` FROM `es_dept_cert_holders` WHERE `deptId` = ? AND `charId` = ? AND `certId` = ? AND `revokedAt` IS NULL LIMIT 1', { d.id, charId, cert.id })
    f._renew = cur ~= nil
    if cur then
        MySQL.update.await('UPDATE `es_dept_cert_holders` SET `grantedBy` = ?, `grantedAt` = NOW(), `expiresAt` = FROM_UNIXTIME(?), `note` = ?, `alerted` = 0 WHERE `id` = ?',
            { f.by, exp, f.note, cur.id })
        career(d.id, charId, 'cert_renew', { toRole = cert.name, by = f.by, reason = f.note, detail = exp and ('until ' .. os.date('!%Y-%m-%d', exp)) or nil })
    else
        MySQL.insert.await('INSERT INTO `es_dept_cert_holders` (`deptId`,`certId`,`charId`,`grantedBy`,`expiresAt`,`note`,`auto`) VALUES (?,?,?,?,FROM_UNIXTIME(?),?,?)',
            { d.id, cert.id, charId, f.by, exp, f.note, f.auto })
        career(d.id, charId, 'cert_grant', { toRole = cert.name, by = f.by, reason = f.note,
            detail = (f.auto == 'graduate' and 'automatic: graduated field training ' or f.auto == 'fto' and 'automatic: made an FTO ' or '') .. (exp and ('until ' .. os.date('!%Y-%m-%d', exp)) or 'no expiry') })
    end
    end)
    if not okDb then
        print(('^1[es_departments] granting %s to %d failed: %s^7'):format(cert.name, charId, tostring(dbWhy)))
        return false, ('Could not save the %s certification (database error, logged for the admin)'):format(cert.name)
    end
    if not isTest(charId) then notifyChar(charId, ('%s: you %s the %s certification'):format(d.short, f._renew and 'renewed' or 'earned', cert.name), 'success') end
    mdtRefresh()
    return true
end

--- auto-grant every cert at d set to `when` ('graduate' | 'fto') that they do not hold yet
function Pers.autoGrant(d, charId, when, who)
    if not up or not d or not charId or isTest(charId) then return end
    for _, c in ipairs(certDefs(d)) do
        if c.auto == when and not hasCert(d, charId, c.id) then
            local ok, why = grant(d, charId, c, { by = who and charOf(who) or nil, auto = when, skipChecks = true })
            if not ok then print(('^3[es_departments] auto cert %s for %d: %s^7'):format(c.name, charId, tostring(why))) end
        end
    end
end

-- ---------------------------------------------------------------- the personnel file

local KIND_ENTRY = { commend = 'Commendation', warning = 'Written warning', suspension = 'Suspension', note = 'Note' }

local function memberAt(d, charId)
    for _, m in ipairs(ctx.fillOnline(ctx.rosterOf(d))) do if m.charId == charId then m.source = nil return m end end
end

local function dutyOf(charId)
    local t = nowT()
    local rows = MySQL.query.await([[SELECT `jobId`, UNIX_TIMESTAMP(`startedAt`) AS `s`, UNIX_TIMESTAMP(COALESCE(`endedAt`, NOW())) AS `e`, `endedAt` IS NULL AS `open`
        FROM `es_duty_sessions` WHERE `charId` = ?]], { charId }) or {}
    local all, d7, d30, last, weeks = 0, 0, 0, nil, {}
    for i = 1, 12 do weeks[i] = 0 end
    for _, r in ipairs(rows) do
        local a, b = tonumber(r.s) or 0, math.min(tonumber(r.e) or 0, t)
        if b > a then
            all = all + (b - a)
            d7 = d7 + math.max(0, b - math.max(a, t - 7 * 86400))
            d30 = d30 + math.max(0, b - math.max(a, t - 30 * 86400))
            for i = 1, 12 do   -- week 12 = the last 7 days, week 1 = 12 weeks ago
                local ws, we = t - (13 - i) * 7 * 86400, t - (12 - i) * 7 * 86400
                local piece = math.min(b, we) - math.max(a, ws)
                if piece > 0 then weeks[i] = weeks[i] + piece end
            end
            local fin = (r.open == 1 or r.open == true) and t or b
            if not last or fin > last then last = fin end
        end
    end
    return { all = all, d7 = d7, d30 = d30, weeks = weeks, last = last }
end

--- The file as `who` may see it. ref = the viewer's department (the file is read in that department when the
--- officer belongs to it, else in their first one). view: 'super' (personnel_manage over them, or staff),
--- 'self', or 'peer' (anyone else in a department: header, stats, certifications, public career only).
exports('GetPersonnelFile', function(who, ref, charId)
    if not up then return false, 'Personnel files are starting' end
    charId = tonumber(charId)
    if not charId then return false, 'Pick someone' end
    local vd = ctx.resolve(ref)
    local viewer = charOf(who)
    local staff = isStaffWho(who)
    -- every department they belong to
    local depts, d, m = {}, nil, nil
    for _, x in ipairs(ctx.sortedDepts()) do
        local mm = memberAt(x, charId)
        if mm then
            depts[#depts + 1] = { id = x.id, short = x.short, name = x.name, color1 = x.color1, color2 = x.color2, roleName = mm.roleName,
                roleLevel = mm.roleLevel, callsign = mm.callsign, badge = mm.badge, onDuty = mm.onDuty, owner = mm.owner }
            if (vd and x.id == vd.id) or not d then d, m = x, mm end
        end
    end
    local name = (ctx.namesOf({ charId }) or {})[charId]
    if not d then
        -- not in any department now: staff and the viewer's supervisors still read what is on file (former members)
        if not name then return false, 'Nobody by that id' end
        local any = MySQL.single.await('SELECT `deptId` FROM `es_dept_career` WHERE `charId` = ? ORDER BY `at` DESC LIMIT 1', { charId })
        d = any and ctx.resolve(any.deptId) or vd
        if not d then return false, 'They have never been in a department' end
        m = { charId = charId, name = name, former = true }
    end
    m.name = m.name or name or ('#' .. charId)
    -- who is looking
    local view = 'peer'
    if staff then view = 'super'
    elseif viewer == charId then view = 'self'
    elseif mayPers(who, d) and (m.former or (levelOfChar(d, charId) or 0) < myLevel(who, d)) then view = 'super' end
    if view == 'peer' then
        local inAny = false
        for _, x in ipairs(ctx.sortedDepts()) do if levelOfChar(x, viewer or 0) then inAny = true break end end
        if not inAny then return false, 'Only department members read personnel files' end
    end
    local full = view ~= 'peer'
    if view ~= 'super' then m.notes = nil end   -- roster notes are for supervisors
    local t = nowT()

    -- status: duty, leave, inactivity
    local act
    if not m.former and Duty.membersOf then
        for _, x in ipairs(Duty.membersOf(d, 30) or {}) do if x.charId == charId then act = x end end
    end
    local duty = dutyOf(charId)
    m.lastDuty = (act and act.lastDuty) or duty.last
    m.onLeave = act and act.loa ~= nil or false
    m.loa = act and act.loa or nil
    m.inactiveDays = act and act.inactiveDays or nil
    m.level = act and act.level or 0

    -- career rows (all departments) and names
    local rows = MySQL.query.await([[SELECT `id`,`deptId`,`kind`,`fromRole`,`toRole`,`fromLevel`,`toLevel`,`byCharId`,`reason`,`detail`,`backfill`,UNIX_TIMESTAMP(`at`) AS `at`
        FROM `es_dept_career` WHERE `charId` = ? ORDER BY `at` DESC, `id` DESC LIMIT 400]], { charId }) or {}
    local entries = MySQL.query.await(([[SELECT `id`,`deptId`,`kind`,`title`,`body`,`visibility`,`days`,`byCharId`,UNIX_TIMESTAMP(`at`) AS `at`
        FROM `es_dept_personnel` WHERE `charId` = ? AND `removedAt` IS NULL%s ORDER BY `at` DESC LIMIT 200]]):format(view == 'self' and " AND `visibility` = 'officer'" or ''), { charId }) or {}
    if view == 'peer' then entries = {} end
    local ftoRows = MySQL.query.await([[SELECT h.`deptId`,h.`action`,h.`detail`,h.`actorCharId`,UNIX_TIMESTAMP(h.`at`) AS `at` FROM `es_fto_history` h
        WHERE h.`traineeCharId` = ? AND h.`action` IN ('queued','assigned','phase_done','ready','completed','promoted','left','recommended') ORDER BY h.`at` DESC LIMIT 120]], { charId }) or {}
    local loas = full and (MySQL.query.await([[SELECT `id`,`deptId`,`status`,UNIX_TIMESTAMP(`startsAt`) AS `startsAt`,UNIX_TIMESTAMP(`endsAt`) AS `endsAt`,`reason`,`decidedBy`,`decisionNote`,
        UNIX_TIMESTAMP(`createdAt`) AS `createdAt` FROM `es_dept_loa` WHERE `charId` = ? ORDER BY `startsAt` DESC LIMIT 50]], { charId }) or {}) or {}

    local ids = {}
    local function addId(x) if x then ids[#ids + 1] = x end end
    for _, r in ipairs(rows) do addId(r.byCharId) end
    for _, r in ipairs(entries) do addId(r.byCharId) end
    for _, r in ipairs(ftoRows) do addId(r.actorCharId) end
    for _, r in ipairs(loas) do addId(r.decidedBy) end
    local names = ctx.namesOf(ids)
    local function nm(x) return x and (names[x] or ('#' .. x)) or nil end
    local function short(id2) local x = ctx.resolve(id2) return x and x.short or '' end

    -- rank since: the newest rank line where they are now
    local rankSince
    for _, r in ipairs(rows) do
        if r.deptId == d.id and r.toRole and (r.kind == 'hired' or r.kind == 'promoted' or r.kind == 'demoted' or r.kind == 'rank') then rankSince = r.at break end
    end
    m.rankSince = rankSince or (m.hiredAt and tonumber(m.hiredAt)) or nil
    local hired
    for _, r in ipairs(rows) do if r.deptId == d.id and r.kind == 'hired' then hired = r.at end end
    m.hiredAt = hired or m.hiredAt

    -- the timeline
    local tl = {}
    local function add(x) tl[#tl + 1] = x end
    local PEER_OK = { hired = true, promoted = true, rank = true, cert_grant = true, cert_renew = true }
    for _, r in ipairs(rows) do
        if full or PEER_OK[r.kind] then
            local x = { at = r.at, kind = r.kind, dept = short(r.deptId), by = nm(r.byCharId), backfill = r.backfill == 1 or nil }
            if r.kind == 'hired' then x.title = ('Joined %s%s'):format(x.dept, r.toRole and (' as ' .. r.toRole) or '') x.detail = r.detail
            elseif r.kind == 'left' then x.title = ('Left %s'):format(x.dept) x.detail = r.fromRole and ('was ' .. r.fromRole) or nil
            elseif r.kind == 'promoted' then x.title = 'Promoted to ' .. (r.toRole or '?') x.detail = r.fromRole and ('from ' .. r.fromRole) or nil
            elseif r.kind == 'demoted' then x.title = 'Demoted to ' .. (r.toRole or '?') x.detail = r.fromRole and ('from ' .. r.fromRole) or nil
            elseif r.kind == 'rank' then x.title = 'Rank set to ' .. (r.toRole or '?') x.detail = r.fromRole and ('was ' .. r.fromRole) or nil
            elseif r.kind == 'cert_grant' then x.title = 'Certified: ' .. (r.toRole or '?') x.detail = r.detail
            elseif r.kind == 'cert_renew' then x.title = 'Certification renewed: ' .. (r.toRole or '?') x.detail = r.detail
            elseif r.kind == 'cert_revoke' then x.title = 'Certification revoked: ' .. (r.toRole or '?')
            elseif r.kind == 'cert_expired' then x.title = 'Certification expired: ' .. (r.toRole or '?') x.by = nil
            elseif r.kind == 'inactive' then x.title = 'Inactivity ' .. (r.toRole or 'warning') x.detail = r.detail x.by = nil
            else x.title = r.kind end
            if full and r.reason then x.reason = r.reason end
            add(x)
        end
    end
    for _, r in ipairs(entries) do
        add({ at = r.at, kind = 'entry_' .. r.kind, dept = short(r.deptId), by = nm(r.byCharId), title = (KIND_ENTRY[r.kind] or r.kind) .. ': ' .. r.title,
            reason = r.body, private = r.visibility ~= 'officer' or nil, entryId = r.id, days = r.days })
    end
    local FT = { queued = 'Started field training', assigned = 'FTO assigned', phase_done = 'Training phase complete', ready = 'Every training item signed',
        completed = 'Graduated field training', promoted = 'Promoted after training', left = 'Left training', recommended = 'Recommended for promotion' }
    local FT_PEER = { queued = true, completed = true }
    for _, r in ipairs(ftoRows) do
        if full or FT_PEER[r.action] then
            add({ at = r.at, kind = 'fto_' .. r.action, dept = short(r.deptId), by = nm(r.actorCharId), title = FT[r.action] or r.action, detail = r.detail,
                training = { deptId = r.deptId, charId = charId } })
        end
    end
    for _, l in ipairs(loas) do
        if l.status == 'approved' or l.status == 'ended' then
            add({ at = l.startsAt, kind = 'loa', dept = short(l.deptId), title = 'Leave of absence', detail = os.date('!%b %d', l.startsAt) .. ' → ' .. os.date('!%b %d, %Y', l.endsAt),
                reason = l.reason, by = nm(l.decidedBy) })
        end
    end
    table.sort(tl, function(a, b) return (a.at or 0) > (b.at or 0) end)

    -- training as trainee / as FTO
    local tr = MySQL.query.await([[SELECT `deptId`,`status`,`ftoCharId`,UNIX_TIMESTAMP(`hiredAt`) AS `startedAt`,UNIX_TIMESTAMP(`doneAt`) AS `doneAt`,`doneBy`
        FROM `es_fto_trainees` WHERE `charId` = ? AND `test` = 0]], { charId }) or {}
    local tids = {}
    for _, r in ipairs(tr) do addId(r.ftoCharId) tids[#tids + 1] = r.ftoCharId tids[#tids + 1] = r.doneBy end
    local tn = ctx.namesOf(tids)
    for _, r in ipairs(tr) do
        r.dept = short(r.deptId) r.ftoName = r.ftoCharId and tn[r.ftoCharId] or nil r.doneByName = r.doneBy and tn[r.doneBy] or nil
        local okp, prog = pcall(function() return exports.es_departments:GetTraineeFile(r.deptId, charId) end)
        if okp and type(prog) == 'table' and prog.trainee then r.pct = (prog.trainee.progress or {}).pct end
    end
    local asFto = MySQL.single.await([[SELECT COUNT(*) AS `dors`, COUNT(DISTINCT `traineeCharId`) AS `trainees`, COALESCE(SUM(`minutes`),0) AS `minutes`, UNIX_TIMESTAMP(MAX(`sessionAt`)) AS `last`
        FROM `es_fto_sessions` WHERE `ftoCharId` = ?]], { charId }) or {}
    local grads = MySQL.single.await([[SELECT COUNT(*) AS `n` FROM `es_fto_trainees` WHERE `ftoCharId` = ? AND `status` IN ('promoted','signed_off') AND `test` = 0]], { charId }) or {}
    local now_ = MySQL.single.await([[SELECT COUNT(*) AS `n` FROM `es_fto_trainees` WHERE `ftoCharId` = ? AND `status` = 'training']], { charId }) or {}

    -- certifications at d (history for self/super)
    local certs = holders(d, charId, full)
    local cn = {}
    for _, c in ipairs(certs) do cn[#cn + 1] = c.grantedBy cn[#cn + 1] = c.revokedBy end
    local cnames = ctx.namesOf(cn)
    for _, c in ipairs(certs) do c.grantedByName = c.grantedBy and cnames[c.grantedBy] or nil c.revokedByName = c.revokedBy and cnames[c.revokedBy] or nil
        if not full then c.note, c.revokeNote = nil, nil end end

    local counts = { commend = 0, warning = 0, suspension = 0, note = 0 }
    for _, e in ipairs(entries) do counts[e.kind] = (counts[e.kind] or 0) + 1 end
    local canAct = view == 'super' and (staff or viewer ~= charId) and not m.former
    return {
        view = view, member = m, dept = { id = d.id, short = d.short, name = d.name, color1 = d.color1, color2 = d.color2 }, depts = depts,
        duty = duty, timeline = tl, training = tr,
        asFto = { dors = tonumber(asFto.dors) or 0, trainees = tonumber(asFto.trainees) or 0, minutes = tonumber(asFto.minutes) or 0,
            last = tonumber(asFto.last), graduated = tonumber(grads.n) or 0, current = tonumber(now_.n) or 0 },
        certs = certs, counts = full and counts or nil,
        can = { entries = canAct and mayPers(who, d), certs = canAct and mayPers(who, d), photo = view == 'self' or canAct },
        certDefs = canAct and certDefs(d) or nil, alertDays = math.floor(soon() / 86400),
    }
end)

exports('CanManagePersonnel', function(who, ref, charId)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    return canActOn(who, d, tonumber(charId) or 0)
end)

--- data: { kind = commend|warning|suspension|note, title, body, visibility = officer|supervisors, days }
exports('AddPersonnelEntry', function(who, ref, charId, data)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    charId = tonumber(charId) or 0
    local ok, why = canActOn(who, d, charId)
    if not ok then return false, why end
    data = type(data) == 'table' and data or {}
    local kind = KIND_ENTRY[data.kind] and data.kind or nil
    if not kind then return false, 'Pick what kind of entry this is' end
    local title = clean(data.title, 100)
    if #title < 3 then return false, 'Give it a short title' end
    local body = clean(data.body, 1000)
    local vis = data.visibility == 'supervisors' and 'supervisors' or 'officer'
    local days = kind == 'suspension' and math.max(1, math.min(365, math.floor(tonumber(data.days) or 1))) or nil
    local id = MySQL.insert.await('INSERT INTO `es_dept_personnel` (`deptId`,`charId`,`kind`,`title`,`body`,`visibility`,`days`,`byCharId`) VALUES (?,?,?,?,?,?,?,?)',
        { d.id, charId, kind, title, body ~= '' and body or nil, vis, days, charOf(who) })
    if not id then return false, 'Could not save that (database error)' end
    if vis == 'officer' then
        notifyChar(charId, ('%s: a %s was added to your personnel file. MDT → My profile'):format(d.short, (KIND_ENTRY[kind]):lower()), kind == 'commend' and 'success' or 'inform')
    end
    if type(who) == 'number' then CreateThread(function() WC:LogActivity(who, 'es_departments_personnel', { detail = ('%s #%d %s: %s'):format(d.short, charId, kind, title) }) end) end
    mdtRefresh()
    return id
end)

exports('RemovePersonnelEntry', function(who, ref, entryId)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    local e = MySQL.single.await('SELECT `charId`,`deptId` FROM `es_dept_personnel` WHERE `id` = ? AND `removedAt` IS NULL', { tonumber(entryId) or 0 })
    if not e or e.deptId ~= d.id then return false, 'That entry is not on file here' end
    local ok, why = canActOn(who, d, e.charId)
    if not ok then return false, why end
    MySQL.update.await('UPDATE `es_dept_personnel` SET `removedAt` = NOW(), `removedBy` = ? WHERE `id` = ?', { charOf(who), tonumber(entryId) })
    mdtRefresh()
    return true
end)

-- certifications: the list
exports('GetCerts', function(ref, opts)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    local defs = certDefs(d)
    local cnt = {}
    for _, r in ipairs(MySQL.query.await([[SELECT `certId`, COUNT(*) AS `n`, SUM(`expiresAt` IS NOT NULL AND `expiresAt` <= NOW()) AS `expired`,
        SUM(`expiresAt` > NOW() AND `expiresAt` <= NOW() + INTERVAL ? SECOND) AS `soon` FROM `es_dept_cert_holders` WHERE `deptId` = ? AND `revokedAt` IS NULL GROUP BY `certId`]],
        { soon(), d.id }) or {}) do cnt[r.certId] = r end
    for _, c in ipairs(defs) do local x = cnt[c.id] or {} c.holders = tonumber(x.n) or 0 c.expired = tonumber(x.expired) or 0 c.soon = tonumber(x.soon) or 0 end
    return { list = defs, gateFto = (Config.Certs or {}).gateFto == true, ftoCert = (Config.Certs or {}).ftoCert or 'FTO', alertDays = math.floor(soon() / 86400) }
end)

exports('CanEditCerts', function(who, ref)
    local d = ctx.resolve(ref)
    return d ~= nil and mayCertEdit(who, d)
end)

--- list = { { id?, name, icon, color, months, minLevel, prereqs = {ids or names}, auto }, ... } in order. Missing ids are retired.
exports('SaveCerts', function(who, ref, list)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    if not mayCertEdit(who, d) then return false, 'Only department heads or personnel supervisors edit certifications' end
    if type(list) ~= 'table' or #list > 40 then return false, 'Up to 40 certifications' end
    local old = {}
    for _, c in ipairs(certDefs(d, true)) do old[c.id] = c end
    local seenName, keep, order = {}, {}, {}
    for i, c in ipairs(list) do
        if type(c) ~= 'table' then return false, 'Bad list' end
        local name = clean(c.name, 40)
        if #name < 2 then return false, ('Certification %d needs a name'):format(i) end
        if seenName[name:lower()] then return false, ('"%s" is in the list twice'):format(name) end
        seenName[name:lower()] = true
        local color = type(c.color) == 'string' and c.color:match('^#%x%x%x%x%x%x$') and c.color or '#3b82f6'
        local icon = clean(c.icon, 16)
        local months = tonumber(c.months) and math.floor(tonumber(c.months)) or nil
        if months and (months < 1 or months > 120) then months = nil end
        local minLevel = tonumber(c.minLevel) and math.floor(tonumber(c.minLevel)) or nil
        local auto = (c.auto == 'graduate' or c.auto == 'fto') and c.auto or nil
        local id = tonumber(c.id)
        if id and not old[id] then id = nil end
        order[#order + 1] = { id = id, name = name, icon = icon ~= '' and icon or nil, color = color, months = months, minLevel = minLevel, auto = auto,
            prereqs = type(c.prereqs) == 'table' and c.prereqs or {}, sort = i }
    end
    -- save rows (ids first, prerequisites by id after)
    for _, c in ipairs(order) do
        if c.id then
            MySQL.update.await('UPDATE `es_dept_certs` SET `name`=?,`icon`=?,`color`=?,`months`=?,`minLevel`=?,`auto`=?,`sort`=?,`active`=1 WHERE `id`=? AND `deptId`=?',
                { c.name, c.icon, c.color, c.months, c.minLevel, c.auto, c.sort, c.id, d.id })
        else
            c.id = MySQL.insert.await('INSERT INTO `es_dept_certs` (`deptId`,`name`,`icon`,`color`,`months`,`minLevel`,`auto`,`sort`) VALUES (?,?,?,?,?,?,?,?)',
                { d.id, c.name, c.icon, c.color, c.months, c.minLevel, c.auto, c.sort })
        end
        keep[c.id] = true
    end
    local byName = {}
    for _, c in ipairs(order) do byName[c.name:lower()] = c.id end
    for _, c in ipairs(order) do
        local pre = {}
        for _, p in ipairs(c.prereqs) do
            local pid = tonumber(p) and keep[tonumber(p)] and tonumber(p) or (type(p) == 'string' and byName[p:lower()]) or nil
            if pid and pid ~= c.id then pre[#pre + 1] = tostring(pid) end
        end
        MySQL.update.await('UPDATE `es_dept_certs` SET `prereqs` = ? WHERE `id` = ?', { #pre > 0 and table.concat(pre, ',') or nil, c.id })
    end
    for id2 in pairs(old) do if not keep[id2] then MySQL.update.await('UPDATE `es_dept_certs` SET `active` = 0 WHERE `id` = ?', { id2 }) end end
    if type(who) == 'number' then CreateThread(function() WC:LogActivity(who, 'es_departments_certs', { detail = ('%s: %d certifications'):format(d.short, #order) }) end) end
    mdtRefresh()
    return true
end)

--- data: { note, expiresAt (unix, optional; nil = the cert's months), noExpiry = true }
exports('GrantCert', function(who, ref, charId, certId, data)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    charId = tonumber(charId) or 0
    local ok, why = canActOn(who, d, charId)
    if not ok then return false, why end
    local cert
    for _, c in ipairs(certDefs(d)) do if c.id == tonumber(certId) then cert = c end end
    if not cert then return false, 'No such certification here' end
    data = type(data) == 'table' and data or {}
    local noExpiry = data.noExpiry == true
    local exp = (not noExpiry) and tonumber(data.expiresAt) or nil   -- 1.5.1: was `exp == false and nil or exp`, which stays false
    local note = clean(data.note, 300)
    return grant(d, charId, cert, { by = charOf(who), note = note ~= '' and note or nil, expiresAt = exp,
        skipChecks = isStaffWho(who) and data.force == true, noMonths = noExpiry })
end)

exports('RevokeCert', function(who, ref, holderId, note)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    local h = MySQL.single.await([[SELECT h.`charId`,h.`deptId`,c.`name` FROM `es_dept_cert_holders` h JOIN `es_dept_certs` c ON c.`id` = h.`certId`
        WHERE h.`id` = ? AND h.`revokedAt` IS NULL]], { tonumber(holderId) or 0 })
    if not h or h.deptId ~= d.id then return false, 'They do not hold that certification' end
    local ok, why = canActOn(who, d, h.charId)
    if not ok then return false, why end
    note = clean(note, 300)
    if #note < 3 then return false, 'Say why it is revoked' end
    MySQL.update.await('UPDATE `es_dept_cert_holders` SET `revokedAt` = NOW(), `revokedBy` = ?, `revokeNote` = ? WHERE `id` = ?', { charOf(who), note, tonumber(holderId) })
    career(d.id, h.charId, 'cert_revoke', { toRole = h.name, by = charOf(who), reason = note })
    notifyChar(h.charId, ('%s: your %s certification was revoked'):format(d.short, h.name), 'error')
    mdtRefresh()
    return true
end)

--- { [charId] = { { certId, name, icon, color, state, expiresAt } } } for the roster (active and not revoked)
exports('GetCertBadges', function(ref)
    local d = ctx.resolve(ref)
    if not d then return {} end
    local out = {}
    for _, h in ipairs(holders(d, nil, false)) do
        out[h.charId] = out[h.charId] or {}
        table.insert(out[h.charId], { holderId = h.id, certId = h.certId, name = h.name, icon = h.icon, color = h.color, state = h.state, expiresAt = h.expiresAt })
    end
    return out
end)

--- active certs expiring within the alert window, or already expired (supervisors renew or revoke them)
exports('GetCertAlerts', function(ref)
    local d = ctx.resolve(ref)
    if not d then return {} end
    local out, ids = {}, {}
    for _, h in ipairs(holders(d, nil, false)) do
        if h.state == 'expiring' or h.state == 'expired' then out[#out + 1] = h ids[#ids + 1] = h.charId end
    end
    local names = ctx.namesOf(ids)
    for _, h in ipairs(out) do h.officer = names[h.charId] or ('#' .. h.charId) end
    table.sort(out, function(a, b) return (a.expiresAt or 0) < (b.expiresAt or 0) end)
    return out
end)

exports('HasCert', function(ref, charId, cert)
    local d = ctx.resolve(ref)
    if not d then return false end
    if tonumber(cert) then return hasCert(d, tonumber(charId) or 0, tonumber(cert)) end
    local c = certByName(d, cert)
    return c ~= nil and hasCert(d, tonumber(charId) or 0, c.id)
end)

-- ---------------------------------------------------------------- the checks: cert expiry alerts, inactivity warnings

local LV = { 'note', 'warning', 'step-in' }
local function check()
    -- certifications about to expire (once) and expired (once)
    local rows = MySQL.query.await([[SELECT h.`id`,h.`deptId`,h.`charId`,h.`alerted`,UNIX_TIMESTAMP(h.`expiresAt`) AS `exp`,c.`name` FROM `es_dept_cert_holders` h
        JOIN `es_dept_certs` c ON c.`id` = h.`certId` WHERE h.`revokedAt` IS NULL AND c.`active` = 1 AND h.`expiresAt` IS NOT NULL
        AND h.`expiresAt` <= NOW() + INTERVAL ? SECOND AND h.`alerted` < 2]], { soon() }) or {}
    local t = nowT()
    local ids = {}
    for _, r in ipairs(rows) do ids[#ids + 1] = r.charId end
    local names = ctx.namesOf(ids)
    for _, r in ipairs(rows) do
        local d = ctx.resolve(r.deptId)
        if d then
            local who = names[r.charId] or ('#' .. r.charId)
            if r.exp <= t then
                MySQL.update.await('UPDATE `es_dept_cert_holders` SET `alerted` = 2 WHERE `id` = ?', { r.id })
                career(d.id, r.charId, 'cert_expired', { toRole = r.name })
                notifyChar(r.charId, ('%s: your %s certification expired'):format(d.short, r.name), 'error')
                for _, s in ipairs(supervisorsOnline(d)) do WC:NotifyPlayer(s, ('%s: %s\'s %s certification expired. MDT → Department → Certifications'):format(d.short, who, r.name), 'warning', 10000) end
            elseif r.alerted == 0 then
                MySQL.update.await('UPDATE `es_dept_cert_holders` SET `alerted` = 1 WHERE `id` = ?', { r.id })
                local days = math.max(0, math.ceil((r.exp - t) / 86400))
                notifyChar(r.charId, ('%s: your %s certification expires in %d day%s'):format(d.short, r.name, days, days == 1 and '' or 's'), 'warning')
                for _, s in ipairs(supervisorsOnline(d)) do WC:NotifyPlayer(s, ('%s: %s\'s %s certification expires in %d day%s'):format(d.short, who, r.name, days, days == 1 and '' or 's'), 'warning', 10000) end
            end
        end
    end
    -- inactivity: a line on their file each time they reach a new level (note, warning, step in)
    if not Duty.membersOf then return end
    local flags = {}
    for _, r in ipairs(MySQL.query.await('SELECT `jobId`,`charId`,`level` FROM `es_dept_pers_flags`') or {}) do flags[r.jobId .. ':' .. r.charId] = r.level end
    for _, d in ipairs(ctx.sortedDepts()) do
        for _, m in ipairs(Duty.membersOf(d, 30) or {}) do
            local k = d.jobId .. ':' .. m.charId
            local was = flags[k] or 0
            if (m.level or 0) > was and not m.neverTracked then
                MySQL.update.await('INSERT INTO `es_dept_pers_flags` (`jobId`,`charId`,`level`) VALUES (?,?,?) ON DUPLICATE KEY UPDATE `level` = VALUES(`level`), `at` = CURRENT_TIMESTAMP',
                    { d.jobId, m.charId, m.level })
                career(d.id, m.charId, 'inactive', { toRole = LV[m.level] or 'warning', detail = ('%d days off duty'):format(m.inactiveDays or 0) })
            elseif (m.level or 0) == 0 and was > 0 then
                MySQL.update.await('DELETE FROM `es_dept_pers_flags` WHERE `jobId` = ? AND `charId` = ?', { d.jobId, m.charId })
            end
        end
    end
end

function Pers.start(c)
    ctx = c
    up = true
    local ok, err = pcall(backfill)
    if not ok then print(('^3[es_departments] personnel backfill failed: %s^7'):format(tostring(err))) end
    ok, err = pcall(seedCerts)
    if not ok then print(('^3[es_departments] cert seed failed: %s^7'):format(tostring(err))) end
    CreateThread(function()
        Wait(60000)
        while true do
            local ok2, err2 = pcall(check)
            if not ok2 then print(('^3[es_departments] personnel check failed: %s^7'):format(tostring(err2))) end
            Wait(30 * 60000)
        end
    end)
end
