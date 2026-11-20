local _ENV = ESAPP('mdt'); -- es_mdt 2.5.0: the EMS side of the MDT, for the members of an EMS department.
--   Dashboard: the active medical calls (P1 first), who is on each, one-tap attach & route, the crew on duty, the calls
--     you still owe a report for. Patients: blood type, a short note, recent treatments and open bills (from whip_jobs),
--     incident reports, custody (es_jail), a death record. Incident reports: what happened, what was done, a line, on
--     the call and the patient. Bills (whip_jobs): what is owed; supervisors waive. Deaths: a character's death, with a
--     post-mortem report (whip_evidence, uploaded to an MDT case) linked when there is one. Stats: calls, treatments,
--     revives, reports per member.
--   Police see only a short line: "deceased" and "treated by EMS" on a person, "EMS: treated, transported" on a call.
--   EMS sees custody, not police records. Kept simple on purpose (RP): no vitals, codes, prescriptions or insurance.

MDT = MDT or {}
local WC = exports.whip_core
local ED = exports.es_departments
local function E() return Config.EMS or {} end

-- ---------------------------------------------------------------- helpers
--- one whip_jobs (or es_jobs) export, never throws; nil when the job pack (or that export) is not there
local function J(fn, ...)
    local res = EsSuite.jobsRes(true)
    if not res then return nil end
    local args = table.pack(...)
    local ok, a, b = pcall(function() return exports[res][fn](exports[res], table.unpack(args, 1, args.n)) end)
    if not ok then return nil end
    return a, b
end
local function medOn() return J('GetMedicalStats', 1, { 0 }) ~= nil end

local function actionMap()
    local m = {}
    for _, a in ipairs(E().actions or {}) do if type(a) == 'table' and type(a.key) == 'string' then m[a.key] = a.label or a.key end end
    return m
