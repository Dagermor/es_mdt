local _ENV = ESAPP('departments'); -- es_departments duty + health: on-duty time per department member, stats for the MDT, and the admin health view.
--   Duty time: a row in es_duty_sessions per stretch on duty (WHIP's job:clockedOn/Off, any route incl. logout).
--   A heartbeat keeps lastSeen fresh, so a crash loses at most Config.Health.heartbeatMinutes; a session left
--   open by a crash or stop is closed at its lastSeen on the next start.
--   Health: each department's heads (top rank, and the job owner) and how long since they were last on duty.
--   Over Config.Health.note / warn days, and at act days, an admin note goes on their account and online
--   staff get a toast. Main.lua calls Duty.start(ctx) once its own tables and caches are up.

Duty = {}
local WC = exports.whip_core
local ctx                    -- { Depts, byJob, resolve, rosterOf, fillOnline, summary, sortedDepts, isStaff, namesOf }
local open = {}              -- [jobId][charId] = sessionId
local up = false
local H = Config.Health

local function now() return os.time() end
local function daysSince(t) return t and math.floor((now() - t) / 86400) or nil end

--- 0 fine, 1 note (> note days), 2 warn (> warn days), 3 act (>= act days)
local function levelOf(days)
    if not days then return 0 end
    if days >= H.act then return 3 end
    if days > H.warn then return 2 end
    if days > H.note then return 1 end
    return 0
end
local LEVEL_NAME = { [0] = 'ok', 'note', 'warning', 'step in' }

local function trackingSince()
    local t = tonumber(GetResourceKvpString('es_departments:dutySince'))
    if not t then t = now() SetResourceKvp('es_departments:dutySince', tostring(t)) end
    return t
end

function Duty.tables()
    local ok, why = EsSchema.ensure('es_duty_sessions', [[CREATE TABLE IF NOT EXISTS `es_duty_sessions` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `charId` INT UNSIGNED NOT NULL,
        `jobId` INT UNSIGNED NOT NULL,
        `startedAt` DATETIME NOT NULL,
        `lastSeen` DATETIME NOT NULL,
        `endedAt` DATETIME NULL,
        `seconds` INT UNSIGNED NULL,
        PRIMARY KEY (`id`),
        KEY `idx_es_duty_job` (`jobId`, `startedAt`),
        KEY `idx_es_duty_char` (`charId`, `startedAt`),
        KEY `idx_es_duty_open` (`endedAt`),
        CONSTRAINT `fk_es_duty_job` FOREIGN KEY (`jobId`) REFERENCES `jobs` (`jobId`) ON DELETE CASCADE,
        CONSTRAINT `fk_es_duty_char` FOREIGN KEY (`charId`) REFERENCES `characters` (`charId`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]], {})
    if not ok then return false, why end
    ok, why = EsSchema.ensure('es_dept_health_flags', [[CREATE TABLE IF NOT EXISTS `es_dept_health_flags` (
        `jobId` INT UNSIGNED NOT NULL,
        `charId` INT UNSIGNED NOT NULL,
        `level` TINYINT UNSIGNED NOT NULL,
        `notedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`jobId`, `charId`),
        CONSTRAINT `fk_es_hflag_job` FOREIGN KEY (`jobId`) REFERENCES `jobs` (`jobId`) ON DELETE CASCADE,
        CONSTRAINT `fk_es_hflag_char` FOREIGN KEY (`charId`) REFERENCES `characters` (`charId`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]], {})
    if not ok then return false, why end
    ok, why = EsSchema.ensure('es_dept_loa', [[CREATE TABLE IF NOT EXISTS `es_dept_loa` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `deptId` INT UNSIGNED NOT NULL,
        `charId` INT UNSIGNED NOT NULL,
        `startsAt` DATETIME NOT NULL,
        `endsAt` DATETIME NOT NULL,
        `reason` VARCHAR(300) NULL,
        `status` ENUM('pending','approved','denied','ended','cancelled') NOT NULL DEFAULT 'pending',
        `decidedBy` INT UNSIGNED NULL,
        `decidedAt` DATETIME NULL,
        `decisionNote` VARCHAR(200) NULL,
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_es_loa_dept` (`deptId`, `status`, `endsAt`),
        KEY `idx_es_loa_char` (`charId`, `deptId`),
        CONSTRAINT `fk_es_loa_dept` FOREIGN KEY (`deptId`) REFERENCES `es_departments` (`id`) ON DELETE CASCADE,
        CONSTRAINT `fk_es_loa_char` FOREIGN KEY (`charId`) REFERENCES `characters` (`charId`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]], {})
    if not ok then return false, why end
    return true
end

-- ---------------------------------------------------------------- sessions

local function openSession(jobId, charId)
    open[jobId] = open[jobId] or {}
    if open[jobId][charId] then return end
    open[jobId][charId] = -1   -- claimed while the insert runs
    local id = MySQL.insert.await('INSERT INTO `es_duty_sessions` (`charId`,`jobId`,`startedAt`,`lastSeen`) VALUES (?,?,NOW(),NOW())',
        { charId, jobId })
    if id then open[jobId][charId] = id else open[jobId][charId] = nil end
    -- back on duty: any health flag on them is spent
    MySQL.update('DELETE FROM `es_dept_health_flags` WHERE `jobId` = ? AND `charId` = ?', { jobId, charId })
end

local function closeSession(jobId, charId, async)
    local id = open[jobId] and open[jobId][charId]
    if not id or id < 0 then return end
    open[jobId][charId] = nil
    local q = 'UPDATE `es_duty_sessions` SET `endedAt` = NOW(), `lastSeen` = NOW(), `seconds` = TIMESTAMPDIFF(SECOND, `startedAt`, NOW()) WHERE `id` = ?'
    if async then MySQL.update(q, { id }) else MySQL.update.await(q, { id }) end
end

AddEventHandler('whip_core:job:clockedOn', function(e)
    if not up or type(e) ~= 'table' or not e.jobId or not e.charId or not ctx.byJob(e.jobId) then return end
    openSession(e.jobId, e.charId)
end)
AddEventHandler('whip_core:job:clockedOff', function(e)
    if not up or type(e) ~= 'table' or not e.jobId or not e.charId then return end
    closeSession(e.jobId, e.charId)
end)
AddEventHandler('whip_core:job:fired', function(e)
    if up and type(e) == 'table' and e.jobId and e.charId then closeSession(e.jobId, e.charId) end
end)
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not up then return end
    for jobId, list in pairs(open) do for charId in pairs(list) do closeSession(jobId, charId, true) end end
end)

-- ---------------------------------------------------------------- reads

local function marks(n) local m = {} for i = 1, n do m[i] = '?' end return table.concat(m, ',') end

--- { [charId] = seconds } on duty at this job in the last `days` days (open stretches count up to now)
local function dutyByChar(jobId, days)
    local out = {}
    local rows = MySQL.query.await([[SELECT `charId`, SUM(GREATEST(0, TIMESTAMPDIFF(SECOND, GREATEST(`startedAt`, NOW() - INTERVAL ? DAY),
        COALESCE(`endedAt`, NOW())))) AS `s` FROM `es_duty_sessions` WHERE `jobId` = ? AND COALESCE(`endedAt`, NOW()) > NOW() - INTERVAL ? DAY
        GROUP BY `charId`]], { days, jobId, days }) or {}
    for _, r in ipairs(rows) do out[r.charId] = tonumber(r.s) or 0 end
    return out
end

--- { [charId] = unix time last on duty at this job }
local function lastDutyByChar(jobId)
    local out = {}
    local rows = MySQL.query.await([[SELECT `charId`, UNIX_TIMESTAMP(MAX(COALESCE(`endedAt`, `lastSeen`))) AS `t`
        FROM `es_duty_sessions` WHERE `jobId` = ? GROUP BY `charId`]], { jobId }) or {}
    for _, r in ipairs(rows) do out[r.charId] = tonumber(r.t) end
    return out
end

local function lastPlayedOf(charIds)
    local out = {}
    if #charIds == 0 then return out end
    local rows = MySQL.query.await(('SELECT `charId`, UNIX_TIMESTAMP(`lastPlayed`) AS `t` FROM `characters` WHERE `charId` IN (%s)')
        :format(marks(#charIds)), charIds) or {}
    for _, r in ipairs(rows) do out[r.charId] = tonumber(r.t) end
    return out
end

local function arrestsOf(jobId, charIds, days)
    if GetResourceState('es_mdt') ~= 'started' then return nil end
    local ok, res = pcall(function() return exports.es_mdt:GetArrestCounts(charIds, { days = days, jobId = jobId }) end)
    return ok and type(res) == 'table' and res or nil
end

--- { [charId] = { active = loa|nil, lastEnd = unix|nil, pending = n } } for a department
local function loaByChar(deptId)
    local out = {}
    local rows = MySQL.query.await([[SELECT `id`,`charId`,`status`,UNIX_TIMESTAMP(`startsAt`) AS `s`,UNIX_TIMESTAMP(`endsAt`) AS `e`,`reason`
        FROM `es_dept_loa` WHERE `deptId` = ? AND (`status` = 'pending' OR (`status` IN ('approved','ended') AND `startsAt` <= NOW()))]],
        { deptId }) or {}
    local t = now()
    for _, r in ipairs(rows) do
        local x = out[r.charId] or { pending = 0 }
        out[r.charId] = x
        local s, e = tonumber(r.s), tonumber(r.e)
        if r.status == 'pending' then
            x.pending = x.pending + 1
        elseif r.status == 'approved' and s <= t and e > t then
            x.active = { id = r.id, startsAt = s, endsAt = e, reason = r.reason }
        else
            local fin = math.min(e, t)
            if not x.lastEnd or fin > x.lastEnd then x.lastEnd = fin end
        end
    end
    return out
end
Duty.loaByChar = loaByChar

local function topLevel(d)
    if (tonumber(H.headLevel) or 0) > 0 then return tonumber(H.headLevel) end   -- 2.0.10: 0 (or nil) = the top rank
    local top = 0
    for _, role in ipairs(WC:GetJobRoles(d.jobId) or {}) do if (role.level or 0) > top then top = role.level end end
    return top
end

--- Every member of a department with duty time in the window, last on duty, last in the city and how inactive.
local function membersOf(d, days)
    local roster = ctx.fillOnline(ctx.rosterOf(d))
    local ids = {}
    for _, m in ipairs(roster) do ids[#ids + 1] = m.charId end
    local secs, last, played, loa = dutyByChar(d.jobId, days), lastDutyByChar(d.jobId), lastPlayedOf(ids), loaByChar(d.id)
    local arrests = arrestsOf(d.jobId, ids, days)
    local since, t, head = trackingSince(), now(), topLevel(d)
    for _, m in ipairs(roster) do
        m.dutySeconds = secs[m.charId] or 0
        m.lastDuty = m.onDuty and t or last[m.charId]
        m.lastPlayed = m.online and t or played[m.charId]
        -- never seen on duty since tracking began: count from then, not from the dawn of time.
        -- Leave: while an approved leave runs the clock is paused; afterwards it counts from the leave's end.
        local l = loa[m.charId] or {}
        local base = m.lastDuty or since
        if l.lastEnd and l.lastEnd > base then base = l.lastEnd end
        m.loa = l.active
        m.loaPending = l.pending or 0
        m.inactiveSince = base
        if l.active and not m.onDuty then
            m.inactiveDays, m.level = 0, 0
        else
            m.inactiveDays = daysSince(base)
            m.level = levelOf(m.inactiveDays)
        end
        m.neverTracked = m.lastDuty == nil
        m.head = m.owner == true or (m.roleLevel or 0) >= head
        m.arrests = arrests and (arrests[m.charId] or 0) or nil
        m.source = nil
    end
    return roster
end

Duty.membersOf = membersOf   -- 1.5.0: personnel files (status, inactivity warnings)

-- ---------------------------------------------------------------- exports

--- Seconds on duty. opts: { days = 30 (nil = all time), dept = ref (nil = every department) }
exports('GetDutySeconds', function(charId, opts)
    charId = tonumber(charId)
    if not charId then return 0 end
    opts = type(opts) == 'table' and opts or {}
    local days = tonumber(opts.days) or 36500
    local jobId
    if opts.dept ~= nil then local d = ctx.resolve(opts.dept) if not d then return 0 end jobId = d.jobId end
    local row = MySQL.single.await(([[SELECT SUM(GREATEST(0, TIMESTAMPDIFF(SECOND, GREATEST(`startedAt`, NOW() - INTERVAL ? DAY),
        COALESCE(`endedAt`, NOW())))) AS `s` FROM `es_duty_sessions` WHERE `charId` = ? AND COALESCE(`endedAt`, NOW()) > NOW() - INTERVAL ? DAY%s]])
        :format(jobId and ' AND `jobId` = ?' or ''), jobId and { days, charId, days, jobId } or { days, charId, days })
    return row and tonumber(row.s) or 0
end)

--- A department's stats for the MDT. opts: { days = 30, top = 5 }
--- { days, trackingSince, arrestsTracked, members = [...], top = { duty = [...], arrests = [...]|nil },
---   totals = { members, onDuty, active, dutySeconds, note, warning, act } }
exports('GetStats', function(ref, opts)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    opts = type(opts) == 'table' and opts or {}
    local days = math.max(1, math.min(365, tonumber(opts.days) or 30))
    local topN = math.max(1, math.min(25, tonumber(opts.top) or 5))
    local members = membersOf(d, days)
    local totals = { members = #members, onDuty = 0, active = 0, dutySeconds = 0, note = 0, warning = 0, act = 0 }
    for _, m in ipairs(members) do
        if m.onDuty then totals.onDuty = totals.onDuty + 1 end
        if m.dutySeconds > 0 then totals.active = totals.active + 1 end
        totals.dutySeconds = totals.dutySeconds + m.dutySeconds
        if m.level == 1 then totals.note = totals.note + 1 elseif m.level == 2 then totals.warning = totals.warning + 1
        elseif m.level == 3 then totals.act = totals.act + 1 end
    end
    local function top(field)
        local list = {}
        for _, m in ipairs(members) do if (m[field] or 0) > 0 then list[#list + 1] = m end end
        table.sort(list, function(a, b) return a[field] > b[field] end)
        local out = {}
        for i = 1, math.min(topN, #list) do
            local m = list[i]
            out[i] = { charId = m.charId, name = m.name, callsign = m.callsign, roleName = m.roleName, value = m[field] }
        end
        return out
    end
    local arrestsTracked = GetResourceState('es_mdt') == 'started'
    return { days = days, trackingSince = trackingSince(), arrestsTracked = arrestsTracked, members = members,
        top = { duty = top('dutySeconds'), arrests = arrestsTracked and top('arrests') or nil }, totals = totals,
        thresholds = { note = H.note, warn = H.warn, act = H.act } }
end)


-- ---------------------------------------------------------------- leave of absence (the MDT's calls; who = caller's server id)

local function mayLead(who, d)
    if type(who) == 'number' and ctx.isStaff(who) then return true end
    return WC:HasJobPermission(who, d.jobId, 'loa_manage', { onDuty = false }) == true
end

local function charOf(who) return type(who) == 'table' and who.charId or WC:GetCharId(who) end

--- 'YYYY-MM-DD' -> unix midnight (server clock), or nil
local function parseDate(s)
    if type(s) ~= 'string' then return nil end
    local y, m, dd = s:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    if not y then return nil end
    return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(dd), hour = 0 })
end

local function notifyChar(charId, text, kind)
    for src, p in pairs(WC:GetPlayers({ light = true }) or {}) do
        if p.charId == charId then WC:NotifyPlayer(tonumber(src), text, kind or 'info', 8000) return end
    end
end

--- File a leave for yourself: dates 'YYYY-MM-DD' (start may be today), inclusive. Leaders' own leave still needs
--- another leader (or staff) to approve.
exports('FileLOA', function(who, ref, startDate, endDate, reason)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    local me = charOf(who)
    if not me or not WC:GetPlayerRole({ charId = me }, d.jobId) then return false, 'You are not in this department' end
    local s, e = parseDate(startDate), parseDate(endDate)
    if not s or not e then return false, 'Pick a start and an end date' end
    local today = os.time({ year = tonumber(os.date('%Y')), month = tonumber(os.date('%m')), day = tonumber(os.date('%d')), hour = 0 })
    if s < today then return false, 'A leave cannot start in the past' end
    if e < s then return false, 'The end date is before the start date' end
    if (e - s) / 86400 + 1 > Config.LOA.maxDays then return false, ('A leave can be %d days at most'):format(Config.LOA.maxDays) end
    if (s - today) / 86400 > Config.LOA.maxAheadDays then return false, ('A leave can start up to %d days ahead'):format(Config.LOA.maxAheadDays) end
    local clash = MySQL.single.await([[SELECT `id` FROM `es_dept_loa` WHERE `deptId` = ? AND `charId` = ? AND `status` IN ('pending','approved')
        AND `startsAt` <= FROM_UNIXTIME(?) AND `endsAt` >= FROM_UNIXTIME(?)]], { d.id, me, e + 86399, s })
    if clash then return false, 'You already have a leave for some of those days' end
    local id = MySQL.insert.await([[INSERT INTO `es_dept_loa` (`deptId`,`charId`,`startsAt`,`endsAt`,`reason`) VALUES (?,?,FROM_UNIXTIME(?),FROM_UNIXTIME(?),?)]],
        { d.id, me, s, e + 86399, tostring(reason or ''):sub(1, Config.LOA.reasonMax) })
    if not id then return false, 'Could not save that (database error)' end
    return id
end)

--- 'approve' / 'deny' (leaders, pending only), 'end' (leaders, or the officer: ends a running leave now),
--- 'cancel' (the officer, before it starts or while pending).
exports('DecideLOA', function(who, loaId, action, note)
    local l = MySQL.single.await('SELECT `id`,`deptId`,`charId`,`status`,UNIX_TIMESTAMP(`startsAt`) AS `s`,UNIX_TIMESTAMP(`endsAt`) AS `e` FROM `es_dept_loa` WHERE `id` = ?',
        { tonumber(loaId) or 0 })
    if not l then return false, 'No such leave' end
    local d = ctx.resolve(l.deptId)
    if not d then return false, 'No such department' end
    local me, lead = charOf(who), mayLead(who, d)
    local t = os.time()
    note = tostring(note or ''):sub(1, 200)
    if action == 'approve' or action == 'deny' then
        if not lead then return false, 'Only leaders can approve leave' end
        if me == l.charId and not (type(who) == 'number' and ctx.isStaff(who)) then return false, 'Another leader has to decide your own leave' end
        if l.status ~= 'pending' then return false, 'That leave was already decided' end
        local st = action == 'approve' and 'approved' or 'denied'
        MySQL.update.await('UPDATE `es_dept_loa` SET `status` = ?, `decidedBy` = NULLIF(?, 0), `decidedAt` = NOW(), `decisionNote` = ? WHERE `id` = ?', { st, me or 0, note, l.id })
        notifyChar(l.charId, ('%s: your leave was %s'):format(d.short, st), st == 'approved' and 'success' or 'error')
        return true
    elseif action == 'end' then
        if not (lead or me == l.charId) then return false, 'Only leaders or the officer can end a leave' end
        if l.status ~= 'approved' then return false, 'That leave is not approved' end
        if tonumber(l.s) > t then
            MySQL.update.await("UPDATE `es_dept_loa` SET `status` = 'cancelled', `decidedBy` = NULLIF(?, 0), `decidedAt` = NOW() WHERE `id` = ?", { me or 0, l.id })
        else
            -- the inactivity clock restarts from now
            MySQL.update.await("UPDATE `es_dept_loa` SET `status` = 'ended', `endsAt` = LEAST(`endsAt`, NOW()), `decidedBy` = NULLIF(?, 0), `decidedAt` = NOW() WHERE `id` = ?", { me or 0, l.id })
        end
        if me ~= l.charId then notifyChar(l.charId, ('%s: your leave was ended'):format(d.short), 'warning') end
        return true
    elseif action == 'cancel' then
        if me ~= l.charId and not lead then return false, 'Only the officer can cancel their leave' end
        if l.status == 'pending' or (l.status == 'approved' and tonumber(l.s) > t) then
            MySQL.update.await("UPDATE `es_dept_loa` SET `status` = 'cancelled' WHERE `id` = ?", { l.id })
            return true
        end
        return false, 'That leave has already started: end it instead'
    end
    return false, 'approve, deny, end or cancel'
end)

--- Leaves at a department. opts: { status = 'pending'|'active'|'all' (default all recent), charId? }
exports('GetLOAs', function(ref, opts)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    opts = type(opts) == 'table' and opts or {}
    local where, args = { '`deptId` = ?' }, { d.id }
    if opts.charId then where[#where + 1] = '`charId` = ?' args[#args + 1] = tonumber(opts.charId) or 0 end
    if opts.status == 'pending' then where[#where + 1] = "`status` = 'pending'"
    elseif opts.status == 'active' then where[#where + 1] = "`status` = 'approved' AND `startsAt` <= NOW() AND `endsAt` > NOW()"
    else where[#where + 1] = '`createdAt` > NOW() - INTERVAL 180 DAY' end
    local rows = MySQL.query.await(([[SELECT `id`,`charId`,UNIX_TIMESTAMP(`startsAt`) AS `startsAt`,UNIX_TIMESTAMP(`endsAt`) AS `endsAt`,`reason`,`status`,
        `decidedBy`,UNIX_TIMESTAMP(`decidedAt`) AS `decidedAt`,`decisionNote`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt`
        FROM `es_dept_loa` WHERE %s ORDER BY `startsAt` DESC LIMIT 200]]):format(table.concat(where, ' AND ')), args) or {}
    local ids = {}
    for _, r in ipairs(rows) do ids[#ids + 1] = r.charId if r.decidedBy then ids[#ids + 1] = r.decidedBy end end
    local names = ctx.namesOf(ids)
    for _, r in ipairs(rows) do r.name, r.decidedByName = names[r.charId], r.decidedBy and names[r.decidedBy] or nil end
    return rows
end)

--- Every member's activity for leaders (MDT): inactivity level (0-3), days, on leave, pending leave.
--- opts: { flaggedOnly = true } for just the ones over the note line.
exports('GetActivity', function(ref, opts)
    local d = ctx.resolve(ref)
    if not d then return false, 'No such department' end
    local list = membersOf(d, 30)
    -- 1.4.0: trainees with no DOR for longer than the training program allows are flagged here too
    local tf = {}
    if Fto and Fto.trainingFlags then
        local ok, res = pcall(Fto.trainingFlags, d)
        if ok and type(res) == 'table' then tf = res end
    end
    for _, m in ipairs(list) do m.training = tf[m.charId] end
    if type(opts) == 'table' and opts.flaggedOnly then
        local out = {}
        for _, m in ipairs(list) do if m.level > 0 or (m.training and m.training.overdue) then out[#out + 1] = m end end
        list = out
    end
    table.sort(list, function(a, b) return (a.inactiveDays or 0) > (b.inactiveDays or 0) end)
    return { members = list, thresholds = { note = H.note, warn = H.warn, act = H.act }, trackingSince = trackingSince() }
end)

-- ---------------------------------------------------------------- health

--- Every department, its heads and how active its people are. For the admin Health view.
function Duty.health()
    local out, t = {}, now()
    for _, d in ipairs(ctx.sortedDepts()) do
        local members = membersOf(d, 7)
        local s = ctx.summary(d)
        s.heads, s.worst = {}, 0
        s.counts = { members = #members, onDuty = 0, active7 = 0, inactive = 0, hours7 = 0, act = 0, loa = 0, loaPending = 0 }
        for _, m in ipairs(members) do
            if m.onDuty then s.counts.onDuty = s.counts.onDuty + 1 end
            if m.dutySeconds > 0 then s.counts.active7 = s.counts.active7 + 1 end
            if m.level > 0 then s.counts.inactive = s.counts.inactive + 1 end
            if m.level == 3 then s.counts.act = (s.counts.act or 0) + 1 end
            if m.loa then s.counts.loa = (s.counts.loa or 0) + 1 end
            if (m.loaPending or 0) > 0 then s.counts.loaPending = (s.counts.loaPending or 0) + m.loaPending end
            s.counts.hours7 = s.counts.hours7 + m.dutySeconds
            if m.head then
                s.heads[#s.heads + 1] = { charId = m.charId, name = m.name, roleName = m.roleName, callsign = m.callsign,
                    owner = m.owner, onDuty = m.onDuty, online = m.online, lastDuty = m.lastDuty, lastPlayed = m.lastPlayed,
                    days = m.inactiveDays, level = m.level, neverTracked = m.neverTracked, loa = m.loa,
                    playedDays = daysSince(m.lastPlayed) }
                if m.level > s.worst then s.worst = m.level end
            end
        end
        s.counts.hours7 = math.floor(s.counts.hours7 / 360 + 0.5) / 10
        table.sort(s.heads, function(a, b) return (a.level or 0) > (b.level or 0) end)
        out[#out + 1] = s
    end
    return { departments = out, now = t, trackingSince = trackingSince(),
        thresholds = { note = H.note, warn = H.warn, act = H.act } }
end

local function staffOnline()
    local list = {}
    for key in pairs(WC:GetPlayers({ light = true }) or {}) do
        local src = tonumber(key)
        if src and ctx.isStaff(src) then list[#list + 1] = src end
    end
    return list
end

--- Heads who need attention: { { dept, head } ... }, worst first
local function flagged()
    local list = {}
    for _, d in ipairs(Duty.health().departments) do
        for _, h in ipairs(d.heads) do if h.level > 0 then list[#list + 1] = { dept = d, head = h } end end
    end
    table.sort(list, function(a, b) return a.head.level > b.head.level end)
    return list
end

local function sayOf(f)
    local h = f.head
    return ('%s %s (%s) has not been on duty for %d days'):format(f.dept.short, h.roleName or 'head', h.name, h.days or 0)
end

--- Check every head; a head who reached a higher level than last noted gets an admin note and staff hear of it.
function Duty.check()
    if not up then return end
    local seen = {}
    for _, r in ipairs(MySQL.query.await('SELECT `jobId`,`charId`,`level` FROM `es_dept_health_flags`') or {}) do
        seen[r.jobId .. ':' .. r.charId] = r.level
    end
    local fresh = {}
    for _, f in ipairs(flagged()) do
        local k = f.dept.jobId .. ':' .. f.head.charId
        if f.head.level > (seen[k] or 0) then
            fresh[#fresh + 1] = f
            MySQL.update.await([[INSERT INTO `es_dept_health_flags` (`jobId`,`charId`,`level`) VALUES (?,?,?)
                ON DUPLICATE KEY UPDATE `level` = VALUES(`level`), `notedAt` = CURRENT_TIMESTAMP]], { f.dept.jobId, f.head.charId, f.head.level })
            if H.adminNotes then
                local c = MySQL.single.await('SELECT `userId` FROM `characters` WHERE `charId` = ?', { f.head.charId })
                if c and c.userId then
                    MySQL.insert.await('INSERT INTO `admin_notes` (`userId`,`note`,`createdBy`,`createdByName`) VALUES (?,?,?,?)',
                        { c.userId, ('[Departments] %s: %s. Level: %s.'):format(sayOf(f), f.head.level == 3 and 'An admin should step in' or 'Keep an eye on it', LEVEL_NAME[f.head.level]),
                          0, 'Departments' })
                end
            end
        end
    end
    if #fresh > 0 then
        for _, src in ipairs(staffOnline()) do
            for i = 1, math.min(3, #fresh) do
                local f = fresh[i]
                WC:NotifyPlayer(src, 'Departments: ' .. sayOf(f) .. (f.head.level == 3 and '. An admin should step in.' or '.'),
                    f.head.level >= 2 and 'error' or 'warning', 12000)
            end
            if #fresh > 3 then WC:NotifyPlayer(src, ('Departments: %d more heads need a look in /departments → Health'):format(#fresh - 3), 'warning', 12000) end
        end
    end
end

-- Staff joining hear of anything flagged, in one line
AddEventHandler('whip_core:player:loaded', function(e)
    if not up or type(e) ~= 'table' or not e.source or e.phantom then return end
    local src = e.source
    SetTimeout(20000, function()
        if not GetPlayerName(src) or not ctx.isStaff(src) then return end
        local list = flagged()
        if #list == 0 then return end
        local worst = list[1].head.level
        WC:NotifyPlayer(src, ('Departments: %d head%s not on duty lately (worst: %s). Open /departments → Health.')
            :format(#list, #list == 1 and '' or 's', sayOf(list[1])), worst >= 2 and 'error' or 'warning', 15000)
    end)
end)

function Duty.start(c)
    ctx = c
    trackingSince()
    -- sessions a crash or stop left open end where they were last seen
    MySQL.update.await('UPDATE `es_duty_sessions` SET `endedAt` = `lastSeen`, `seconds` = TIMESTAMPDIFF(SECOND, `startedAt`, `lastSeen`) WHERE `endedAt` IS NULL')
    open = {}
    up = true
    for _, d in ipairs(ctx.sortedDepts()) do
        for _, e in ipairs(WC:GetClockedOnEmployees(d.jobId) or {}) do openSession(d.jobId, e.charId) end
    end
    CreateThread(function()
        while true do
            Wait(H.heartbeatMinutes * 60000)
            MySQL.update.await('UPDATE `es_duty_sessions` SET `lastSeen` = NOW() WHERE `endedAt` IS NULL')
        end
    end)
    CreateThread(function()
        Wait(60000)
        while true do
            local ok, err = pcall(Duty.check)
            if not ok then print(('^3[es_departments] health check failed: %s^7'):format(tostring(err))) end
            Wait(H.checkMinutes * 60000)
        end
    end)
end
