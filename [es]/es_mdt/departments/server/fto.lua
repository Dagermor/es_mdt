local _ENV = ESAPP('departments'); -- es_departments FTO (1.4.0: the field training program).
--   Each department has a training PROGRAM: phases, each with checklist items, the 1-5 rating categories, how often a
--   Daily Observation Report (DOR) is due, which ranks are recruit/probationary, and the rank a graduate gets.
--   Department heads (fto_manage) edit it in the MDT. A hire into a recruit rank lands in the training queue.
--   FTOs (fto_train) write DORs (date, minutes, ratings, notes, items signed off) and sign items off; each phase fills
--   as its items are signed. A supervisor (fto_manage) gives the final sign-off: completed, and (if set) the rank up.
--   Trainees with no DOR for longer than the program allows are flagged (MDT Training + the Activity view).
--   Everything that happens to a trainee goes in es_fto_history. The MDT is the screen; these are its exports.

Fto = {}
local WC = exports.whip_core
local ctx
local up = false

function Fto.tables()
    local defs = {
        { 'es_fto_trainees', [[CREATE TABLE IF NOT EXISTS `es_fto_trainees` (
            `deptId` INT UNSIGNED NOT NULL,
            `charId` INT UNSIGNED NOT NULL,
            `hiredAt` DATETIME NULL,
            `hireRoleId` INT UNSIGNED NULL,
            `status` ENUM('training','signed_off','promoted','left') NOT NULL DEFAULT 'training',
            `ftoCharId` INT UNSIGNED NULL,
            `claimedAt` DATETIME NULL,
            `doneAt` DATETIME NULL,
            `doneBy` INT UNSIGNED NULL,
            `origin` ENUM('hired','backfill','manual') NOT NULL DEFAULT 'hired',
            `test` TINYINT(1) NOT NULL DEFAULT 0,
            `testName` VARCHAR(60) NULL,
            `updatedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`deptId`, `charId`),
            KEY `idx_es_ftot_status` (`deptId`, `status`),
            KEY `idx_es_ftot_fto` (`ftoCharId`),
            CONSTRAINT `fk_es_ftot_dept` FOREIGN KEY (`deptId`) REFERENCES `es_departments` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
        { 'es_fto_sessions', [[CREATE TABLE IF NOT EXISTS `es_fto_sessions` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `deptId` INT UNSIGNED NOT NULL,
            `traineeCharId` INT UNSIGNED NOT NULL,
            `ftoCharId` INT UNSIGNED NOT NULL,
            `kind` ENUM('ridealong','training','evaluation') NOT NULL DEFAULT 'ridealong',
            `sessionAt` DATETIME NOT NULL,
            `minutes` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
            `notes` TEXT NULL,
            `ratings` JSON NULL,
            `checklist` JSON NULL,
            `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_es_ftos_trainee` (`deptId`, `traineeCharId`, `sessionAt`),
            KEY `idx_es_ftos_fto` (`ftoCharId`, `sessionAt`),
            CONSTRAINT `fk_es_ftos_dept` FOREIGN KEY (`deptId`) REFERENCES `es_departments` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
        { 'es_fto_recommendations', [[CREATE TABLE IF NOT EXISTS `es_fto_recommendations` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `deptId` INT UNSIGNED NOT NULL,
            `traineeCharId` INT UNSIGNED NOT NULL,
            `ftoCharId` INT UNSIGNED NOT NULL,
            `toRoleId` INT UNSIGNED NULL,
            `reason` VARCHAR(500) NULL,
            `status` ENUM('pending','approved','denied','withdrawn') NOT NULL DEFAULT 'pending',
            `decidedBy` INT UNSIGNED NULL,
            `decidedAt` DATETIME NULL,
            `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_es_ftor_dept` (`deptId`, `status`),
            CONSTRAINT `fk_es_ftor_dept` FOREIGN KEY (`deptId`) REFERENCES `es_departments` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
        { 'es_fto_programs', [[CREATE TABLE IF NOT EXISTS `es_fto_programs` (
            `deptId` INT UNSIGNED NOT NULL,
            `program` JSON NOT NULL,
            `updatedBy` INT UNSIGNED NULL,
            `updatedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`deptId`),
            CONSTRAINT `fk_es_ftop_dept` FOREIGN KEY (`deptId`) REFERENCES `es_departments` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
        { 'es_fto_signoffs', [[CREATE TABLE IF NOT EXISTS `es_fto_signoffs` (
            `deptId` INT UNSIGNED NOT NULL,
            `traineeCharId` INT UNSIGNED NOT NULL,
            `itemKey` VARCHAR(16) NOT NULL,
            `ftoCharId` INT UNSIGNED NOT NULL,
            `sessionId` INT UNSIGNED NULL,
            `signedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`deptId`, `traineeCharId`, `itemKey`),
            CONSTRAINT `fk_es_ftosg_dept` FOREIGN KEY (`deptId`) REFERENCES `es_departments` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
        { 'es_fto_history', [[CREATE TABLE IF NOT EXISTS `es_fto_history` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `deptId` INT UNSIGNED NOT NULL,
            `traineeCharId` INT UNSIGNED NOT NULL DEFAULT 0,
            `actorCharId` INT UNSIGNED NULL,
            `action` VARCHAR(24) NOT NULL,
            `detail` VARCHAR(500) NULL,
            `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_es_ftoh_trainee` (`deptId`, `traineeCharId`, `at`),
            CONSTRAINT `fk_es_ftoh_dept` FOREIGN KEY (`deptId`) REFERENCES `es_departments` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    }
    -- 1.4.1: staff test trainees (no character): test columns, and the trainee FKs to characters go (Fto.start cleans orphans)
    local MIG = {
        es_fto_trainees = { { id = 'fto_test_1', statements = {
            { sql = 'ALTER TABLE `es_fto_trainees` ADD COLUMN `test` TINYINT(1) NOT NULL DEFAULT 0', unless = { column = { 'es_fto_trainees', 'test' } } },
            { sql = 'ALTER TABLE `es_fto_trainees` ADD COLUMN `testName` VARCHAR(60) NULL', unless = { column = { 'es_fto_trainees', 'testName' } } },
            { sql = 'ALTER TABLE `es_fto_trainees` DROP FOREIGN KEY `fk_es_ftot_char`', onlyIf = { constraint = { 'es_fto_trainees', 'fk_es_ftot_char' } } },
        } } },
        es_fto_sessions = { { id = 'fto_test_2', statements = {
            { sql = 'ALTER TABLE `es_fto_sessions` DROP FOREIGN KEY `fk_es_ftos_trainee`', onlyIf = { constraint = { 'es_fto_sessions', 'fk_es_ftos_trainee' } } },
        } } },
        es_fto_recommendations = { { id = 'fto_test_4', statements = {
            { sql = 'ALTER TABLE `es_fto_recommendations` DROP FOREIGN KEY `fk_es_ftor_trainee`', onlyIf = { constraint = { 'es_fto_recommendations', 'fk_es_ftor_trainee' } } },
        } } },
        es_fto_signoffs = { { id = 'fto_test_3', statements = {
            { sql = 'ALTER TABLE `es_fto_signoffs` DROP FOREIGN KEY `fk_es_ftosg_trainee`', onlyIf = { constraint = { 'es_fto_signoffs', 'fk_es_ftosg_trainee' } } },
        } } },
    }
    for _, t in ipairs(defs) do
        local ok, why = Whip.core:EnsureTable(t[1], t[2], MIG[t[1]] or {})
        if not ok then return false, ('%s: %s'):format(t[1], tostring(why)) end
    end
    return true
end

-- ---------------------------------------------------------------- helpers

local function levelOfRole(jobId, roleId)
    for _, r in ipairs(WC:GetJobRoles(jobId) or {}) do if r.roleId == roleId then return r.level or 0 end end
    return nil
end

local function lowestLevel(jobId)
    local low
    for _, r in ipairs(WC:GetJobRoles(jobId) or {}) do if not low or (r.level or 0) < low then low = r.level or 0 end end
    return low
end

local function charOf(who)
    if type(who) == 'table' then return who.charId end
    return WC:GetCharId(who)
end

local function isStaffWho(who) return type(who) == 'number' and ctx.isStaff(who) end

-- staff test trainees (/ftotest) get char ids from here up; they have no character, no rank, nobody to notify
local TEST_BASE = 900000000
local function isTestId(charId) return (tonumber(charId) or 0) >= TEST_BASE end
local function testRow(d, charId)
    if not isTestId(charId) then return nil end
    return MySQL.single.await('SELECT `testName`,`status` FROM `es_fto_trainees` WHERE `deptId` = ? AND `charId` = ? AND `test` = 1', { d.id, charId })
end

--- May `who` (server id) do `perm` at department d? Staff may do anything.
local function may(who, d, perm)
    if isStaffWho(who) then return true end
    return WC:HasJobPermission(who, d.jobId, perm, { onDuty = false }) == true
end

local function myLevel(who, d)
    if isStaffWho(who) then return 1e9 end
    local job = WC:GetJob(d.jobId)
    local me = charOf(who)
    if job and me and job.ownerCharId == me then return 1e9 end
    local r = WC:GetPlayerRole(who, d.jobId)
    return r and r.level or 0
end

local function notifyChar(charId, text, kind)
    for src, p in pairs(WC:GetPlayers({ light = true }) or {}) do
        if p.charId == charId then WC:NotifyPlayer(tonumber(src), text, kind or 'info', 8000) return tonumber(src) end
    end
end

--- One line in the trainee's history (and the actor's WHIP activity log)
local function hist(deptId, traineeCharId, who, action, detail)
    local actor = who and charOf(who) or nil
    MySQL.insert.await('INSERT INTO `es_fto_history` (`deptId`,`traineeCharId`,`actorCharId`,`action`,`detail`) VALUES (?,?,?,?,?)',
        { deptId, traineeCharId or 0, actor, action, detail and tostring(detail):sub(1, 500) or nil })
    if type(who) == 'number' and who > 0 then
        CreateThread(function() WC:LogActivity(who, 'es_departments_fto_' .. action, { detail = ('#%d %s'):format(traineeCharId or 0, detail or '') }) end)
    end
end

local function finish(deptId, charId, status, by)
    return (MySQL.update.await([[UPDATE `es_fto_trainees` SET `status` = ?, `doneAt` = NOW(), `doneBy` = NULLIF(?, 0)
        WHERE `deptId` = ? AND `charId` = ? AND `status` = 'training']], { status, by or 0, deptId, charId }) or 0) > 0
end

-- ---------------------------------------------------------------- the program

local DEFAULT_PHASES = {
    { 'Orientation', { 'Department policy and chain of command', 'Station, armory and vehicle tour', 'Uniform and equipment check', 'Clocking on, unit status and callsign' } },
    { 'Radio and 10-codes', { '10-codes and signals', 'Radio etiquette and traffic', 'Running plates and people over the radio', 'Panic button and calling for backup' } },
    { 'Traffic stops', { 'Low-risk traffic stop', 'Approach and vehicle positioning', 'Citations and fines in the MDT', 'Radar and plate reader' } },
    { 'Felony stops', { 'High-risk (felony) stop', 'Verbal commands and suspect extraction', 'Cover, positioning and crossfire' } },
    { 'Report writing', { 'Incident report', 'Arrest report with charges', 'Report templates and evidence links' } },
    { 'MDT and evidence', { 'Person and vehicle lookups', 'Warrants and BOLOs', 'Collecting and bagging evidence', 'Fingerprint dusting', 'Evidence locker and chain of custody' } },
    { 'Arrest and jail processing', { 'Cuffing and searching', 'Mugshot and booking prints', 'Charging and sending to jail', 'Prisoner transport to Bolingbroke' } },
    { 'Pursuits', { 'Pursuit policy and radio calls', 'Vehicle pursuit', 'Foot pursuit', 'Ending a pursuit (PIT and termination)' } },
    { 'Use of force', { 'Use of force continuum', 'De-escalation', 'Less-lethal options', 'Lethal force and the report after' } },
}
local DEFAULT_RATINGS = { 'Driving', 'Radio', 'Officer safety', 'Report writing', 'Law knowledge', 'Decision making', 'Conduct' }
local LIM = { phases = 15, items = 25, ratings = 12, label = 80, name = 60 }

local function defaultProgram(d)
    local p = { phases = {}, ratings = {}, dorDays = 3, recruitRoles = {}, completeRoleId = false, autoRank = true, seq = 0 }
    for _, ph in ipairs(DEFAULT_PHASES) do
        p.seq = p.seq + 1
        local phase = { key = 'p' .. p.seq, name = ph[1], items = {} }
        for _, lbl in ipairs(ph[2]) do p.seq = p.seq + 1 phase.items[#phase.items + 1] = { key = 'i' .. p.seq, label = lbl } end
        p.phases[#p.phases + 1] = phase
    end
    for _, r in ipairs(DEFAULT_RATINGS) do p.ratings[#p.ratings + 1] = r end
    -- recruit rank by default: the department's lowest rank; graduates go one rank up
    local roles = WC:GetJobRoles(d.jobId) or {}
    table.sort(roles, function(a, b) return (a.level or 0) < (b.level or 0) end)
    if roles[1] then p.recruitRoles = { roles[1].roleId } end
    if roles[2] then p.completeRoleId = roles[2].roleId end
    return p
end

local Programs = {}   -- [deptId] = program (cache)
local completing = {} -- ['deptId:charId'] while CompleteTraining changes the rank (its own history line says so)

local function programOf(d)
    if Programs[d.id] then return Programs[d.id] end
    local row = MySQL.single.await('SELECT `program` FROM `es_fto_programs` WHERE `deptId` = ?', { d.id })
    local p = row and row.program and select(2, pcall(json.decode, row.program))
    if type(p) ~= 'table' or type(p.phases) ~= 'table' then
        p = defaultProgram(d)
        MySQL.insert.await('INSERT IGNORE INTO `es_fto_programs` (`deptId`,`program`) VALUES (?,?)', { d.id, json.encode(p) })
    end
    Programs[d.id] = p
    return p
end

--- [itemKey] = { phase, label } for a program
local function itemIndex(p)
    local out = {}
    for _, ph in ipairs(p.phases) do for _, it in ipairs(ph.items or {}) do out[it.key] = { phase = ph.key, label = it.label } end end
    return out
end

local function isRecruitRole(p, roleId)
    for _, r in ipairs(p.recruitRoles or {}) do if r == roleId then return true end end
    return false
end

--- Progress of one trainee from their signed set { [itemKey] = true }
local function progressOf(p, signed)
    local out, done, total, current = {}, 0, 0, nil
    for _, ph in ipairs(p.phases) do
        local n, m = 0, #(ph.items or {})
        for _, it in ipairs(ph.items or {}) do if signed[it.key] then n = n + 1 end end
        out[#out + 1] = { key = ph.key, name = ph.name, done = n, total = m }
        done, total = done + n, total + m
        if not current and n < m then current = ph.key end
    end
    return { phases = out, done = done, total = total, pct = total > 0 and math.floor(done * 100 / total) or 0, current = current }
end

local function cleanLabel(s, max)
    s = type(s) == 'string' and s:gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '') or ''
    return s:sub(1, max)
end

--- A program from the editor, checked. Keeps known keys (so sign-offs survive renames), gives new rows new keys.
local function cleanProgram(d, old, data, who)
    if type(data) ~= 'table' then return false, 'Nothing to save' end
    local p = { phases = {}, ratings = {}, seq = tonumber(old.seq) or 0 }
    local used = {}
    local function keyOf(k, prefix)
        if type(k) == 'string' and k:match('^[%w_]+$') and #k <= 16 and not used[k] then used[k] = true return k end
        repeat p.seq = p.seq + 1 k = prefix .. p.seq until not used[k]
        used[k] = true
        return k
    end
    for _, ph in ipairs(type(data.phases) == 'table' and data.phases or {}) do
        if #p.phases >= LIM.phases then break end
        local name = cleanLabel(type(ph) == 'table' and ph.name, LIM.name)
        if name ~= '' then
            local phase = { key = keyOf(ph.key, 'p'), name = name, items = {} }
            for _, it in ipairs(type(ph.items) == 'table' and ph.items or {}) do
                if #phase.items >= LIM.items then break end
                local lbl = cleanLabel(type(it) == 'table' and it.label, LIM.label)
                if lbl ~= '' then phase.items[#phase.items + 1] = { key = keyOf(it.key, 'i'), label = lbl } end
            end
            p.phases[#p.phases + 1] = phase
        end
    end
    if #p.phases == 0 then return false, 'Add at least one phase' end
    local seen = {}
    for _, r in ipairs(type(data.ratings) == 'table' and data.ratings or {}) do
        local lbl = cleanLabel(r, 40)
        if lbl ~= '' and not seen[lbl:lower()] and #p.ratings < LIM.ratings then seen[lbl:lower()] = true p.ratings[#p.ratings + 1] = lbl end
    end
    if #p.ratings == 0 then return false, 'Add at least one rating category' end
    p.dorDays = math.max(1, math.min(30, math.floor(tonumber(data.dorDays) or 3)))
    local roles, lv = {}, {}
    for _, r in ipairs(WC:GetJobRoles(d.jobId) or {}) do roles[r.roleId] = r lv[r.roleId] = r.level or 0 end
    p.recruitRoles = {}
    for _, rid in ipairs(type(data.recruitRoles) == 'table' and data.recruitRoles or {}) do
        rid = tonumber(rid)
        if rid and roles[rid] and #p.recruitRoles < 10 then p.recruitRoles[#p.recruitRoles + 1] = rid end
    end
    p.completeRoleId = false
    local cr = tonumber(data.completeRoleId)
    if cr and roles[cr] then
        if lv[cr] >= myLevel(who, d) then return false, 'The graduation rank must be below your own' end
        p.completeRoleId = cr
    end
    p.autoRank = data.autoRank ~= false
    return p
end

-- ---------------------------------------------------------------- queue in and out

local function queue(d, charId, roleId, origin, who, why)
    local n = MySQL.update.await([[INSERT INTO `es_fto_trainees` (`deptId`,`charId`,`hiredAt`,`hireRoleId`,`status`,`origin`)
        VALUES (?,?,NOW(),NULLIF(?, 0),'training',?) ON DUPLICATE KEY UPDATE `hiredAt` = IF(`status` = 'training', `hiredAt`, NOW()),
        `hireRoleId` = VALUES(`hireRoleId`), `ftoCharId` = IF(`status` = 'training', `ftoCharId`, NULL),
        `claimedAt` = IF(`status` = 'training', `claimedAt`, NULL), `doneAt` = NULL, `doneBy` = NULL, `origin` = VALUES(`origin`), `status` = 'training']],
        { d.id, charId, tonumber(roleId) or 0, origin })
    hist(d.id, charId, who, 'queued', why)
    return n
end

AddEventHandler('whip_core:job:hired', function(e)
    if not up or type(e) ~= 'table' or not e.jobId or not e.charId then return end
    local d = ctx.byJob(e.jobId)
    if not d then return end
    local p = programOf(d)
    -- with recruit ranks set, only a hire into one of them needs training
    if #(p.recruitRoles or {}) > 0 and not isRecruitRole(p, tonumber(e.roleId)) then return end
    queue(d, e.charId, e.roleId, 'hired', nil, 'Hired')
end)

AddEventHandler('whip_core:job:roleChanged', function(e)
    if not up or type(e) ~= 'table' or not e.jobId or not e.charId then return end
    local d = ctx.byJob(e.jobId)
    if not d then return end
    local p = programOf(d)
    local rid = tonumber(e.roleId)
    local t = MySQL.single.await('SELECT `status` FROM `es_fto_trainees` WHERE `deptId` = ? AND `charId` = ?', { d.id, e.charId })
    if isRecruitRole(p, rid) then
        if not t or t.status ~= 'training' then queue(d, e.charId, rid, 'manual', nil, 'Moved to a recruit rank') end
        return
    end
    local new, old = levelOfRole(e.jobId, rid), e.oldRoleId and levelOfRole(e.jobId, e.oldRoleId)
    if new and old and new > old and t and t.status == 'training' and not completing[d.id .. ':' .. e.charId] then
        finish(d.id, e.charId, 'promoted', nil)
        hist(d.id, e.charId, nil, 'promoted', 'Promoted out of training')
    end
end)

AddEventHandler('whip_core:job:fired', function(e)
    if not up or type(e) ~= 'table' or not e.jobId or not e.charId then return end
    local d = ctx.byJob(e.jobId)
    if d and finish(d.id, e.charId, 'left', nil) then hist(d.id, e.charId, nil, 'left', 'Left the department') end
end)

--- Once: everyone now at a department's lowest rank with no training record needs training.
local function backfill()
    if GetResourceKvpString('es_departments:ftoBackfill') == '1' then return end
    for _, d in ipairs(ctx.sortedDepts()) do
        local low = lowestLevel(d.jobId)
        local job = WC:GetJob(d.jobId)
        if low then
            MySQL.update.await([[INSERT IGNORE INTO `es_fto_trainees` (`deptId`,`charId`,`hiredAt`,`hireRoleId`,`status`,`origin`)
                SELECT ?, e.`charId`, e.`hiredAt`, e.`roleId`, 'training', 'backfill' FROM `job_employees` e
                JOIN `job_roles` r ON r.`roleId` = e.`roleId` WHERE e.`jobId` = ? AND r.`level` = ? AND e.`charId` <> ?]],
                { d.id, d.jobId, low, job and job.ownerCharId or 0 })
        end
    end
    SetResourceKvp('es_departments:ftoBackfill', '1')
end

-- ---------------------------------------------------------------- reads

local function signedOf(deptId, charId)
    local out = {}
    local rows = MySQL.query.await(([[SELECT `traineeCharId`,`itemKey`,`ftoCharId`,`sessionId`,UNIX_TIMESTAMP(`signedAt`) AS `at`
        FROM `es_fto_signoffs` WHERE `deptId` = ?%s]]):format(charId and ' AND `traineeCharId` = ?' or ''), { deptId, charId }) or {}
    for _, r in ipairs(rows) do
        out[r.traineeCharId] = out[r.traineeCharId] or {}
        out[r.traineeCharId][r.itemKey] = { by = r.ftoCharId, at = r.at, sessionId = r.sessionId }
    end
    return out
end

--- The queue (opts.status = 'training' by default, or 'all'), each with sessions, progress and whether a DOR is overdue.
local function trainees(d, opts)
    opts = type(opts) == 'table' and opts or {}
    local all = opts.status == 'all'
    local rows = MySQL.query.await(([[SELECT t.`charId`, UNIX_TIMESTAMP(t.`hiredAt`) AS `hiredAt`, t.`hireRoleId`, t.`status`,
        t.`ftoCharId`, UNIX_TIMESTAMP(t.`claimedAt`) AS `claimedAt`, UNIX_TIMESTAMP(t.`doneAt`) AS `doneAt`, t.`doneBy`, t.`origin`, t.`test`, t.`testName`,
        (SELECT COUNT(*) FROM `es_fto_sessions` s WHERE s.`deptId` = t.`deptId` AND s.`traineeCharId` = t.`charId`) AS `sessions`,
        (SELECT COUNT(*) FROM `es_fto_sessions` s WHERE s.`deptId` = t.`deptId` AND s.`traineeCharId` = t.`charId` AND s.`kind` = 'ridealong') AS `rideAlongs`,
        (SELECT COALESCE(SUM(s.`minutes`), 0) FROM `es_fto_sessions` s WHERE s.`deptId` = t.`deptId` AND s.`traineeCharId` = t.`charId`) AS `minutes`,
        (SELECT UNIX_TIMESTAMP(MAX(s.`sessionAt`)) FROM `es_fto_sessions` s WHERE s.`deptId` = t.`deptId` AND s.`traineeCharId` = t.`charId`) AS `lastSession`,
        (SELECT COUNT(*) FROM `es_fto_recommendations` r WHERE r.`deptId` = t.`deptId` AND r.`traineeCharId` = t.`charId` AND r.`status` = 'pending') AS `recommended`
        FROM `es_fto_trainees` t WHERE t.`deptId` = ?%s%s ORDER BY t.`hiredAt` IS NULL, t.`hiredAt`]]):format(
            all and '' or " AND t.`status` = 'training'", opts.charId and ' AND t.`charId` = ?' or ''),
        { d.id, opts.charId }) or {}
    local p = programOf(d)
    local signed = signedOf(d.id, opts.charId)
    local loa = (Duty.loaByChar and Duty.loaByChar(d.id)) or {}
    local ids = {}
    for _, r in ipairs(rows) do ids[#ids + 1] = r.charId if r.ftoCharId then ids[#ids + 1] = r.ftoCharId end if r.doneBy then ids[#ids + 1] = r.doneBy end end
    local names = ctx.namesOf(ids)
    local now = os.time()
    for _, r in ipairs(rows) do
        r.test = r.test == 1 or r.test == true
        r.name = r.test and (r.testName or 'Test Cadet') or names[r.charId] or ('#' .. r.charId)
        r.testName = nil
        r.ftoName = r.ftoCharId and (names[r.ftoCharId] or ('#' .. r.ftoCharId)) or nil
        r.doneByName = r.doneBy and names[r.doneBy] or nil
        local role = (not r.test) and WC:GetPlayerRole({ charId = r.charId }, d.jobId) or nil
        r.roleId, r.roleName, r.roleLevel = role and role.roleId, role and role.name, role and role.level
        if r.test then
            for _, x in ipairs(WC:GetJobRoles(d.jobId) or {}) do if x.roleId == r.hireRoleId then r.roleId, r.roleName, r.roleLevel = x.roleId, x.name, x.level end end
            r.roleName = (r.roleName or 'Recruit') .. ' (test)'
        end
        r.required = Config.FTO.rideAlongsRequired
        r.ready = (tonumber(r.rideAlongs) or 0) >= Config.FTO.rideAlongsRequired
        r.recommended = (tonumber(r.recommended) or 0) > 0
        r.sessions, r.minutes = tonumber(r.sessions) or 0, tonumber(r.minutes) or 0
        local set = {}
        for k in pairs(signed[r.charId] or {}) do set[k] = true end
        r.progress = progressOf(p, set)
        if r.status == 'training' then
            -- a DOR is due every dorDays from the last one (or from being claimed / hired); leave pauses it
            local base = math.max(tonumber(r.lastSession) or 0, tonumber(r.claimedAt) or 0, tonumber(r.hiredAt) or 0)
            local l = loa[r.charId] or {}
            if l.lastEnd and l.lastEnd > base then base = l.lastEnd end
            r.dorDueAt = base > 0 and (base + p.dorDays * 86400) or nil
            r.daysSinceDor = base > 0 and math.floor((now - base) / 86400) or nil
            r.onLeave = l.active ~= nil
            r.overdue = r.dorDueAt ~= nil and now > r.dorDueAt and not r.onLeave and r.ftoCharId ~= nil
            r.daysInTraining = r.hiredAt and math.floor((now - r.hiredAt) / 86400) or nil
        elseif r.doneAt and r.hiredAt then
            r.daysInTraining = math.floor((r.doneAt - r.hiredAt) / 86400)
        end
    end
    return rows
end
Fto.trainees = trainees

--- [charId] = { overdue, days, dorDays, ftoName } for everyone in training (the Activity view uses it)
function Fto.trainingFlags(d)
    local out = {}
    local p = programOf(d)
    for _, t in ipairs(trainees(d)) do
        out[t.charId] = { overdue = t.overdue == true, days = t.daysSinceDor, dorDays = p.dorDays, ftoName = t.ftoName,
            unassigned = t.ftoCharId == nil, pct = t.progress.pct }
    end
    return out
end

exports('GetTrainees', function(ref, opts)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    return trainees(d, opts)
end)

exports('GetTrainingProgram', function(ref)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    local p = programOf(d)
    local roles = {}
    for _, r in ipairs(WC:GetJobRoles(d.jobId) or {}) do roles[#roles + 1] = { roleId = r.roleId, name = r.name, level = r.level or 0 } end
    table.sort(roles, function(a, b) return a.level < b.level end)
    return { program = p, ranks = roles, limits = LIM }
end)

--- Is this character in training here right now?
exports('IsTrainee', function(ref, charId)
    local d = ctx.resolve(ref)
    if not d then return false end
    local t = MySQL.single.await("SELECT 1 AS `x` FROM `es_fto_trainees` WHERE `deptId` = ? AND `charId` = ? AND `status` = 'training'", { d.id, tonumber(charId) or 0 })
    return t ~= nil
end)

local function sessionsOf(d, traineeCharId)
    local rows = MySQL.query.await([[SELECT `id`,`ftoCharId`,`kind`,UNIX_TIMESTAMP(`sessionAt`) AS `sessionAt`,`minutes`,`notes`,`ratings`,`checklist`
        FROM `es_fto_sessions` WHERE `deptId` = ? AND `traineeCharId` = ? ORDER BY `sessionAt` DESC]], { d.id, tonumber(traineeCharId) or 0 }) or {}
    local ids = {}
    for _, r in ipairs(rows) do ids[#ids + 1] = r.ftoCharId end
    local names = ctx.namesOf(ids)
    local signs = {}
    for _, s in ipairs(MySQL.query.await('SELECT `sessionId`,`itemKey` FROM `es_fto_signoffs` WHERE `deptId` = ? AND `traineeCharId` = ? AND `sessionId` IS NOT NULL',
        { d.id, tonumber(traineeCharId) or 0 }) or {}) do
        signs[s.sessionId] = signs[s.sessionId] or {}
        table.insert(signs[s.sessionId], s.itemKey)
    end
    for _, r in ipairs(rows) do
        r.ftoName = names[r.ftoCharId]
        r.ratings = r.ratings and json.decode(r.ratings) or {}
        r.checklist = r.checklist and json.decode(r.checklist) or {}
        r.signed = signs[r.id] or {}
    end
    return rows
end

exports('GetTrainingSessions', function(ref, traineeCharId)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    return sessionsOf(d, traineeCharId)
end)

--- Everything about one trainee: their row, program, sign-offs, DORs, history.
exports('GetTraineeFile', function(ref, charId)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    charId = tonumber(charId) or 0
    local list = trainees(d, { status = 'all', charId = charId })
    local t = list[1]
    if not t then return false, 'They have no training record here' end
    local signed = signedOf(d.id, charId)[charId] or {}
    local hrows = MySQL.query.await([[SELECT `id`,`actorCharId`,`action`,`detail`,UNIX_TIMESTAMP(`at`) AS `at` FROM `es_fto_history`
        WHERE `deptId` = ? AND `traineeCharId` = ? ORDER BY `at` DESC, `id` DESC LIMIT 200]], { d.id, charId }) or {}
    local ids = {}
    for _, s in pairs(signed) do ids[#ids + 1] = s.by end
    for _, h in ipairs(hrows) do if h.actorCharId then ids[#ids + 1] = h.actorCharId end end
    local names = ctx.namesOf(ids)
    for _, s in pairs(signed) do s.byName = names[s.by] end
    for _, h in ipairs(hrows) do h.actorName = h.actorCharId and names[h.actorCharId] or nil end
    return { trainee = t, signed = signed, sessions = sessionsOf(d, charId), history = hrows }
end)

--- The department head's numbers: in training, overdue, unassigned, completed lately, time to complete, FTO load.
exports('GetTrainingStats', function(ref)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    local p = programOf(d)
    local list = trainees(d, { status = 'all' })
    local s = { training = 0, overdue = 0, unassigned = 0, completed30 = 0, left30 = 0, avgDays = nil, avgPct = nil, phases = {}, ftos = {} }
    local now, daysSum, daysN, pctSum = os.time(), 0, 0, 0
    for _, ph in ipairs(p.phases) do s.phases[#s.phases + 1] = { key = ph.key, name = ph.name, at = 0 } end
    local at = {}
    for i, ph in ipairs(s.phases) do at[ph.key] = i end
    s.tests = 0
    local real = {}
    for _, t in ipairs(list) do if t.test then s.tests = s.tests + 1 else real[#real + 1] = t end end
    list = real
    for _, t in ipairs(list) do
        if t.status == 'training' then
            s.training = s.training + 1
            pctSum = pctSum + t.progress.pct
            if t.overdue then s.overdue = s.overdue + 1 end
            if not t.ftoCharId then s.unassigned = s.unassigned + 1 end
            local i = t.progress.current and at[t.progress.current]
            if i then s.phases[i].at = s.phases[i].at + 1 end
        elseif t.doneAt and now - t.doneAt < 30 * 86400 then
            if t.status == 'left' then s.left30 = s.left30 + 1 else s.completed30 = s.completed30 + 1 end
        end
        if t.status ~= 'training' and t.status ~= 'left' and t.daysInTraining then daysSum, daysN = daysSum + t.daysInTraining, daysN + 1 end
    end
    if daysN > 0 then s.avgDays = math.floor(daysSum / daysN * 10 + 0.5) / 10 end
    if s.training > 0 then s.avgPct = math.floor(pctSum / s.training) end
    -- FTO load: trainees now, DORs in 30 days, last DOR
    local load = {}
    for _, t in ipairs(list) do
        if t.status == 'training' and t.ftoCharId then
            local x = load[t.ftoCharId] or { charId = t.ftoCharId, name = t.ftoName, trainees = 0, overdue = 0, dors30 = 0, minutes30 = 0 }
            load[t.ftoCharId] = x
            x.trainees = x.trainees + 1
            if t.overdue then x.overdue = x.overdue + 1 end
        end
    end
    local rows = MySQL.query.await([[SELECT `ftoCharId`, COUNT(*) AS `n`, COALESCE(SUM(`minutes`),0) AS `m`, UNIX_TIMESTAMP(MAX(`sessionAt`)) AS `last`
        FROM `es_fto_sessions` WHERE `deptId` = ? AND `sessionAt` > NOW() - INTERVAL 30 DAY GROUP BY `ftoCharId`]], { d.id }) or {}
    local ids = {}
    for _, r in ipairs(rows) do if not load[r.ftoCharId] then ids[#ids + 1] = r.ftoCharId end end
    local names = ctx.namesOf(ids)
    for _, r in ipairs(rows) do
        local x = load[r.ftoCharId] or { charId = r.ftoCharId, name = names[r.ftoCharId] or ('#' .. r.ftoCharId), trainees = 0, overdue = 0 }
        load[r.ftoCharId] = x
        x.dors30, x.minutes30, x.lastDor = tonumber(r.n) or 0, tonumber(r.m) or 0, r.last
    end
    for _, x in pairs(load) do x.dors30 = x.dors30 or 0 x.minutes30 = x.minutes30 or 0 s.ftos[#s.ftos + 1] = x end
    table.sort(s.ftos, function(a, b) return (a.trainees * 1000 + a.dors30) > (b.trainees * 1000 + b.dors30) end)
    return s
end)

exports('GetRecommendations', function(ref, status)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    local rows = MySQL.query.await([[SELECT `id`,`traineeCharId`,`ftoCharId`,`toRoleId`,`reason`,`status`,`decidedBy`,
        UNIX_TIMESTAMP(`decidedAt`) AS `decidedAt`, UNIX_TIMESTAMP(`createdAt`) AS `createdAt`
        FROM `es_fto_recommendations` WHERE `deptId` = ? AND (? = 'all' OR `status` = ?) ORDER BY `createdAt` DESC LIMIT 200]],
        { d.id, status or 'pending', status or 'pending' }) or {}
    local ids = {}
    for _, r in ipairs(rows) do ids[#ids + 1] = r.traineeCharId ids[#ids + 1] = r.ftoCharId end
    local names = ctx.namesOf(ids)
    for _, r in ipairs(rows) do r.traineeName, r.ftoName = names[r.traineeCharId], names[r.ftoCharId] end
    return rows
end)

-- ---------------------------------------------------------------- actions (who = the caller's server id)

local function inQueue(d, charId)
    return MySQL.single.await("SELECT `status`,`ftoCharId` FROM `es_fto_trainees` WHERE `deptId` = ? AND `charId` = ?", { d.id, charId })
end

exports('SaveTrainingProgram', function(who, ref, data)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    if not may(who, d, 'fto_manage') then return false, 'Only training supervisors (FTO manage) can edit the program' end
    local old = programOf(d)
    local p, why = cleanProgram(d, old, data, who)
    if not p then return false, why end
    local ok = MySQL.update.await([[INSERT INTO `es_fto_programs` (`deptId`,`program`,`updatedBy`) VALUES (?,?,?)
        ON DUPLICATE KEY UPDATE `program` = VALUES(`program`), `updatedBy` = VALUES(`updatedBy`)]], { d.id, json.encode(p), charOf(who) })
    if not ok then return false, 'Could not save that (database error)' end
    Programs[d.id] = p
    local items = 0
    for _, ph in ipairs(p.phases) do items = items + #ph.items end
    hist(d.id, 0, who, 'program', ('%d phases, %d items, DOR every %d days'):format(#p.phases, items, p.dorDays))
    return true
end)

--- Put a member into training by hand (a supervisor).
exports('StartTraining', function(who, ref, charId)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    if not may(who, d, 'fto_manage') then return false, 'Only training supervisors can start training' end
    charId = tonumber(charId) or 0
    local role = WC:GetPlayerRole({ charId = charId }, d.jobId)
    if not role then return false, 'They are not in this department' end
    local t = inQueue(d, charId)
    if t and t.status == 'training' then return false, 'They are already in training' end
    queue(d, charId, role.roleId, 'manual', who, 'Put into training')
    notifyChar(charId, ('%s: you are now in field training. Open the MDT → Training to follow it.'):format(d.short), 'inform')
    return true
end)

--- Claim a trainee for yourself, or (ftoCharId) assign them to another FTO; ftoCharId = false unassigns.
--- FTOs claim unclaimed trainees; moving someone else's trainee takes fto_manage.
exports('AssignTrainee', function(who, ref, traineeCharId, ftoCharId)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    if not may(who, d, 'fto_train') and not may(who, d, 'fto_manage') then return false, 'Only FTOs can take trainees' end
    local t = inQueue(d, traineeCharId)
    if not t or t.status ~= 'training' then return false, 'They are not in training' end
    local me = charOf(who)
    local to = ftoCharId == nil and me or ftoCharId
    local manager = may(who, d, 'fto_manage')
    if not manager then
        if to ~= me then return false, 'Only training supervisors assign trainees to others' end
        if t.ftoCharId and t.ftoCharId ~= me then return false, 'They already have an FTO. Ask a training supervisor to move them' end
    end
    if to and to ~= me then
        if not WC:HasJobPermission({ charId = to }, d.jobId, 'fto_train', { onDuty = false }) then return false, 'That person is not an FTO here' end
    end
    -- 1.5.0: with Config.Certs.gateFto on, an FTO also needs the department's FTO certification (on top of fto_train)
    if to and (Config.Certs or {}).gateFto and Pers and Pers.hasCertNamed and not Pers.hasCertNamed(d, to, (Config.Certs or {}).ftoCert or 'FTO') then
        return false, to == me and 'You need a valid FTO certification first (ask a supervisor: your profile → Certifications)'
            or 'They need a valid FTO certification first (their profile → Certifications)'
    end
    if to == traineeCharId then return false, 'Nobody trains themselves' end
    if to then
        if t.ftoCharId == to then return true end
        MySQL.update.await('UPDATE `es_fto_trainees` SET `ftoCharId` = ?, `claimedAt` = NOW() WHERE `deptId` = ? AND `charId` = ?', { to, d.id, traineeCharId })
        local n = ctx.namesOf({ to })
        hist(d.id, traineeCharId, who, 'assigned', 'FTO: ' .. (n[to] or ('#' .. to)))
        notifyChar(traineeCharId, ('%s: your FTO is now %s'):format(d.short, n[to] or 'assigned'), 'inform')
        if to ~= me then notifyChar(to, ('%s: you have a new trainee. MDT → Training'):format(d.short), 'inform') end
        if Pers and Pers.autoGrant then pcall(Pers.autoGrant, d, to, 'fto', who) end   -- 1.5.0: certs set to "made an FTO"
    else
        MySQL.update.await('UPDATE `es_fto_trainees` SET `ftoCharId` = NULL, `claimedAt` = NULL WHERE `deptId` = ? AND `charId` = ?', { d.id, traineeCharId })
        hist(d.id, traineeCharId, who, 'unassigned', 'No FTO')
    end
    return true
end)

--- Sign off (or take back) items. keys = { itemKey, ... }. Returns the number changed.
local function signItems(d, who, traineeCharId, keys, sessionId, on)
    local p = programOf(d)
    local idx = itemIndex(p)
    local me = charOf(who)
    local have = signedOf(d.id, traineeCharId)[traineeCharId] or {}
    local before = progressOf(p, (function() local s = {} for k in pairs(have) do s[k] = true end return s end)())
    local n, labels = 0, {}
    for _, k in ipairs(keys) do
        if idx[k] then
            if on and not have[k] then
                MySQL.insert.await('INSERT IGNORE INTO `es_fto_signoffs` (`deptId`,`traineeCharId`,`itemKey`,`ftoCharId`,`sessionId`) VALUES (?,?,?,?,?)',
                    { d.id, traineeCharId, k, me, sessionId })
                have[k] = { by = me } n = n + 1 labels[#labels + 1] = idx[k].label
            elseif not on and have[k] then
                MySQL.update.await('DELETE FROM `es_fto_signoffs` WHERE `deptId` = ? AND `traineeCharId` = ? AND `itemKey` = ?', { d.id, traineeCharId, k })
                have[k] = nil n = n + 1 labels[#labels + 1] = idx[k].label
            end
        end
    end
    if n > 0 then
        hist(d.id, traineeCharId, who, on and 'signed' or 'unsigned', table.concat(labels, ', '))
        local set = {}
        for k in pairs(have) do set[k] = true end
        local after = progressOf(p, set)
        for i, ph in ipairs(after.phases) do
            local b = before.phases[i]
            if on and ph.total > 0 and ph.done == ph.total and b and b.done < b.total then
                hist(d.id, traineeCharId, who, 'phase_done', ph.name)
                notifyChar(traineeCharId, ('%s training: phase "%s" complete'):format(d.short, ph.name), 'success')
            end
        end
        if on and after.total > 0 and after.done == after.total then
            hist(d.id, traineeCharId, who, 'ready', 'Every item signed: ready for the final sign-off')
        end
    end
    return n
end

exports('SignTrainingItems', function(who, ref, traineeCharId, keys, on)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    if not may(who, d, 'fto_train') and not may(who, d, 'fto_manage') then return false, 'Only FTOs sign off training' end
    traineeCharId = tonumber(traineeCharId) or 0
    if charOf(who) == traineeCharId then return false, 'You cannot sign off your own training' end
    local t = inQueue(d, traineeCharId)
    if not t or t.status ~= 'training' then return false, 'They are not in training' end
    if type(keys) ~= 'table' or #keys == 0 or #keys > 200 then return false, 'Pick what to sign off' end
    if not on then
        -- taking a sign-off back: whoever signed it, or a supervisor
        local mine = true
        local have = signedOf(d.id, traineeCharId)[traineeCharId] or {}
        for _, k in ipairs(keys) do if have[k] and have[k].by ~= charOf(who) then mine = false end end
        if not mine and not may(who, d, 'fto_manage') then return false, 'Only the FTO who signed it (or a supervisor) can take it back' end
    end
    return signItems(d, who, traineeCharId, keys, nil, on ~= false)
end)

--- Write a DOR. data: { kind, minutes, notes, ratings = { [label] = 1..5 }, signed = { itemKey... }, at = unix?, checklist? }
exports('LogTraining', function(who, ref, traineeCharId, data)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    if not may(who, d, 'fto_train') then return false, 'Only FTOs can write DORs' end
    data = type(data) == 'table' and data or {}
    local me = charOf(who)
    if not me then return false, 'Who are you?' end
    traineeCharId = tonumber(traineeCharId) or 0
    if me == traineeCharId then return false, 'You cannot write your own DOR' end
    local test = testRow(d, traineeCharId)
    if not test and not WC:GetPlayerRole({ charId = traineeCharId }, d.jobId) then return false, 'They are not in this department' end
    local p = programOf(d)
    local kind = 'ridealong'
    for _, k in ipairs(Config.FTO.kinds) do if data.kind == k then kind = k end end
    local minutes = math.max(0, math.min(1440, math.floor(tonumber(data.minutes) or 0)))
    if minutes < 1 then return false, 'How long was it? (minutes)' end
    local ratings, checklist = {}, {}
    for _, lbl in ipairs(p.ratings) do
        local v = tonumber((data.ratings or {})[lbl])
        if v then ratings[lbl] = math.max(1, math.min(5, math.floor(v))) end
    end
    if next(ratings) == nil then return false, 'Rate at least one category' end
    for _, item in ipairs(Config.FTO.checklist) do if (data.checklist or {})[item] then checklist[item] = true end end
    local at = math.floor(tonumber(data.at) or 0)
    if at > os.time() + 300 then return false, 'That date is in the future' end
    if at ~= 0 and at < os.time() - 60 * 86400 then return false, 'A DOR can be at most 60 days back' end
    -- someone never queued (hired before tracking) joins training with their first DOR; a graduate's DOR is just kept
    local t = inQueue(d, traineeCharId)
    if not t then queue(d, traineeCharId, nil, 'manual', who, 'First DOR') end
    local id = MySQL.insert.await([[INSERT INTO `es_fto_sessions` (`deptId`,`traineeCharId`,`ftoCharId`,`kind`,`sessionAt`,`minutes`,`notes`,`ratings`,`checklist`)
        VALUES (?,?,?,?,IF(? = 0, NOW(), FROM_UNIXTIME(?)),?,?,?,?)]],
        { d.id, traineeCharId, me, kind, at, at, minutes, tostring(data.notes or ''):sub(1, 4000), json.encode(ratings), json.encode(checklist) })
    if not id then return false, 'Could not save that (database error)' end
    MySQL.update.await('UPDATE `es_fto_trainees` SET `ftoCharId` = COALESCE(`ftoCharId`, ?), `claimedAt` = COALESCE(`claimedAt`, NOW()) WHERE `deptId` = ? AND `charId` = ?',
        { me, d.id, traineeCharId })
    local avg, n = 0, 0
    for _, v in pairs(ratings) do avg, n = avg + v, n + 1 end
    hist(d.id, traineeCharId, who, 'dor', ('DOR #%d · %d min · avg %.1f'):format(id, minutes, avg / n))
    local keys = {}
    for _, k in ipairs(type(data.signed) == 'table' and data.signed or {}) do if type(k) == 'string' and #keys < 200 then keys[#keys + 1] = k end end
    if #keys > 0 then signItems(d, who, traineeCharId, keys, id, true) end
    notifyChar(traineeCharId, ('%s: your FTO wrote a DOR (avg %.1f/5). MDT → Training'):format(d.short, avg / n), 'inform')
    return id
end)

--- The final sign-off (a supervisor). opts: { promote = bool, roleId = n?, override = bool, note = str }
--- promote: to opts.roleId (needs the caller's own Promote right) or the program's graduation rank (the department's rule).
exports('CompleteTraining', function(who, ref, traineeCharId, opts)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    if not may(who, d, 'fto_manage') then return false, 'Only training supervisors give the final sign-off' end
    opts = type(opts) == 'table' and opts or {}
    traineeCharId = tonumber(traineeCharId) or 0
    if charOf(who) == traineeCharId then return false, 'You cannot sign off your own training' end
    local t = inQueue(d, traineeCharId)
    if not t or t.status ~= 'training' then return false, 'They are not in training' end
    local p = programOf(d)
    local set = {}
    for k in pairs(signedOf(d.id, traineeCharId)[traineeCharId] or {}) do set[k] = true end
    local pr = progressOf(p, set)
    local note = tostring(opts.note or ''):sub(1, 300)
    if pr.done < pr.total then
        if not opts.override then return false, ('%d of %d items are still open'):format(pr.total - pr.done, pr.total) end
        if #note < 5 then return false, 'Say why you are signing off with items still open' end
    end
    local status, rankName = 'signed_off', nil
    if opts.promote then
        local target, how = tonumber(opts.roleId), nil
        if target and target ~= p.completeRoleId then
            if not may(who, d, 'canPromote') then return false, 'Picking another rank needs the Promote right. Use the graduation rank' end
            if not isStaffWho(who) then how = { by = who } end
        else
            target = p.completeRoleId
            if not target then return false, 'The program has no graduation rank. Pick one, or complete without a rank change' end
            if not p.autoRank and not may(who, d, 'canPromote') then return false, 'Ranking up needs the Promote right here' end
            if not (p.autoRank or isStaffWho(who)) then how = { by = who } end
        end
        local cur = (not isTestId(traineeCharId)) and WC:GetPlayerRole({ charId = traineeCharId }, d.jobId) or nil
        if isTestId(traineeCharId) then
            -- a test trainee has no character: the rank change is only simulated (and logged)
        elseif cur and cur.roleId ~= target then
            local ck = d.id .. ':' .. traineeCharId
            completing[ck] = true
            if Pers and Pers.expect then Pers.expect(d.jobId, traineeCharId, charOf(who), 'Graduated field training' .. (note ~= '' and (': ' .. note) or '')) end
            local ok, why = WC:SetPlayerRole({ charId = traineeCharId }, d.jobId, target, how)
            SetTimeout(5000, function() completing[ck] = nil end)
            if not ok then return false, 'Could not change their rank: ' .. tostring(why) end
        end
        for _, r in ipairs(WC:GetJobRoles(d.jobId) or {}) do if r.roleId == target then rankName = r.name end end
        status = 'promoted'
    end
    -- the roleChanged event may already have closed it as 'promoted'; either way it is done now
    finish(d.id, traineeCharId, status, charOf(who))
    MySQL.update.await("UPDATE `es_fto_trainees` SET `doneBy` = ? WHERE `deptId` = ? AND `charId` = ?", { charOf(who), d.id, traineeCharId })
    MySQL.update.await("UPDATE `es_fto_recommendations` SET `status` = 'withdrawn', `decidedAt` = NOW() WHERE `deptId` = ? AND `traineeCharId` = ? AND `status` = 'pending'",
        { d.id, traineeCharId })
    hist(d.id, traineeCharId, who, 'completed', ('Final sign-off (%d/%d items)%s%s'):format(pr.done, pr.total,
        rankName and ((isTestId(traineeCharId) and ' · TEST: would be promoted to ' or ' · promoted to ') .. rankName) or '', note ~= '' and (' · ' .. note) or ''))
    notifyChar(traineeCharId, ('%s: you completed field training%s. Well done!'):format(d.short, rankName and (' and are now ' .. rankName) or ''), 'success')
    if Pers and Pers.autoGrant and not isTestId(traineeCharId) then pcall(Pers.autoGrant, d, traineeCharId, 'graduate', who) end   -- 1.5.0
    return true
end)

--- Old "sign off" (1.3): the final sign-off without a rank change, for supervisors.
exports('SignOffTrainee', function(who, ref, traineeCharId)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    if not (may(who, d, 'fto_manage') or may(who, d, 'canPromote')) then return false, 'Only training supervisors can sign off training' end
    local t = inQueue(d, traineeCharId)
    if not t or t.status ~= 'training' then return false, 'They are not in training' end
    finish(d.id, traineeCharId, 'signed_off', charOf(who))
    hist(d.id, traineeCharId, who, 'completed', 'Signed off')
    notifyChar(traineeCharId, ('%s: your training is signed off'):format(d.short), 'success')
    return true
end)

--- An FTO recommends a trainee for promotion now (skip the rest of the program).
exports('RecommendPromotion', function(who, ref, traineeCharId, reason, toRoleId)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    if not may(who, d, 'fto_train') then return false, 'Only FTOs can recommend' end
    local me = charOf(who)
    if me == traineeCharId then return false, 'You cannot recommend yourself' end
    if not testRow(d, traineeCharId) and not WC:GetPlayerRole({ charId = traineeCharId }, d.jobId) then return false, 'They are not in this department' end
    local dup = MySQL.single.await("SELECT `id` FROM `es_fto_recommendations` WHERE `deptId` = ? AND `traineeCharId` = ? AND `status` = 'pending'", { d.id, traineeCharId })
    if dup then return false, 'There is already a recommendation waiting for them' end
    local id = MySQL.insert.await('INSERT INTO `es_fto_recommendations` (`deptId`,`traineeCharId`,`ftoCharId`,`toRoleId`,`reason`) VALUES (?,?,?,NULLIF(?, 0),?)',
        { d.id, traineeCharId, me, tonumber(toRoleId) or 0, tostring(reason or ''):sub(1, 500) })
    if id then hist(d.id, traineeCharId, who, 'recommended', tostring(reason or ''):sub(1, 300)) end
    return id
end)

--- A leader acts on a recommendation: 'approve' (promotes to roleId, or the rank above), 'deny'; the FTO may 'withdraw'.
exports('DecideRecommendation', function(who, recId, action, roleId)
    local rec = MySQL.single.await("SELECT * FROM `es_fto_recommendations` WHERE `id` = ?", { tonumber(recId) or 0 })
    if not rec or rec.status ~= 'pending' then return false, 'That recommendation is not waiting' end
    local d = ctx.resolve(rec.deptId)
    if not d then return false, 'No such department' end
    local me = charOf(who)
    if action == 'withdraw' then
        if me ~= rec.ftoCharId and not may(who, d, 'canPromote') then return false, 'Only the FTO who made it can withdraw it' end
    elseif not may(who, d, 'canPromote') then return false, 'Only leaders who can promote may decide' end
    local status = ({ approve = 'approved', deny = 'denied', withdraw = 'withdrawn' })[action]
    if not status then return false, 'approve, deny or withdraw' end
    if status == 'approved' then
        local target = tonumber(roleId) or rec.toRoleId
        if not target then
            local cur = WC:GetPlayerRole({ charId = rec.traineeCharId }, d.jobId)
            local best
            for _, r in ipairs(WC:GetJobRoles(d.jobId) or {}) do
                if cur and (r.level or 0) > (cur.level or 0) and (not best or r.level < best.level) then best = r end
            end
            target = best and best.roleId
        end
        if not target and isTestId(rec.traineeCharId) then target = programOf(d).completeRoleId end
        if not target then return false, 'Pick the rank to promote them to' end
        local opts = nil
        if not isStaffWho(who) then opts = { by = who } end
        if not isTestId(rec.traineeCharId) then
            if Pers and Pers.expect then Pers.expect(d.jobId, rec.traineeCharId, me, 'FTO recommendation approved' .. (rec.reason and (': ' .. rec.reason) or '')) end
            local ok, why = WC:SetPlayerRole({ charId = rec.traineeCharId }, d.jobId, target, opts)
            if not ok then return false, why end
        end
        finish(d.id, rec.traineeCharId, 'promoted', me)
        notifyChar(rec.traineeCharId, ('%s: you have been promoted'):format(d.short), 'success')
    end
    MySQL.update.await('UPDATE `es_fto_recommendations` SET `status` = ?, `decidedBy` = NULLIF(?, 0), `decidedAt` = NOW() WHERE `id` = ?', { status, me or 0, rec.id })
    hist(d.id, rec.traineeCharId, who, 'rec_' .. action, status == 'approved' and 'Recommendation approved: promoted' or ('Recommendation ' .. status))
    return true
end)

-- ---------------------------------------------------------------- overdue DORs: tell the FTO (once a day each)

local told = {}   -- ['deptId:charId'] = os.date day
local function checkOverdue()
    local day = os.date('!%Y-%m-%d')
    for _, d in ipairs(ctx.sortedDepts()) do
        local ok, list = pcall(trainees, d)
        for _, t in ipairs(ok and list or {}) do
            local k = d.id .. ':' .. t.charId
            if t.overdue and told[k] ~= day then
                if notifyChar(t.ftoCharId, ('%s training: %s has had no DOR for %d days. MDT → Training'):format(d.short, t.name, t.daysSinceDor or 0), 'warning') then
                    told[k] = day
                end
            end
        end
    end
end

-- ---------------------------------------------------------------- staff test trainees (/ftotest)

local function mdtRefresh() TriggerClientEvent('es_mdt:client:refresh', -1, 'training') end
local function say(src, text, kind) if src and src > 0 then WC:NotifyPlayer(src, text, kind or 'info', 7000) else print('[es_departments] ' .. text) end end
local function isTestStaff(src)
    if not src or src <= 0 then return false end
    return ctx.isStaff(src) or IsPlayerAceAllowed(src, Config.AdminAce) or IsPlayerAceAllowed(src, 'command')
end
--- the department to test in: one named by its short name in args, else the first one the caller belongs to
local function testDept(src, args)
    for _, a in ipairs(args) do
        for _, d in ipairs(ctx.sortedDepts()) do if d.short:lower() == tostring(a):lower() then return d, a end end
    end
    for _, d in ipairs(ctx.sortedDepts()) do if WC:GetPlayerRole(src, d.jobId) then return d end end
end
local function deleteTests(d)
    local ids = {}
    for _, r in ipairs(MySQL.query.await('SELECT `charId` FROM `es_fto_trainees` WHERE `deptId` = ? AND `test` = 1', { d.id }) or {}) do ids[#ids + 1] = r.charId end
    MySQL.update.await('DELETE FROM `es_fto_signoffs` WHERE `deptId` = ? AND `traineeCharId` >= ?', { d.id, TEST_BASE })
    MySQL.update.await('DELETE FROM `es_fto_sessions` WHERE `deptId` = ? AND `traineeCharId` >= ?', { d.id, TEST_BASE })
    MySQL.update.await('DELETE FROM `es_fto_recommendations` WHERE `deptId` = ? AND `traineeCharId` >= ?', { d.id, TEST_BASE })
    MySQL.update.await('DELETE FROM `es_fto_history` WHERE `deptId` = ? AND `traineeCharId` >= ?', { d.id, TEST_BASE })
    MySQL.update.await('DELETE FROM `es_fto_trainees` WHERE `deptId` = ? AND (`test` = 1 OR `charId` >= ?)', { d.id, TEST_BASE })
    return #ids
end
-- 1.6.0: for the MDT's test-data cleanup (staff only there): FTO test trainees in every department
exports('ListTestTrainees', function()
    return MySQL.query.await([[SELECT t.`deptId`, t.`charId`, t.`status`, t.`testName` AS `name` FROM `es_fto_trainees` t
        WHERE t.`test` = 1 OR t.`charId` >= ? ORDER BY t.`deptId`, t.`charId`]], { TEST_BASE }) or {}
end)
exports('ClearTestTrainees', function()
    local n = 0
    for _, d in ipairs(ctx.sortedDepts()) do n = n + (deleteTests(d) or 0) end
    return n
end)
local FTOTEST_USE = 'Use: /ftotest trainee [name] | overdue | clear  (add a department short name, e.g. LSPD, to pick one)'

local function registerTest()
    Whip.command('ftotest', { rateLimit = { burst = 4, everyMs = 1000 }, console = false }, function(src, args)
        if not isTestStaff(src) then return say(src, 'FTO test mode is for staff', 'error') end
        args = args or {}
        local sub = tostring(args[1] or ''):lower()
        local d, used = testDept(src, { table.unpack(args, 2) })
        if not d then return say(src, '[TEST] You are not in a department (or name one: /ftotest trainee Test Cadet LSPD)', 'error') end
        if sub == 'trainee' then
            local words = {}
            for i = 2, #args do if args[i] ~= used then words[#words + 1] = args[i] end end
            local row = MySQL.single.await('SELECT COALESCE(MAX(`charId`), ?) AS `m`, COUNT(*) AS `n` FROM `es_fto_trainees` WHERE `charId` >= ?', { TEST_BASE, TEST_BASE })
            local n = row and tonumber(row.n) or 0
            if n >= 10 then return say(src, '[TEST] 10 test trainees is the most. /ftotest clear', 'error') end
            local cid = math.max(TEST_BASE, tonumber(row and row.m) or TEST_BASE) + 1
            local name = cleanLabel(table.concat(words, ' '), 40)
            if name == '' then name = 'Test Cadet ' .. (n + 1) end
            local p = programOf(d)
            MySQL.insert.await([[INSERT INTO `es_fto_trainees` (`deptId`,`charId`,`hiredAt`,`hireRoleId`,`status`,`origin`,`test`,`testName`)
                VALUES (?,?,NOW() - INTERVAL 1 DAY,NULLIF(?, 0),'training','manual',1,?)]], { d.id, cid, (p.recruitRoles or {})[1] or 0, name })
            hist(d.id, cid, src, 'queued', 'Staff test trainee (no real character)')
            mdtRefresh()
            say(src, ('[TEST] "%s" is in %s training. MDT → Training → All trainees: claim them, write DORs, sign off. /ftotest overdue, /ftotest clear'):format(name, d.short), 'success')
        elseif sub == 'overdue' then
            local p = programOf(d)
            local back = (p.dorDays or 3) + 1
            local n = MySQL.update.await([[UPDATE `es_fto_trainees` SET `hiredAt` = LEAST(COALESCE(`hiredAt`, NOW()), NOW() - INTERVAL ? DAY),
                `claimedAt` = IF(`claimedAt` IS NULL, NULL, NOW() - INTERVAL ? DAY) WHERE `deptId` = ? AND `test` = 1 AND `status` = 'training']], { back + 1, back, d.id }) or 0
            -- every DOR of a test trainee moves back so their newest is `back` days old
            for _, r in ipairs(MySQL.query.await([[SELECT `traineeCharId`, TIMESTAMPDIFF(SECOND, MAX(`sessionAt`), NOW()) AS `age` FROM `es_fto_sessions`
                WHERE `deptId` = ? AND `traineeCharId` >= ? GROUP BY `traineeCharId`]], { d.id, TEST_BASE }) or {}) do
                local shift = back * 86400 - (tonumber(r.age) or 0)
                if shift > 0 then
                    MySQL.update.await('UPDATE `es_fto_sessions` SET `sessionAt` = `sessionAt` - INTERVAL ? SECOND WHERE `deptId` = ? AND `traineeCharId` = ?',
                        { shift, d.id, r.traineeCharId })
                end
            end
            if n == 0 then return say(src, '[TEST] No test trainee in training. /ftotest trainee first', 'error') end
            for _, r in ipairs(MySQL.query.await("SELECT `charId` FROM `es_fto_trainees` WHERE `deptId` = ? AND `test` = 1 AND `status` = 'training'", { d.id }) or {}) do
                hist(d.id, r.charId, src, 'test', ('Last DOR moved back %d days (overdue test)'):format(back))
            end
            mdtRefresh()
            say(src, ('[TEST] %d test trainee%s now %d days without a DOR (overdue after %d). Look in Training and Department → Activity.'):format(n, n == 1 and ' is' or 's are', back, p.dorDays), 'success')
        elseif sub == 'clear' then
            local n = deleteTests(d)
            mdtRefresh()
            say(src, ('[TEST] Removed %d test trainee%s with their DORs, sign-offs and history (%s)'):format(n, n == 1 and '' or 's', d.short), 'success')
        else
            say(src, FTOTEST_USE, 'info')
        end
    end)
end

--- Rows whose character is gone (the old FK cascade), never test ones
local function cleanOrphans()
    MySQL.update.await([[DELETE t FROM `es_fto_trainees` t LEFT JOIN `characters` c ON c.`charId` = t.`charId`
        WHERE t.`test` = 0 AND t.`charId` < ? AND c.`charId` IS NULL]], { TEST_BASE })
    MySQL.update.await([[DELETE s FROM `es_fto_sessions` s LEFT JOIN `characters` c ON c.`charId` = s.`traineeCharId`
        WHERE s.`traineeCharId` < ? AND c.`charId` IS NULL]], { TEST_BASE })
    MySQL.update.await([[DELETE s FROM `es_fto_recommendations` s LEFT JOIN `characters` c ON c.`charId` = s.`traineeCharId`
        WHERE s.`traineeCharId` < ? AND c.`charId` IS NULL]], { TEST_BASE })
    MySQL.update.await([[DELETE s FROM `es_fto_signoffs` s LEFT JOIN `characters` c ON c.`charId` = s.`traineeCharId`
        WHERE s.`traineeCharId` < ? AND c.`charId` IS NULL]], { TEST_BASE })
end

function Fto.start(c)
    ctx = c
    up = true
    registerTest()
    local okc, errc = pcall(cleanOrphans)
    if not okc then print(('^3[es_departments] FTO cleanup failed: %s^7'):format(tostring(errc))) end
    local ok, err = pcall(backfill)
    if not ok then print(('^3[es_departments] FTO backfill failed: %s^7'):format(tostring(err))) end
    CreateThread(function()
        Wait(90000)
        while true do
            local ok2, err2 = pcall(checkOverdue)
            if not ok2 then print(('^3[es_departments] FTO overdue check failed: %s^7'):format(tostring(err2))) end
            Wait(30 * 60000)
        end
    end)
end
