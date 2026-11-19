local _ENV = ESAPP('departments'); -- es_departments server: departments on top of WHIP jobs.
--   A department IS a WHIP job (jobs / job_roles / job_employees): its ranks are the job's roles, its
--   people the job's staff, duty is WHIP duty. This resource adds what a job lacks: a short name, a type,
--   colours, a logo, rank extras (abbreviation, insignia, callsign prefix) and member extras (callsign,
--   badge, notes), and declares each type's permissions on the job so every rank gets toggles for them.

local WC = exports.whip_core
local CHUNK = 15000          -- characters of a logo per callback message, either way
local MAX_PARTS = 24         -- 24 x 15000 > the largest logo (192 KB -> 262 KB of base64)

local Depts   = {}           -- [id] = department (no logo)
local Logos   = {}           -- [id] = data URL
local Ranks   = {}           -- [roleId] = { abbr, insignia, callsignPrefix }
local Members = {}           -- [jobId][charId] = { callsign, badge, notes }
local ready   = false

local TYPE = {}
for i, t in ipairs(Config.Types) do TYPE[t.key] = i end

-- ---------------------------------------------------------------- helpers

local function permMap(typeKey)
    local out = {}
    for _, p in ipairs(Config.Permissions[typeKey] or {}) do out[p.key] = p.label end
    return out
end

local function trim(s) return (type(s) == 'string' and s:gsub('^%s+', ''):gsub('%s+$', '')) or '' end

local function validColor(c) return type(c) == 'string' and c:match('^#%x%x%x%x%x%x$') ~= nil end

local function jobKeyOf(jobId)
    local job = WC:GetJob(jobId)
    return job and job.key or nil
end

local function summary(d)
    return {
        id = d.id, jobId = d.jobId, key = jobKeyOf(d.jobId), short = d.short, name = d.name, type = d.type,
        color1 = d.color1, color2 = d.color2, logoVer = d.logoVer, sort = d.sort, settings = d.settings,
    }
end

--- A department by id (number), job key or short name (string), or { jobId = n }.
local function resolve(ref)
    if type(ref) == 'number' then return Depts[ref] end
    if type(ref) == 'table' and ref.jobId then
        for _, d in pairs(Depts) do if d.jobId == ref.jobId then return d end end
        return nil
    end
    if type(ref) == 'string' then
        local low = ref:lower()
        for _, d in pairs(Depts) do
            if d.short:lower() == low or (jobKeyOf(d.jobId) or ''):lower() == low then return d end
        end
    end
    return nil
end

local function byJob(jobId)
    for _, d in pairs(Depts) do if d.jobId == jobId then return d end end
    return nil
end