end
local function actionsText(s)
    local m, out = actionMap(), {}
    for k in tostring(s or ''):gmatch('[^,]+') do out[#out + 1] = m[k] or k end
    return table.concat(out, ', ')
end

local function bloodList()
    local out = {}
    for _, b in ipairs(E().bloodTypes or {}) do if type(b) == 'table' and type(b[1]) == 'string' then out[#out + 1] = b[1] end end
    return out
end
--- a person's blood type until a medic sets one: from their ID, weighted (the same every time)
local function defaultBlood(cid)
    local list, total = E().bloodTypes or {}, 0
    for _, b in ipairs(list) do total = total + (tonumber(b[2]) or 0) end
    if total <= 0 or not cid then return nil end
    local x = ((math.floor(cid) * 2654435761) % 4294967296) % total
    for _, b in ipairs(list) do
        x = x - (tonumber(b[2]) or 0)
        if x < 0 then return b[1] end
    end
    return nil
end

local function emsDepts()
    local out = {}
    for _, d in ipairs(ED:GetDepartments() or {}) do if d.type == 'ems' then out[#out + 1] = d end end
    return out
end
local function emsJobIds()
    local out = {}
    for _, d in ipairs(emsDepts()) do if d.jobId then out[#out + 1] = d.jobId end end
    return out
end

local function personRow(cid)
    return MySQL.single.await([[SELECT c.`charId`, c.`firstName`, c.`lastName`, DATE_FORMAT(c.`dateOfBirth`,'%Y-%m-%d') AS `dob`, c.`gender`,
        (SELECT p.`phoneNumber` FROM `phone_numbers` p WHERE p.`charId` = c.`charId` AND p.`retiredAt` IS NULL LIMIT 1) AS `phone`
        FROM `characters` c WHERE c.`charId` = ? AND c.`deleted` IS NULL]], { cid })
end

local DEATH_COLS = [[`id`,`charId`,`name`,`deptId`,`cause`,`place`,UNIX_TIMESTAMP(`diedAt`) AS `diedAt`,`caseId`,`autopsyRef`,`byCharId`,`byName`,
    UNIX_TIMESTAMP(`createdAt`) AS `createdAt`,UNIX_TIMESTAMP(`revokedAt`) AS `revokedAt`,`revokedBy`,`revokeNote`]]
local function deathOf(cid)
    return MySQL.single.await(('SELECT %s FROM `es_mdt_deaths` WHERE `charId` = ? AND `revokedAt` IS NULL ORDER BY `id` DESC LIMIT 1'):format(DEATH_COLS), { cid })
end
local function caseNumberOf(caseId)
    if not caseId then return nil end
    local k = MySQL.single.await('SELECT `number` FROM `es_mdt_cases` WHERE `id` = ?', { caseId })
    return k and k.number or nil
end
--- the post-mortem report's short view (whip_evidence entry kept in the MDT case), or nil
local function autopsyOf(caseId, ref)
    if not caseId or not ref then return nil end
    local r = MySQL.single.await("SELECT `data` FROM `es_mdt_wev_entries` WHERE `caseId` = ? AND `ref` = ? AND `kind` = 'autopsy'", { caseId, ref })
    if not r or type(r.data) ~= 'string' or not MDT.wevView then return nil end
    local ok, e = pcall(json.decode, r.data)
    if not ok or type(e) ~= 'table' then return nil end
    local v = MDT.wevView(e, ref)
    local rep = v and v.report
    if not rep then return nil end
    return { ref = ref, caseId = caseId, title = rep.title, text = rep.text and rep.text:sub(1, 400) or nil, examinedAt = rep.examinedAt,
        examinedBy = rep.examinedBy, street = rep.street, fatal = rep.fatal, wounds = rep.wounds, diedAt = rep.diedAt, impact = rep.impact }
end

--- es_jail: in jail / cuffed right now (EMS sees custody, nothing else of police records)
local function custodyOf(cid, online)
    local out = { state = 'free' }
    if GetResourceState('es_jail') ~= 'started' then out.state = 'unknown' return out end
    local ok, jailed, rem = pcall(function() return exports.es_jail:IsJailed(cid) end)
    if ok and jailed then out.jailed = true out.months = tonumber(rem) end
    local src = (online or MDT.onlineByChar())[cid]
    out.online = src ~= nil
    if src then
        local okc, mode = pcall(function() return exports.es_jail:IsCuffed(src) end)
        if okc and mode then out.cuffed = tostring(mode) end
    end
    out.state = out.jailed and 'jailed' or out.cuffed and 'cuffed' or 'free'
    return out
end

local REP_COLS = [[`id`,`deptId`,`callId`,`charId`,`patientName`,`what`,`actions`,`note`,`street`,`byCharId`,`byName`,
    UNIX_TIMESTAMP(`createdAt`) AS `createdAt`,UNIX_TIMESTAMP(`updatedAt`) AS `updatedAt`]]
local function shapeReport(r, depts)
    depts = depts or MDT.deptShort()
    local d = depts[r.deptId]
    r.deptShort = d and d.short or nil
    r.actionsList = {}
    for k in tostring(r.actions or ''):gmatch('[^,]+') do r.actionsList[#r.actionsList + 1] = k end
    r.actionsText = actionsText(r.actions)
    return r
end

-- ---------------------------------------------------------------- for the police side (short lines only)
--- a person: { deceased = {...}, treated = {...} } or nil
function MDT.emsForPolice(cid)
    if (E().enabled == false) then return nil end
    local out = {}
    local dth = deathOf(cid)
    if dth then
        local depts = MDT.deptShort()
        out.deceased = { cause = dth.cause, at = dth.diedAt or dth.createdAt, place = dth.place, by = dth.byName,
            dept = dth.deptId and depts[dth.deptId] and depts[dth.deptId].short or nil, caseId = dth.caseId, caseNumber = caseNumberOf(dth.caseId) }
    end
    local days = math.max(1, math.floor(tonumber(E().policeDays) or 7))
    local t = J('LastTreatment', cid, days)
    local rep = MySQL.single.await([[SELECT `actions`,`deptId`,UNIX_TIMESTAMP(`createdAt`) AS `at` FROM `es_mdt_ems_reports` WHERE `charId` = ?
        AND `createdAt` > NOW() - INTERVAL ? DAY ORDER BY `id` DESC LIMIT 1]], { cid, days })
    if type(t) == 'table' and t.at and (not rep or t.at >= (rep.at or 0)) then
        out.treated = { at = t.at, what = t.kindLabel or t.kind, dept = t.dept }
    elseif rep then
        local d = MDT.deptShort()[rep.deptId]
        out.treated = { at = rep.at, what = actionsText(rep.actions) ~= '' and actionsText(rep.actions) or 'Seen by EMS', dept = d and d.short or nil }
    end
    if not out.deceased and not out.treated then return nil end
    return out
end

--- a call: what EMS did on it (law: one line; EMS: also their own report and whether they may write one)
function MDT.emsForCall(callId, c)
    if (E().enabled == false) then return nil end
    local rows = MySQL.query.await('SELECT `id`,`actions`,`deptId`,`byCharId`,`byName`,UNIX_TIMESTAMP(`createdAt`) AS `at` FROM `es_mdt_ems_reports` WHERE `callId` = ? ORDER BY `id`', { callId }) or {}
    local isEms = c and c.dept and c.dept.type == 'ems'
    if #rows == 0 and not isEms then return nil end
    local seen, acts = {}, {}
    local m = actionMap()
    local depts = MDT.deptShort()
    local deptNames = {}
    for _, r in ipairs(rows) do
        for k in tostring(r.actions or ''):gmatch('[^,]+') do if not seen[k] then seen[k] = true acts[#acts + 1] = m[k] or k end end
        local d = depts[r.deptId]
        if d and not deptNames[d.short] then deptNames[d.short] = true end
    end
    local ds = {}
    for k in pairs(deptNames) do ds[#ds + 1] = k end
    local out = { reports = #rows, line = #rows > 0 and (#acts > 0 and table.concat(acts, ', ') or 'Report filed') or nil, depts = ds,
        at = rows[#rows] and rows[#rows].at or nil }
    if isEms then
        for _, r in ipairs(rows) do if r.byCharId == c.charId then out.mine = r.id end end
        local on = MySQL.single.await('SELECT 1 AS `x` FROM `es_mdt_call_units` WHERE `callId` = ? AND `charId` = ?', { callId, c.charId })
        out.canReport = (on ~= nil or c.staff) and (c.perms.ems_reports or c.staff) and not c.readOnly or false
    end
    return out
end

function MDT.emsPageConfig()
    return { actions = E().actions or {}, bloodTypes = bloodList(), reportHours = E().reportHours or 6, med = medOn(),
        jail = GetResourceState('es_jail') == 'started' }
end

-- ---------------------------------------------------------------- the page's calls
function MDT.registerEms()
    if E().enabled == false then return end
    local cb, str, id, int, log = MDT.cb, MDT.str, MDT.id, MDT.int, MDT.log

    local function needReport(c)
        return MySQL.query.await([[SELECT c.`id`, c.`title`, c.`street`, c.`status`, c.`priority`, UNIX_TIMESTAMP(c.`createdAt`) AS `createdAt`,
            UNIX_TIMESTAMP(c.`closedAt`) AS `closedAt` FROM `es_mdt_call_units` u JOIN `es_mdt_calls` c ON c.`id` = u.`callId`
            WHERE u.`charId` = ? AND c.`createdAt` > NOW() - INTERVAL ? HOUR
            AND NOT EXISTS (SELECT 1 FROM `es_mdt_ems_reports` r WHERE r.`callId` = c.`id` AND r.`byCharId` = ?)
            ORDER BY c.`id` DESC LIMIT 10]], { c.charId, math.max(1, math.floor(tonumber(E().reportHours) or 6)), c.charId }) or {}
    end

    -- 1) dashboard
    cb('emsHome', { ems = true, rate = 600, burst = 6 }, function(c)
        local calls = MDT.callsList('active', 40, c)
        local onCall = {}
        for _, r in ipairs(calls) do
            r.callerPhone, r.closeNote = nil, nil
            r.mine = false
            for _, u in ipairs(r.units) do
                if u.charId == c.charId then r.mine = true end
                onCall[u.charId] = onCall[u.charId] or r.id
            end
        end
        local groups = MDT.dutyNow()
        local crew = {}
        for _, g in ipairs(groups) do
            if g.type == 'ems' then
                for _, u in ipairs(g.units) do
                    crew[#crew + 1] = { charId = u.charId, name = u.name, callsign = u.callsign, roleName = u.roleName, roleLevel = u.roleLevel,
                        status = u.status, since = u.since, dept = g.short, color1 = g.color1, callId = onCall[u.charId], me = u.charId == c.charId }
                end
            end
        end
        table.sort(crew, function(a, b) if (a.roleLevel or 0) ~= (b.roleLevel or 0) then return (a.roleLevel or 0) > (b.roleLevel or 0) end return a.name < b.name end)
        local bills = J('GetMedicalBills', { status = 'unpaid', jobIds = emsJobIds(), limit = 300 })
        local owed = 0
        for _, b in ipairs(type(bills) == 'table' and bills or {}) do owed = owed + (tonumber(b.amount) or 0) end
        local today = MySQL.single.await('SELECT COUNT(*) AS `n` FROM `es_mdt_ems_reports` WHERE `deptId` = ? AND `createdAt` > NOW() - INTERVAL 1 DAY', { c.dept.id })
        local deaths = MySQL.single.await('SELECT COUNT(*) AS `n` FROM `es_mdt_deaths` WHERE `revokedAt` IS NULL AND `createdAt` > NOW() - INTERVAL 7 DAY')
        local recent = MySQL.query.await(('SELECT %s FROM `es_mdt_ems_reports` WHERE `deptId` = ? ORDER BY `id` DESC LIMIT 5'):format(REP_COLS), { c.dept.id }) or {}
        local depts = MDT.deptShort()
        for _, r in ipairs(recent) do shapeReport(r, depts) end
        return { calls = calls, crew = crew, needReport = needReport(c), recent = recent, now = os.time(),
            counts = { openBills = type(bills) == 'table' and #bills or nil, owed = type(bills) == 'table' and owed or nil,
                reportsToday = today and tonumber(today.n) or 0, deathsWeek = deaths and tonumber(deaths.n) or 0 } }
    end)

    cb('emsBadges', { ems = true, rate = 1500, burst = 3 }, function(c)
        return { reports = #needReport(c) }
    end)

    -- 2) patients
    cb('emsPeople', { ems = true, rate = 300, burst = 6 }, function(c, d)
        local q = str(d.q, 60)
        if #q < 2 then return {} end
        local rows
        if q:match('^%d+$') then
            rows = MySQL.query.await([[SELECT c.`charId`, CONCAT(c.`firstName`,' ',c.`lastName`) AS `name`, DATE_FORMAT(c.`dateOfBirth`,'%Y-%m-%d') AS `dob`, c.`gender`
                FROM `characters` c WHERE c.`deleted` IS NULL AND (c.`charId` = ? OR c.`charId` IN (SELECT `charId` FROM `phone_numbers` WHERE `phoneNumber` LIKE CONCAT(?, '%')))
                LIMIT 25]], { tonumber(q), q }) or {}
        else
            rows = MySQL.query.await([[SELECT c.`charId`, CONCAT(c.`firstName`,' ',c.`lastName`) AS `name`, DATE_FORMAT(c.`dateOfBirth`,'%Y-%m-%d') AS `dob`, c.`gender`
                FROM `characters` c WHERE c.`deleted` IS NULL AND CONCAT(c.`firstName`,' ',c.`lastName`) LIKE CONCAT('%', ?, '%')
                ORDER BY c.`lastName`, c.`firstName` LIMIT 25]], { q }) or {}
        end
        if #rows > 0 then
            local ids = {}
            for _, r in ipairs(rows) do ids[#ids + 1] = r.charId end
            local dead = {}
            for _, x in ipairs(MySQL.query.await(('SELECT `charId` FROM `es_mdt_deaths` WHERE `revokedAt` IS NULL AND `charId` IN (%s)'):format(MDT.marks(#ids)), ids) or {}) do dead[x.charId] = true end
            for _, r in ipairs(rows) do r.deceased = dead[r.charId] or nil end
        end
        return rows
    end)

    -- recent patients (records from whip_jobs, reports from here) for the empty search
    cb('emsRecent', { ems = true, rate = 600, burst = 4 }, function(c)
        local rows = MySQL.query.await([[SELECT `charId`, MAX(`patientName`) AS `name`, MAX(UNIX_TIMESTAMP(`createdAt`)) AS `last`, COUNT(*) AS `n`
            FROM `es_mdt_ems_reports` WHERE `charId` IS NOT NULL GROUP BY `charId` ORDER BY `last` DESC LIMIT 12]]) or {}
        return rows
    end)

    cb('emsPatient', { ems = true, perm = 'medical_records', rate = 400, burst = 6 }, function(c, d)
        local cid = id(d.charId)
        if not cid then return false, 'Pick a patient' end
        local p = personRow(cid)
        if not p then return false, 'No such person' end
        p.name = p.firstName .. ' ' .. p.lastName
        local img = MySQL.single.await('SELECT `image` FROM `character_portraits` WHERE `charId` = ?', { cid })
        p.portrait = img and type(img.image) == 'string' and #img.image < 400000 and img.image:sub(1, 11) == 'data:image/' and img.image or nil
        local pr = MySQL.single.await('SELECT `blood`,`note`,`updatedBy`,UNIX_TIMESTAMP(`updatedAt`) AS `updatedAt` FROM `es_mdt_ems_patients` WHERE `charId` = ?', { cid })
        p.blood = pr and pr.blood or defaultBlood(cid)
        p.bloodSet = pr and pr.blood ~= nil or false
        p.note = pr and pr.note or ''
        if pr and pr.updatedBy then p.noteBy = MDT.namesOf({ pr.updatedBy })[pr.updatedBy] p.noteAt = pr.updatedAt end
        local med = J('GetMedical', cid, 40)
        p.med = type(med) == 'table'
        p.records = p.med and med.records or {}
        p.bills = p.med and med.bills or {}
        p.owed = p.med and med.owed or 0
        local depts = MDT.deptShort()
        p.reports = MySQL.query.await(('SELECT %s FROM `es_mdt_ems_reports` WHERE `charId` = ? ORDER BY `id` DESC LIMIT 30'):format(REP_COLS), { cid }) or {}
        for _, r in ipairs(p.reports) do shapeReport(r, depts) end
        local dth = deathOf(cid)
        if dth then
            dth.dept = dth.deptId and depts[dth.deptId] and depts[dth.deptId].short or nil
            dth.autopsy = autopsyOf(dth.caseId, dth.autopsyRef)
            dth.caseNumber = caseNumberOf(dth.caseId)
        end
        p.death = dth
        p.custody = custodyOf(cid)
        p.canEdit = (c.perms.medical_records or c.staff) and not c.readOnly or false
        p.canDeath = (c.perms.ems_deaths or c.staff) and not c.readOnly or false
        p.canWaive = (c.perms.ems_bills_waive or c.staff) and not c.readOnly or false
        return p
    end)

    cb('emsPatientSave', { ems = true, perm = 'medical_records', write = true, rate = 1200, burst = 3 }, function(c, d)
        local cid = id(d.charId)
        if not cid or not personRow(cid) then return false, 'No such person' end
        local blood = str(d.blood, 3)
        local okB = blood == ''
        for _, b in ipairs(bloodList()) do if b == blood then okB = true end end
        if not okB then return false, 'Pick a blood type' end
        local note = str(d.note, 300)
        MySQL.insert.await([[INSERT INTO `es_mdt_ems_patients` (`charId`,`blood`,`note`,`updatedBy`) VALUES (?,?,?,?)
            ON DUPLICATE KEY UPDATE `blood` = VALUES(`blood`), `note` = VALUES(`note`), `updatedBy` = VALUES(`updatedBy`)]],
            { cid, blood ~= '' and blood or nil, note ~= '' and note or nil, c.charId })
        log(c, 'ems_patient', ('#%d blood %s'):format(cid, blood ~= '' and blood or '-'))
        return true
    end)

    -- 3) incident reports
    cb('emsReports', { ems = true, rate = 500, burst = 6 }, function(c, d)
        local where, args = {}, {}
        if d.scope == 'mine' then where[#where + 1] = '`byCharId` = ?' args[#args + 1] = c.charId
        elseif d.scope ~= 'all' then where[#where + 1] = '`deptId` = ?' args[#args + 1] = c.dept.id end
        local q = str(d.q, 60)
        if #q >= 2 then
            where[#where + 1] = '(`patientName` LIKE ? OR `what` LIKE ? OR `byName` LIKE ? OR `callId` = ?)'
            local like = '%' .. q:gsub('[%%_\\]', '\\%0') .. '%'
            args[#args + 1] = like args[#args + 1] = like args[#args + 1] = like args[#args + 1] = tonumber(q) or 0
        end
        args[#args + 1] = 80
        local rows = MySQL.query.await(('SELECT %s FROM `es_mdt_ems_reports`%s ORDER BY `id` DESC LIMIT ?'):format(REP_COLS,
            #where > 0 and (' WHERE ' .. table.concat(where, ' AND ')) or ''), args) or {}
        local depts = MDT.deptShort()
        for _, r in ipairs(rows) do shapeReport(r, depts) end
        return { reports = rows, needReport = needReport(c) }
    end)

    cb('emsReport', { ems = true, rate = 400, burst = 6 }, function(c, d)
        local rid = id(d.id)
        local r = rid and MySQL.single.await(('SELECT %s FROM `es_mdt_ems_reports` WHERE `id` = ?'):format(REP_COLS), { rid })
        if not r then return false, 'No such report' end
        shapeReport(r)
        local hours = tonumber(E().reportEditHours) or 24
        r.canEdit = not c.readOnly and (c.staff or c.perms.ems_deaths or (r.byCharId == c.charId and os.time() - (r.createdAt or 0) < hours * 3600)) or false
        if r.callId then
            local k = MySQL.single.await('SELECT `id`,`title`,`priority`,`status` FROM `es_mdt_calls` WHERE `id` = ?', { r.callId })
            r.call = k
        end
        return r
    end)

    -- a call's details for a new report (the patient: the caller when they are a character)
    cb('emsReportForm', { ems = true, rate = 500, burst = 4 }, function(c, d)
        local cid = id(d.callId)
        if not cid then return { actions = E().actions or {} } end
        local k = MySQL.single.await([[SELECT `id`,`title`,`message`,`street`,`priority`,`status`,`callerCharId`,`callerName`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt`
            FROM `es_mdt_calls` WHERE `id` = ?]], { cid })
        if not k then return false, 'No such call' end
        local units = (MDT.unitsOfCalls({ cid })[cid]) or {}
        return { call = k, units = units, actions = E().actions or {} }
    end)

    cb('emsReportSave', { ems = true, perm = 'ems_reports', write = true, rate = 1500, burst = 3 }, function(c, d)
        local what = str(d.what, 200)
        if #what < 3 then return false, 'Say what happened' end
        local m, acts, seen = actionMap(), {}, {}
        for _, k in ipairs(type(d.actions) == 'table' and d.actions or {}) do
            if type(k) == 'string' and m[k] and not seen[k] and #acts < 8 then seen[k] = true acts[#acts + 1] = k end
        end
        local note = str(d.note, 500)
        local charId, pname = id(d.charId), str(d.patientName, 80)
        if charId then
            local p = personRow(charId)
            if not p then return false, 'No such person' end
            pname = p.firstName .. ' ' .. p.lastName
        end
        local rid = id(d.id)
        if rid then
            local r = MySQL.single.await('SELECT `id`,`byCharId`,`callId`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt` FROM `es_mdt_ems_reports` WHERE `id` = ?', { rid })
            if not r then return false, 'No such report' end
            local hours = tonumber(E().reportEditHours) or 24
            if not (c.staff or c.perms.ems_deaths or (r.byCharId == c.charId and os.time() - (r.createdAt or 0) < hours * 3600)) then
                return false, 'Only the writer (for a day) or a supervisor edits a report'
            end
            MySQL.update.await('UPDATE `es_mdt_ems_reports` SET `charId` = ?, `patientName` = ?, `what` = ?, `actions` = ?, `note` = ?, `updatedAt` = NOW() WHERE `id` = ?',
                { charId, pname ~= '' and pname or nil, what, table.concat(acts, ','), note ~= '' and note or nil, rid })
            log(c, 'ems_report', ('edited #%d'):format(rid))
            return { id = rid }
        end
        local callId, street = id(d.callId), str(d.street, 120)
        if callId then
            local k = MySQL.single.await('SELECT `id`,`street` FROM `es_mdt_calls` WHERE `id` = ?', { callId })
            if not k then return false, 'No such call' end
            local on = MySQL.single.await('SELECT 1 AS `x` FROM `es_mdt_call_units` WHERE `callId` = ? AND `charId` = ?', { callId, c.charId })
            if not (on or c.staff or (c.myLevel or 0) >= 60) then return false, 'Attach to the call to report on it' end
            local dup = MySQL.single.await('SELECT `id` FROM `es_mdt_ems_reports` WHERE `callId` = ? AND `byCharId` = ?', { callId, c.charId })
            if dup then return false, ('You already reported on this call (report #%d): edit that one'):format(dup.id) end
            street = (k.street and k.street ~= '') and k.street or street
        end
        local newId = MySQL.insert.await([[INSERT INTO `es_mdt_ems_reports` (`deptId`,`callId`,`charId`,`patientName`,`what`,`actions`,`note`,`street`,`byCharId`,`byName`)
            VALUES (?,?,?,?,?,?,?,?,?,?)]], { c.dept.id, callId, charId, pname ~= '' and pname or nil, what, table.concat(acts, ','),
            note ~= '' and note or nil, street ~= '' and street or nil, c.charId, c.name })
        if not newId then return false, 'The report could not be saved' end
        if callId then
            local txt = actionsText(table.concat(acts, ','))
            MySQL.insert.await('INSERT INTO `es_mdt_call_notes` (`callId`,`byCharId`,`note`) VALUES (?,?,?)',
                { callId, c.charId, ('EMS report filed%s'):format(txt ~= '' and (': ' .. txt) or '') })
            MDT.refresh('calls')
        end
        log(c, 'ems_report', ('#%d%s'):format(newId, callId and (' on call #' .. callId) or ''))
        return { id = newId }
    end)

    -- 4) bills (whip_jobs)
    cb('emsBills', { ems = true, perm = 'medical_records', rate = 600, burst = 4 }, function(c, d)
        local st = (d.status == 'paid' or d.status == 'waived' or d.status == 'all') and d.status or 'unpaid'
        local rows = J('GetMedicalBills', { status = st, jobIds = emsJobIds(), limit = 200 })
        if type(rows) ~= 'table' then return { med = false, bills = {} } end
        local owed, people = 0, {}
        for _, b in ipairs(rows) do
            if b.status == 'unpaid' then owed = owed + (tonumber(b.amount) or 0) people[b.charId] = true end
        end
        local n = 0 for _ in pairs(people) do n = n + 1 end
        return { med = true, bills = rows, owed = owed, people = n, canWaive = (c.perms.ems_bills_waive or c.staff) and not c.readOnly or false }
    end)

    cb('emsBillWaive', { ems = true, perm = 'ems_bills_waive', write = true, rate = 1200, burst = 3 }, function(c, d)
        local bid = id(d.id)
        if not bid then return false, 'No such bill' end
        local note = str(d.note, 120)
        local open = J('GetMedicalBills', { status = 'unpaid', jobIds = emsJobIds(), limit = 300 })
        if type(open) ~= 'table' then return false, 'The job pack (whip_jobs 0.6.0+) is not running' end
        local found
        for _, b in ipairs(open) do if b.id == bid then found = b end end
        if not found then return false, 'That bill is not open' end
        local ok, why = J('WaiveMedicalBill', bid, { charId = c.charId, name = c.name, source = c.source }, note)
        if not ok then return false, type(why) == 'string' and why or 'Could not waive it' end
        log(c, 'ems_waive', ('bill #%d ($%d) of #%d%s'):format(bid, found.amount or 0, found.charId or 0, note ~= '' and (': ' .. note) or ''))
        return true
    end)

    -- 5) deaths
    cb('emsDeaths', { ems = true, rate = 600, burst = 4 }, function(c, d)
        local rows = MySQL.query.await(('SELECT %s FROM `es_mdt_deaths` %s ORDER BY `id` DESC LIMIT 80'):format(DEATH_COLS,
            d.all and '' or 'WHERE `revokedAt` IS NULL'), {}) or {}
        local depts = MDT.deptShort()
        local cases = {}
        for _, r in ipairs(rows) do
            r.dept = r.deptId and depts[r.deptId] and depts[r.deptId].short or nil
            if r.caseId then cases[r.caseId] = cases[r.caseId] or caseNumberOf(r.caseId) r.caseNumber = cases[r.caseId] end
        end
        return { deaths = rows, canDeath = (c.perms.ems_deaths or c.staff) and not c.readOnly or false }
    end)

    cb('emsAutopsies', { ems = true, perm = 'ems_deaths', rate = 800, burst = 4 }, function(c)
        local rows = MySQL.query.await([[SELECT e.`caseId`, e.`ref`, e.`data`, k.`number`, UNIX_TIMESTAMP(e.`uploadedAt`) AS `uploadedAt` FROM `es_mdt_wev_entries` e
            JOIN `es_mdt_cases` k ON k.`id` = e.`caseId` WHERE e.`kind` = 'autopsy' AND e.`gone` = 0 AND e.`uploadedAt` > NOW() - INTERVAL ? DAY
            ORDER BY e.`uploadedAt` DESC LIMIT 40]], { math.max(1, math.floor(tonumber(E().autopsyDays) or 60)) }) or {}
        local out = {}
        for _, r in ipairs(rows) do
            local ok, e = pcall(json.decode, r.data or '')
            local v = ok and type(e) == 'table' and MDT.wevView and MDT.wevView(e, r.ref)
            local rep = v and v.report
            if rep then
                out[#out + 1] = { caseId = r.caseId, ref = r.ref, caseNumber = r.number, uploadedAt = r.uploadedAt, title = rep.title,
                    examinedAt = rep.examinedAt, street = rep.street, fatal = rep.fatal, diedAt = rep.diedAt, kind = rep.kind }
            end
        end
        return out
    end)

    cb('emsDeathSave', { ems = true, perm = 'ems_deaths', write = true, rate = 2000, burst = 2 }, function(c, d)
        local cid = id(d.charId)
        local p = cid and personRow(cid)
        if not p then return false, 'Pick the person' end
        if deathOf(cid) then return false, 'They already have a death record' end
        local cause = str(d.cause, 200)
        if #cause < 3 then return false, 'Give the cause of death' end
        local place = str(d.place, 120)
        local caseId, ref = id(d.caseId), str(d.ref, 80)
        if caseId or ref ~= '' then
            local okA = caseId and ref ~= '' and MySQL.single.await("SELECT 1 AS `x` FROM `es_mdt_wev_entries` WHERE `caseId` = ? AND `ref` = ? AND `kind` = 'autopsy'", { caseId, ref })
            if not okA then return false, 'That post-mortem report is not in the MDT' end
        end
        local diedAt = tonumber(d.diedAt)
        if diedAt and (diedAt > os.time() + 60 or diedAt < os.time() - 86400 * 30) then diedAt = nil end
        local newId = MySQL.insert.await([[INSERT INTO `es_mdt_deaths` (`charId`,`name`,`deptId`,`cause`,`place`,`diedAt`,`caseId`,`autopsyRef`,`byCharId`,`byName`)
            VALUES (?,?,?,?,?,FROM_UNIXTIME(?),?,?,?,?)]], { cid, p.firstName .. ' ' .. p.lastName, c.dept.id, cause, place ~= '' and place or nil,
            diedAt or os.time(), caseId, ref ~= '' and ref or nil, c.charId, c.name })
        if not newId then return false, 'The record could not be saved' end
        log(c, 'ems_death', ('#%d %s: %s'):format(cid, p.firstName .. ' ' .. p.lastName, cause))
        return { id = newId }
    end)

    cb('emsDeathRevoke', { ems = true, perm = 'ems_deaths', write = true, rate = 2000, burst = 2 }, function(c, d)
        local did = id(d.id)
        local note = str(d.note, 200)
        if #note < 3 then return false, 'Say why it is undone' end
        local n = did and MySQL.update.await('UPDATE `es_mdt_deaths` SET `revokedAt` = NOW(), `revokedBy` = ?, `revokeNote` = ? WHERE `id` = ? AND `revokedAt` IS NULL',
            { c.name, note, did }) or 0
        if (tonumber(n) or 0) < 1 then return false, 'That record is not active' end
        log(c, 'ems_death_undo', ('record #%d: %s'):format(did, note))
        return true
    end)

    -- 7) roster and stats (the department's members: the same ranks and tools as the police, Department tab)
    cb('emsStats', { ems = true, rate = 1500, burst = 3 }, function(c, d)
        local days = int(d.days or 7, 1, 90)
        local s = ED:GetStats(c.dept.id, { days = days, top = 3 }) or {}
        local members = type(s.members) == 'table' and s.members or {}
        local ids = {}
        for _, m in ipairs(members) do ids[#ids + 1] = m.charId end
        local calls, reps, deaths = {}, {}, {}
        if #ids > 0 then
            local args = { days }
            for _, x in ipairs(ids) do args[#args + 1] = x end
            for _, r in ipairs(MySQL.query.await(('SELECT `charId`, COUNT(DISTINCT `callId`) AS `n` FROM `es_mdt_call_units` WHERE `attachedAt` > NOW() - INTERVAL ? DAY AND `charId` IN (%s) GROUP BY `charId`')
                :format(MDT.marks(#ids)), args) or {}) do calls[r.charId] = tonumber(r.n) or 0 end
            for _, r in ipairs(MySQL.query.await(('SELECT `byCharId`, COUNT(*) AS `n` FROM `es_mdt_ems_reports` WHERE `createdAt` > NOW() - INTERVAL ? DAY AND `byCharId` IN (%s) GROUP BY `byCharId`')
                :format(MDT.marks(#ids)), args) or {}) do reps[r.byCharId] = tonumber(r.n) or 0 end
            for _, r in ipairs(MySQL.query.await(('SELECT `byCharId`, COUNT(*) AS `n` FROM `es_mdt_deaths` WHERE `createdAt` > NOW() - INTERVAL ? DAY AND `byCharId` IN (%s) GROUP BY `byCharId`')
                :format(MDT.marks(#ids)), args) or {}) do deaths[r.byCharId] = tonumber(r.n) or 0 end
        end
        local med = J('GetMedicalStats', days, emsJobIds())
        local leader = c.staff or c.perms.loa_manage
        local out, totals = {}, { calls = 0, treated = 0, revived = 0, reports = 0, members = #members, onDuty = 0, dutySeconds = 0 }
        for _, m in ipairs(members) do
            local ms = type(med) == 'table' and (med[m.charId] or med[tostring(m.charId)]) or {}
            local row = { charId = m.charId, name = m.name, callsign = m.callsign, roleName = m.roleName, onDuty = m.onDuty == true,
                calls = calls[m.charId] or 0, treated = (tonumber(ms.treat) or 0) + (tonumber(ms.desk) or 0), revived = tonumber(ms.revive) or 0,
                aid = tonumber(ms.aid) or 0, reports = reps[m.charId] or 0, deaths = deaths[m.charId] or 0,
                dutySeconds = leader and (m.dutySeconds or 0) or nil, me = m.charId == c.charId }
            row.score = row.revived * 3 + row.treated * 2 + row.calls + row.reports
            out[#out + 1] = row
            totals.calls = totals.calls + row.calls totals.treated = totals.treated + row.treated totals.revived = totals.revived + row.revived
            totals.reports = totals.reports + row.reports
            if row.onDuty then totals.onDuty = totals.onDuty + 1 end
            totals.dutySeconds = totals.dutySeconds + (m.dutySeconds or 0)
        end
        table.sort(out, function(a, b) if a.score ~= b.score then return a.score > b.score end return tostring(a.name) < tostring(b.name) end)
        if not leader then totals.dutySeconds = nil end
        return { days = days, members = out, totals = totals, med = type(med) == 'table', leader = leader or false }
    end)
end
