local _ENV = ESAPP('doj'); -- es_doj records: the person view (everything the state has on someone), public records search, sealing and
-- expungement (court orders that es_mdt honors), and the summaries es_mdt shows on a profile.
local cb, str, id = DOJ.cb, DOJ.str, DOJ.id

-- ---------------------------------------------------------------- court orders on records
--- { [refId] = 'sealed' | 'expunged' } for a kind ('report' | 'case'); ids optional; charId optional (0 = everyone on it)
function DOJ.courtMarks(kind, ids, charId)
    local where, args = { '`kind` = ?' }, { kind }
    if type(ids) == 'table' and #ids > 0 then
        local list = {}
        for _, x in ipairs(ids) do x = id(x) if x and #list < 500 then list[#list + 1] = x end end
        if #list == 0 then return {} end
        where[#where + 1] = ('`refId` IN (%s)'):format(DOJ.marks(#list))
        for _, x in ipairs(list) do args[#args + 1] = x end
    end
    charId = id(charId)
    if charId then where[#where + 1] = '`charId` IN (?, 0)' args[#args + 1] = charId end
    local out = {}
    for _, r in ipairs(MySQL.query.await(('SELECT `refId`,`mode` FROM `es_doj_seals` WHERE %s'):format(table.concat(where, ' AND ')), args) or {}) do
        if out[r.refId] ~= 'expunged' then out[r.refId] = r.mode end
    end
    return out
end
exports('GetCourtMarks', function(kind, ids, charId)
    local ok, r = pcall(DOJ.courtMarks, tostring(kind or 'report'), ids, charId)
    return ok and r or {}
end)

--- What the court has on a person: convictions, money owed, probation, community service, (cases)
function DOJ.recordSummary(cid, opts)
    cid = id(cid)
    if not cid then return nil end
    opts = type(opts) == 'table' and opts or {}
    local conv = MySQL.single.await([[SELECT COALESCE(SUM(g.`category` = 'felony'), 0) AS `fel`, COUNT(*) AS `n` FROM `es_doj_charges` g JOIN `es_doj_cases` k ON k.`id` = g.`caseId`
        WHERE k.`defendantCharId` = ? AND k.`test` = 0 AND g.`disposition` = 'guilty'
        AND NOT EXISTS (SELECT 1 FROM `es_doj_seals` s WHERE s.`kind` = 'case' AND s.`refId` = k.`id` AND s.`mode` = 'expunged')]], { cid }) or {}
    local owed = MySQL.scalar.await("SELECT COALESCE(SUM(`amount`), 0) FROM `es_doj_fees` WHERE `charId` = ? AND `status` = 'unpaid' AND `kind` <> 'bail' AND `test` = 0", { cid }) or 0
    local prob = MySQL.scalar.await([[SELECT UNIX_TIMESTAMP(MAX(`createdAt` + INTERVAL `probationDays` DAY)) FROM `es_doj_sentences`
        WHERE `charId` = ? AND `status` = 'active' AND `probationDays` > 0 AND `createdAt` + INTERVAL `probationDays` DAY > NOW()]], { cid })
    local svc = MySQL.scalar.await("SELECT COALESCE(SUM(`total` - `done`), 0) FROM `es_doj_service` WHERE `charId` = ? AND `status` = 'active' AND `test` = 0", { cid }) or 0
    local out = { felonyConvictions = tonumber(conv.fel) or 0, convictions = tonumber(conv.n) or 0, owed = tonumber(owed) or 0,
        probation = tonumber(prob), service = tonumber(svc) or 0 }
    if opts.cases then
        local rows = MySQL.query.await([[SELECT k.`id`,k.`number`,k.`title`,k.`status`,k.`stage`,k.`verdict`,k.`bailStatus`,k.`bailAmount`,UNIX_TIMESTAMP(k.`createdAt`) AS `createdAt`,
            (SELECT UNIX_TIMESTAMP(MIN(h.`startsAt`)) FROM `es_doj_hearings` h WHERE h.`caseId` = k.`id` AND h.`status` = 'scheduled' AND h.`startsAt` > NOW()) AS `next`
            FROM `es_doj_cases` k WHERE k.`defendantCharId` = ? AND k.`test` = 0 AND k.`sealed` = 0 ORDER BY (k.`status` = 'open') DESC, k.`id` DESC LIMIT 15]], { cid }) or {}
        for _, r in ipairs(rows) do
            r.stageLabel = r.status == 'open' and DOJ.stageLabel(r.stage) or (r.status == 'dismissed' and 'Dismissed' or 'Closed')
            r.bail = (r.bailStatus ~= 'none') and (r.bailStatus == 'set' and ('$' .. r.bailAmount .. ' set') or r.bailStatus) or nil
            r.bailStatus, r.bailAmount, r.stage = nil, nil, nil
        end
        out.cases = rows
        -- 1.1.0: the sentences themselves (fine, jail, service, probation), newest first
        out.sentences = MySQL.query.await([[SELECT s.`id`,s.`caseId`,k.`number`,s.`source`,s.`fine`,s.`months`,s.`service`,s.`probationDays`,s.`restitution`,s.`jailed`,s.`status`,
            UNIX_TIMESTAMP(s.`createdAt`) AS `createdAt` FROM `es_doj_sentences` s JOIN `es_doj_cases` k ON k.`id` = s.`caseId`
            WHERE s.`charId` = ? AND k.`test` = 0 AND k.`sealed` = 0 ORDER BY s.`id` DESC LIMIT 10]], { cid }) or {}
        for _, x in ipairs(out.sentences) do x.jailed = x.jailed == 1 or x.jailed == true end
    end
    return out
end
exports('GetRecordSummary', function(cid, opts)
    local ok, r = pcall(DOJ.recordSummary, cid, opts)
    if not ok then print('^3[es_doj] GetRecordSummary: ' .. tostring(r) .. '^7') return nil end
    return r
end)

--- Seal, expunge or clear an order on one record. kind 'report' | 'case'. Returns true | false, why
function DOJ.applySeal(c, kind, refId, charId, mode, reason, petitionId, test)
    refId, charId = id(refId), id(charId) or 0
    if not refId then return false, 'Which record?' end
    if kind == 'report' then
        if not MySQL.scalar.await('SELECT 1 FROM `es_mdt_reports` WHERE `id` = ?', { refId }) then return false, 'No such MDT report' end
        if charId > 0 and not MySQL.scalar.await('SELECT 1 FROM `es_mdt_report_people` WHERE `reportId` = ? AND `charId` = ?', { refId, charId }) then return false, 'That person is not on the report' end
    elseif kind == 'case' then
        if not DOJ.caseRow(refId) then return false, 'No such court case' end
    else return false, 'report or case' end
    if mode == 'clear' then
        MySQL.update.await('DELETE FROM `es_doj_seals` WHERE `kind` = ? AND `refId` = ? AND `charId` = ?', { kind, refId, charId })
        if kind == 'case' then MySQL.update.await('UPDATE `es_doj_cases` SET `sealed` = 0, `sealedBy` = NULL, `sealedAt` = NULL, `sealReason` = NULL WHERE `id` = ?', { refId }) end
    else
        mode = mode == 'expunged' and 'expunged' or 'sealed'
        MySQL.insert.await([[INSERT INTO `es_doj_seals` (`kind`,`refId`,`charId`,`mode`,`reason`,`byCharId`,`petitionId`,`test`) VALUES (?,?,?,?,?,?,?,?)
            ON DUPLICATE KEY UPDATE `mode` = VALUES(`mode`), `reason` = VALUES(`reason`), `byCharId` = VALUES(`byCharId`), `petitionId` = COALESCE(VALUES(`petitionId`), `petitionId`)]],
            { kind, refId, charId, mode, str(reason, 300), c and c.charId or nil, petitionId, test and 1 or 0 })
        if kind == 'case' then
            MySQL.update.await('UPDATE `es_doj_cases` SET `sealed` = 1, `sealedBy` = ?, `sealedAt` = NOW(), `sealReason` = ? WHERE `id` = ?', { c and c.charId or nil, str(reason, 300), refId })
        end
        -- an expunged report's unpaid fines go with it (not on a test)
        if mode == 'expunged' and kind == 'report' and not test and GetResourceState('es_mdt') == 'started' then
            local args, extra = { refId }, ''
            if charId > 0 then extra = ' AND `charId` = ?' args[2] = charId end
            for _, f in ipairs(MySQL.query.await("SELECT `id` FROM `es_mdt_fines` WHERE `reportId` = ? AND `status` = 'unpaid'" .. extra, args) or {}) do
                pcall(function() exports.es_mdt:VoidFine(f.id, c and c.charId) end)
            end
        end
    end
    DOJ.log(kind == 'case' and refId or nil, c, 'record_' .. mode, ('%s #%d%s: %s%s'):format(kind, refId, charId > 0 and (' (' .. (DOJ.nameOf(charId) or ('#' .. charId)) .. ')') or '',
        mode, (reason and reason ~= '') and (' — ' .. tostring(reason):sub(1, 200)) or ''))
    return true
end

-- ---------------------------------------------------------------- the person view
local function personView(c, cid)
    local p = MySQL.single.await([[SELECT c.`charId`,c.`firstName`,c.`lastName`,DATE_FORMAT(c.`dateOfBirth`,'%Y-%m-%d') AS `dob`,c.`gender`,
        (SELECT ph.`phoneNumber` FROM `phone_numbers` ph WHERE ph.`charId` = c.`charId` AND ph.`retiredAt` IS NULL LIMIT 1) AS `phone`
        FROM `characters` c WHERE c.`charId` = ? AND c.`deleted` IS NULL]], { cid })
    if not p then return nil end
    p.name = p.firstName .. ' ' .. p.lastName
    local mug = MySQL.single.await('SELECT m.`image` FROM `es_mdt_profiles` pr JOIN `es_mdt_mugshots` m ON m.`id` = pr.`mugshotId` WHERE pr.`charId` = ?', { cid })
    if mug and type(mug.image) == 'string' and mug.image:sub(1, 11) == 'data:image/' then p.photo = mug.image
    else
        local img = MySQL.single.await('SELECT `image` FROM `character_portraits` WHERE `charId` = ?', { cid })
        p.photo = img and type(img.image) == 'string' and #img.image < 400000 and img.image:sub(1, 11) == 'data:image/' and img.image or nil
    end
    p.summary = DOJ.recordSummary(cid)
    local seeSealed = c.staff or c.r.judge or c.r.seal
    p.cases = MySQL.query.await(([[SELECT `id`,`number`,`kind`,`title`,`status`,`stage`,`verdict`,`sealed`,`test`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt`
        FROM `es_doj_cases` WHERE (`defendantCharId` = ? OR `plaintiffCharId` = ?) %s ORDER BY `id` DESC LIMIT 60]]):format(seeSealed and '' or 'AND `sealed` = 0'), { cid, cid }) or {}
    local caseMarks = DOJ.courtMarks('case', nil, cid)
    for _, k in ipairs(p.cases) do k.sealed = k.sealed == 1 k.test = k.test == 1 k.court = caseMarks[k.id] k.stageLabel = DOJ.stageLabel(k.stage) end
    -- the police record (es_mdt): reports, with the court's marks; sealed and expunged ones only for those who may
    p.reports = MySQL.query.await([[SELECT r.`id`,r.`type`,r.`title`,pp.`role`,d.`short` AS `dept`,UNIX_TIMESTAMP(r.`createdAt`) AS `createdAt`,
        (SELECT GROUP_CONCAT(CONCAT(g.`code`, IF(g.`count` > 1, CONCAT(' x', g.`count`), '')) ORDER BY g.`id` SEPARATOR ', ') FROM `es_mdt_report_charges` g WHERE g.`reportId` = r.`id` AND g.`charId` = pp.`charId`) AS `charges`,
        (SELECT k.`id` FROM `es_doj_cases` k WHERE k.`reportId` = r.`id` AND k.`defendantCharId` = pp.`charId` ORDER BY k.`id` DESC LIMIT 1) AS `courtCaseId`
        FROM `es_mdt_report_people` pp JOIN `es_mdt_reports` r ON r.`id` = pp.`reportId` LEFT JOIN `es_departments` d ON d.`id` = r.`deptId`
        WHERE pp.`charId` = ? ORDER BY r.`id` DESC LIMIT 80]], { cid }) or {}
    local marks = DOJ.courtMarks('report', nil, cid)
    local shown = {}
    for _, r in ipairs(p.reports) do
        r.court = marks[r.id]
        if not r.court or seeSealed then shown[#shown + 1] = r end
    end
    p.reports, p.hiddenReports = shown, #p.reports - #shown
    p.warrants = MySQL.query.await([[SELECT `id`,`kind`,`reason`,`status`,`judgeName`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt`,UNIX_TIMESTAMP(`expiresAt`) AS `expiresAt`
        FROM `es_mdt_warrants` WHERE `charId` = ? AND `status` IN ('active','requested') ORDER BY `id` DESC LIMIT 20]], { cid }) or {}
    p.mdtFines = MySQL.query.await([[SELECT `id`,`amount`,`reason`,`status`,`reportId`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt` FROM `es_mdt_fines`
        WHERE `charId` = ? AND `status` = 'unpaid' ORDER BY `id` DESC LIMIT 30]], { cid }) or {}
    p.fees = MySQL.query.await([[SELECT f.`id`,f.`kind`,f.`amount`,f.`reason`,f.`status`,f.`caseId`,f.`test`,UNIX_TIMESTAMP(f.`dueAt`) AS `dueAt`,UNIX_TIMESTAMP(f.`createdAt`) AS `createdAt`
        FROM `es_doj_fees` f WHERE f.`charId` = ? ORDER BY FIELD(f.`status`,'unpaid','paid','refunded','void'), f.`id` DESC LIMIT 40]], { cid }) or {}
    p.service = MySQL.query.await('SELECT `id`,`caseId`,`total`,`done`,`status`,`note` FROM `es_doj_service` WHERE `charId` = ? ORDER BY `id` DESC LIMIT 10', { cid }) or {}
    p.sentences = MySQL.query.await(([[SELECT s.`id`,s.`caseId`,k.`number`,s.`source`,s.`fine`,s.`months`,s.`service`,s.`probationDays`,s.`restitution`,s.`status`,s.`jailed`,
        UNIX_TIMESTAMP(s.`createdAt`) AS `createdAt` FROM `es_doj_sentences` s JOIN `es_doj_cases` k ON k.`id` = s.`caseId` WHERE s.`charId` = ? %s ORDER BY s.`id` DESC LIMIT 20]]):format(seeSealed and '' or 'AND k.`sealed` = 0'), { cid }) or {}
    p.bar = DOJ.barOf(cid)
    p.businesses = MySQL.query.await("SELECT `id`,`licenseNo`,`name`,`kind`,`status`,UNIX_TIMESTAMP(`expiresAt`) AS `expiresAt` FROM `es_doj_businesses` WHERE `ownerCharId` = ? ORDER BY `id` DESC", { cid }) or {}
    if GetResourceState('es_mdt') == 'started' then
        local ok, st = pcall(function() return exports.es_mdt:GetPermitStatus(cid) end)
        p.permit = ok and st or nil
    end
    do   -- 2.0.0: the jail bridge
        local ok, jailed, left = pcall(EsJail.isJailed, cid)
        p.jailed = ok and jailed or false
        p.jailLeft = ok and left or nil
    end
    p.lawyers = MySQL.query.await("SELECT `attorneyCharId` AS `charId` FROM `es_doj_clients` WHERE `clientCharId` = ? AND `status` = 'active'", { cid }) or {}
    local ln = {}
    for _, l in ipairs(p.lawyers) do ln[#ln + 1] = l.charId end
    local names = DOJ.namesOf(ln)
    for _, l in ipairs(p.lawyers) do l.name = names[l.charId] end
    p.canSeal = (c.staff or c.r.seal or c.r.judge) and not c.readOnly
    p.canCharge = (c.r.cases or c.r.prosecutor or c.r.judge) and not c.readOnly
    return p
end
DOJ.personView = personView

function DOJ.registerRecords()
    cb('people', { rate = 250, burst = 8 }, function(_, d)
        local q = str(d.q, 40)
        if #q < 2 then return {} end
        local rows
        local n = tonumber(q)
        if n then
            rows = MySQL.query.await([[SELECT `charId`,`firstName`,`lastName`,DATE_FORMAT(`dateOfBirth`,'%Y-%m-%d') AS `dob` FROM `characters` WHERE `deleted` IS NULL AND `charId` = ? LIMIT 1]], { n }) or {}
        else
            rows = MySQL.query.await([[SELECT `charId`,`firstName`,`lastName`,DATE_FORMAT(`dateOfBirth`,'%Y-%m-%d') AS `dob` FROM `characters`
                WHERE `deleted` IS NULL AND CONCAT(`firstName`,' ',`lastName`) LIKE CONCAT('%', ?, '%') ORDER BY `lastName`,`firstName` LIMIT 15]], { q }) or {}
        end
        for _, r in ipairs(rows) do r.name = r.firstName .. ' ' .. r.lastName end
        return rows
    end)

    cb('person', { rate = 300, burst = 6 }, function(c, d)
        local cid = id(d.charId)
        if not cid then return false, 'Pick a person' end
        return personView(c, cid) or false, 'No such person'
    end)

    -- the camera roll (es_evidence): pick a photo for an exhibit
    cb('roll', { rate = 800, burst = 4 }, function(c)
        if GetResourceState('es_evidence') ~= 'started' then return {} end
        return exports.es_evidence:Roll(c.charId) or {}
    end)
    cb('rollImage', { rate = 200, burst = 12 }, function(c, d)
        if GetResourceState('es_evidence') ~= 'started' then return false, 'No camera roll' end
        return exports.es_evidence:RollImage(c.charId, id(d.id)) or false, 'No such photo'
    end)

    cb('recordSeal', { role = { 'seal', 'judge' }, write = true, why = 'Only judges and the records office seal records' }, function(c, d)
        local mode = DOJ.oneOf(d.mode, { 'sealed', 'expunged', 'clear' }, nil)
        if not mode then return false, 'sealed, expunged or clear' end
        local reason = str(d.reason, 300)
        if mode ~= 'clear' and reason == '' then return false, 'Give the reason (court order)' end
        local kind = d.kind == 'case' and 'case' or 'report'
        local ok, why = DOJ.applySeal(c, kind, d.refId, d.charId, mode, reason, nil, false)
        if not ok then return false, why end
        if id(d.charId) and mode ~= 'clear' then
            DOJ.notice(id(d.charId), ('Record %s'):format(mode), ('A court order %s %s #%d.'):format(mode, kind == 'case' and 'court case' or 'police report', id(d.refId)), kind == 'case' and id(d.refId) or nil, 'record', c.charId)
        end
        DOJ.refresh('records')
        return true
    end)
end
