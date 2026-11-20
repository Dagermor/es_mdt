local _ENV = ESAPP('doj'); -- es_doj cases: court cases (criminal, traffic, civil, appeals, petitions), their charges, hearings, filings and
-- exhibits, transcripts, plea deals, verdicts and sentences, bail and bond, appeals, sealing, subpoenas and bench
-- warrants. Everything is decided here; the page only asks. Loaded before server/main.lua; DOJ.registerCases() runs it.
local WC, cb, str, int, id = DOJ.WC, DOJ.cb, DOJ.str, DOJ.int, DOJ.id
local S = Config.Sentence or {}

local function now() return os.time() end
local function isTest(k) return k and (k.test == 1 or k.test == true) end
local function closed(k) return k.status ~= 'open' end
DOJ.isTest = isTest

-- ---------------------------------------------------------------- numbers, charges
local function numberFor(kind, cid)
    local p = (DOJ.KINDS[kind] or {}).prefix or 'CR'
    return ('%s-%s-%04d'):format(p, os.date('%Y'), cid)
end

--- Charges from the penal code: list = { { penalId, count } } -> rows ready to insert
local function chargesFrom(list)
    local ids, want = {}, {}
    for _, x in ipairs(type(list) == 'table' and list or {}) do
        local pid = id(type(x) == 'table' and x.penalId or x)
        if pid and #ids < 40 and not want[pid] then ids[#ids + 1] = pid want[pid] = int(type(x) == 'table' and x.count or 1, 1, 20) end
    end
    if #ids == 0 then return {} end
    local rows = MySQL.query.await(('SELECT `id`,`code`,`title`,`category`,`fine`,`months` FROM `es_penal_code` WHERE `id` IN (%s)'):format(DOJ.marks(#ids)), ids) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = { penalId = r.id, code = r.code, title = r.title, category = r.category, count = want[r.id], fine = r.fine, months = r.months }
    end
    return out
end
DOJ.chargesFrom = chargesFrom

--- The charges an MDT report put on one person (to bring them to court)
function DOJ.reportCharges(reportId, charId)
    return MySQL.query.await([[SELECT `penalId`,`code`,`title`,`category`,`count`,`fine`,`months` FROM `es_mdt_report_charges`
        WHERE `reportId` = ? AND `charId` = ? ORDER BY `id`]], { reportId, charId }) or {}
end

local function insertCharges(caseId, rows)
    for _, r in ipairs(rows) do
        MySQL.insert.await([[INSERT INTO `es_doj_charges` (`caseId`,`penalId`,`code`,`title`,`category`,`count`,`fine`,`months`) VALUES (?,?,?,?,?,?,?,?)]],
            { caseId, r.penalId, str(r.code, 16), str(r.title, 120), str(r.category, 16), int(r.count, 1, 20), int(r.fine, 0, 10000000), int(r.months, 0, 3000) })
    end
end

local function chargeList(caseId)
    return MySQL.query.await('SELECT `id`,`penalId`,`code`,`title`,`category`,`count`,`fine`,`months`,`plea`,`disposition` FROM `es_doj_charges` WHERE `caseId` = ? ORDER BY `id`', { caseId }) or {}
end
DOJ.chargeList = chargeList
DOJ.insertCharges = insertCharges
DOJ.numberFor = numberFor
DOJ.closed = closed

-- ---------------------------------------------------------------- create
--- d: kind, title, summary, defendantCharId, plaintiffCharId, plaintiffName, reportId, mdtCaseId, judgeCharId, prosecutorCharId,
--- charges = { {penalId,count} }, importReport = bool, parentId, test
function DOJ.createCase(c, d)
    local kind = DOJ.KINDS[d.kind] and d.kind or 'criminal'
    local title = str(d.title, 160)
    local def = id(d.defendantCharId)
    if kind ~= 'petition' and kind ~= 'civil' and not def then return false, 'Pick the defendant' end
    if def and not DOJ.charExists(def) then return false, 'No such person' end
    local pl = id(d.plaintiffCharId)
    local plName = str(d.plaintiffName, 80)
    if kind == 'civil' and not pl and plName == '' then return false, 'Name the plaintiff' end
    local rid = id(d.reportId)
    if rid and not MySQL.scalar.await('SELECT 1 FROM `es_mdt_reports` WHERE `id` = ?', { rid }) then return false, 'No such MDT report' end
    local mdtCase = id(d.mdtCaseId)
    if mdtCase and not MySQL.scalar.await('SELECT 1 FROM `es_mdt_cases` WHERE `id` = ?', { mdtCase }) then return false, 'No such MDT case' end
    if rid and not mdtCase then mdtCase = MySQL.scalar.await('SELECT `caseId` FROM `es_mdt_reports` WHERE `id` = ?', { rid }) end
    if title == '' then
        local who = def and DOJ.nameOf(def) or '?'
        if kind == 'civil' then title = ('%s v. %s'):format(pl and DOJ.nameOf(pl) or plName, who)
        elseif kind == 'petition' then title = ('In re %s'):format(who)
        else title = ('State of San Andreas v. %s'):format(who) end
    end
    local rows = chargesFrom(d.charges)
    if rid and def and d.importReport ~= false and #rows == 0 then rows = DOJ.reportCharges(rid, def) end
    local tmp = ('TMP-%d-%d'):format(now(), math.random(100000, 999999))
    local mineAsProsecutor = (c and c.r.prosecutor and not c.staff) and c.charId or nil
    local cid = MySQL.insert.await([[INSERT INTO `es_doj_cases` (`number`,`kind`,`title`,`summary`,`defendantCharId`,`plaintiffCharId`,`plaintiffName`,`judgeCharId`,
        `prosecutorCharId`,`mdtCaseId`,`reportId`,`parentId`,`test`,`createdBy`) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)]],
        { tmp, kind, title, str(d.summary, 4000), def, pl, (not pl and plName ~= '') and plName or nil,
          id(d.judgeCharId), id(d.prosecutorCharId) or (kind ~= 'civil' and mineAsProsecutor or nil), mdtCase, rid, id(d.parentId), d.test and 1 or 0, c and c.charId or nil })
    if not cid then return false, 'Could not file the case' end
    local number = numberFor(kind, cid)
    MySQL.update.await('UPDATE `es_doj_cases` SET `number` = ? WHERE `id` = ?', { number, cid })
    insertCharges(cid, rows)
    DOJ.log(cid, c, 'filed', ('%s filed: %s (%d charge%s)'):format(number, title, #rows, #rows == 1 and '' or 's'))
    if def and kind ~= 'petition' then
        DOJ.notice(def, ('Case %s filed against you'):format(number), ('%s. You will be told of every hearing. You may hire a lawyer (/%s, Lawyers) or ask the court for a public defender.')
            :format(title, Config.PortalCommand or 'court'), cid, 'case', c and c.charId, d.test)
    end
    if pl and kind == 'civil' then DOJ.notice(pl, ('Your case %s was filed'):format(number), title, cid, 'case', c and c.charId, d.test) end
    DOJ.refresh('cases')
    return { id = cid, number = number }
end

-- ---------------------------------------------------------------- money: fees and bail
function DOJ.addFee(charId, kind, amount, reason, caseId, by, test, dueDays)
    if kind == 'bail' and not DOJ.bailOn() then return nil end   -- 2.3.1: no bail
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 or not charId then return nil end
    dueDays = tonumber(dueDays) or 0
    local fid = MySQL.insert.await([[INSERT INTO `es_doj_fees` (`charId`,`caseId`,`kind`,`amount`,`reason`,`dueAt`,`createdBy`,`test`)
        VALUES (?,?,?,?,?,IF(? > 0, NOW() + INTERVAL ? DAY, NULL),?,?)]], { charId, caseId, kind, amount, tostring(reason or ''):sub(1, 200), dueDays, dueDays, by, test and 1 or 0 })
    DOJ.refresh('fees')
    return fid
end

function DOJ.refundBail(k, c, why)
    local f = k.bailFeeId and MySQL.single.await("SELECT `id`,`amount`,`paidBy`,`method`,`status`,`test` FROM `es_doj_fees` WHERE `id` = ?", { k.bailFeeId })
    if not f or f.status ~= 'paid' or f.method == 'bond' then return false end
    local n = MySQL.update.await("UPDATE `es_doj_fees` SET `status` = 'refunded' WHERE `id` = ? AND `status` = 'paid'", { f.id })
    if (tonumber(n) or 0) < 1 then return false end
    if f.test ~= 1 and f.paidBy then
        local ok, err = WC:PayPlayer({ charId = f.paidBy }, f.amount, { method = 'bank', reason = ('Bail returned: %s'):format(k.number) })
        if not ok then
            print(('^1[es_doj] bail refund %s ($%d to char %s) failed: %s; left as paid so it can be returned later^7'):format(k.number, f.amount, tostring(f.paidBy), tostring(err)))
            MySQL.update.await("UPDATE `es_doj_fees` SET `status` = 'paid' WHERE `id` = ? AND `status` = 'refunded'", { f.id })
            return false
        end
    end
    MySQL.update.await("UPDATE `es_doj_cases` SET `bailStatus` = 'returned' WHERE `id` = ?", { k.id })
    DOJ.log(k.id, c, 'bail_returned', ('$%d bail returned (%s)'):format(f.amount, why or 'case ended'))
    if f.paidBy then DOJ.notice(f.paidBy, ('Bail returned: %s'):format(k.number), ('$%d was paid back to your bank.'):format(f.amount), k.id, 'bail', c and c.charId, isTest(k)) end
    return true
end

-- ---------------------------------------------------------------- close, sentence
function DOJ.closeCase(k, status, c, reason)
    status = status == 'dismissed' and 'dismissed' or 'closed'
    MySQL.update.await("UPDATE `es_doj_cases` SET `status` = ?, `stage` = 'closed', `closedAt` = NOW() WHERE `id` = ?", { status, k.id })
    MySQL.update.await("UPDATE `es_doj_hearings` SET `status` = 'cancelled' WHERE `caseId` = ? AND `status` = 'scheduled'", { k.id })
    MySQL.update.await("UPDATE `es_doj_pleas` SET `status` = 'withdrawn' WHERE `caseId` = ? AND `status` IN ('offered','accepted')", { k.id })
    if k.bailStatus == 'posted' then DOJ.refundBail(k, c, status) end
    if k.bailFeeId then MySQL.update.await("UPDATE `es_doj_fees` SET `status` = 'void' WHERE `id` = ? AND `status` = 'unpaid'", { k.bailFeeId }) end
    DOJ.log(k.id, c, status, reason and reason ~= '' and reason or (status == 'dismissed' and 'Case dismissed' or 'Case closed'))
    if k.defendantCharId then
        DOJ.notice(k.defendantCharId, ('Case %s %s'):format(k.number, status == 'dismissed' and 'dismissed' or 'closed'), reason, k.id, 'case', c and c.charId, isTest(k))
    end
    DOJ.refresh('cases')
end

--- Void what an acquittal / reversal takes away: unpaid court fines on the case, MDT fines on its report, community service
function DOJ.undoPenalties(k, c, why)
    MySQL.update.await("UPDATE `es_doj_fees` SET `status` = 'void' WHERE `caseId` = ? AND `status` = 'unpaid' AND `kind` IN ('fine','restitution')", { k.id })
    MySQL.update.await("UPDATE `es_doj_service` SET `status` = 'void' WHERE `caseId` = ? AND `status` = 'active'", { k.id })
    MySQL.update.await("UPDATE `es_doj_sentences` SET `status` = 'void' WHERE `caseId` = ?", { k.id })
    if k.reportId and k.defendantCharId and GetResourceState('es_mdt') == 'started' then
        for _, f in ipairs(MySQL.query.await("SELECT `id` FROM `es_mdt_fines` WHERE `reportId` = ? AND `charId` = ? AND `status` = 'unpaid'", { k.reportId, k.defendantCharId }) or {}) do
            pcall(function() exports.es_mdt:VoidFine(f.id, c and c.charId) end)
        end
    end
    DOJ.log(k.id, c, 'penalties_void', why)
    if DOJ.serviceChanged then DOJ.serviceChanged(k.defendantCharId) end
end

--- s = { fine, months, service, probationDays, restitution, notes }; source 'verdict' | 'plea' | 'judgment'
function DOJ.applySentence(k, s, c, source)
    local cid = k.defendantCharId
    if not cid then return false, 'The case has no defendant' end
    local fine = int(s.fine, 0, S.maxFine or 1000000)
    local months = int(s.months, 0, S.maxMonths or 300)
    local service = int(s.service, 0, S.maxService or 100)
    local prob = int(s.probationDays, 0, S.maxProbationDays or 365)
    local rest = int(s.restitution, 0, S.maxFine or 1000000)
    local notes = str(s.notes, 1000)
    local test = isTest(k)
    local due = (Config.Fees or {}).dueDays
    local feeId = fine > 0 and DOJ.addFee(cid, 'fine', fine, ('Court fine: %s'):format(k.number), k.id, c and c.charId, test, due) or nil
    if rest > 0 then DOJ.addFee(cid, 'restitution', rest, ('Restitution: %s'):format(k.number), k.id, c and c.charId, test, due) end
    local svcId
    if service > 0 then
        svcId = MySQL.insert.await('INSERT INTO `es_doj_service` (`charId`,`caseId`,`total`,`note`,`createdBy`,`test`) VALUES (?,?,?,?,?,?)',
            { cid, k.id, service, ('Sentence: %s'):format(k.number), c and c.charId, test and 1 or 0 })
    end
    local jailed, jailWhy = false, nil
    if months > 0 then
        if test then
            jailWhy = 'test case: nobody jailed'
        else
            -- 2.0.0: the jail bridge (any jail script; none = recorded in the MDT only)
            local ok, res = pcall(EsJail.send, { charId = cid, months = months, origin = 'court', courtCase = k.number,
                reason = ('Court sentence %s'):format(k.number), byCharId = c and c.charId, bySource = c and c.source })
            jailed = ok and res.ok == true
            if not jailed then jailWhy = ok and tostring(res.why or 'refused') or tostring(res) end
        end
    end
    local sid = MySQL.insert.await([[INSERT INTO `es_doj_sentences` (`caseId`,`charId`,`source`,`fine`,`months`,`service`,`probationDays`,`restitution`,`notes`,`judgeCharId`,`feeId`,`serviceId`,`jailed`)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)]], { k.id, cid, source or 'verdict', fine, months, service, prob, rest, notes, c and c.charId, feeId, svcId, jailed and 1 or 0 })
    local parts = {}
    if fine > 0 then parts[#parts + 1] = ('$%d fine'):format(fine) end
    if months > 0 then parts[#parts + 1] = ('%d months%s'):format(months, jailed and '' or (' (not jailed: ' .. tostring(jailWhy) .. ')')) end
    if service > 0 then parts[#parts + 1] = ('%d community service tasks'):format(service) end
    if prob > 0 then parts[#parts + 1] = ('%d days probation'):format(prob) end
    if rest > 0 then parts[#parts + 1] = ('$%d %s'):format(rest, source == 'judgment' and 'award' or 'restitution') end
    local text = #parts > 0 and table.concat(parts, ', ') or 'no penalty'
    DOJ.log(k.id, c, 'sentence', ('Sentence (%s): %s'):format(source or 'verdict', text))
    DOJ.notice(cid, ('Sentence in %s'):format(k.number), ('%s.%s%s'):format(text, (fine + rest) > 0 and (' Pay at the courthouse (/' .. (Config.PortalCommand or 'court') .. ', Payments).') or '',
        service > 0 and ' Community service: your first spot is marked on the map.' or ''), k.id, 'sentence', c and c.charId, test)
    if service > 0 and DOJ.serviceChanged then DOJ.serviceChanged(cid) end
    return { id = sid, jailed = jailed, jailWhy = jailWhy, text = text }
end

-- ---------------------------------------------------------------- reading a case
local function caseFull(c, k, side, access)
    local ids = { k.defendantCharId, k.plaintiffCharId, k.judgeCharId, k.prosecutorCharId, k.defenseCharId, k.createdBy }
    k.charges = chargeList(k.id)
    k.hearings = MySQL.query.await([[SELECT h.`id`,h.`kind`,h.`title`,UNIX_TIMESTAMP(h.`startsAt`) AS `startsAt`,h.`minutes`,h.`room`,h.`judgeCharId`,h.`status`,h.`outcome`,
        (SELECT COUNT(*) FROM `es_doj_transcripts` t WHERE t.`hearingId` = h.`id`) AS `lines` FROM `es_doj_hearings` h WHERE h.`caseId` = ? ORDER BY h.`startsAt`]], { k.id }) or {}
    for _, h in ipairs(k.hearings) do ids[#ids + 1] = h.judgeCharId end
    if access == 'full' then
        local where = DOJ.visibleFilingSql(c, k, side)
        k.filings = MySQL.query.await(([[SELECT `id`,`kind`,`title`,`body`,(`image` IS NOT NULL) AS `hasImage`,`evidenceId`,`exhibitNo`,`side`,`visibility`,`status`,`ruling`,`ruledBy`,
            `byCharId`,`byLabel`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt`,UNIX_TIMESTAMP(`ruledAt`) AS `ruledAt` FROM `es_doj_filings` WHERE `caseId` = ? AND %s ORDER BY `id`]]):format(where), { k.id }) or {}
        for _, f in ipairs(k.filings) do f.hasImage = f.hasImage == 1 or f.hasImage == true ids[#ids + 1] = f.ruledBy end
        k.pleas = MySQL.query.await([[SELECT `id`,`terms`,`fine`,`months`,`service`,`probationDays`,`chargesJson`,`status`,`offeredBy`,`offeredByLabel`,`respondedBy`,`decidedBy`,`note`,
            UNIX_TIMESTAMP(`createdAt`) AS `createdAt`,UNIX_TIMESTAMP(`decidedAt`) AS `decidedAt` FROM `es_doj_pleas` WHERE `caseId` = ? ORDER BY `id` DESC]], { k.id }) or {}
        for _, p in ipairs(k.pleas) do
            local ok, list = pcall(json.decode, p.chargesJson or '[]') p.charges = ok and list or {} p.chargesJson = nil
            ids[#ids + 1] = p.respondedBy ids[#ids + 1] = p.decidedBy
        end
        k.subpoenas = MySQL.query.await([[SELECT `id`,`hearingId`,`charId`,`kind`,`details`,`status`,`requestedBy`,`issuedBy`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt`
            FROM `es_doj_subpoenas` WHERE `caseId` = ? ORDER BY `id`]], { k.id }) or {}
        for _, s in ipairs(k.subpoenas) do ids[#ids + 1] = s.charId ids[#ids + 1] = s.requestedBy end
        k.log = MySQL.query.await('SELECT `id`,`what`,`detail`,`byLabel`,UNIX_TIMESTAMP(`createdAt`) AS `at` FROM `es_doj_log` WHERE `caseId` = ? AND (? = 1 OR `what` NOT LIKE \'bail%\') ORDER BY `id` DESC LIMIT 80', { k.id, DOJ.bailOn() and 1 or 0 }) or {}
        k.fees = MySQL.query.await([[SELECT `id`,`charId`,`kind`,`amount`,`reason`,`status`,`method`,UNIX_TIMESTAMP(`dueAt`) AS `dueAt`,UNIX_TIMESTAMP(`paidAt`) AS `paidAt`
            FROM `es_doj_fees` WHERE `caseId` = ? AND (? = 1 OR `kind` <> 'bail') ORDER BY `id`]], { k.id, DOJ.bailOn() and 1 or 0 }) or {}
        k.sentences = MySQL.query.await([[SELECT `id`,`source`,`fine`,`months`,`service`,`probationDays`,`restitution`,`notes`,`jailed`,`status`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt`
            FROM `es_doj_sentences` WHERE `caseId` = ? ORDER BY `id`]], { k.id }) or {}
        -- the police side: the MDT report and the MDT case's evidence (discovery)
        if k.reportId then
            k.report = MySQL.single.await([[SELECT r.`id`,r.`type`,r.`title`,r.`body`,r.`location`,r.`authorCharId`,UNIX_TIMESTAMP(r.`createdAt`) AS `createdAt`,d.`short` AS `dept`
                FROM `es_mdt_reports` r LEFT JOIN `es_departments` d ON d.`id` = r.`deptId` WHERE r.`id` = ?]], { k.reportId })
            if k.report then ids[#ids + 1] = k.report.authorCharId end
        end
        if k.mdtCaseId then
            k.mdtCase = MySQL.single.await('SELECT `id`,`number`,`title`,`status` FROM `es_mdt_cases` WHERE `id` = ?', { k.mdtCaseId })
            if GetResourceState('es_evidence') == 'started' then
                local ok, ev = pcall(function() return exports.es_evidence:ForCase(k.mdtCaseId) end)
                if ok and type(ev) == 'table' then
                    k.evidence = {}
                    for _, e in ipairs(ev.items or {}) do
                        k.evidence[#k.evidence + 1] = { id = e.id, code = e.code, kind = e.kind, label = e.label or e.itemLabel or e.kind, status = e.status,
                            result = e.result, note = e.note, hasPhoto = e.kind == 'photo', at = e.collectedAt or e.createdAt }
                    end
                end
            end
        end
        k.appeals = MySQL.query.await("SELECT `id`,`number`,`status`,`verdict` FROM `es_doj_cases` WHERE `parentId` = ? ORDER BY `id`", { k.id }) or {}
        if k.parentId then k.parent = MySQL.single.await('SELECT `id`,`number`,`title`,`verdict`,`status` FROM `es_doj_cases` WHERE `id` = ?', { k.parentId }) end
    else
        k.summary = nil
        k.filings = MySQL.query.await([[SELECT `id`,`kind`,`title`,`body`,`side`,`status`,`byLabel`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt` FROM `es_doj_filings`
            WHERE `caseId` = ? AND `visibility` = 'public' ORDER BY `id`]], { k.id }) or {}
    end
    local names = DOJ.namesOf(ids)
    k.defendant = k.defendantCharId and names[k.defendantCharId] or nil
    k.plaintiff = k.plaintiffCharId and names[k.plaintiffCharId] or k.plaintiffName
    k.judge, k.prosecutor, k.defense = names[k.judgeCharId or 0], names[k.prosecutorCharId or 0], names[k.defenseCharId or 0]
    for _, h in ipairs(k.hearings) do h.judge = names[h.judgeCharId or 0] end
    for _, s in ipairs(k.subpoenas or {}) do s.name = names[s.charId] s.requestedByName = names[s.requestedBy or 0] end
    for _, p in ipairs(k.pleas or {}) do p.respondedByName = names[p.respondedBy or 0] p.decidedByName = names[p.decidedBy or 0] end
    for _, f in ipairs(k.filings or {}) do f.ruledByName = names[f.ruledBy or 0] end
    if k.report then k.report.author = names[k.report.authorCharId] end
    k.sealed = k.sealed == 1 or k.sealed == true
    k.test = isTest(k)
    k.side, k.access = side, access
    k.bond = math.ceil((k.bailAmount or 0) * ((Config.Bail or {}).bondPercent or 10) / 100)
    if not DOJ.bailOn() then k.bond, k.bailStatus, k.bailAmount, k.bailFeeId = nil, nil, nil, nil end
    -- what this person may do (the page shows buttons; the server checks again)
    local open = not closed(k)
    local judge = c.staff or (c.r.judge and (not k.judgeCharId or k.judgeCharId == c.charId))
    local W = not c.readOnly and access == 'full'
    k.can = {
        edit = W and (c.r.court or side == 'prosecution' or side == 'court'),
        stage = W and open and (c.r.court or side == 'court'),
        assignJudge = W and (c.r.judge or c.r.clerk),
        assignProsecutor = W and (c.r.judge or c.r.clerk or c.r.prosecutor),
        assignDefense = W and (c.r.judge or c.r.clerk or c.r.defender or c.r.attorney),
        charges = W and open and k.verdict == 'none' and (side == 'prosecution' or judge),
        pleaEntry = W and open and (c.r.judge or c.r.clerk),
        schedule = W and open and (c.r.clerk or c.r.cases or c.r.judge),
        file = W and side ~= nil,
        order = W and side == 'court',
        rule = W and judge,
        plea = W and open and side == 'prosecution' and k.kind ~= 'civil' and k.kind ~= 'appeal' and k.verdict == 'none',
        pleaRespond = W and open and (side == 'defense' or c.staff),
        pleaApprove = W and open and judge,
        verdict = W and open and judge and k.kind ~= 'appeal' and (k.verdict == 'none'),
        sentence = W and open and judge and (k.verdict == 'guilty' or k.verdict == 'plaintiff'),
        bail = DOJ.bailOn() and W and open and judge and k.kind ~= 'civil' and k.defendantCharId ~= nil,
        close = W and open and (judge or (side == 'prosecution' and k.verdict == 'none')),
        appeal = W and not open and k.kind ~= 'appeal' and (side == 'defense' or side == 'prosecution' or c.staff),
        appealRule = W and open and k.kind == 'appeal' and judge,
        seal = W and (c.r.seal or c.r.judge),
        subpoena = W and open and side ~= nil,
        subpoenaIssue = W and judge,
        subpoenaServe = W and (judge or c.r.clerk),
        transcript = W and (c.r.clerk or c.r.judge),
        bench = W and open and judge and k.defendantCharId ~= nil,
        reopen = W and not open and judge,
    }
    return k
end
DOJ.caseFull = caseFull

local function load(c, caseId, needFull)
    local k = DOJ.caseRow(caseId)
    if not k then return nil, 'No such case' end
    local access = DOJ.access(c, k)
    if not access then return nil, 'That case is sealed' end
    if needFull and access ~= 'full' then return nil, 'You are not on that case' end
    return k, DOJ.sideOf(c, k), access
end
DOJ.loadCase = load

-- ---------------------------------------------------------------- the page asks
local PLEAS = { 'none', 'guilty', 'not_guilty', 'no_contest' }
local function testSql(c) return c.staff and '1=1' or ('(k.`test` = 0 OR k.`createdBy` = ' .. math.floor(c.charId) .. ')') end

local function hearingClash(judge, room, startsAt, minutes, skipId)
    return MySQL.single.await([[SELECT h.`id`,h.`title`,k.`number` FROM `es_doj_hearings` h LEFT JOIN `es_doj_cases` k ON k.`id` = h.`caseId`
        WHERE h.`status` = 'scheduled' AND h.`id` <> ? AND (h.`judgeCharId` = ? OR (h.`room` = ? AND h.`room` <> 'Virtual'))
        AND h.`startsAt` < FROM_UNIXTIME(?) AND h.`startsAt` + INTERVAL h.`minutes` MINUTE > FROM_UNIXTIME(?) LIMIT 1]],
        { skipId or 0, judge or 0, room or '', startsAt + minutes * 60, startsAt })
end
DOJ.hearingClash = hearingClash

--- Everyone on a case hears of something (defendant, plaintiff, judge, lawyers), except `skip`
local function tellParties(k, title, body, kind, c, skip)
    local seen = { [skip or 0] = true }
    for _, cid in ipairs({ k.defendantCharId, k.plaintiffCharId, k.judgeCharId, k.prosecutorCharId, k.defenseCharId }) do
        if cid and not seen[cid] then seen[cid] = true DOJ.notice(cid, title, body, k.id, kind, c and c.charId, isTest(k)) end
    end
end
DOJ.tellParties = tellParties

function DOJ.registerCases()
    cb('cases', {}, function(c, d)
        local where, args = { testSql(c) }, {}
        local st = DOJ.oneOf(d.status, { 'open', 'closed', 'dismissed', 'all' }, 'open')
        if st ~= 'all' then where[#where + 1] = 'k.`status` = ?' args[#args + 1] = st end
        if DOJ.KINDS[d.kind] then where[#where + 1] = 'k.`kind` = ?' args[#args + 1] = d.kind end
        if not (c.staff or c.r.judge or c.r.seal) then
            where[#where + 1] = '(k.`sealed` = 0 OR ? IN (k.`judgeCharId`, k.`prosecutorCharId`, k.`defenseCharId`))' args[#args + 1] = c.charId
        end
        if d.mine then
            where[#where + 1] = '(? IN (k.`judgeCharId`, k.`prosecutorCharId`, k.`defenseCharId`, k.`createdBy`) OR k.`defendantCharId` IN (SELECT `clientCharId` FROM `es_doj_clients` WHERE `attorneyCharId` = ? AND `status` = \'active\'))'
            args[#args + 1] = c.charId args[#args + 1] = c.charId
        end
        local who = id(d.charId)
        if who then where[#where + 1] = '(k.`defendantCharId` = ? OR k.`plaintiffCharId` = ?)' args[#args + 1] = who args[#args + 1] = who end
        local q = str(d.q, 60)
        if q ~= '' then
            where[#where + 1] = [[(k.`number` LIKE CONCAT('%', ?, '%') OR k.`title` LIKE CONCAT('%', ?, '%') OR k.`defendantCharId` IN
                (SELECT `charId` FROM `characters` WHERE CONCAT(`firstName`,' ',`lastName`) LIKE CONCAT('%', ?, '%')))]]
            args[#args + 1] = q args[#args + 1] = q args[#args + 1] = q
        end
        local page = int(d.page, 0, 1000)
        args[#args + 1] = page * 60
        local rows = MySQL.query.await(([[SELECT k.`id`,k.`number`,k.`kind`,k.`title`,k.`status`,k.`stage`,k.`defendantCharId`,k.`judgeCharId`,k.`prosecutorCharId`,k.`defenseCharId`,
            k.`plea`,k.`verdict`,k.`bailStatus`,k.`sealed`,k.`test`,UNIX_TIMESTAMP(k.`updatedAt`) AS `updatedAt`,UNIX_TIMESTAMP(k.`createdAt`) AS `createdAt`,
            (SELECT UNIX_TIMESTAMP(MIN(h.`startsAt`)) FROM `es_doj_hearings` h WHERE h.`caseId` = k.`id` AND h.`status` = 'scheduled' AND h.`startsAt` > NOW() - INTERVAL 2 HOUR) AS `nextHearing`,
            (SELECT COUNT(*) FROM `es_doj_charges` g WHERE g.`caseId` = k.`id`) AS `charges`
            FROM `es_doj_cases` k WHERE %s ORDER BY (k.`status` = 'open') DESC, k.`updatedAt` DESC LIMIT 61 OFFSET ?]]):format(table.concat(where, ' AND ')), args) or {}
        local more = #rows > 60
        if more then rows[61] = nil end
        local ids = {}
        for _, r in ipairs(rows) do ids[#ids + 1] = r.defendantCharId ids[#ids + 1] = r.judgeCharId ids[#ids + 1] = r.prosecutorCharId ids[#ids + 1] = r.defenseCharId end
        local names = DOJ.namesOf(ids)
        for _, r in ipairs(rows) do
            r.defendant, r.judge = names[r.defendantCharId or 0], names[r.judgeCharId or 0]
            r.prosecutor, r.defense = names[r.prosecutorCharId or 0], names[r.defenseCharId or 0]
            r.sealed, r.test = r.sealed == 1, r.test == 1
        end
        return { rows = rows, more = more, page = page }
    end)

    cb('case', {}, function(c, d)
        local k, side, access = load(c, d.id)
        if not k then return false, side end
        return caseFull(c, k, side, access)
    end)

    cb('reportLookup', { role = { 'cases', 'judge', 'prosecutor' } }, function(_, d)
        local rid = id(d.reportId)
        if not rid then return false, 'Type the MDT report number' end
        local r = MySQL.single.await([[SELECT r.`id`,r.`type`,r.`title`,r.`caseId`,UNIX_TIMESTAMP(r.`createdAt`) AS `createdAt`,d.`short` AS `dept`
            FROM `es_mdt_reports` r LEFT JOIN `es_departments` d ON d.`id` = r.`deptId` WHERE r.`id` = ?]], { rid })
        if not r then return false, 'No such MDT report' end
        local people = MySQL.query.await("SELECT `charId`,`role` FROM `es_mdt_report_people` WHERE `reportId` = ? ORDER BY FIELD(`role`,'suspect','victim','witness','other')", { rid }) or {}
        local ids = {}
        for _, p in ipairs(people) do ids[#ids + 1] = p.charId end
        local names = DOJ.namesOf(ids)
        for _, p in ipairs(people) do
            p.name = names[p.charId] or ('#' .. p.charId)
            p.charges = DOJ.reportCharges(rid, p.charId)
            p.courtCase = MySQL.single.await("SELECT `id`,`number` FROM `es_doj_cases` WHERE `reportId` = ? AND `defendantCharId` = ? AND `status` = 'open' LIMIT 1", { rid, p.charId })
        end
        r.people = people
        return r
    end)

    cb('caseCreate', { role = { 'cases', 'judge', 'prosecutor' }, write = true, rate = 2000, burst = 3 }, function(c, d)
        d.test = (DOJ.ViewAs[c.source] or c.staff) and d.test == true or false
        if d.test then d.defendantCharId = d.defendantCharId or c.charId end
        local rid, def = id(d.reportId), id(d.defendantCharId)
        if rid and def and not d.force then
            local dup = MySQL.single.await("SELECT `number` FROM `es_doj_cases` WHERE `reportId` = ? AND `defendantCharId` = ? AND `status` = 'open' AND `test` = 0 LIMIT 1", { rid, def })
            if dup and not d.test then return false, ('%s is already open for that report and person'):format(dup.number) end
        end
        return DOJ.createCase(c, d)
    end)

    cb('caseUpdate', { write = true }, function(c, d)
        local k, side = load(c, d.id, true)
        if not k then return false, side end
        local set, args, said = {}, {}, {}
        local judge = c.staff or c.r.judge
        if d.title ~= nil or d.summary ~= nil then
            if not (c.r.court or side == 'prosecution' or side == 'court') then return false, 'Only the court or the prosecution edit the case' end
            if d.title ~= nil then local t = str(d.title, 160) if t == '' then return false, 'Give it a title' end set[#set + 1] = '`title` = ?' args[#args + 1] = t end
            if d.summary ~= nil then set[#set + 1] = '`summary` = ?' args[#args + 1] = str(d.summary, 4000) end
            said[#said + 1] = 'details edited'
        end
        if d.stage ~= nil then
            if not (c.r.court or side == 'court') then return false, 'Only the court moves the stage' end
            if closed(k) then return false, 'The case is closed' end
            local st = DOJ.oneOf(d.stage, DOJ.keys(Config.Stages), nil)
            if not st or st == 'closed' then return false, 'Pick a stage (close the case with Close)' end
            set[#set + 1] = '`stage` = ?' args[#args + 1] = st
            said[#said + 1] = 'stage: ' .. DOJ.stageLabel(st)
        end
        local function assign(field, val, may, why, check)
            if val == nil then return true end
            if not may then return false, why end
            local cid = val ~= false and val ~= 0 and id(val) or nil
            if val ~= false and val ~= 0 and not cid then return false, 'Pick a person' end
            if cid and check then local ok, e = check(cid) if not ok then return false, e end end
            set[#set + 1] = ('`%s` = ?'):format(field) args[#args + 1] = cid
            said[#said + 1] = ('%s: %s'):format((field:gsub('CharId', '')), cid and (DOJ.nameOf(cid) or ('#' .. cid)) or 'none')
            return true, nil, cid
        end
        local ok, e, cid
        ok, e, cid = assign('judgeCharId', d.judgeCharId, c.r.judge or c.r.clerk, 'Only judges and clerks assign the judge')
        if not ok then return false, e end
        if cid and cid ~= k.judgeCharId then DOJ.notice(cid, ('Assigned: %s'):format(k.number), k.title, k.id, 'assign', c.charId, isTest(k)) end
        ok, e, cid = assign('prosecutorCharId', d.prosecutorCharId, c.r.judge or c.r.clerk or c.r.prosecutor, 'Only the DA office, judges and clerks assign the prosecutor')
        if not ok then return false, e end
        if cid and cid ~= k.prosecutorCharId then DOJ.notice(cid, ('Assigned to prosecute: %s'):format(k.number), k.title, k.id, 'assign', c.charId, isTest(k)) end
        if d.defenseCharId ~= nil then
            local kind = DOJ.oneOf(d.defenseKind, { 'public', 'private', 'self', 'none' }, 'private')
            if d.defenseCharId == false or d.defenseCharId == 0 then kind = d.defenseKind == 'self' and 'self' or 'none' end
            ok, e, cid = assign('defenseCharId', d.defenseCharId, c.r.judge or c.r.clerk or c.r.defender or (c.r.attorney and side == 'defense') or c.r.attorney,
                'Only the court, public defenders or the defendant\'s lawyer set the defense', function(x)
                    if kind == 'public' then return true end
                    local b = DOJ.barOf(x)
                    if not (b and b.status == 'active') and not c.staff then return false, 'That person holds no active bar license' end
                    if c.r.attorney and not (c.r.court or c.r.defender) and x ~= c.charId then return false, 'You can only put yourself on a case' end
                    if c.r.attorney and not (c.r.court or c.r.defender) and not DOJ.isClient(x, k.defendantCharId) then return false, 'Add the defendant as your client first (Clients)' end
                    return true
                end)
            if not ok then return false, e end
            set[#set + 1] = '`defenseKind` = ?' args[#args + 1] = kind
            if cid and cid ~= k.defenseCharId then
                DOJ.notice(cid, ('Assigned to defend: %s'):format(k.number), k.title, k.id, 'assign', c.charId, isTest(k))
                if k.defendantCharId then DOJ.notice(k.defendantCharId, ('Your lawyer in %s'):format(k.number), ('%s (%s) now represents you.'):format(DOJ.nameOf(cid) or '?', kind == 'public' and 'public defender' or 'private counsel'), k.id, 'assign', c.charId, isTest(k)) end
            end
        end
        if d.plea ~= nil then
            if not (judge or c.r.clerk) then return false, 'Only the court enters a plea' end
            local p = DOJ.oneOf(d.plea, PLEAS, nil)
            if not p then return false, 'Pick a plea' end
            set[#set + 1] = '`plea` = ?' args[#args + 1] = p
            MySQL.update.await("UPDATE `es_doj_charges` SET `plea` = ? WHERE `caseId` = ? AND `disposition` = 'pending'", { p, k.id })
            said[#said + 1] = 'plea entered: ' .. p:gsub('_', ' ')
        end
        if #set == 0 then return false, 'Nothing to change' end
        args[#args + 1] = k.id
        MySQL.update.await(('UPDATE `es_doj_cases` SET %s WHERE `id` = ?'):format(table.concat(set, ', ')), args)
        DOJ.log(k.id, c, 'update', table.concat(said, '; '))
        DOJ.refresh('case:' .. k.id)
        return true
    end)

    cb('caseCharges', { write = true }, function(c, d)
        local k, side = load(c, d.id, true)
        if not k then return false, side end
        if closed(k) or k.verdict ~= 'none' then return false, 'Charges are fixed once there is a verdict' end
        if not (side == 'prosecution' or c.staff or (c.r.judge and side == 'court')) then return false, 'Only the prosecution or the judge amend charges' end
        local said = {}
        if type(d.add) == 'table' and #d.add > 0 then
            local rows = chargesFrom(d.add)
            insertCharges(k.id, rows)
            for _, r in ipairs(rows) do said[#said + 1] = ('+ %s %s x%d'):format(r.code, r.title, r.count) end
        end
        for _, x in ipairs(type(d.drop) == 'table' and d.drop or {}) do
            local gid = id(x)
            local g = gid and MySQL.single.await("SELECT `code`,`title` FROM `es_doj_charges` WHERE `id` = ? AND `caseId` = ?", { gid, k.id })
            if g then
                MySQL.update.await("UPDATE `es_doj_charges` SET `disposition` = 'dropped' WHERE `id` = ?", { gid })
                said[#said + 1] = ('dropped %s %s'):format(g.code, g.title)
            end
        end
        for _, x in ipairs(type(d.restore) == 'table' and d.restore or {}) do
            local gid = id(x)
            if gid then MySQL.update.await("UPDATE `es_doj_charges` SET `disposition` = 'pending' WHERE `id` = ? AND `caseId` = ? AND `disposition` = 'dropped'", { gid, k.id }) said[#said + 1] = 'restored a charge' end
        end
        if type(d.counts) == 'table' then
            for gidS, n in pairs(d.counts) do
                local gid = id(gidS)
                if gid then MySQL.update.await('UPDATE `es_doj_charges` SET `count` = ? WHERE `id` = ? AND `caseId` = ?', { int(n, 1, 20), gid, k.id }) end
            end
            said[#said + 1] = 'counts changed'
        end
        if #said == 0 then return false, 'Nothing to change' end
        DOJ.log(k.id, c, 'charges', table.concat(said, '; '))
        DOJ.refresh('case:' .. k.id)
        return chargeList(k.id)
    end)

    -- ------------------------------------------------------------ hearings
    cb('hearingSave', { role = { 'clerk', 'cases', 'judge' }, write = true }, function(c, d)
        local hid = id(d.id)
        local old = hid and MySQL.single.await('SELECT `id`,`caseId`,`status`,`test` FROM `es_doj_hearings` WHERE `id` = ?', { hid })
        if hid and not old then return false, 'No such hearing' end
        if old and old.status ~= 'scheduled' then return false, 'Only a scheduled hearing can be changed' end
        local k
        local caseId = old and old.caseId or id(d.caseId)
        if caseId then
            local why
            k, why = load(c, caseId, true)
            if not k then return false, why end
            if closed(k) then return false, 'The case is closed' end
        end
        local kind = DOJ.oneOf(d.kind, DOJ.keys(Config.HearingKinds), 'other')
        local startsAt = math.floor(tonumber(d.startsAt) or 0)
        if startsAt < now() - 3600 then return false, 'Pick a time that has not passed' end
        if startsAt > now() + 86400 * 120 then return false, 'Pick a time within 4 months' end
        local minutes = int(d.minutes or 30, 5, 480)
        local room = DOJ.oneOf(d.room, Config.Courthouse.rooms, Config.Courthouse.rooms[1])
        local judge = id(d.judgeCharId) or (k and k.judgeCharId) or (c.r.judge and not c.staff and c.charId) or nil
        local title = str(d.title, 160)
        if title == '' then title = DOJ.labelOf(Config.HearingKinds, kind) .. (k and (' — ' .. k.number) or '') end
        if not d.force then
            local hit = hearingClash(judge, room, startsAt, minutes, hid)
            if hit then return false, ('Clashes with %s%s (same judge or room). Save anyway to double-book.'):format(hit.title or 'a hearing', hit.number and (' · ' .. hit.number) or ''), 'clash' end
        end
        if old then
            MySQL.update.await('UPDATE `es_doj_hearings` SET `kind` = ?, `title` = ?, `startsAt` = FROM_UNIXTIME(?), `minutes` = ?, `room` = ?, `judgeCharId` = ?, `reminded` = 0 WHERE `id` = ?',
                { kind, title, startsAt, minutes, room, judge, hid })
        else
            hid = MySQL.insert.await([[INSERT INTO `es_doj_hearings` (`caseId`,`kind`,`title`,`startsAt`,`minutes`,`room`,`judgeCharId`,`test`,`createdBy`)
                VALUES (?,?,?,FROM_UNIXTIME(?),?,?,?,?,?)]], { caseId, kind, title, startsAt, minutes, room, judge, (k and isTest(k)) and 1 or 0, c.charId })
        end
        local when = os.date('!%a %d %b %H:%M', startsAt) .. ' UTC'
        if k then
            if kind ~= 'other' and DOJ.oneOf(kind, DOJ.keys(Config.Stages), nil) and (k.stage == 'filed' or kind ~= 'arraignment') then
                MySQL.update.await("UPDATE `es_doj_cases` SET `stage` = ? WHERE `id` = ? AND `status` = 'open'", { kind, k.id })
            end
            DOJ.log(k.id, c, old and 'hearing_moved' or 'hearing', ('%s: %s, %s (%d min)'):format(title, when, room, minutes))
            tellParties(k, ('%s %s'):format(old and 'Hearing moved:' or 'Hearing set:', title), ('%s in %s at the courthouse (%d min). Your time: see /%s.'):format(when, room, minutes, Config.PortalCommand or 'court'), 'hearing', c, c.charId)
        elseif judge and judge ~= c.charId then
            DOJ.notice(judge, ('Hearing on your calendar: %s'):format(title), ('%s in %s'):format(when, room), nil, 'hearing', c.charId)
        end
        DOJ.refresh('calendar')
        return { id = hid }
    end)

    cb('hearingAct', { write = true }, function(c, d)
        local h = MySQL.single.await('SELECT `id`,`caseId`,`title`,`status`,`judgeCharId`,`kind` FROM `es_doj_hearings` WHERE `id` = ?', { id(d.id) or 0 })
        if not h then return false, 'No such hearing' end
        local k
        if h.caseId then local why k, why = load(c, h.caseId, true) if not k then return false, why end end
        if not (c.r.judge or c.r.clerk or c.r.cases or h.judgeCharId == c.charId) then return false, 'Only the court runs hearings' end
        local act = DOJ.oneOf(d.act, { 'held', 'cancelled', 'noshow', 'adjourned' }, nil)
        if not act then return false, 'held, cancelled, noshow or adjourned' end
        if h.status ~= 'scheduled' and h.status ~= 'adjourned' then return false, 'That hearing is already ' .. h.status end
        local outcome = str(d.outcome, 500)
        MySQL.update.await('UPDATE `es_doj_hearings` SET `status` = ?, `outcome` = ? WHERE `id` = ?', { act, outcome ~= '' and outcome or nil, h.id })
        if k then
            DOJ.log(k.id, c, 'hearing_' .. act, ('%s: %s%s'):format(h.title or 'Hearing', act, outcome ~= '' and (' — ' .. outcome) or ''))
            if act == 'cancelled' then tellParties(k, ('Hearing cancelled: %s'):format(h.title or k.number), outcome, 'hearing', c, c.charId) end
            if act == 'noshow' and k.defendantCharId then
                DOJ.notice(k.defendantCharId, ('You missed court: %s'):format(k.number), DOJ.bailOn() and 'The judge may forfeit your bail and issue a bench warrant. Contact the court.' or 'The judge may issue a bench warrant. Contact the court.', k.id, 'hearing', c.charId, isTest(k))
            end
        end
        DOJ.refresh('calendar')
        return true
    end)

    cb('transcript', {}, function(c, d)
        local h = MySQL.single.await([[SELECT `id`,`caseId`,`title`,`kind`,UNIX_TIMESTAMP(`startsAt`) AS `startsAt`,`room`,`judgeCharId`,`status`,`outcome`
            FROM `es_doj_hearings` WHERE `id` = ?]], { id(d.id) or 0 })
        if not h then return false, 'No such hearing' end
        if h.caseId then local k, why = load(c, h.caseId, true) if not k then return false, why end
        elseif not c.r.member and not c.staff then return false, 'Not yours to read' end
        h.lines = MySQL.query.await('SELECT `id`,`speaker`,`text`,UNIX_TIMESTAMP(`createdAt`) AS `at` FROM `es_doj_transcripts` WHERE `hearingId` = ? ORDER BY `id`', { h.id }) or {}
        h.judge = DOJ.nameOf(h.judgeCharId)
        return h
    end)

    cb('transcriptAdd', { role = { 'clerk', 'judge' }, write = true, rate = 300, burst = 20 }, function(c, d)
        local h = MySQL.single.await('SELECT `id`,`caseId` FROM `es_doj_hearings` WHERE `id` = ?', { id(d.id) or 0 })
        if not h then return false, 'No such hearing' end
        if h.caseId then local k, why = load(c, h.caseId, true) if not k then return false, why end end
        local speaker, text = str(d.speaker, 80), str(d.text, 1000)
        if speaker == '' then speaker = c.label end
        if text == '' then return false, 'Type what was said' end
        local lid = MySQL.insert.await('INSERT INTO `es_doj_transcripts` (`hearingId`,`speaker`,`text`,`byCharId`) VALUES (?,?,?,?)', { h.id, speaker, text, c.charId })
        return { id = lid, speaker = speaker, text = text, at = now() }
    end)

    -- ------------------------------------------------------------ filings and exhibits
    cb('filingSave', { write = true, rate = 1500, burst = 4 }, function(c, d)
        local k, side = load(c, d.caseId, true)
        if not k then return false, side end
        if not side then
            if c.r.court then side = 'court' else return false, 'You are not on that case' end
        end
        if side == 'clerk' then side = 'court' end
        local kind = DOJ.oneOf(d.kind, DOJ.keys(Config.FilingKinds), 'motion')
        if kind == 'order' and not (c.r.judge or c.staff) then return false, 'Only a judge files a court order' end
        if kind == 'note' and side ~= 'court' and side ~= 'prosecution' and side ~= 'defense' then return false, 'Notes are for the parties' end
        local title = str(d.title, 160)
        if title == '' then return false, 'Give it a title' end
        local vis = DOJ.oneOf(d.visibility, { 'public', 'parties', 'prosecution', 'defense', 'court' }, 'parties')
        if kind == 'note' then vis = side == 'court' and 'court' or side end
        if (vis == 'prosecution' and side ~= 'prosecution' and side ~= 'court') or (vis == 'defense' and side ~= 'defense' and side ~= 'court') then vis = 'parties' end
        local image, evId
        if d.evidenceId then
            evId = id(d.evidenceId)
            if not k.mdtCaseId then return false, 'This case has no police case to take evidence from' end
            local ok, ev = pcall(function() return exports.es_evidence:ForCase(k.mdtCaseId) end)
            local found
            for _, e in ipairs(ok and type(ev) == 'table' and ev.items or {}) do if e.id == evId then found = e end end
            if not found then return false, 'That evidence is not on the police case' end
            if found.kind == 'photo' then image = exports.es_evidence:Image(evId) end
        elseif d.image ~= nil or d.imageUrl ~= nil or d.photoId ~= nil then
            local why
            image, why = DOJ.imageFrom(d, c.charId)
            if not image then return false, why end
        end
        local exhibitNo
        if kind == 'exhibit' or evId then
            kind = 'exhibit'
            local pre = side == 'prosecution' and 'P' or (side == 'defense' and 'D' or 'C')
            local n = MySQL.scalar.await("SELECT COUNT(*) FROM `es_doj_filings` WHERE `caseId` = ? AND `exhibitNo` LIKE CONCAT(?, '-%')", { k.id, pre }) or 0
            exhibitNo = ('%s-%d'):format(pre, n + 1)
        end
        local status = (kind == 'motion') and 'pending' or 'filed'
        local fid = MySQL.insert.await([[INSERT INTO `es_doj_filings` (`caseId`,`kind`,`title`,`body`,`image`,`evidenceId`,`exhibitNo`,`side`,`visibility`,`status`,`byCharId`,`byLabel`)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?)]], { k.id, kind, title, str(d.body, 8000), image, evId, exhibitNo, side, vis, status, c.charId, c.label })
        DOJ.log(k.id, c, 'filing', ('%s%s: %s'):format(DOJ.labelOf(Config.FilingKinds, kind), exhibitNo and (' ' .. exhibitNo) or '', title))
        if vis ~= 'court' and vis ~= side then
            tellParties(k, ('New %s in %s'):format(DOJ.labelOf(Config.FilingKinds, kind):lower(), k.number), title, 'filing', c, c.charId)
        end
        DOJ.refresh('case:' .. k.id)
        return { id = fid, exhibitNo = exhibitNo }
    end)

    cb('filingImage', { rate = 300, burst = 10 }, function(c, d)
        local f = MySQL.single.await('SELECT `id`,`caseId`,`visibility`,`image` FROM `es_doj_filings` WHERE `id` = ?', { id(d.id) or 0 })
        if not f or not f.image then return false, 'No picture' end
        local k, side, access = load(c, f.caseId)
        if not k then return false, side end
        if access ~= 'full' then if f.visibility ~= 'public' then return false, 'Not yours to see' end return f.image end
        local where = DOJ.visibleFilingSql(c, k, side)
        if not MySQL.scalar.await(('SELECT 1 FROM `es_doj_filings` WHERE `id` = ? AND %s'):format(where), { f.id }) then return false, 'Not yours to see' end
        return f.image
    end)

    cb('evidenceImage', { rate = 300, burst = 10 }, function(c, d)
        local k, why = load(c, d.caseId, true)
        if not k then return false, why end
        local eid = id(d.id)
        if not (k.mdtCaseId and eid) then return false, 'No picture' end
        local ok, ev = pcall(function() return exports.es_evidence:ForCase(k.mdtCaseId) end)
        for _, e in ipairs(ok and type(ev) == 'table' and ev.items or {}) do
            if e.id == eid then return exports.es_evidence:Image(eid) or false, 'No picture' end
        end
        return false, 'That evidence is not on this case'
    end)

    cb('filingRule', { role = 'judge', write = true }, function(c, d)
        local f = MySQL.single.await('SELECT `id`,`caseId`,`title`,`kind`,`status` FROM `es_doj_filings` WHERE `id` = ?', { id(d.id) or 0 })
        if not f then return false, 'No such filing' end
        local k, why = load(c, f.caseId, true)
        if not k then return false, why end
        if k.judgeCharId and k.judgeCharId ~= c.charId and not c.staff then return false, 'Only the case judge rules on it' end
        local r = DOJ.oneOf(d.ruling, { 'granted', 'denied', 'admitted', 'excluded', 'struck', 'withdrawn' }, nil)
        if not r then return false, 'Pick a ruling' end
        local note = str(d.note, 500)
        MySQL.update.await('UPDATE `es_doj_filings` SET `status` = ?, `ruling` = ?, `ruledBy` = ?, `ruledAt` = NOW() WHERE `id` = ?', { r, note ~= '' and note or nil, c.charId, f.id })
        DOJ.log(k.id, c, 'ruling', ('%s: %s%s'):format(f.title, r, note ~= '' and (' — ' .. note) or ''))
        tellParties(k, ('Ruling in %s: %s'):format(k.number, r), ('%s%s'):format(f.title, note ~= '' and (': ' .. note) or ''), 'ruling', c, c.charId)
        DOJ.refresh('case:' .. k.id)
        return true
    end)

    -- ------------------------------------------------------------ plea deals
    cb('pleaOffer', { write = true, rate = 1500, burst = 3 }, function(c, d)
        local k, side = load(c, d.caseId, true)
        if not k then return false, side end
        if closed(k) or k.verdict ~= 'none' then return false, 'The case is past pleas' end
        if side ~= 'prosecution' and not c.staff then return false, 'Only the prosecution offers a plea deal' end
        if k.kind == 'civil' or k.kind == 'appeal' or k.kind == 'petition' then return false, 'Plea deals are for criminal and traffic cases' end
        local terms = str(d.terms, 1000)
        if terms == '' then return false, 'Write the terms' end
        local keep, live = {}, {}
        for _, g in ipairs(chargeList(k.id)) do if g.disposition == 'pending' then live[g.id] = g end end
        for _, x in ipairs(type(d.charges) == 'table' and d.charges or {}) do local g = live[id(x) or 0] if g then keep[#keep + 1] = g.id end end
        if #keep == 0 then return false, 'Pick the charges they plead to' end
        MySQL.update.await("UPDATE `es_doj_pleas` SET `status` = 'withdrawn' WHERE `caseId` = ? AND `status` IN ('offered','accepted')", { k.id })
        local pid = MySQL.insert.await([[INSERT INTO `es_doj_pleas` (`caseId`,`terms`,`fine`,`months`,`service`,`probationDays`,`chargesJson`,`offeredBy`,`offeredByLabel`)
            VALUES (?,?,?,?,?,?,?,?,?)]], { k.id, terms, int(d.fine, 0, S.maxFine or 1000000), int(d.months, 0, S.maxMonths or 300), int(d.service, 0, S.maxService or 100),
            int(d.probationDays, 0, S.maxProbationDays or 365), json.encode(keep), c.charId, c.label })
        DOJ.log(k.id, c, 'plea_offer', ('Plea offered: %s'):format(terms))
        for _, cid in ipairs({ k.defenseCharId, k.defendantCharId }) do
            if cid then DOJ.notice(cid, ('Plea offer in %s'):format(k.number), ('%s. Answer it in /%s (or through your lawyer).'):format(terms, Config.PortalCommand or 'court'), k.id, 'plea', c.charId, isTest(k)) end
        end
        DOJ.refresh('case:' .. k.id)
        return { id = pid }
    end)

    --- accept / reject (defense or the defendant), withdraw (prosecution), approve / refuse (judge)
    function DOJ.pleaAct(c, d, asDefendant)
        local p = MySQL.single.await('SELECT * FROM `es_doj_pleas` WHERE `id` = ?', { id(d.id) or 0 })
        if not p then return false, 'No such plea offer' end
        local k, side
        if asDefendant then
            k = DOJ.caseRow(p.caseId)
            if not k or k.defendantCharId ~= c.charId then return false, 'Not your case' end
            side = 'defendant'
        else
            local why
            k, side = load(c, p.caseId, true)
            if not k then why = side return false, why end
        end
        if closed(k) then return false, 'The case is closed' end
        local act = d.act
        local note = str(d.note, 300)
        local function set(status, by)
            local n = MySQL.update.await(('UPDATE `es_doj_pleas` SET `status` = ?, `note` = COALESCE(NULLIF(?, \'\'), `note`), %s = ?, `decidedAt` = IF(? IN (\'approved\',\'refused\',\'rejected\'), NOW(), `decidedAt`) WHERE `id` = ? AND `status` = ?')
                :format(by), { status, note, c.charId, status, p.id, p.status })
            return (tonumber(n) or 0) > 0
        end
        if act == 'accept' or act == 'reject' then
            if not (side == 'defense' or side == 'defendant' or c.staff) then return false, 'Only the defense answers a plea offer' end
            if p.status ~= 'offered' then return false, 'That offer is no longer open' end
            if not set(act == 'accept' and 'accepted' or 'rejected', '`respondedBy`') then return false, 'Someone answered it first' end
            DOJ.log(k.id, c, 'plea_' .. act, ('Plea %s by %s'):format(act == 'accept' and 'accepted' or 'rejected', side == 'defendant' and 'the defendant' or c.label))
            for _, cid in ipairs({ k.prosecutorCharId, p.offeredBy, act == 'accept' and k.judgeCharId or nil }) do
                if cid and cid ~= c.charId then DOJ.notice(cid, ('Plea %s: %s'):format(act == 'accept' and 'accepted' or 'rejected', k.number), act == 'accept' and 'It waits for the judge to approve it.' or note, k.id, 'plea', c.charId, isTest(k)) end
            end
        elseif act == 'withdraw' then
            if side ~= 'prosecution' and not c.staff then return false, 'Only the prosecution withdraws its offer' end
            if p.status ~= 'offered' and p.status ~= 'accepted' then return false, 'That offer is no longer open' end
            if not set('withdrawn', '`decidedBy`') then return false, 'It changed; reload' end
            DOJ.log(k.id, c, 'plea_withdrawn', 'Plea offer withdrawn')
        elseif act == 'approve' or act == 'refuse' then
            if asDefendant or not (c.staff or (c.r.judge and (not k.judgeCharId or k.judgeCharId == c.charId))) then return false, 'Only the case judge approves a plea' end
            if p.status ~= 'accepted' then return false, 'The defense has not accepted it' end
            if not set(act == 'approve' and 'approved' or 'refused', '`decidedBy`') then return false, 'It changed; reload' end
            if act == 'refuse' then
                DOJ.log(k.id, c, 'plea_refused', 'The judge refused the plea' .. (note ~= '' and (': ' .. note) or ''))
                tellParties(k, ('Plea refused: %s'):format(k.number), note, 'plea', c, c.charId)
            else
                local ok, keep = pcall(json.decode, p.chargesJson or '[]')
                keep = ok and type(keep) == 'table' and keep or {}
                local kept = {}
                for _, x in ipairs(keep) do kept[#kept + 1] = id(x) end
                MySQL.update.await("UPDATE `es_doj_charges` SET `disposition` = 'dropped' WHERE `caseId` = ? AND `disposition` = 'pending'", { k.id })
                if #kept > 0 then
                    local a = { k.id } for _, x in ipairs(kept) do a[#a + 1] = x end
                    MySQL.update.await(("UPDATE `es_doj_charges` SET `disposition` = 'guilty', `plea` = 'guilty' WHERE `caseId` = ? AND `id` IN (%s)"):format(DOJ.marks(#kept)), a)
                end
                MySQL.update.await("UPDATE `es_doj_cases` SET `plea` = 'guilty', `verdict` = 'plea', `verdictAt` = NOW() WHERE `id` = ?", { k.id })
                DOJ.log(k.id, c, 'plea_approved', ('Plea approved: %s'):format(p.terms))
                local res = DOJ.applySentence(k, { fine = p.fine, months = p.months, service = p.service, probationDays = p.probationDays, notes = p.terms }, c, 'plea')
                DOJ.closeCase(DOJ.caseRow(k.id), 'closed', c, ('Closed on a plea deal: %s'):format(type(res) == 'table' and res.text or ''))
                DOJ.refresh('case:' .. k.id)
                return { sentence = res }
            end
        else
            return false, 'accept, reject, withdraw, approve or refuse'
        end
        DOJ.refresh('case:' .. k.id)
        return true
    end
    cb('pleaAct', { write = true }, function(c, d) return DOJ.pleaAct(c, d, false) end)

    -- ------------------------------------------------------------ verdict, sentence, close
    local function judgeOf(c, k)
        if c.staff then return true end
        if not c.r.judge then return false, 'Only a judge does that' end
        if k.judgeCharId and k.judgeCharId ~= c.charId then return false, ('%s is the judge on this case'):format(DOJ.nameOf(k.judgeCharId) or 'Another judge') end
        return true
    end
    DOJ.judgeOf = judgeOf

    cb('verdict', { role = 'judge', write = true }, function(c, d)
        local k, why = load(c, d.caseId, true)
        if not k then return false, why end
        local okj, e = judgeOf(c, k) if not okj then return false, e end
        if closed(k) then return false, 'The case is closed' end
        if k.verdict ~= 'none' then return false, 'There is already a verdict' end
        if k.kind == 'appeal' then return false, 'Rule on an appeal with Appeal ruling' end
        local v
        if k.kind == 'civil' then
            v = DOJ.oneOf(d.verdict, { 'plaintiff', 'defendant', 'dismissed', 'settled' }, nil)
        else
            v = DOJ.oneOf(d.verdict, { 'guilty', 'not_guilty', 'dismissed' }, nil)
        end
        if not v then return false, 'Pick a verdict' end
        local note = str(d.note, 500)
        if v == 'guilty' then
            local per = type(d.charges) == 'table' and d.charges or {}
            local any = false
            for _, g in ipairs(chargeList(k.id)) do
                if g.disposition == 'pending' then
                    local dv = per[tostring(g.id)] or per[g.id]
                    dv = (dv == 'not_guilty' or dv == false) and 'not_guilty' or 'guilty'
                    if dv == 'guilty' then any = true end
                    MySQL.update.await('UPDATE `es_doj_charges` SET `disposition` = ? WHERE `id` = ?', { dv, g.id })
                end
            end
            if not any then v = 'not_guilty' end
        elseif v == 'not_guilty' then
            MySQL.update.await("UPDATE `es_doj_charges` SET `disposition` = 'not_guilty' WHERE `caseId` = ? AND `disposition` = 'pending'", { k.id })
        elseif v == 'dismissed' then
            MySQL.update.await("UPDATE `es_doj_charges` SET `disposition` = 'dismissed' WHERE `caseId` = ? AND `disposition` = 'pending'", { k.id })
        end
        MySQL.update.await("UPDATE `es_doj_cases` SET `verdict` = ?, `verdictAt` = NOW(), `stage` = IF(? IN ('guilty','plaintiff'), 'sentencing', `stage`) WHERE `id` = ?", { v, v, k.id })
        DOJ.log(k.id, c, 'verdict', ('Verdict: %s%s'):format(v:gsub('_', ' '), note ~= '' and (' — ' .. note) or ''))
        tellParties(k, ('Verdict in %s: %s'):format(k.number, (v:gsub('_', ' '))), note, 'verdict', c, c.charId)
        k = DOJ.caseRow(k.id)
        if v == 'not_guilty' or v == 'dismissed' then
            if k.kind ~= 'civil' then DOJ.undoPenalties(k, c, 'Verdict: ' .. v) end
            DOJ.closeCase(k, v == 'dismissed' and 'dismissed' or 'closed', c, ('Verdict: %s'):format((v:gsub('_', ' '))))
        elseif v == 'defendant' or v == 'settled' then
            DOJ.closeCase(k, 'closed', c, ('Verdict: %s'):format(v == 'settled' and 'settled' or 'for the defendant'))
        end
        DOJ.refresh('case:' .. k.id)
        return { verdict = v }
    end)

    cb('sentence', { role = 'judge', write = true, rate = 3000, burst = 2 }, function(c, d)
        local k, why = load(c, d.caseId, true)
        if not k then return false, why end
        local okj, e = judgeOf(c, k) if not okj then return false, e end
        if closed(k) then return false, 'The case is closed' end
        if k.verdict ~= 'guilty' and k.verdict ~= 'plaintiff' then return false, 'Sentence follows a guilty verdict (or a judgment for the plaintiff)' end
        if MySQL.scalar.await("SELECT 1 FROM `es_doj_sentences` WHERE `caseId` = ? AND `status` = 'active' LIMIT 1", { k.id }) then return false, 'This case already has a sentence' end
        local civil = k.kind == 'civil'
        if civil then d.months, d.service, d.probationDays = 0, 0, 0 end
        local res, err = DOJ.applySentence(k, d, c, civil and 'judgment' or 'verdict')
        if not res then return false, err end
        DOJ.closeCase(DOJ.caseRow(k.id), 'closed', c, ('%s: %s'):format(civil and 'Judgment' or 'Sentenced', res.text))
        return res
    end)

    cb('caseClose', { write = true }, function(c, d)
        local k, side = load(c, d.caseId, true)
        if not k then return false, side end
        if closed(k) then return false, 'Already closed' end
        local status = d.status == 'dismissed' and 'dismissed' or 'closed'
        local reason = str(d.reason, 500)
        if reason == '' then return false, 'Give the reason (it goes on the record)' end
        if side == 'prosecution' and not c.staff then
            if k.verdict ~= 'none' then return false, 'Only the judge closes a case after the verdict' end
            status = 'dismissed'   -- the prosecution drops the case (nolle prosequi)
        else
            local okj, e = judgeOf(c, k) if not okj then return false, e end
        end
        if status == 'dismissed' then
            MySQL.update.await("UPDATE `es_doj_charges` SET `disposition` = 'dismissed' WHERE `caseId` = ? AND `disposition` = 'pending'", { k.id })
            if k.verdict == 'none' then MySQL.update.await("UPDATE `es_doj_cases` SET `verdict` = 'dismissed', `verdictAt` = NOW() WHERE `id` = ?", { k.id }) end
            if d.voidFines and k.kind ~= 'civil' then DOJ.undoPenalties(k, c, 'Dismissed: ' .. reason) end
        end
        DOJ.closeCase(k, status, c, reason)
        return true
    end)

    cb('caseReopen', { role = 'judge', write = true }, function(c, d)
        local k, why = load(c, d.caseId, true)
        if not k then return false, why end
        local okj, e = judgeOf(c, k) if not okj then return false, e end
        if not closed(k) then return false, 'It is open' end
        local reason = str(d.reason, 500)
        if reason == '' then return false, 'Give the reason' end
        MySQL.update.await("UPDATE `es_doj_cases` SET `status` = 'open', `stage` = 'pretrial', `closedAt` = NULL WHERE `id` = ?", { k.id })
        DOJ.log(k.id, c, 'reopened', reason)
        tellParties(k, ('Case reopened: %s'):format(k.number), reason, 'case', c, c.charId)
        DOJ.refresh('cases')
        return true
    end)

    -- ------------------------------------------------------------ bail and bond
    cb('bail', { role = 'judge', write = true }, function(c, d)
        if not DOJ.bailOn() then return false, 'This court has no bail' end
        local k, why = load(c, d.caseId, true)
        if not k then return false, why end
        local okj, e = judgeOf(c, k) if not okj then return false, e end
        if closed(k) then return false, 'The case is closed' end
        if not k.defendantCharId or k.kind == 'civil' then return false, 'Bail is for a criminal defendant' end
        local act = d.act
        local note = str(d.note, 300)
        local function voidUnpaid() if k.bailFeeId then MySQL.update.await("UPDATE `es_doj_fees` SET `status` = 'void' WHERE `id` = ? AND `status` = 'unpaid'", { k.bailFeeId }) end end
        local text
        if act == 'set' then
            if k.bailStatus == 'posted' then return false, 'Bail is already posted (revoke it first)' end
            local amount = int(d.amount, 0, (Config.Bail or {}).max or 1000000)
            if amount < 1 then return false, 'Set an amount' end
            voidUnpaid()
            local fid = DOJ.addFee(k.defendantCharId, 'bail', amount, ('Bail: %s'):format(k.number), k.id, c.charId, isTest(k), 0)
            MySQL.update.await("UPDATE `es_doj_cases` SET `bailStatus` = 'set', `bailAmount` = ?, `bailFeeId` = ? WHERE `id` = ?", { amount, fid, k.id })
            local bond = math.ceil(amount * ((Config.Bail or {}).bondPercent or 10) / 100)
            text = ('Bail set at $%d (or a $%d bond, not refunded)'):format(amount, bond)
            DOJ.notice(k.defendantCharId, ('Bail set: %s'):format(k.number), ('%s. Anyone can pay it for you at the courthouse (/%s, Payments). Full bail comes back when the case ends if you attend court.')
                :format(text, Config.PortalCommand or 'court'), k.id, 'bail', c.charId, isTest(k))
        elseif act == 'deny' then
            if k.bailStatus == 'posted' then return false, 'Bail is posted: revoke it instead' end
            voidUnpaid()
            MySQL.update.await("UPDATE `es_doj_cases` SET `bailStatus` = 'denied', `bailAmount` = 0 WHERE `id` = ?", { k.id })
            text = 'Bail denied: held until trial'
            DOJ.notice(k.defendantCharId, ('Bail denied: %s'):format(k.number), note, k.id, 'bail', c.charId, isTest(k))
        elseif act == 'ror' then
            if k.bailStatus == 'posted' then return false, 'Bail is already posted' end
            voidUnpaid()
            MySQL.update.await("UPDATE `es_doj_cases` SET `bailStatus` = 'ror', `bailAmount` = 0 WHERE `id` = ?", { k.id })
            text = 'Released on own recognizance'
            DOJ.releaseFromJail(k, c, 'Released on own recognizance (' .. k.number .. ')')
            DOJ.notice(k.defendantCharId, ('Released: %s'):format(k.number), 'You are released on your own recognizance. Attend every hearing.', k.id, 'bail', c.charId, isTest(k))
        elseif act == 'revoke' then
            if k.bailStatus ~= 'posted' and k.bailStatus ~= 'ror' then return false, 'There is no release to revoke' end
            if k.bailStatus == 'posted' then DOJ.refundBail(k, c, 'revoked') end
            MySQL.update.await("UPDATE `es_doj_cases` SET `bailStatus` = 'revoked' WHERE `id` = ?", { k.id })
            text = 'Release revoked'
            DOJ.notice(k.defendantCharId, ('Release revoked: %s'):format(k.number), (note ~= '' and note or 'Turn yourself in at the courthouse or the police.'), k.id, 'bail', c.charId, isTest(k))
        elseif act == 'forfeit' then
            if k.bailStatus ~= 'posted' then return false, 'No bail is posted' end
            local f = MySQL.single.await('SELECT `id`,`amount`,`method`,`test` FROM `es_doj_fees` WHERE `id` = ?', { k.bailFeeId or 0 })
            MySQL.update.await("UPDATE `es_doj_cases` SET `bailStatus` = 'forfeited' WHERE `id` = ?", { k.id })
            if f and f.method ~= 'bond' and f.test ~= 1 then DOJ.deposit(f.amount, ('Bail forfeited: %s'):format(k.number)) end
            text = ('Bail forfeited%s'):format(f and (' ($' .. f.amount .. ')') or '')
            DOJ.notice(k.defendantCharId, ('Bail forfeited: %s'):format(k.number), note ~= '' and note or 'You missed court.', k.id, 'bail', c.charId, isTest(k))
        else
            return false, 'set, deny, ror, revoke or forfeit'
        end
        DOJ.log(k.id, c, 'bail', text .. (note ~= '' and (' — ' .. note) or ''))
        DOJ.refresh('case:' .. k.id)
        return true
    end)

    -- ------------------------------------------------------------ appeals
    cb('appealFile', { write = true, rate = 5000, burst = 2 }, function(c, d)
        local k, side = load(c, d.caseId, true)
        if not k then return false, side end
        if not closed(k) then return false, 'Appeal once the case is closed' end
        if k.kind == 'appeal' then return false, 'An appeal cannot be appealed here' end
        if not (side == 'defense' or side == 'prosecution' or c.staff) then return false, 'Only a party appeals' end
        if MySQL.scalar.await("SELECT 1 FROM `es_doj_cases` WHERE `parentId` = ? AND `status` = 'open' LIMIT 1", { k.id }) then return false, 'An appeal is already open' end
        local reason = str(d.reason, 4000)
        if #reason < 10 then return false, 'Write the grounds for the appeal' end
        local res, e = DOJ.createCase(c, { kind = 'appeal', title = ('Appeal: %s'):format(k.title):sub(1, 160), summary = reason, defendantCharId = k.defendantCharId,
            plaintiffCharId = k.plaintiffCharId, plaintiffName = k.plaintiffName, mdtCaseId = k.mdtCaseId, parentId = k.id, test = isTest(k), importReport = false })
        if not res then return false, e end
        MySQL.update.await('UPDATE `es_doj_cases` SET `prosecutorCharId` = ?, `defenseCharId` = ?, `defenseKind` = ?, `reportId` = ? WHERE `id` = ?',
            { k.prosecutorCharId, k.defenseCharId, k.defenseKind, k.reportId, res.id })
        MySQL.update.await([[INSERT INTO `es_doj_charges` (`caseId`,`penalId`,`code`,`title`,`category`,`count`,`fine`,`months`,`plea`,`disposition`)
            SELECT ?,`penalId`,`code`,`title`,`category`,`count`,`fine`,`months`,`plea`,`disposition` FROM `es_doj_charges` WHERE `caseId` = ?]], { res.id, k.id })
        local fee = (Config.Fees or {}).appeal or 0
        if fee > 0 and side == 'defense' and k.defendantCharId then DOJ.addFee(k.defendantCharId, 'fee', fee, ('Appeal fee: %s'):format(res.number), res.id, c.charId, isTest(k), (Config.Fees or {}).dueDays) end
        DOJ.log(k.id, c, 'appealed', ('Appeal %s filed by the %s'):format(res.number, side))
        tellParties(k, ('Appeal filed: %s'):format(res.number), ('Against %s.'):format(k.number), 'case', c, c.charId)
        return res
    end)

    cb('appealRule', { role = 'judge', write = true }, function(c, d)
        local k, why = load(c, d.caseId, true)
        if not k then return false, why end
        local okj, e = judgeOf(c, k) if not okj then return false, e end
        if k.kind ~= 'appeal' or closed(k) then return false, 'That is not an open appeal' end
        local r = DOJ.oneOf(d.ruling, { 'affirmed', 'reversed', 'remanded' }, nil)
        if not r then return false, 'affirmed, reversed or remanded' end
        local note = str(d.note, 500)
        local parent = k.parentId and DOJ.caseRow(k.parentId)
        if not parent then return false, 'The original case is gone' end
        if r == 'reversed' then
            MySQL.update.await("UPDATE `es_doj_cases` SET `verdict` = 'reversed' WHERE `id` = ?", { parent.id })
            MySQL.update.await("UPDATE `es_doj_charges` SET `disposition` = 'reversed' WHERE `caseId` = ? AND `disposition` = 'guilty'", { parent.id })
            DOJ.undoPenalties(parent, c, 'Reversed on appeal ' .. k.number)
            DOJ.releaseFromJail(parent, c, 'Conviction reversed on appeal (' .. k.number .. ')')
            DOJ.log(parent.id, c, 'reversed', ('Reversed on appeal %s%s'):format(k.number, note ~= '' and (': ' .. note) or ''))
        elseif r == 'remanded' then
            MySQL.update.await("UPDATE `es_doj_cases` SET `status` = 'open', `stage` = 'pretrial', `closedAt` = NULL, `verdict` = 'none', `verdictAt` = NULL WHERE `id` = ?", { parent.id })
            MySQL.update.await("UPDATE `es_doj_charges` SET `disposition` = 'pending' WHERE `caseId` = ? AND `disposition` IN ('guilty','not_guilty')", { parent.id })
            DOJ.undoPenalties(parent, c, 'Remanded on appeal ' .. k.number)
            DOJ.log(parent.id, c, 'remanded', ('Sent back for a new hearing by appeal %s%s'):format(k.number, note ~= '' and (': ' .. note) or ''))
        else
            DOJ.log(parent.id, c, 'affirmed', ('Affirmed on appeal %s'):format(k.number))
        end
        MySQL.update.await("UPDATE `es_doj_cases` SET `verdict` = ?, `verdictAt` = NOW() WHERE `id` = ?", { r, k.id })
        DOJ.closeCase(DOJ.caseRow(k.id), 'closed', c, ('Appeal %s%s'):format(r, note ~= '' and (': ' .. note) or ''))
        tellParties(parent, ('Appeal ruling: %s %s'):format(parent.number, r), note, 'verdict', c, c.charId)
        return true
    end)

    -- ------------------------------------------------------------ sealing a case
    cb('caseSeal', { role = { 'seal', 'judge' }, write = true }, function(c, d)
        local k, why = load(c, d.caseId, true)
        if not k then return false, why end
        local seal = d.seal == true
        local reason = str(d.reason, 300)
        if seal and reason == '' then return false, 'Give the reason' end
        MySQL.update.await('UPDATE `es_doj_cases` SET `sealed` = ?, `sealedBy` = ?, `sealedAt` = IF(? = 1, NOW(), NULL), `sealReason` = ? WHERE `id` = ?',
            { seal and 1 or 0, seal and c.charId or nil, seal and 1 or 0, seal and reason or nil, k.id })
        if seal then
            MySQL.insert.await([[INSERT INTO `es_doj_seals` (`kind`,`refId`,`charId`,`mode`,`reason`,`byCharId`,`test`) VALUES ('case',?,?,'sealed',?,?,?)
                ON DUPLICATE KEY UPDATE `mode` = 'sealed', `reason` = VALUES(`reason`), `byCharId` = VALUES(`byCharId`)]], { k.id, k.defendantCharId or 0, reason, c.charId, isTest(k) and 1 or 0 })
        else
            MySQL.update.await("DELETE FROM `es_doj_seals` WHERE `kind` = 'case' AND `refId` = ?", { k.id })
        end
        DOJ.log(k.id, c, seal and 'sealed' or 'unsealed', seal and reason or 'Unsealed')
        DOJ.refresh('cases')
        return true
    end)

    -- ------------------------------------------------------------ subpoenas and bench warrants
    cb('subpoenaSave', { write = true, rate = 1500, burst = 4 }, function(c, d)
        local k, side = load(c, d.caseId, true)
        if not k then return false, side end
        if closed(k) then return false, 'The case is closed' end
        if not side and not c.r.court then return false, 'You are not on that case' end
        local who = id(d.charId)
        if not who or not DOJ.charExists(who) then return false, 'Pick the person' end
        local hid = id(d.hearingId)
        if hid and not MySQL.scalar.await("SELECT 1 FROM `es_doj_hearings` WHERE `id` = ? AND `caseId` = ? AND `status` = 'scheduled'", { hid, k.id }) then return false, 'Pick one of this case\'s scheduled hearings' end
        local kind = DOJ.oneOf(d.kind, { 'appear', 'documents' }, 'appear')
        local details = str(d.details, 500)
        local judge = judgeOf(c, k) == true
        local sid = MySQL.insert.await('INSERT INTO `es_doj_subpoenas` (`caseId`,`hearingId`,`charId`,`kind`,`details`,`status`,`requestedBy`,`issuedBy`) VALUES (?,?,?,?,?,?,?,?)',
            { k.id, hid, who, kind, details, judge and 'issued' or 'requested', c.charId, judge and c.charId or nil })
        DOJ.log(k.id, c, judge and 'subpoena' or 'subpoena_req', ('Subpoena %s for %s'):format(judge and 'issued' or 'requested', DOJ.nameOf(who) or ('#' .. who)))
        if judge then
            DOJ.notice(who, ('Subpoena: %s'):format(k.number), ('You are ordered to %s. %s'):format(kind == 'appear' and 'appear in court' or 'hand the court documents', details), k.id, 'subpoena', c.charId, isTest(k))
        elseif k.judgeCharId then
            DOJ.notice(k.judgeCharId, ('Subpoena to sign: %s'):format(k.number), DOJ.nameOf(who), k.id, 'subpoena', c.charId, isTest(k))
        end
        DOJ.refresh('case:' .. k.id)
        return { id = sid }
    end)

    cb('subpoenaAct', { write = true }, function(c, d)
        local s = MySQL.single.await('SELECT `id`,`caseId`,`charId`,`kind`,`details`,`status` FROM `es_doj_subpoenas` WHERE `id` = ?', { id(d.id) or 0 })
        if not s then return false, 'No such subpoena' end
        local k, why = load(c, s.caseId, true)
        if not k then return false, why end
        local act = d.act
        local judge = judgeOf(c, k) == true
        local to
        if act == 'issue' or act == 'deny' or act == 'quash' then
            if not judge then return false, 'Only the case judge does that' end
            if act == 'issue' and s.status ~= 'requested' then return false, 'Not waiting' end
            to = act == 'issue' and 'issued' or (act == 'deny' and 'denied' or 'quashed')
        elseif act == 'served' or act == 'complied' or act == 'ignored' then
            if not (judge or c.r.clerk) then return false, 'Only the court marks that' end
            if s.status == 'requested' or s.status == 'denied' or s.status == 'quashed' then return false, 'It was never issued' end
            to = act
        else return false, 'issue, deny, quash, served, complied or ignored' end
        MySQL.update.await('UPDATE `es_doj_subpoenas` SET `status` = ?, `issuedBy` = IF(? = \'issued\', ?, `issuedBy`) WHERE `id` = ?', { to, to, c.charId, s.id })
        if to == 'issued' then
            DOJ.notice(s.charId, ('Subpoena: %s'):format(k.number), ('You are ordered to %s. %s'):format(s.kind == 'appear' and 'appear in court' or 'hand the court documents', s.details or ''), k.id, 'subpoena', c.charId, isTest(k))
        elseif to == 'quashed' then
            DOJ.notice(s.charId, ('Subpoena withdrawn: %s'):format(k.number), 'You no longer need to answer it.', k.id, 'subpoena', c.charId, isTest(k))
        end
        DOJ.log(k.id, c, 'subpoena_' .. to, ('Subpoena for %s: %s'):format(DOJ.nameOf(s.charId) or ('#' .. s.charId), to))
        DOJ.refresh('case:' .. k.id)
        return true
    end)

    cb('benchWarrant', { role = 'judge', write = true, rate = 5000, burst = 2 }, function(c, d)
        local k, why = load(c, d.caseId, true)
        if not k then return false, why end
        local okj, e = judgeOf(c, k) if not okj then return false, e end
        local who = id(d.charId) or k.defendantCharId
        if not who then return false, 'Who?' end
        local reason = str(d.reason, 400)
        if reason == '' then reason = 'Failure to appear' end
        local full = ('Bench warrant (%s): %s'):format(k.number, reason)
        if isTest(k) then
            DOJ.log(k.id, c, 'bench_warrant', full .. ' [test case: no real warrant]')
            return { test = true }
        end
        if GetResourceState('es_mdt') ~= 'started' then return false, 'The MDT is not running' end
        local ok, wid, err = pcall(function() return exports.es_mdt:IssueWarrant({ charId = who, reason = full, days = int(d.days or 14, 1, 90),
            byCharId = c.charId, byName = c.label, caseId = k.mdtCaseId }) end)
        if not ok or not wid then return false, tostring(ok and err or wid or 'The MDT refused') end
        DOJ.log(k.id, c, 'bench_warrant', ('%s (MDT warrant #%s)'):format(full, tostring(wid)))
        DOJ.notice(who, ('Bench warrant: %s'):format(k.number), 'A judge issued a warrant for your arrest. Turn yourself in.', k.id, 'warrant', c.charId)
        return { id = wid }
    end)
end

-- ---------------------------------------------------------------- helpers other files use
--- A picture from the page: d.image (a data URL the page resized) or d.imageUrl (the server fetches it). image | false, why
function DOJ.imageFrom(d, charId)
    if d.photoId and charId then
        if GetResourceState('es_evidence') ~= 'started' then return false, 'The camera roll is not available' end
        local img = exports.es_evidence:RollImage(charId, id(d.photoId))
        if type(img) ~= 'string' or img:sub(1, 11) ~= 'data:image/' then return false, 'That photo is not in your camera roll' end
        return img
    end
    if type(d.image) == 'string' and d.image ~= '' then
        if not DOJ.isImg(d.image) then return false, 'That picture is too big or not a picture' end
        return d.image
    end
    if type(d.imageUrl) == 'string' and d.imageUrl ~= '' then
        local ok, why = Fetch.check(d.imageUrl)
        if not ok then return false, why end
        local img, err = Fetch.get(d.imageUrl)
        if not img then return false, err end
        if #img > ((Config.Images or {}).maxBytes or 420000) * 2 then return false, 'That picture is too big: save it and use Choose picture (it gets resized)' end
        return img
    end
    return false, 'Add a picture'
end

--- Let them out of es_jail (bail posted, ROR, reversal). Never on a test case.
function DOJ.releaseFromJail(k, c, why)
    if isTest(k) or not k.defendantCharId then return false end
    local ok, jailed = pcall(EsJail.isJailed, k.defendantCharId)
    if not (ok and jailed) then return false end
    local ok2, a = pcall(EsJail.release, k.defendantCharId, c and c.charId, why)
    if ok2 and a then DOJ.log(k.id, c, 'released', why) return true end
    return false
end

--- The bail fee was paid (clerk.lua): posted, out of jail, everyone told
function DOJ.bailPosted(k, fee, c)
    MySQL.update.await("UPDATE `es_doj_cases` SET `bailStatus` = 'posted' WHERE `id` = ?", { k.id })
    DOJ.log(k.id, c, 'bail_posted', ('%s posted ($%d%s)'):format(fee.method == 'bond' and 'Bond' or 'Bail', fee.amount, fee.method == 'bond' and ', not refunded' or ', refunded when the case ends'))
    DOJ.releaseFromJail(k, c, ('Bail posted (%s)'):format(k.number))
    tellParties(k, ('Bail posted: %s'):format(k.number), 'The defendant is released until trial.', 'bail', c, nil)
    DOJ.refresh('case:' .. k.id)
end