local function sortedDepts()
    local list = {}
    for _, d in pairs(Depts) do list[#list + 1] = d end
    table.sort(list, function(a, b)
        if a.sort ~= b.sort then return a.sort < b.sort end
        return a.id < b.id
    end)
    return list
end

local function isAdmin(source)
    return WC:HasDevTools(source) == true or IsPlayerAceAllowed(source, Config.AdminAce)
end

local function isStaff(source)
    return isAdmin(source) or WC:HasPermission(source, Config.StaffPerm) == true
end

--- What this player may do at this department. Staff act as a trusted caller (no `by`); everyone else acts
--- as themselves, and WHIP's rank rules decide (outrank, hold the permission, give nothing they lack).
local function rightsOf(source, d)
    local staff = isStaff(source)
    local role = WC:GetPlayerRole(source, d.jobId)
    local function jp(p) return staff or (role ~= nil and WC:HasJobPermission(source, d.jobId, p) == true) end
    return {
        admin   = isAdmin(source),
        staff   = staff,
        view    = staff or role ~= nil,
        edit    = jp('canManage'),
        ranks   = jp('canManage'),
        hire    = jp('canHire'),
        fire    = jp('canFire'),
        promote = jp('canPromote') or jp('canDemote'),
        roster  = jp('canManage') or jp('canHire'),
        myLevel = role and role.level or nil,
    }
end

-- 1.6.0: staff act with no rank check (nil); `x and nil or y` always gave y, so staff were rank-checked
local function byOpts(source, r) if r and r.staff then return nil end return { by = source } end

local function broadcast(id)
    TriggerClientEvent('es_departments:client:changed', -1, id)
    TriggerEvent('es_departments:server:changed', id)   -- 2.0.10: the MDT drops what it keeps (permissions, the on-duty list)
end

local function log(source, what, detail)
    if source and source > 0 then
        CreateThread(function() WC:LogActivity(source, 'es_departments_' .. what, { detail = detail }) end)
    end
end

-- ---------------------------------------------------------------- database

local function load()
    local rows = MySQL.query.await('SELECT `id`,`jobId`,`short`,`name`,`type`,`color1`,`color2`,`logo`,`logoVer`,`sort`,`settings` FROM `es_departments`')
    if not rows then return false end
    Depts, Logos = {}, {}
    for _, r in ipairs(rows) do
        local settings = {}
        if type(r.settings) == 'string' and r.settings ~= '' then settings = json.decode(r.settings) or {} end
        Depts[r.id] = { id = r.id, jobId = r.jobId, short = r.short, name = r.name, type = r.type,
            color1 = r.color1, color2 = r.color2, logoVer = r.logoVer or 0, sort = r.sort or 0, settings = settings }
        Logos[r.id] = r.logo
    end
    Ranks = {}
    for _, r in ipairs(MySQL.query.await('SELECT `roleId`,`abbr`,`insignia`,`callsignPrefix` FROM `es_dept_ranks`') or {}) do
        Ranks[r.roleId] = { abbr = r.abbr, insignia = r.insignia, callsignPrefix = r.callsignPrefix }
    end
    Members = {}
    for _, r in ipairs(MySQL.query.await('SELECT `jobId`,`charId`,`callsign`,`badge`,`notes` FROM `es_dept_members`') or {}) do
        Members[r.jobId] = Members[r.jobId] or {}
        Members[r.jobId][r.charId] = { callsign = r.callsign, badge = r.badge, notes = r.notes }
    end
    return true
end

local function ensureTables()
    local ok, why = EsSchema.ensure('es_departments', [[CREATE TABLE IF NOT EXISTS `es_departments` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `jobId` INT UNSIGNED NOT NULL,
        `short` VARCHAR(12) NOT NULL,
        `name` VARCHAR(80) NOT NULL,
        `type` VARCHAR(16) NOT NULL,
        `color1` CHAR(7) NOT NULL DEFAULT '#1b2a5c',
        `color2` CHAR(7) NOT NULL DEFAULT '#f2c230',
        `logo` MEDIUMTEXT NULL,
        `logoVer` INT UNSIGNED NOT NULL DEFAULT 0,
        `sort` INT NOT NULL DEFAULT 0,
        `settings` JSON NULL,
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `createdBy` INT UNSIGNED NULL,
        PRIMARY KEY (`id`),
        UNIQUE KEY `uk_es_dept_job` (`jobId`),
        CONSTRAINT `fk_es_dept_job` FOREIGN KEY (`jobId`) REFERENCES `jobs` (`jobId`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]], {})
    if not ok then return false, why end

    ok, why = EsSchema.ensure('es_dept_ranks', [[CREATE TABLE IF NOT EXISTS `es_dept_ranks` (
        `roleId` INT UNSIGNED NOT NULL,
        `jobId` INT UNSIGNED NOT NULL,
        `abbr` VARCHAR(8) NULL,
        `insignia` VARCHAR(24) NULL,
        `callsignPrefix` VARCHAR(8) NULL,
        PRIMARY KEY (`roleId`),
        KEY `idx_es_rank_job` (`jobId`),
        CONSTRAINT `fk_es_rank_role` FOREIGN KEY (`roleId`) REFERENCES `job_roles` (`roleId`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]], {})
    if not ok then return false, why end

    ok, why = EsSchema.ensure('es_dept_members', [[CREATE TABLE IF NOT EXISTS `es_dept_members` (
        `jobId` INT UNSIGNED NOT NULL,
        `charId` INT UNSIGNED NOT NULL,
        `callsign` VARCHAR(16) NULL,
        `badge` VARCHAR(12) NULL,
        `notes` VARCHAR(500) NULL,
        `updatedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`jobId`, `charId`),
        KEY `idx_es_member_char` (`charId`),
        CONSTRAINT `fk_es_member_job` FOREIGN KEY (`jobId`) REFERENCES `jobs` (`jobId`) ON DELETE CASCADE,
        CONSTRAINT `fk_es_member_char` FOREIGN KEY (`charId`) REFERENCES `characters` (`charId`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]], {})
    if not ok then return false, why end
    return true
end

local function saveRankExtra(roleId, jobId, extra)
    local ok = MySQL.query.await([[INSERT INTO `es_dept_ranks` (`roleId`,`jobId`,`abbr`,`insignia`,`callsignPrefix`)
        VALUES (?,?,?,?,?) ON DUPLICATE KEY UPDATE `abbr`=VALUES(`abbr`), `insignia`=VALUES(`insignia`),
        `callsignPrefix`=VALUES(`callsignPrefix`)]],
        { roleId, jobId, extra.abbr, extra.insignia, extra.callsignPrefix })
    if not ok then return false end
    Ranks[roleId] = { abbr = extra.abbr, insignia = extra.insignia, callsignPrefix = extra.callsignPrefix }
    return true
end

-- ---------------------------------------------------------------- jobs

--- A rank's department permissions by its level, from Config.DefaultRankPermissions.
local function defaultPerms(typeKey, level)
    local family = (typeKey == 'ems' or typeKey == 'doj') and typeKey or 'law'
    local out = {}
    for _, rule in ipairs(Config.DefaultRankPermissions[family] or {}) do
        if level >= rule.min then
            if rule.perms == 'all' then
                for _, p in ipairs(Config.Permissions[typeKey] or {}) do out[p.key] = true end
            else
                for _, k in ipairs(rule.perms) do out[k] = true end
            end
            break
        end
    end
    return out
end

--- Declare the department's job to WHIP: its name and its type's permissions. Every start and on change.
local function declareJob(d)
    local key = jobKeyOf(d.jobId)
    if not key then return false, 'its job is gone' end
    return WC:EnsureJob(key, { name = d.short, permissions = permMap(d.type) })
end

--- Make (or adopt) the job, then the department row.
local function createDepartment(data, createdBy)
    local existing = WC:GetJob(data.key)
    local roles = {}
    local rankDefs = data.rankList or Config.DefaultRanks[data.type] or Config.DefaultRanks.police
    for _, r in ipairs(rankDefs) do
        local perms = defaultPerms(data.type, r.level)
        for k, v in pairs(r.permissions or {}) do perms[k] = v end
        roles[#roles + 1] = { name = r.name, level = r.level, permissions = perms }
    end
    local spec = { name = data.short, permissions = permMap(data.type) }
    if not existing then
        spec.roles = roles
        if data.owner then spec.owner = { charId = data.owner } end
    end
    local job, why = WC:EnsureJob(data.key, spec)
    if not job and spec.owner then
        spec.owner = nil
        job, why = WC:EnsureJob(data.key, spec)
    end
    if not job then return false, why end
    if byJob(job.jobId) then return false, 'That job already has a department' end

    local id = MySQL.insert.await([[INSERT INTO `es_departments`
        (`jobId`,`short`,`name`,`type`,`color1`,`color2`,`logo`,`logoVer`,`sort`,`createdBy`) VALUES (?,?,?,?,?,?,?,?,?,?)]],
        { job.jobId, data.short, data.name, data.type, data.color1, data.color2, data.logo, data.logo and 1 or 0,
          data.sort or 0, createdBy })
    if not id then return false, 'Could not save that (database error)' end
    Depts[id] = { id = id, jobId = job.jobId, short = data.short, name = data.name, type = data.type,
        color1 = data.color1, color2 = data.color2, logoVer = data.logo and 1 or 0, sort = data.sort or 0, settings = {} }
    Logos[id] = data.logo

    -- Rank extras: abbreviations for the type's default ranks (and for an adopted job's ranks by name)
    local abbrByName = {}
    for _, r in ipairs(rankDefs) do abbrByName[r.name:lower()] = r.abbr end
    for name, abbr in pairs(data.rankAbbr or {}) do abbrByName[name:lower()] = abbr end
    for _, role in ipairs(WC:GetJobRoles(job.jobId) or {}) do
        local abbr = abbrByName[role.name:lower()]
        if abbr and not Ranks[role.roleId] then saveRankExtra(role.roleId, job.jobId, { abbr = abbr }) end
    end
    -- An adopted job's ranks get the type's permissions by level, added to what they hold
    if existing then
        for _, role in ipairs(WC:GetJobRoles(job.jobId) or {}) do
            if role.level < 100 then
                local add = defaultPerms(data.type, role.level)
                if next(add) then WC:UpdateJobRole(job.jobId, role.roleId, { permissions = add }) end
            end
        end
    end
    return Depts[id]
end

local function seedLogo(path)
    local raw = path and LoadResourceFile(GetCurrentResourceName(), path)
    if not raw or raw == '' then return nil end
    local mime = path:match('%.(%a+)%.b64$') or 'webp'
    local logo = Logo.check(('data:image/%s;base64,%s'):format(mime, (raw:gsub('%s', ''))))
    if not logo then print(('[es_departments] seed logo %s did not pass the check'):format(path)) end
    return logo or nil
end

--- The seed list, by version: version 1 on the first start (an empty table), later entries (since = n) once
--- each, on the first start that knows them. One whose job already has a department is not made again; it
--- only gets the seed logo when it has none.
local function seed()
    local done = tonumber(GetResourceKvpString('es_departments:seeded') or '0') or 0
    local want = 1
    for _, s in ipairs(Config.Seed) do want = math.max(want, s.since or 1) end
    if done >= want then return end
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM `es_departments`')
    if count == nil then return end
    if done == 0 and tonumber(count) > 0 then done = 1 end
    for _, s in ipairs(Config.Seed) do
        if (s.since or 1) > done then
            local job = WC:GetJob(s.key)
            local have = job and byJob(job.jobId)
            if have then
                if not Logos[have.id] then
                    local logo = seedLogo(s.logo)
                    if logo and MySQL.update.await('UPDATE `es_departments` SET `logo`=?, `logoVer`=`logoVer`+1 WHERE `id`=?', { logo, have.id }) then
                        Logos[have.id], have.logoVer = logo, (have.logoVer or 0) + 1
                    end
                end
                print(('[es_departments] %s: a department for job "%s" is already there (%s), not made again'):format(s.short, s.key, have.short))
            else
                local d, why = createDepartment({ key = s.key, short = s.short, name = s.name, type = s.type,
                    color1 = s.color1, color2 = s.color2, logo = seedLogo(s.logo), sort = s.sort, owner = s.owner,
                    rankAbbr = s.ranks, rankList = s.rankList }, nil)
                if d then
                    print(('[es_departments] seeded %s (job "%s")'):format(s.short, s.key))
                else
                    Whip.startProblem('seeding %s failed: %s', s.short, tostring(why))
                end
            end
        end
    end
    SetResourceKvp('es_departments:seeded', tostring(want))
end

-- ---------------------------------------------------------------- reads

local function rolesOf(d)
    local list = {}
    for _, role in ipairs(WC:GetJobRoles(d.jobId) or {}) do
        local x = Ranks[role.roleId] or {}
        list[#list + 1] = { roleId = role.roleId, name = role.name, level = role.level,
            permissions = role.permissions or {}, abbr = x.abbr, insignia = x.insignia, callsignPrefix = x.callsignPrefix }
    end
    return list
end

local function namesOf(charIds)
    local out = {}
    if #charIds == 0 then return out end
    local marks = {}
    for i = 1, #charIds do marks[i] = '?' end
    local rows = MySQL.query.await(('SELECT `charId`,`firstName`,`lastName` FROM `characters` WHERE `charId` IN (%s)')
        :format(table.concat(marks, ',')), charIds) or {}
    for _, r in ipairs(rows) do out[r.charId] = (r.firstName or '') .. ' ' .. (r.lastName or '') end
    return out
end

local function rosterOf(d)
    local job = WC:GetJob(d.jobId)
    if not job then return {} end
    local emps = WC:GetJobEmployees(d.jobId) or {}
    local list, ids = {}, {}
    for charId, e in pairs(emps) do
        list[#list + 1] = { charId = charId, roleId = e.roleId, roleName = e.roleName, roleLevel = e.roleLevel,
            onDuty = e.onDuty == true, online = e.source ~= nil, source = e.source, hiredAt = e.hiredAt }
        ids[#ids + 1] = charId
    end
    if job.ownerCharId and not emps[job.ownerCharId] then
        local role = WC:GetPlayerRole({ charId = job.ownerCharId }, d.jobId)
        local onDuty = false
        for _, c in ipairs(WC:GetClockedOnEmployees(d.jobId) or {}) do
            if c.charId == job.ownerCharId then onDuty = true end
        end
        list[#list + 1] = { charId = job.ownerCharId, roleId = role and role.roleId, roleName = role and role.name,
            roleLevel = role and role.level, onDuty = onDuty, online = false, owner = true }
        ids[#ids + 1] = job.ownerCharId
    end
    local names = namesOf(ids)
    local extra = Members[d.jobId] or {}
    for _, m in ipairs(list) do
        m.name = names[m.charId] or ('#' .. m.charId)
        if m.charId == job.ownerCharId then m.owner = true end
        local x = extra[m.charId] or {}
        m.callsign, m.badge, m.notes = x.callsign, x.badge, x.notes
        local rx = m.roleId and Ranks[m.roleId]
        m.abbr = rx and rx.abbr or nil
    end
    table.sort(list, function(a, b)
        if (a.roleLevel or 0) ~= (b.roleLevel or 0) then return (a.roleLevel or 0) > (b.roleLevel or 0) end
        return a.name < b.name
    end)
    return list
end

-- Who is in the city right now (an owner who was never hired has no employee row to say so)
local function fillOnline(list)
    local online = {}
    for src, p in pairs(WC:GetPlayers({ light = true }) or {}) do
        if p.charId then online[p.charId] = tonumber(src) end
    end
    for _, m in ipairs(list) do
        if online[m.charId] then m.online = true m.source = online[m.charId] else m.online = false m.source = nil end
    end
    return list
end

-- ---------------------------------------------------------------- exports

exports('GetDepartments', function()
    local out = {}
    for _, d in ipairs(sortedDepts()) do out[#out + 1] = summary(d) end
    return out
end)

exports('GetDepartment', function(ref)
    local d = resolve(ref)
    if not d then return false, 'No such department' end
    local s = summary(d)
    s.ranks = rolesOf(d)
    return s
end)

exports('GetPlayerDepartments', function(who)
    local jobs, why = WC:GetPlayerJobs(who)
    if type(jobs) ~= 'table' then return {}, why end
    local out = {}
    for jobId, j in pairs(jobs) do
        local d = byJob(jobId)
        if d then
            local s = summary(d)
            local charId = type(who) == 'table' and who.charId or WC:GetCharId(who)
            local x = (Members[jobId] or {})[charId or 0] or {}
            s.roleId, s.roleName, s.roleLevel, s.onDuty = j.roleId, j.roleName, j.roleLevel, j.clockedOn == true
            s.callsign, s.badge = x.callsign, x.badge
            out[#out + 1] = s
        end
    end
    table.sort(out, function(a, b) return a.sort < b.sort end)
    return out
end)

exports('GetActiveDepartment', function(who)
    local job = WC:GetPlayerJob(who)
    if not job then return false, 'Not on duty' end
    local d = byJob(job.jobId)
    if not d then return false, 'Not on duty at a department' end
    local s = summary(d)
    s.roleId, s.roleName, s.roleLevel = job.roleId, job.roleName, job.roleLevel
    local charId = type(who) == 'table' and who.charId or WC:GetCharId(who)
    local x = (Members[d.jobId] or {})[charId or 0] or {}
    s.callsign, s.badge = x.callsign, x.badge
    return s
end)

--- 1.9.0: May they, at ANY of their departments? For resources that do not know the department (e.g. whip_evidence):
--- exports.es_departments:HasPerm(source, 'evidence_upload') -> true, dept summary | false, why. On duty unless opts.onDuty == false.
exports('HasPerm', function(who, permission, opts)
    if type(permission) ~= 'string' or permission == '' then return false, 'No permission named' end
    local onDuty = not (type(opts) == 'table' and opts.onDuty == false)
    local jobs = WC:GetPlayerJobs(who)
    if type(jobs) ~= 'table' then return false, 'Not in a department' end
    local why = 'Not in a department'
    for jobId in pairs(jobs) do
        local d = byJob(jobId)
        if d then
            local ok, w = WC:HasJobPermission(who, d.jobId, permission, { onDuty = onDuty })
            if ok then return true, summary(d) end
            why = w or ('Your rank at ' .. d.short .. ' does not have that permission')
        end
    end
    return false, why
end)

--- May they? Department permission (or WHIP built-in) at a department; on duty there unless opts.onDuty == false.
exports('Can', function(who, ref, permission, opts)
    local d = resolve(ref)
    if not d then return false, 'No such department' end
    local onDuty = not (type(opts) == 'table' and opts.onDuty == false)
    return WC:HasJobPermission(who, d.jobId, permission, { onDuty = onDuty })
end)

exports('GetRoster', function(ref)
    local d = resolve(ref)
    if not d then return false, 'No such department' end
    return fillOnline(rosterOf(d))
end)

exports('GetOnDuty', function(ref)
    local d = resolve(ref)
    if not d then return false, 'No such department' end
    local out = {}
    local extra = Members[d.jobId] or {}
    for _, c in ipairs(WC:GetClockedOnEmployees(d.jobId) or {}) do
        local role = WC:GetPlayerRole({ charId = c.charId }, d.jobId)
        local x = extra[c.charId] or {}
        out[#out + 1] = { charId = c.charId, source = c.source, roleId = role and role.roleId,
            roleName = role and role.name, roleLevel = role and role.level, callsign = x.callsign, badge = x.badge }
    end
    return out
end)

exports('GetLogo', function(ref)
    local d = resolve(ref)
    if not d then return false, 'No such department' end
    if not Logos[d.id] then return false, 'No logo' end
    return Logos[d.id], d.logoVer
end)

-- ---------------------------------------------------------------- the screen's calls

local uploads = {}   -- [source] = { deptId, total, parts = {} }
local fetched = {}   -- [source] = data URL of a picture fetched from a link, until it is collected
local FETCH_CHUNK = 45000
AddEventHandler('playerDropped', function() uploads[source] = nil fetched[source] = nil end)

local function deptFor(source, id, need)
    local d = Depts[id]
    if not d then return false, false, 'No such department' end
    local r = rightsOf(source, d)
    if need and not r[need] then return false, false, 'Your rank is not allowed to do that' end
    return d, r
end

local function cleanText(s, max) return trim(s):sub(1, max) end

local function register()
    -- The list for the screen: what this player may see, and whether they may create
    Whip.core:SecureCallback('es_departments:open', { rateLimit = 300, burst = 6, sheet = 'light' }, function(source)
        local staff = isStaff(source)
        local list = {}
        local mine = WC:GetPlayerJobs(source) or {}
        for _, d in ipairs(sortedDepts()) do
            if staff or mine[d.jobId] then list[#list + 1] = summary(d) end
        end
        if #list == 0 and not staff then return false, 'You are not in a department' end
        local perms = {}
        for k, v in pairs(Config.Permissions) do perms[k] = v end
        return { departments = list, admin = isAdmin(source), staff = staff, health = staff, types = Config.Types,
            permissions = perms, builtins = Config.BuiltinPermissions, insignia = Config.Insignia }
    end)

    -- Admin health view: every department's heads and how active its people are
    Whip.core:SecureCallback('es_departments:health', { rateLimit = 1500, burst = 3, sheet = 'light' }, function(source)
        if not isStaff(source) then return false, 'Only admins can see department health' end
        return Duty.health()
    end)

    Whip.core:SecureCallback('es_departments:get', { rateLimit = 250, burst = 6, sheet = 'light',
        params = { { 'id', 'id' } } }, function(source, _, id)
        local d, r, why = deptFor(source, id, 'view')
        if not d then return false, why end
        local s = summary(d)
        s.ranks = rolesOf(d)
        s.roster = fillOnline(rosterOf(d))
        s.rights = r
        local job = WC:GetJob(d.jobId)
        s.ownerCharId = job and job.ownerCharId or nil
        return s
    end)

    Whip.core:SecureCallback('es_departments:create', { rateLimit = 2000, sheet = 'light',
        params = { { 'data', 'record', {
            { 'short', 'string', 12 }, { 'name', 'string', 80 }, { 'key', 'key', 50 },
            { 'type', 'enum', { 'police', 'sheriff', 'state', 'ems', 'doj' } },
            { 'color1', 'string', 7, '#1b2a5c' }, { 'color2', 'string', 7, '#f2c230' },
        } } } }, function(source, player, data)
        if not isAdmin(source) then return false, 'Only full admins can create departments' end
        local short, name = cleanText(data.short, 12), cleanText(data.name, 80)
        if short == '' or name == '' then return false, 'A department needs a name and a short name' end
        if not data.key:match('^[%a_][%w_]*$') then return false, 'The job key is letters, digits and _' end
        for _, d in pairs(Depts) do
            if d.short:lower() == short:lower() then return false, 'Another department is called ' .. short end
        end
        local d, why = createDepartment({ key = data.key:lower(), short = short, name = name, type = data.type,
            color1 = validColor(data.color1) and data.color1 or '#1b2a5c',
            color2 = validColor(data.color2) and data.color2 or '#f2c230',
            sort = #sortedDepts() + 1 }, player.charId)
        if not d then return false, why end
        log(source, 'created', ('%s (%s, job %s)'):format(name, short, data.key))
        broadcast(d.id)
        return d.id
    end)

    Whip.core:SecureCallback('es_departments:update', { rateLimit = 1000, burst = 3, sheet = 'light',
        params = { { 'id', 'id' }, { 'data', 'record', {
            { 'short', 'string', 12 }, { 'name', 'string', 80 },
            { 'type', 'enum', { 'police', 'sheriff', 'state', 'ems', 'doj' } },
            { 'color1', 'string', 7, '#1b2a5c' }, { 'color2', 'string', 7, '#f2c230' },
            { 'sort', 'int', 0, 999, 0 },
        } } } }, function(source, _, id, data)
        local d, r, why = deptFor(source, id, 'edit')
        if not d then return false, why end
        local short, name = cleanText(data.short, 12), cleanText(data.name, 80)
        if short == '' or name == '' then return false, 'A department needs a name and a short name' end
        for _, o in pairs(Depts) do
            if o.id ~= d.id and o.short:lower() == short:lower() then return false, 'Another department is called ' .. short end
        end
        local typ = d.type
        if data.type ~= d.type then
            if not r.admin then return false, 'Only full admins can change a department type' end
            typ = data.type
        end
        local c1 = validColor(data.color1) and data.color1 or d.color1
        local c2 = validColor(data.color2) and data.color2 or d.color2
        local sort = r.staff and data.sort or d.sort
        local ok = MySQL.update.await('UPDATE `es_departments` SET `short`=?,`name`=?,`type`=?,`color1`=?,`color2`=?,`sort`=? WHERE `id`=?',
            { short, name, typ, c1, c2, sort, d.id })
        if ok == nil then return false, 'Could not save that (database error)' end
        d.short, d.name, d.type, d.color1, d.color2, d.sort = short, name, typ, c1, c2, sort
        local done, jwhy = declareJob(d)
        if not done then print(('[es_departments] %s: job not updated: %s'):format(short, tostring(jwhy))) end
        log(source, 'updated', short)
        broadcast(d.id)
        return true
    end)

    Whip.core:SecureCallback('es_departments:delete', { rateLimit = 3000, sheet = 'light',
        params = { { 'id', 'id' }, { 'alsoJob', 'bool', false } } }, function(source, _, id, alsoJob)
        if not isAdmin(source) then return false, 'Only full admins can delete departments' end
        local d = Depts[id]
        if not d then return false, 'No such department' end
        local key = jobKeyOf(d.jobId)
        if alsoJob then
            local ok, why = WC:DeleteJob(d.jobId)   -- cascades the department's rows
            if not ok then return false, why end
        end
        local ok = MySQL.update.await('DELETE FROM `es_departments` WHERE `id`=?', { d.id })
        if ok == nil then return false, 'Could not save that (database error)' end
        Depts[d.id], Logos[d.id] = nil, nil
        log(source, 'deleted', ('%s (job %s%s)'):format(d.short, tostring(key), alsoJob and ', job deleted' or ', job kept'))
        broadcast(d.id)
        return true
    end)

    -- A logo, in parts (a net message has to stay small). The last part checks and saves it.
    Whip.core:SecureCallback('es_departments:logoPart', { rateLimit = 60, burst = MAX_PARTS + 2, sheet = 'light',
        params = { { 'id', 'id' }, { 'idx', 'id', 1, MAX_PARTS }, { 'total', 'id', 1, MAX_PARTS },
            { 'part', 'string', CHUNK } } }, function(source, _, id, idx, total, part)
        local d, _, why = deptFor(source, id, 'edit')
        if not d then return false, why end
        local up = uploads[source]
        if idx == 1 or not up or up.deptId ~= id or up.total ~= total then
            up = { deptId = id, total = total, parts = {} }
            uploads[source] = up
        end
        up.parts[idx] = part
        for i = 1, total do if not up.parts[i] then return { pending = true } end end
        uploads[source] = nil
        local logo, bad = Logo.check(table.concat(up.parts))
        if not logo then return false, bad end
        local ver = (d.logoVer or 0) + 1
        local ok = MySQL.update.await('UPDATE `es_departments` SET `logo`=?, `logoVer`=? WHERE `id`=?', { logo, ver, d.id })
        if ok == nil then return false, 'Could not save that (database error)' end
        Logos[d.id], d.logoVer = logo, ver
        log(source, 'logo', d.short)
        broadcast(d.id)
        return { done = true, logoVer = ver }
    end)

    -- Logos are badges anyone may see (the MDT and duty lists show them): part by part, with the version
    Whip.core:SecureCallback('es_departments:logo', { rateLimit = 50, burst = 40, sheet = 'light',
        params = { { 'id', 'id' }, { 'idx', 'id', 1, MAX_PARTS } } }, function(source, _, id, idx)
        local d = Depts[id]
        if not d then return false, 'No such department' end
        local logo = Logos[id]
        if not logo then return { ver = d.logoVer, total = 0 } end
        local total = math.ceil(#logo / CHUNK)
        return { ver = d.logoVer, total = total, part = logo:sub((idx - 1) * CHUNK + 1, idx * CHUNK) }
    end)

    -- A picture from a link, fetched by the server when the player's own browser is not allowed to read it.
    -- Only for people who may change a logo (id 0 = a new department: full admins). Only pictures come back.
    Whip.core:SecureCallback('es_departments:urlFetch', { rateLimit = 3000, burst = 2, sheet = 'light',
        params = { { 'id', 'int', 0, 2147483647, 0 }, { 'url', 'string', 500 } } }, function(source, _, id, url)
        if id == 0 then
            if not isAdmin(source) then return false, 'Only full admins can create departments' end
        else
            local d, _, why = deptFor(source, id, 'edit')
            if not d then return false, why end
        end
        local ok, why = Fetch.check(url)
        if not ok then return false, why end
        local data, ferr = Fetch.get(url)
        if not data then return false, ferr end
        fetched[source] = data
        return { total = math.ceil(#data / FETCH_CHUNK), length = #data }
    end)

    Whip.core:SecureCallback('es_departments:urlPart', { rateLimit = 25, burst = 40, sheet = 'light',
        params = { { 'idx', 'id', 1, 400 } } }, function(source, _, idx)
        local data = fetched[source]
        if not data then return false, 'Nothing fetched' end
        local part = data:sub((idx - 1) * FETCH_CHUNK + 1, idx * FETCH_CHUNK)
        if idx * FETCH_CHUNK >= #data then fetched[source] = nil end
        return part
    end)

    -- A rank: new (roleId 0) or changed; its WHIP permissions and its extras
    Whip.core:SecureCallback('es_departments:rankSave', { rateLimit = 500, burst = 4, sheet = 'light',
        params = { { 'id', 'id' }, { 'roleId', 'int', 0, 2147483647, 0 }, { 'data', 'record', {
            { 'name', 'string', 60 }, { 'level', 'int', 1, 100, 1 },
            { 'abbr', 'string', 8, '' }, { 'insignia', 'string', 24, 'none' }, { 'callsignPrefix', 'string', 8, '' },
            { 'bankAccess', 'enum', { 'none', 'view', 'deposit', 'withdraw', 'manager' }, 'none' },
        } }, { 'perms', 'list', { 'perm', 'key', 40 }, 40 } } }, function(source, _, id, roleId, data, perms)
        local d, r, why = deptFor(source, id, 'ranks')
        if not d then return false, why end
        local name = cleanText(data.name, 60)
        if name == '' then return false, 'A rank needs a name' end
        local on = {}
        for _, k in ipairs(perms) do on[k] = true end
        local permissions = { bankAccess = data.bankAccess }
        for _, p in ipairs(Config.BuiltinPermissions) do permissions[p.key] = on[p.key] == true end
        for _, p in ipairs(Config.Permissions[d.type] or {}) do permissions[p.key] = on[p.key] == true end
        local opts = byOpts(source, r)
        local role, rwhy
        if roleId == 0 then
            role, rwhy = WC:CreateJobRole(d.jobId, { name = name, level = data.level, permissions = permissions }, opts)
            if not role then return false, rwhy end
            roleId = role.roleId
        else
            local found = false
            for _, x in ipairs(WC:GetJobRoles(d.jobId) or {}) do if x.roleId == roleId then found = true end end
            if not found then return false, 'No such rank' end
            local ok
            ok, rwhy = WC:UpdateJobRole(d.jobId, roleId, { name = name, level = data.level, permissions = permissions }, opts)
            if not ok then return false, rwhy end
        end
        local ins = data.insignia
        local okIns = false
        for _, i in ipairs(Config.Insignia) do if i == ins then okIns = true end end
        if not saveRankExtra(roleId, d.jobId, { abbr = cleanText(data.abbr, 8):upper(), insignia = okIns and ins or 'none',
            callsignPrefix = cleanText(data.callsignPrefix, 8) }) then
            return false, 'The rank saved, but its abbreviation could not be (database error)'
        end
        log(source, 'rank', ('%s: %s (%d)'):format(d.short, name, data.level))
        broadcast(d.id)
        return roleId
    end)

    Whip.core:SecureCallback('es_departments:rankDelete', { rateLimit = 1000, sheet = 'light',
        params = { { 'id', 'id' }, { 'roleId', 'id' } } }, function(source, _, id, roleId)
        local d, r, why = deptFor(source, id, 'ranks')
        if not d then return false, why end
        local ok, dwhy = WC:DeleteJobRole(d.jobId, roleId, byOpts(source, r))
        if not ok then return false, dwhy end
        Ranks[roleId] = nil
        log(source, 'rank_deleted', ('%s: role %d'):format(d.short, roleId))
        broadcast(d.id)
        return true
    end)

    -- Hire someone who is on the server, by their server id
    Whip.core:SecureCallback('es_departments:hire', { rateLimit = 1000, sheet = 'light',
        params = { { 'id', 'id' }, { 'target', 'id', 1, 65535 }, { 'roleId', 'id' } } }, function(source, _, id, target, roleId)
        local d, r, why = deptFor(source, id, 'hire')
        if not d then return false, why end
        if not WC:GetCharId(target) then return false, 'Nobody with that server id is in the city' end
        if Pers and Pers.expect then Pers.expect(d.jobId, WC:GetCharId(target), WC:GetCharId(source), nil) end
        local ok, hwhy = WC:HirePlayer(target, d.jobId, roleId, byOpts(source, r))
        if not ok then return false, hwhy end
        WC:NotifyPlayer(target, ('You joined %s'):format(d.name), 'success')
        log(source, 'hired', ('%s: server id %d'):format(d.short, target))
        broadcast(d.id)
        return true
    end)

    Whip.core:SecureCallback('es_departments:setRank', { rateLimit = 500, burst = 3, sheet = 'light',
        params = { { 'id', 'id' }, { 'charId', 'id' }, { 'roleId', 'id' } } }, function(source, _, id, charId, roleId)
        local d, r, why = deptFor(source, id, 'promote')
        if not d then return false, why end
        if Pers and Pers.expect then Pers.expect(d.jobId, charId, WC:GetCharId(source), nil) end
        local ok, pwhy = WC:SetPlayerRole({ charId = charId }, d.jobId, roleId, byOpts(source, r))
        if not ok then return false, pwhy end
        log(source, 'set_rank', ('%s: char %d -> role %d'):format(d.short, charId, roleId))
        broadcast(d.id)
        return true
    end)

    Whip.core:SecureCallback('es_departments:fire', { rateLimit = 1000, sheet = 'light',
        params = { { 'id', 'id' }, { 'charId', 'id' } } }, function(source, _, id, charId)
        local d, r, why = deptFor(source, id, 'fire')
        if not d then return false, why end
        if Pers and Pers.expect then Pers.expect(d.jobId, charId, WC:GetCharId(source), nil) end
        local ok, fwhy = WC:FirePlayer({ charId = charId }, d.jobId, byOpts(source, r))
        if not ok then return false, fwhy end
        MySQL.update.await('DELETE FROM `es_dept_members` WHERE `jobId`=? AND `charId`=?', { d.jobId, charId })
        if Members[d.jobId] then Members[d.jobId][charId] = nil end
        log(source, 'fired', ('%s: char %d'):format(d.short, charId))
        broadcast(d.id)
        return true
    end)

    -- Callsign, badge number and notes of someone in the department
    Whip.core:SecureCallback('es_departments:member', { rateLimit = 300, burst = 5, sheet = 'light',
        params = { { 'id', 'id' }, { 'charId', 'id' }, { 'data', 'record', {
            { 'callsign', 'string', 16, '' }, { 'badge', 'string', 12, '' }, { 'notes', 'string', 500, '' },
        } } } }, function(source, _, id, charId, data)
        local d, _, why = deptFor(source, id, 'roster')
        if not d then return false, why end
        if not WC:GetPlayerRole({ charId = charId }, d.jobId) then return false, 'They are not in this department' end
        local callsign, badge, notes = cleanText(data.callsign, 16):upper(), cleanText(data.badge, 12), cleanText(data.notes, 500)
        for other, x in pairs(Members[d.jobId] or {}) do
            if other ~= charId then
                if callsign ~= '' and x.callsign == callsign then return false, 'Callsign ' .. callsign .. ' is taken' end
                if badge ~= '' and x.badge == badge then return false, 'Badge ' .. badge .. ' is taken' end
            end
        end
        local ok = MySQL.query.await([[INSERT INTO `es_dept_members` (`jobId`,`charId`,`callsign`,`badge`,`notes`) VALUES (?,?,?,?,?)
            ON DUPLICATE KEY UPDATE `callsign`=VALUES(`callsign`),`badge`=VALUES(`badge`),`notes`=VALUES(`notes`)]],
            { d.jobId, charId, callsign ~= '' and callsign or nil, badge ~= '' and badge or nil, notes ~= '' and notes or nil })
        if not ok then return false, 'Could not save that (database error)' end
        Members[d.jobId] = Members[d.jobId] or {}
        Members[d.jobId][charId] = { callsign = callsign ~= '' and callsign or nil, badge = badge ~= '' and badge or nil,
            notes = notes ~= '' and notes or nil }
        broadcast(d.id)
        return true
    end)
end

-- ---------------------------------------------------------------- people management for other resources (the MDT)
-- who = the caller's server id: they act as themselves under WHIP's rank rules, plus the MDT rule that a leader
-- only moves people below their own rank, to ranks below their own. Staff act without those limits.

local function levelIn(d, charId)
    local role = WC:GetPlayerRole({ charId = charId }, d.jobId)
    return role and role.level or nil, role
end

local function roleLevel(d, roleId)
    for _, r in ipairs(WC:GetJobRoles(d.jobId) or {}) do if r.roleId == roleId then return r.level end end
    return nil
end

local function belowMe(source, d, r, charId, roleId)
    if r.staff then return true end
    local mine = r.myLevel or 0
    if charId then
        local theirs = levelIn(d, charId)
        if theirs and theirs >= mine then return false, 'You can only manage people below your rank' end
    end
    if roleId then
        local lv = roleLevel(d, roleId)
        if not lv then return false, 'No such rank' end
        if lv >= mine then return false, 'You can only give ranks below your own' end
    end
    return true
end

exports('IsStaff', function(source) return isStaff(source) end)

--- Settings other resources show: FTO (ratings, checklist, ride-alongs), leave limits, inactivity lines
exports('GetConfig', function()
    return { fto = Config.FTO, loa = Config.LOA, health = { note = Config.Health.note, warn = Config.Health.warn, act = Config.Health.act } }
end)

exports('GetRights', function(source, ref)
    local d = resolve(ref)
    if not d then return false, 'No such department' end
    return rightsOf(source, d)
end)

exports('HireMember', function(source, ref, target, roleId)
    local d = resolve(ref)
    if not d then return false, 'No such department' end
    local r = rightsOf(source, d)
    if not r.hire then return false, 'Your rank cannot hire' end
    if not WC:GetCharId(target) then return false, 'Nobody with that server id is in the city' end
    local ok, why = belowMe(source, d, r, nil, roleId)
    if not ok then return false, why end
    if Pers and Pers.expect then Pers.expect(d.jobId, WC:GetCharId(target), WC:GetCharId(source), nil) end
    ok, why = WC:HirePlayer(target, d.jobId, roleId, byOpts(source, r))
    if not ok then return false, why end
    WC:NotifyPlayer(target, ('You joined %s'):format(d.name), 'success')
    log(source, 'hired', ('%s: server id %d (MDT)'):format(d.short, target))
    broadcast(d.id)
    return true
end)

exports('SetMemberRank', function(source, ref, charId, roleId, reason)
    local d = resolve(ref)
    if not d then return false, 'No such department' end
    local r = rightsOf(source, d)
    if not r.promote then return false, 'Your rank cannot promote or demote' end
    local job = WC:GetJob(d.jobId)
    if job and job.ownerCharId == charId then return false, 'The owner always holds the top rank' end
    local ok, why = belowMe(source, d, r, charId, roleId)
    if not ok then return false, why end
    if Pers and Pers.expect then Pers.expect(d.jobId, charId, WC:GetCharId(source), type(reason) == 'string' and reason ~= '' and reason:sub(1, 500) or nil) end
    ok, why = WC:SetPlayerRole({ charId = charId }, d.jobId, roleId, byOpts(source, r))
    if not ok then return false, why end
    log(source, 'set_rank', ('%s: char %d -> role %d (MDT)'):format(d.short, charId, roleId))
    broadcast(d.id)
    return true
end)

exports('FireMember', function(source, ref, charId, reason)
    local d = resolve(ref)
    if not d then return false, 'No such department' end
    local r = rightsOf(source, d)
    if not r.fire then return false, 'Your rank cannot remove people' end
    local job = WC:GetJob(d.jobId)
    if job and job.ownerCharId == charId then return false, 'The owner cannot be removed' end
    local ok, why = belowMe(source, d, r, charId, nil)
    if not ok then return false, why end
    if Pers and Pers.expect then Pers.expect(d.jobId, charId, WC:GetCharId(source), type(reason) == 'string' and reason ~= '' and reason:sub(1, 500) or nil) end
    ok, why = WC:FirePlayer({ charId = charId }, d.jobId, byOpts(source, r))
    if not ok then return false, why end
    MySQL.update.await('DELETE FROM `es_dept_members` WHERE `jobId`=? AND `charId`=?', { d.jobId, charId })
    if Members[d.jobId] then Members[d.jobId][charId] = nil end
    log(source, 'fired', ('%s: char %d (MDT)'):format(d.short, charId))
    broadcast(d.id)
    return true
end)

--- Callsign / badge / notes. Anyone may set their OWN callsign and badge only if Config.SelfCallsign; leaders (roster) anyone below them.
exports('SetMemberInfo', function(source, ref, charId, data)
    local d = resolve(ref)
    if not d then return false, 'No such department' end
    local r = rightsOf(source, d)
    if not r.roster then return false, 'Your rank cannot edit the roster' end
    local me = WC:GetCharId(source)
    if me ~= charId then
        local ok, why = belowMe(source, d, r, charId, nil)
        if not ok then return false, why end
    end
    if not levelIn(d, charId) then return false, 'They are not in this department' end
    data = type(data) == 'table' and data or {}
    local cur = (Members[d.jobId] or {})[charId] or {}
    local function pick(k, max) if data[k] == nil then return cur[k] end local v = trim(tostring(data[k])):sub(1, max) return v ~= '' and v or nil end
    local callsign, badge, notes = pick('callsign', 16), pick('badge', 12), pick('notes', 500)
    local ok = MySQL.update.await([[INSERT INTO `es_dept_members` (`jobId`,`charId`,`callsign`,`badge`,`notes`) VALUES (?,?,?,?,?)
        ON DUPLICATE KEY UPDATE `callsign`=VALUES(`callsign`),`badge`=VALUES(`badge`),`notes`=VALUES(`notes`)]],
        { d.jobId, charId, callsign or '', badge or '', notes or '' })
    if not ok then return false, 'Could not save that (database error)' end
    MySQL.update.await("UPDATE `es_dept_members` SET `callsign`=NULLIF(`callsign`,''),`badge`=NULLIF(`badge`,''),`notes`=NULLIF(`notes`,'') WHERE `jobId`=? AND `charId`=?", { d.jobId, charId })
    Members[d.jobId] = Members[d.jobId] or {}
    Members[d.jobId][charId] = { callsign = callsign, badge = badge, notes = notes }
    broadcast(d.id)
    return true
end)

-- A job deleted in /whip takes its department with it (the database cascades; the cache follows)
AddEventHandler('whip_core:job:deleted', function(e)
    if type(e) ~= 'table' then return end
    local d = byJob(e.jobId)
    if d then Depts[d.id], Logos[d.id] = nil, nil broadcast(d.id) end
end)
for _, ev in ipairs({ 'whip_core:job:hired', 'whip_core:job:fired', 'whip_core:job:roleChanged', 'whip_core:job:updated' }) do
    AddEventHandler(ev, function(e)
        if type(e) == 'table' and e.jobId and byJob(e.jobId) then broadcast(byJob(e.jobId).id) end
    end)
end

--- New department permissions handed once to existing ranks by level (Config.PermissionGrants); ranks keep the rest.
--- 1.8.0: Config.RankAdds, once each (a department that already has a rank by that name is left alone)
local function addRanks()
    for _, a in ipairs(Config.RankAdds or {}) do
        local kvp = 'es_departments:rankadd:' .. a.id
        if GetResourceKvpString(kvp) ~= '1' then
            local okAll = true
            for _, d in ipairs(sortedDepts()) do
                if d.type == a.type then
                    local have = false
                    for _, role in ipairs(WC:GetJobRoles(d.jobId) or {}) do if role.name:lower() == a.name:lower() then have = true end end
                    if not have then
                        local perms = defaultPerms(d.type, a.level)
                        for k, v in pairs(a.permissions or {}) do perms[k] = v end
                        local role, why = WC:CreateJobRole(d.jobId, { name = a.name, level = a.level, permissions = perms })
                        if role and role.roleId then
                            if a.abbr then saveRankExtra(role.roleId, d.jobId, { abbr = a.abbr }) end
                            print(('[es_departments] %s: rank "%s" added'):format(d.short, a.name))
                        else
                            okAll = false
                            print(('^3[es_departments] %s: adding rank "%s" failed: %s^7'):format(d.short, a.name, tostring(why)))
                        end
                    end
                end
            end
            if okAll then SetResourceKvp(kvp, '1') end
        end
    end
end

local function grantPermissions()
    for _, g in ipairs(Config.PermissionGrants or {}) do
        local kvp = 'es_departments:grant:' .. g.id
        if GetResourceKvpString(kvp) ~= '1' then
            for _, d in ipairs(sortedDepts()) do
                local known = permMap(d.type)
                for _, role in ipairs(WC:GetJobRoles(d.jobId) or {}) do
                    local perms, changed = {}, false
                    for k, v in pairs(role.permissions or {}) do perms[k] = v end
                    for perm, minLevel in pairs(g.perms) do
                        if known[perm] and (role.level or 0) >= minLevel and not perms[perm] then perms[perm] = true changed = true end
                    end
                    if changed then
                        local ok, why = WC:UpdateJobRole(d.jobId, role.roleId, { permissions = perms })
                        if not ok then print(('^3[es_departments] grant %s to %s/%s: %s^7'):format(g.id, d.short, role.name, tostring(why))) end
                    end
                end
            end
            SetResourceKvp(kvp, '1')
        end
    end
end

--- 1.9.0: Config.PermissionMirrors, once each: a rank holding the source permission gets the target one too
local function mirrorPermissions()
    for _, g in ipairs(Config.PermissionMirrors or {}) do
        local kvp = 'es_departments:mirror:' .. g.id
        if GetResourceKvpString(kvp) ~= '1' then
            local okAll = true
            for _, d in ipairs(sortedDepts()) do
                local known = permMap(d.type)
                for _, role in ipairs(WC:GetJobRoles(d.jobId) or {}) do
                    local perms, changed = {}, false
                    for k, v in pairs(role.permissions or {}) do perms[k] = v end
                    for target, src in pairs(g.perms) do
                        if known[target] and known[src] and perms[src] and not perms[target] then perms[target] = true changed = true end
                    end
                    if changed then
                        local ok, why = WC:UpdateJobRole(d.jobId, role.roleId, { permissions = perms })
                        if ok then print(('[es_departments] %s/%s: permissions %s copied'):format(d.short, role.name, g.id))
                        else okAll = false print(('^3[es_departments] mirror %s to %s/%s: %s^7'):format(g.id, d.short, role.name, tostring(why))) end
                    end
                end
            end
            if okAll then SetResourceKvp(kvp, '1') end
        end
    end
end

Whip.register(function()
    local ok, why = ensureTables()
    if not ok then Whip.startProblem('tables: %s', tostring(why)) return end
    if not load() then Whip.startProblem('could not read the departments (database error)') return end
    local dok, dwhy = Duty.tables()
    if not dok then Whip.startProblem('duty tables: %s', tostring(dwhy)) return end
    dok, dwhy = Fto.tables()
    if not dok then Whip.startProblem('fto tables: %s', tostring(dwhy)) return end
    dok, dwhy = Pers.tables()
    if not dok then Whip.startProblem('personnel tables: %s', tostring(dwhy)) return end
    seed()
    for _, d in ipairs(sortedDepts()) do
        local done, jwhy = declareJob(d)
        if not done then Whip.startProblem('%s: %s', d.short, tostring(jwhy)) end
    end
    Whip.core:RegisterPermission(Config.StaffPerm, { label = 'Departments: edit any department',
        description = 'Edit every department in /departments (creating and deleting stays with full admins).' })
    register()
    local c = { byJob = byJob, resolve = resolve, rosterOf = rosterOf, fillOnline = fillOnline, summary = summary,
        sortedDepts = sortedDepts, isStaff = isStaff, namesOf = namesOf }
    grantPermissions()
    local okM, mwhy = pcall(mirrorPermissions)
    if not okM then print('^3[es_departments] permission mirrors: ' .. tostring(mwhy) .. '^7') end
    local okR, rwhy = pcall(addRanks)
    if not okR then print('^3[es_departments] rank adds: ' .. tostring(rwhy) .. '^7') end
    Duty.start(c)
    Fto.start(c)
    Pers.start(c)
    ready = true
end)

Whip.sayStarted()
