local _ENV = ESAPP('mdt'); -- es_mdt 1.5.0: Cases. A case (C-2026-0001) ties reports, evidence (and its photos and lab results), warrants
-- and suspects together, with a lead detective, assigned officers, notes and a timeline. Cases are shared by every
-- department (investigations cross them); a report inside a case still shows only to those who may see it.
-- Evidence lives in es_evidence (its caseId); each case's evidence locker is there too (one per case, no limit).
-- Permissions: cases_create (rank 30+) opens cases and edits them; cases_close (60+) closes, archives, reopens.
-- The lead and assigned officers may edit their case. Everything is logged (case timeline + activity log).

local function evOn() return GetResourceState('es_evidence') == 'started' end
local function EV() return exports.es_evidence end

local STATUSES = { open = true, closed = true, archived = true }

exports('OpenCase', function(source, title)
    if not MDT.openCaseFor then return false, 'The MDT is still starting' end
    return MDT.openCaseFor(tonumber(source), title)
end)
exports('CanOpenCase', function(source) return MDT.canOpenCase and MDT.canOpenCase(tonumber(source)) or false end)

function MDT.registerCases()
    local cb, str, int, id, marks, namesOf, log = MDT.cb, MDT.str, MDT.int, MDT.id, MDT.marks, MDT.namesOf, MDT.log
    local CFG = Config.Cases or {}

    local function caseLog(caseId, c, what, detail)
        MySQL.insert('INSERT INTO `es_mdt_case_log` (`caseId`,`what`,`detail`,`byCharId`) VALUES (?,?,?,?)',
            { caseId, what, detail and str(detail, 255) or nil, c and c.charId or nil })
        if c then log(c, 'case_' .. what, ('#%d %s'):format(caseId, detail or '')) end
    end
    MDT.caseLog = caseLog

    local function getCase(caseId)
        caseId = id(caseId)
        return caseId and MySQL.single.await([[SELECT `id`,`number`,`title`,`status`,`deptId`,`leadCharId`,`notes`,`createdBy`,
            UNIX_TIMESTAMP(`createdAt`) AS `createdAt`,UNIX_TIMESTAMP(`closedAt`) AS `closedAt`,UNIX_TIMESTAMP(`archivedAt`) AS `archivedAt`
            FROM `es_mdt_cases` WHERE `id` = ?]], { caseId }) or nil
    end
    MDT.getCase = getCase

    local function isMember(caseRow, charId)
        if caseRow.leadCharId == charId then return true end
        return MySQL.scalar.await('SELECT 1 FROM `es_mdt_case_officers` WHERE `caseId` = ? AND `charId` = ?', { caseRow.id, charId }) ~= nil
    end
    --- may edit the case's details, people and notes
    local function canEdit(c, k)
        if c.readOnly then return false, 'You are off duty: the MDT is read-only' end
        if k.status == 'archived' then return false, 'This case is archived (read-only). Someone with "close cases" can reopen it.' end
        if c.staff or c.perms.cases_create or isMember(k, c.charId) then return true end
        return false, 'Only the lead, the assigned officers, or a rank that can open cases can change this case'
    end
    --- may file things (reports, evidence, warrants) into it
    local function canFile(c, k)
        if c.readOnly then return false, 'You are off duty: the MDT is read-only' end
        if k.status == 'archived' then return false, 'This case is archived (read-only)' end
        if c.staff or c.perms.cases_create or c.perms.mdt_reports_write or c.perms.evidence_collect then return true end
        return false, 'Your rank cannot file into cases'
    end
    MDT.caseCanFile, MDT.caseCanEdit = canFile, canEdit

    local function nextNumber()
        local prefix = CFG.prefix or 'C'
        local year = os.date('%Y')
        local head = ('%s-%s-'):format(prefix, year)
        local last = MySQL.scalar.await('SELECT MAX(CAST(SUBSTRING(`number`, ?) AS UNSIGNED)) FROM `es_mdt_cases` WHERE `number` LIKE ?', { #head + 1, head .. '%' })
        return head, (tonumber(last) or 0) + 1
    end

    local function create(c, title, notes, leadCharId)
        local head, n = nextNumber()
        for _ = 1, 5 do
            local number = ('%s%04d'):format(head, n)
            local ok, cid = pcall(function()
                return MySQL.insert.await('INSERT INTO `es_mdt_cases` (`number`,`title`,`status`,`deptId`,`leadCharId`,`notes`,`createdBy`) VALUES (?,?,?,?,?,?,?)',
                    { number, title, 'open', c.dept and c.dept.id or nil, leadCharId or c.charId, notes ~= '' and notes or nil, c.charId })
            end)
            if ok and cid then
                caseLog(cid, c, 'opened', number .. ' · ' .. title)
                return cid, number
            end
            n = n + 1
        end
        return nil
    end

    -- ------------------------------------------------------------ list / search
    cb('cases', { rate = 300, burst = 6 }, function(c, d)
        local where, args = {}, {}
        local st = str(d.status, 12)
        if STATUSES[st] then where[#where + 1] = 'k.`status` = ?' args[#args + 1] = st end
        if d.mine then
            where[#where + 1] = '(k.`leadCharId` = ? OR k.`id` IN (SELECT o.`caseId` FROM `es_mdt_case_officers` o WHERE o.`charId` = ?))'
            args[#args + 1] = c.charId args[#args + 1] = c.charId
        end
        local q = str(d.q, 60)
        if q ~= '' then
            local like = '%' .. q:gsub('[%%_\\]', '\\%0') .. '%'
            where[#where + 1] = [[(k.`number` LIKE ? OR k.`title` LIKE ? OR k.`notes` LIKE ?
                OR k.`id` IN (SELECT s.`caseId` FROM `es_mdt_case_suspects` s JOIN `characters` ch ON ch.`charId` = s.`charId` WHERE CONCAT(ch.`firstName`,' ',ch.`lastName`) LIKE ?)
                OR k.`id` IN (SELECT r.`caseId` FROM `es_mdt_reports` r WHERE r.`caseId` IS NOT NULL AND (r.`title` LIKE ? OR CAST(r.`id` AS CHAR) = ?)))]]
            for _ = 1, 5 do args[#args + 1] = like end
            args[#args + 1] = (q:gsub('^#', ''))
        end
        args[#args + 1] = int(d.offset, 0, 100000)
        local rows = MySQL.query.await(([[SELECT k.`id`,k.`number`,k.`title`,k.`status`,k.`leadCharId`,UNIX_TIMESTAMP(k.`createdAt`) AS `createdAt`,
            UNIX_TIMESTAMP(k.`updatedAt`) AS `updatedAt`,
            (SELECT COUNT(*) FROM `es_mdt_reports` r WHERE r.`caseId` = k.`id`) AS `reports`,
            (SELECT COUNT(*) FROM `es_mdt_case_suspects` s WHERE s.`caseId` = k.`id`) AS `suspects`,
            (SELECT COUNT(*) FROM `es_mdt_warrants` w WHERE w.`caseId` = k.`id` AND w.`status` IN ('active','requested')) AS `warrants`
            FROM `es_mdt_cases` k %s ORDER BY (k.`status` = 'open') DESC, k.`id` DESC LIMIT 50 OFFSET ?]]):format(#where > 0 and ('WHERE ' .. table.concat(where, ' AND ')) or ''), args) or {}
        local ids, cids = {}, {}
        for _, r in ipairs(rows) do ids[#ids + 1] = r.leadCharId cids[#cids + 1] = r.id end
        local nm = namesOf(ids)
        local evCount = {}
        if #cids > 0 and evOn() then
            local okc, res = pcall(function()
                return MySQL.query.await('SELECT `caseId`, COUNT(*) AS `n` FROM `es_evidence` WHERE `caseId` IN (' .. marks(#cids) .. ") AND `status` NOT IN ('scene','gone','destroyed') GROUP BY `caseId`", cids)
            end)
            for _, x in ipairs(okc and res or {}) do evCount[x.caseId] = tonumber(x.n) or 0 end
        end
        for _, r in ipairs(rows) do
            r.lead = r.leadCharId and nm[r.leadCharId] or nil
            r.reports, r.suspects, r.warrants = tonumber(r.reports) or 0, tonumber(r.suspects) or 0, tonumber(r.warrants) or 0
            r.evidence = evCount[r.id] or 0
        end
        return rows
    end)

    -- a small list for pickers (open first)
    cb('caseFind', { rate = 200, burst = 8 }, function(c, d)
        local q = str(d.q, 60)
        local like = '%' .. q:gsub('[%%_\\]', '\\%0') .. '%'
        return MySQL.query.await([[SELECT `id`,`number`,`title`,`status` FROM `es_mdt_cases` WHERE `status` <> 'archived' AND (? = '' OR `number` LIKE ? OR `title` LIKE ?)
            ORDER BY (`status` = 'open') DESC, `id` DESC LIMIT 15]], { q, like, like }) or {}
    end)

    -- ------------------------------------------------------------ one case, everything linked
    cb('case', { rate = 300, burst = 6 }, function(c, d)
        local k = getCase(d.id)
        if not k then return false, 'No such case' end
        local ids = { k.leadCharId, k.createdBy }
        local officers = MySQL.query.await('SELECT `charId`, UNIX_TIMESTAMP(`addedAt`) AS `at` FROM `es_mdt_case_officers` WHERE `caseId` = ? ORDER BY `addedAt`', { k.id }) or {}
        local suspects = MySQL.query.await([[SELECT s.`charId`, s.`note`, UNIX_TIMESTAMP(s.`addedAt`) AS `at`,
            (SELECT COUNT(*) FROM `es_mdt_warrants` w WHERE w.`charId` = s.`charId` AND w.`status` = 'active' AND w.`kind` = 'arrest') AS `warrants`,
            (SELECT m.`id` FROM `es_mdt_mugshots` m WHERE m.`charId` = s.`charId` ORDER BY m.`id` DESC LIMIT 1) AS `mugId`
            FROM `es_mdt_case_suspects` s WHERE s.`caseId` = ? ORDER BY s.`addedAt`]], { k.id }) or {}
        local reports = MySQL.query.await([[SELECT `id`,`deptId`,`type`,`title`,`authorCharId`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt`
            FROM `es_mdt_reports` WHERE `caseId` = ? ORDER BY `id`]], { k.id }) or {}
        local rids = {}
        for _, r in ipairs(reports) do rids[#rids + 1] = r.id end
        -- suspects named on the case's reports (not added by hand)
        local fromReports = {}
        if #rids > 0 then
            fromReports = MySQL.query.await('SELECT DISTINCT `charId`, `reportId` FROM `es_mdt_report_people` WHERE `role` = \'suspect\' AND `reportId` IN (' .. marks(#rids) .. ')', rids) or {}
        end
        local wargs, wq = { k.id }, '`caseId` = ?'
        if #rids > 0 then wq = wq .. ' OR `reportId` IN (' .. marks(#rids) .. ')' for _, x in ipairs(rids) do wargs[#wargs + 1] = x end end
        local warrants = MySQL.query.await(([[SELECT `id`,`charId`,`reportId`,`caseId`,`reason`,`status`,`requestedBy`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt`
            FROM `es_mdt_warrants` WHERE %s ORDER BY `id`]]):format(wq), wargs) or {}
        local logs = MySQL.query.await('SELECT `id`,`what`,`detail`,`byCharId`,UNIX_TIMESTAMP(`at`) AS `at` FROM `es_mdt_case_log` WHERE `caseId` = ? ORDER BY `id` DESC LIMIT 200', { k.id }) or {}
        for _, x in ipairs(officers) do ids[#ids + 1] = x.charId end
        for _, x in ipairs(suspects) do ids[#ids + 1] = x.charId end
        for _, x in ipairs(fromReports) do ids[#ids + 1] = x.charId end
        for _, x in ipairs(reports) do ids[#ids + 1] = x.authorCharId end
        for _, x in ipairs(warrants) do ids[#ids + 1] = x.charId ids[#ids + 1] = x.requestedBy end
        for _, x in ipairs(logs) do ids[#ids + 1] = x.byCharId end
        local nm = namesOf(ids)
        local ds = MDT.deptShort()
        for _, x in ipairs(officers) do x.name = nm[x.charId] end
        local seen = {}
        for _, x in ipairs(suspects) do x.name = nm[x.charId] x.warrants = tonumber(x.warrants) or 0 x.added = true seen[x.charId] = x end
        for _, x in ipairs(fromReports) do
            local s = seen[x.charId]
            if s then s.reports = s.reports or {} table.insert(s.reports, x.reportId)
            else
                s = { charId = x.charId, name = nm[x.charId], fromReport = true, reports = { x.reportId } }
                seen[x.charId] = s
                suspects[#suspects + 1] = s
            end
        end
        for _, r in ipairs(reports) do
            r.visible = MDT.canSeeReport(c, r) == true
            r.author = nm[r.authorCharId]
            r.deptShort = ds[r.deptId] and ds[r.deptId].short
            if not r.visible then r.title = nil end
        end
        for _, w in ipairs(warrants) do w.name = nm[w.charId] w.requestedByName = nm[w.requestedBy] end
        for _, x in ipairs(logs) do x.by = x.byCharId and nm[x.byCharId] or nil end
        local ev = { items = {}, custody = {}, locker = { items = {} }, installed = evOn() }
        if ev.installed then
            local okE, res = pcall(function() return EV():ForCase(k.id) end)
            if okE and type(res) == 'table' then res.installed = true ev = res end
        end
        k.lead = k.leadCharId and nm[k.leadCharId] or nil
        k.createdByName = k.createdBy and nm[k.createdBy] or nil
        local editOk = canEdit(c, k)
        local fileOk = canFile(c, k)
        k.ver = MDT.verOf and MDT.verOf('case:' .. k.id) or 0
        -- 1.11.0: optional whip_evidence locker (nil when the integration is off / not installed)
        local wev = nil
        if MDT.wevForCase then
            local okW, res = pcall(MDT.wevForCase, k)
            if okW then wev = res else print(('^3[es_mdt] whip_evidence case view: %s^7'):format(tostring(res))) end
        end
        return { case = k, officers = officers, suspects = suspects, reports = reports, warrants = warrants, log = logs, evidence = ev, wev = wev,
            can = { edit = editOk == true, file = fileOk == true, close = (c.staff or c.perms.cases_close) and not c.readOnly or false,
                purge = (c.staff or c.perms.evidence_manage) and not c.readOnly or false } }
    end)

    -- 1.5.4: es_evidence's evidence room can open a case from its locker picker (same rule as the MDT: cases_create)
    MDT.openCaseFor = function(source, title)
        local c, why = MDT.ctxOf(source)
        if not c then return false, why end
        if c.readOnly then return false, 'You are off duty: the MDT is read-only' end
        if not (c.staff or c.perms.cases_create) then return false, 'Your rank cannot open cases' end
        title = str(title, 120)
        if title == '' then return false, 'Give the case a title' end
        local cid, number = create(c, title, '', nil)
        if not cid then return false, 'Could not open the case' end
        MDT.refresh('cases')
        return { id = cid, number = number, title = title }
    end
    MDT.canOpenCase = function(source)
        local c = MDT.ctxOf(source)
        return c and not c.readOnly and (c.staff or c.perms.cases_create) and true or false
    end

    -- ------------------------------------------------------------ create / edit
    cb('caseSave', { write = true, rate = 1000, burst = 3, lock = 'case' }, function(c, d)
        local title = str(d.title, 120)
        if title == '' then return false, 'Give the case a title' end
        local notes = str(d.notes, 4000)
        local lead = id(d.leadCharId)
        if not id(d.id) then
            if not (c.staff or c.perms.cases_create) then return false, 'Your rank cannot open cases' end
            local cid, number = create(c, title, notes, lead)
            if not cid then return false, 'Could not open the case' end
            if lead and lead ~= c.charId then caseLog(cid, c, 'lead', 'Lead: ' .. (namesOf({ lead })[lead] or ('#' .. lead))) end
            MDT.refresh('cases')
            return { id = cid, number = number }
        end
        local k = getCase(d.id)
        if not k then return false, 'No such case' end
        local ok, why = canEdit(c, k)
        if not ok then return false, why end
        local changes = {}
        if title ~= k.title then changes[#changes + 1] = 'title' end
        if notes ~= (k.notes or '') then changes[#changes + 1] = 'notes' end
        if d.leadCharId ~= nil and lead ~= k.leadCharId then
            if not (c.staff or c.perms.cases_create or c.perms.cases_close or k.leadCharId == c.charId) then return false, 'Only the lead or a rank that can open cases can hand the case over' end
            changes[#changes + 1] = 'lead'
        else lead = k.leadCharId end
        if #changes == 0 then return { id = k.id, number = k.number } end
        MySQL.update.await('UPDATE `es_mdt_cases` SET `title` = ?, `notes` = ?, `leadCharId` = ? WHERE `id` = ?', { title, notes ~= '' and notes or nil, lead, k.id })
        for _, ch in ipairs(changes) do
            if ch == 'lead' then caseLog(k.id, c, 'lead', 'Lead: ' .. (lead and (namesOf({ lead })[lead] or ('#' .. lead)) or 'none'))
            elseif ch == 'notes' then caseLog(k.id, c, 'notes', 'Notes edited')
            else caseLog(k.id, c, 'title', 'Title: ' .. title) end
        end
        MDT.refresh('cases')
        return { id = k.id, number = k.number }
    end)

    cb('caseStatus', { write = true, rate = 1000, burst = 3 }, function(c, d)
        if not (c.staff or c.perms.cases_close) then return false, 'Your rank cannot close, archive or reopen cases' end
        local k = getCase(d.id)
        if not k then return false, 'No such case' end
        local st = str(d.status, 12)
        if not STATUSES[st] then return false, 'open, closed or archived' end
        if st == k.status then return true end
        local note = str(d.note, 200)
        MySQL.update.await([[UPDATE `es_mdt_cases` SET `status` = ?, `closedAt` = IF(? = 'open', NULL, COALESCE(`closedAt`, NOW())),
            `archivedAt` = IF(? = 'archived', NOW(), NULL) WHERE `id` = ?]], { st, st, st, k.id })
        caseLog(k.id, c, st == 'open' and 'reopened' or st, (note ~= '' and note) or nil)
        -- 1.11.0: close / reopen the case's whip_evidence locker too (their evidence_case_close perm); the MDT change stands
        local warn = nil
        if MDT.wevCaseStatus then
            local okW, res = pcall(MDT.wevCaseStatus, c.source, k, st)
            warn = okW and res or nil
            if warn then caseLog(k.id, nil, 'evidence', warn) end
        end
        MDT.refresh('cases')
        if warn then return { warn = warn } end
        return true
    end)

    -- officers and suspects
    cb('casePerson', { write = true, rate = 500, burst = 6 }, function(c, d)
        local k = getCase(d.id)
        if not k then return false, 'No such case' end
        local ok, why = canEdit(c, k)
        if not ok then return false, why end
        local who = id(d.charId)
        if not who then return false, 'Pick a person' end
        local name = namesOf({ who })[who] or ('#' .. who)
        if d.kind == 'officer' then
            if d.remove then
                MySQL.update.await('DELETE FROM `es_mdt_case_officers` WHERE `caseId` = ? AND `charId` = ?', { k.id, who })
                caseLog(k.id, c, 'officer_off', name)
            else
                MySQL.insert.await('INSERT IGNORE INTO `es_mdt_case_officers` (`caseId`,`charId`,`addedBy`) VALUES (?,?,?)', { k.id, who, c.charId })
                caseLog(k.id, c, 'officer', name)
                MDT.notifyChar(who, ('You were assigned to case %s · %s'):format(k.number, k.title), 'inform')
            end
        elseif d.kind == 'suspect' then
            if d.remove then
                MySQL.update.await('DELETE FROM `es_mdt_case_suspects` WHERE `caseId` = ? AND `charId` = ?', { k.id, who })
                caseLog(k.id, c, 'suspect_off', name)
            else
                MySQL.insert.await('INSERT INTO `es_mdt_case_suspects` (`caseId`,`charId`,`note`,`addedBy`) VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE `note` = VALUES(`note`)',
                    { k.id, who, str(d.note, 200) ~= '' and str(d.note, 200) or nil, c.charId })
                caseLog(k.id, c, 'suspect', name)
            end
        else return false, 'officer or suspect' end
        return true
    end)

    -- reports, evidence and warrants in (or out of) a case
    cb('caseLink', { write = true, rate = 400, burst = 8 }, function(c, d)
        local kind, ref = str(d.kind, 12), id(d.refId)
        if not ref then return false, 'Pick what to file' end
        local cid = id(d.caseId)
        local k = cid and getCase(cid)
        if cid and not k then return false, 'No such case' end
        if k then local ok, why = canFile(c, k) if not ok then return false, why end
        elseif c.readOnly then return false, 'You are off duty: the MDT is read-only' end
        if kind == 'report' then
            local r = MySQL.single.await('SELECT `id`,`deptId`,`authorCharId`,`caseId` FROM `es_mdt_reports` WHERE `id` = ?', { ref })
            if not r then return false, 'No such report' end
            if not MDT.canSeeReport(c, r) then return false, 'That report is not yours to file' end
            if not c.perms.mdt_reports_write and not c.staff then return false, 'Your rank cannot change reports' end
            local old = r.caseId and getCase(r.caseId)
            if r.caseId == (k and k.id) then return true end
            MySQL.update.await('UPDATE `es_mdt_reports` SET `caseId` = ? WHERE `id` = ?', { k and k.id or nil, ref })
            if old then caseLog(old.id, c, 'report_off', ('Report #%d'):format(ref)) end
            if k then caseLog(k.id, c, 'report', ('Report #%d'):format(ref)) end
            MySQL.insert('INSERT INTO `es_mdt_report_log` (`reportId`,`what`,`detail`,`byCharId`) VALUES (?,?,?,?)',
                { ref, 'case', k and ('Filed to case ' .. k.number) or ('Taken off case ' .. (old and old.number or '')), c.charId })
        elseif kind == 'evidence' then
            if not evOn() then return false, 'The evidence system (es_evidence) is not running' end
            if not (c.staff or c.perms.evidence_collect or c.perms.mdt_reports_write) then return false, 'Your rank cannot file evidence' end
            local ok, err = EV():SetCase(ref, k and k.id or nil, c.charId)
            if not ok then return false, err end
            local code = ('EV-%05d'):format(ref)
            if k then caseLog(k.id, c, 'evidence', code) end
            if d.fromCase and id(d.fromCase) and (not k or id(d.fromCase) ~= k.id) then caseLog(id(d.fromCase), c, 'evidence_off', code) end
        elseif kind == 'warrant' then
            local w = MySQL.single.await('SELECT `id`,`caseId` FROM `es_mdt_warrants` WHERE `id` = ?', { ref })
            if not w then return false, 'No such warrant' end
            MySQL.update.await('UPDATE `es_mdt_warrants` SET `caseId` = ? WHERE `id` = ?', { k and k.id or nil, ref })
            if k then caseLog(k.id, c, 'warrant', ('Warrant #%d'):format(ref)) end
            if w.caseId and (not k or w.caseId ~= k.id) then caseLog(w.caseId, c, 'warrant_off', ('Warrant #%d'):format(ref)) end
        else return false, 'report, evidence or warrant' end
        MDT.refresh('cases')
        return { caseId = k and k.id or nil, number = k and k.number or nil }
    end)

    -- a report page: its case and that case's evidence in full
    cb('reportCase', { rate = 300, burst = 6 }, function(c, d)
        local r = MySQL.single.await('SELECT `id`,`deptId`,`authorCharId`,`caseId` FROM `es_mdt_reports` WHERE `id` = ?', { id(d.reportId) or 0 })
        if not r then return false, 'No such report' end
        if not MDT.canSeeReport(c, r) then return false, 'That report is not yours to see' end
        local k = r.caseId and getCase(r.caseId)
        if not k then return { case = nil } end
        local ev = { items = {} }
        if evOn() then
            local okE, res = pcall(function() return EV():ForCase(k.id) end)
            if okE and type(res) == 'table' then ev = res end
        end
        local onReport = {}
        pcall(function() for _, x in ipairs(MySQL.query.await('SELECT `evidenceId` FROM `es_evidence_reports` WHERE `reportId` = ?', { r.id }) or {}) do onReport[#onReport + 1] = x.evidenceId end end)
        return { case = { id = k.id, number = k.number, title = k.title, status = k.status }, evidence = ev.items or {}, locker = ev.locker, onReport = onReport }
    end)

    -- a photo's full picture (case pages and reports show them)
    cb('evImage', { rate = 100, burst = 16 }, function(c, d)
        if not evOn() then return false, 'The evidence system (es_evidence) is not running' end
        local img = EV():Image(id(d.id))
        if not img then return false, 'No such photo' end
        return { id = id(d.id), image = img }
    end)

    -- evidence_manage: empty the lockers of old archived cases
    cb('casePurge', { perm = 'evidence_manage', write = true, rate = 5000, burst = 1 }, function(c, d)
        if not evOn() then return false, 'The evidence system (es_evidence) is not running' end
        local res, err = EV():PurgeArchived(c.charId, int(d.days, 0, 3650) > 0 and int(d.days, 1, 3650) or nil)
        if not res then return false, err end
        log(c, 'case_purge', ('%d lockers, %d bags, %d items (archived %d+ days)'):format(res.lockers, res.bags, res.items, res.days))
        return res
    end)
end
