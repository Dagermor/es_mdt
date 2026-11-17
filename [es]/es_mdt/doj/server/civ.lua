local _ENV = ESAPP('doj'); -- es_doj portal: /court (and the clerk's window at the courthouse) for everyone: your cases and hearings, court
-- notices, paying fines, fees and bail (yours or someone else's), plea offers, petitions (name change, business
-- license, expungement), civil suits, lawyers, public records. Also community service sentences.
local WC, str, int, id = DOJ.WC, DOJ.str, DOJ.int, DOJ.id

-- ---------------------------------------------------------------- the portal's callback wrapper (any character)
function DOJ.pcb(name, opts, fn)
    Whip.core:SecureCallback('es_doj:pub:' .. name, { rateLimit = opts.rate or 300, burst = opts.burst or 6, sheet = 'light',
        params = { { 'd', 'any' } } }, function(source, _, d)
        local charId = WC:GetCharId(source)
        if not charId then return false, 'No character' end
        local nm = DOJ.nameOf(charId) or ('#' .. charId)
        local p = { source = source, charId = charId, name = nm, label = nm, r = {}, staff = false }
        local ok, a, b = pcall(fn, p, type(d) == 'table' and d or {})
        if not ok then
            print(('^1[es_doj] pub:%s failed: %s^7'):format(name, tostring(a)))
            return false, 'Something went wrong (the server console says why)'
        end
        return a, b
    end)
end
local pcb = DOJ.pcb

local function myCase(p, caseId)
    local k = DOJ.caseRow(caseId)
    if not k then return nil, 'No such case' end
    if k.defendantCharId ~= p.charId and k.plaintiffCharId ~= p.charId then return nil, 'Not your case' end
    return k
end

-- ---------------------------------------------------------------- community service
local Svc = {}      -- [charId] = { spot = i, point = pointId, busy = bool }
local S = Config.Service or {}

local function svcLeft(cid)
    local r = MySQL.single.await("SELECT COALESCE(SUM(`total` - `done`), 0) AS `left`, COUNT(*) AS `n` FROM `es_doj_service` WHERE `charId` = ? AND `status` = 'active'", { cid }) or {}
    return tonumber(r.left) or 0
end

local function svcClear(cid)
    local s = Svc[cid]
    if not s then return end
    if s.point then pcall(function() WC:RemovePoint(s.point) end) end
    pcall(function() WC:HideBlip('svc:' .. cid) end)
    Svc[cid] = nil
end

local svcPlace
local function svcPress(source, cid)
    local s = Svc[cid]
    if not s or s.busy then return end
    if WC:GetCharId(source) ~= cid then return false, 'That is not for you' end
    s.busy = true
    CreateThread(function()
        local spot = S.spots[s.spot]
        local done = WC:Progress(source, { label = S.label or 'Community service...', duration = (S.seconds or 8) * 1000, anim = S.anim,
            near = { coords = spot, range = 4.0 }, tag = 'es_doj:svc' })
        s.busy = false
        if not done then return end
        local row = MySQL.single.await("SELECT `id`,`total`,`done`,`caseId`,`test` FROM `es_doj_service` WHERE `charId` = ? AND `status` = 'active' ORDER BY `id` LIMIT 1", { cid })
        if not row then svcClear(cid) return end
        local n = row.done + 1
        MySQL.update.await("UPDATE `es_doj_service` SET `done` = ?, `status` = IF(? >= `total`, 'done', `status`), `doneAt` = IF(? >= `total`, NOW(), `doneAt`) WHERE `id` = ?", { n, n, n, row.id })
        local left = svcLeft(cid)
        if left <= 0 then
            svcClear(cid)
            WC:NotifyPlayer(source, 'Community service complete. Thank you.', 'success', 8000)
            if row.caseId then DOJ.log(row.caseId, { charId = cid, label = DOJ.nameOf(cid) or '?', source = source }, 'service_done', 'Community service completed') end
            DOJ.notice(cid, 'Community service complete', 'Your community service sentence is served.', row.caseId, 'sentence', nil, row.test == 1)
        else
            WC:NotifyPlayer(source, ('Done. %d task%s left: the next spot is on your map.'):format(left, left == 1 and '' or 's'), 'info', 6000)
            svcPlace(cid, source)
        end
    end)
    return true
end

svcPlace = function(cid, source)
    if not S.spots or #S.spots == 0 then return end
    local s = Svc[cid] or {}
    local pick = math.random(1, #S.spots)
    if #S.spots > 1 and pick == s.spot then pick = pick % #S.spots + 1 end
    if s.point then pcall(function() WC:RemovePoint(s.point) end) end
    s.spot, s.point, s.busy = pick, nil, false
    Svc[cid] = s
    local c = S.spots[pick]
    local pid = WC:AddPoint({ at = { coords = c }, label = 'Community service', icon = 'pickup', reach = 2.5, seeFrom = 15.0,
        audience = { people = { { charId = cid } } }, tag = 'es_doj:svc',
        options = { { id = 'work', label = S.label and S.label:gsub('%.+$', '') or 'Pick up litter' } },
        onUse = function(src) return svcPress(src, cid) end })
    s.point = pid or nil
    WC:ShowBlip({ people = { { charId = cid } } }, 'svc:' .. cid, { coords = c, label = 'Community service', sprite = 318, color = 2, route = true })
    if source then WC:NotifyPlayer(source, 'Community service: your spot is marked on the map.', 'info', 6000) end
end

--- Their community service changed (sentenced, voided, logged in): put up (or take down) their spot
function DOJ.serviceChanged(cid)
    cid = id(cid)
    if not cid then return end
    local src = DOJ.onlineByChar()[cid]
    if not src or svcLeft(cid) <= 0 then svcClear(cid) return end
    if not Svc[cid] then svcPlace(cid, src) end
end

AddEventHandler('whip_core:player:loaded', function(e)
    if not e or not e.charId or e.phantom then return end
    CreateThread(function() Wait(4000) DOJ.serviceChanged(e.charId) end)
end)
AddEventHandler('whip_core:player:logout', function(e) if e and e.charId then svcClear(e.charId) end end)

-- ---------------------------------------------------------------- the portal
local function notices(cid)
    return MySQL.query.await([[SELECT `id`,`caseId`,`kind`,`title`,`body`,`test`,UNIX_TIMESTAMP(`createdAt`) AS `at`,UNIX_TIMESTAMP(`readAt`) AS `readAt`
        FROM `es_doj_notices` WHERE `charId` = ? ORDER BY `id` DESC LIMIT 40]], { cid }) or {}
end

function DOJ.registerPortal()
    pcb('home', { rate = 400 }, function(p)
        local cid = p.charId
        local out = { me = { charId = cid, name = p.name }, fees = DOJ.billsOf(cid) }
        out.cases = MySQL.query.await([[SELECT k.`id`,k.`number`,k.`kind`,k.`title`,k.`status`,k.`stage`,k.`verdict`,k.`bailStatus`,k.`bailAmount`,k.`defendantCharId`,k.`plaintiffCharId`,
            k.`defenseCharId`,k.`defenseKind`,k.`test`,UNIX_TIMESTAMP(k.`createdAt`) AS `createdAt`,
            (SELECT UNIX_TIMESTAMP(MIN(h.`startsAt`)) FROM `es_doj_hearings` h WHERE h.`caseId` = k.`id` AND h.`status` = 'scheduled' AND h.`startsAt` > NOW() - INTERVAL 1 HOUR) AS `next`,
            (SELECT COUNT(*) FROM `es_doj_pleas` pl WHERE pl.`caseId` = k.`id` AND pl.`status` = 'offered') AS `offers`
            FROM `es_doj_cases` k WHERE (k.`defendantCharId` = ? OR k.`plaintiffCharId` = ?) ORDER BY (k.`status` = 'open') DESC, k.`id` DESC LIMIT 30]], { cid, cid }) or {}
        local ids = {}
        for _, k in ipairs(out.cases) do ids[#ids + 1] = k.defenseCharId end
        local names = DOJ.namesOf(ids)
        for _, k in ipairs(out.cases) do
            k.stageLabel = k.status == 'open' and DOJ.stageLabel(k.stage) or (k.status == 'dismissed' and 'Dismissed' or 'Closed')
            k.defense = names[k.defenseCharId or 0]
            k.role = k.defendantCharId == cid and 'defendant' or 'plaintiff'
            k.test = k.test == 1
        end
        out.notices = notices(cid)
        out.unread = 0
        for _, n in ipairs(out.notices) do if not n.readAt then out.unread = out.unread + 1 end end
        out.subpoenas = MySQL.query.await([[SELECT s.`id`,s.`kind`,s.`details`,s.`status`,k.`number`,UNIX_TIMESTAMP(h.`startsAt`) AS `startsAt`,h.`room`
            FROM `es_doj_subpoenas` s JOIN `es_doj_cases` k ON k.`id` = s.`caseId` LEFT JOIN `es_doj_hearings` h ON h.`id` = s.`hearingId`
            WHERE s.`charId` = ? AND s.`status` IN ('issued','served') ORDER BY s.`id` DESC LIMIT 10]], { cid }) or {}
        out.lawyers = MySQL.query.await("SELECT `attorneyCharId` AS `charId` FROM `es_doj_clients` WHERE `clientCharId` = ? AND `status` = 'active'", { cid }) or {}
        ids = {}
        for _, l in ipairs(out.lawyers) do ids[#ids + 1] = l.charId end
        names = DOJ.namesOf(ids)
        for _, l in ipairs(out.lawyers) do l.name = names[l.charId] local b = DOJ.barOf(l.charId) l.number = b and b.number l.phone = b and b.phone l.firm = b and b.firm end
        out.petitions = MySQL.query.await([[SELECT `id`,`kind`,`status`,`fee`,`paid`,`decisionNote`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt`,UNIX_TIMESTAMP(`decidedAt`) AS `decidedAt`
            FROM `es_doj_petitions` WHERE `charId` = ? ORDER BY `id` DESC LIMIT 15]], { cid }) or {}
        for _, x in ipairs(out.petitions) do x.label = DOJ.PET[x.kind] and DOJ.PET[x.kind].label or x.kind x.paid = x.paid == 1 end
        out.businesses = MySQL.query.await("SELECT `id`,`licenseNo`,`name`,`kind`,`status`,UNIX_TIMESTAMP(`expiresAt`) AS `expiresAt` FROM `es_doj_businesses` WHERE `ownerCharId` = ? ORDER BY `id` DESC", { cid }) or {}
        out.service = svcLeft(cid)
        out.summary = DOJ.recordSummary(cid)
        out.fees.petitionFees = { name_change = (Config.Fees or {}).nameChange or 0, business = (Config.Fees or {}).businessLicense or 0, expungement = (Config.Fees or {}).expungement or 0,
            filing = (Config.Fees or {}).filing or 0 }
        out.courthouse = Config.Courthouse.label
        return out
    end)

    pcb('case', {}, function(p, d)
        local k, why = myCase(p, d.id)
        if not k then return false, why end
        local side = k.defendantCharId == p.charId and 'defense' or 'plaintiff'
        local vis = side == 'defense' and "('public','parties','defense')" or "('public','parties')"
        k.charges = DOJ.chargeList(k.id)
        k.hearings = MySQL.query.await([[SELECT `id`,`kind`,`title`,UNIX_TIMESTAMP(`startsAt`) AS `startsAt`,`minutes`,`room`,`status`,`outcome` FROM `es_doj_hearings`
            WHERE `caseId` = ? ORDER BY `startsAt`]], { k.id }) or {}
        k.filings = MySQL.query.await(([[SELECT `id`,`kind`,`title`,`body`,(`image` IS NOT NULL) AS `hasImage`,`exhibitNo`,`side`,`status`,`ruling`,`byLabel`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt`
            FROM `es_doj_filings` WHERE `caseId` = ? AND `visibility` IN %s ORDER BY `id`]]):format(vis), { k.id }) or {}
        for _, f in ipairs(k.filings) do f.hasImage = f.hasImage == 1 or f.hasImage == true end
        k.pleas = side == 'defense' and (MySQL.query.await([[SELECT `id`,`terms`,`fine`,`months`,`service`,`probationDays`,`status`,`offeredByLabel`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt`
            FROM `es_doj_pleas` WHERE `caseId` = ? ORDER BY `id` DESC]], { k.id }) or {}) or {}
        k.sentences = MySQL.query.await('SELECT `source`,`fine`,`months`,`service`,`probationDays`,`restitution`,`notes`,`status`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt` FROM `es_doj_sentences` WHERE `caseId` = ?', { k.id }) or {}
        local names = DOJ.namesOf({ k.judgeCharId, k.prosecutorCharId, k.defenseCharId, k.defendantCharId, k.plaintiffCharId })
        k.judge, k.prosecutor, k.defense = names[k.judgeCharId or 0], names[k.prosecutorCharId or 0], names[k.defenseCharId or 0]
        k.defendant, k.plaintiff = names[k.defendantCharId or 0], names[k.plaintiffCharId or 0] or k.plaintiffName
        k.stageLabel = k.status == 'open' and DOJ.stageLabel(k.stage) or (k.status == 'dismissed' and 'Dismissed' or 'Closed')
        k.role = side == 'defense' and 'defendant' or 'plaintiff'
        k.bond = math.ceil((k.bailAmount or 0) * ((Config.Bail or {}).bondPercent or 10) / 100)
        k.summary = k.summary
        k.sealed, k.test = k.sealed == 1, k.test == 1
        k.canAppeal = k.status ~= 'open' and k.kind ~= 'appeal' and k.defendantCharId == p.charId
            and not MySQL.scalar.await("SELECT 1 FROM `es_doj_cases` WHERE `parentId` = ? AND `status` = 'open'", { k.id })
        return k
    end)

    pcb('filingImage', { rate = 300, burst = 10 }, function(p, d)
        local f = MySQL.single.await('SELECT `caseId`,`visibility`,`image` FROM `es_doj_filings` WHERE `id` = ?', { id(d.id) or 0 })
        if not f or not f.image then return false, 'No picture' end
        local k = myCase(p, f.caseId)
        if not k then return false, 'Not your case' end
        local ok = f.visibility == 'public' or f.visibility == 'parties' or (f.visibility == 'defense' and k.defendantCharId == p.charId)
        if not ok then return false, 'Not yours to see' end
        return f.image
    end)

    pcb('noticeRead', { rate = 200, burst = 10 }, function(p, d)
        if d.all then MySQL.update.await('UPDATE `es_doj_notices` SET `readAt` = NOW() WHERE `charId` = ? AND `readAt` IS NULL', { p.charId })
        else MySQL.update.await('UPDATE `es_doj_notices` SET `readAt` = NOW() WHERE `id` = ? AND `charId` = ? AND `readAt` IS NULL', { id(d.id) or 0, p.charId }) end
        return true
    end)

    pcb('pay', { rate = 2000, burst = 3 }, function(p, d)
        return DOJ.payFee(p, d.id, d.method, d.bond == true)
    end)

    pcb('payFine', { rate = 2000, burst = 3 }, function(p, d)
        return DOJ.payMdtFine(p, d.id, d.method)
    end)

    -- pay for someone else (bail, a fine): find them, see what they owe (amounts only)
    pcb('people', { rate = 400, burst = 6 }, function(_, d)
        local q = str(d.q, 40)
        if #q < 3 then return {} end
        local rows = MySQL.query.await([[SELECT `charId`,`firstName`,`lastName` FROM `characters` WHERE `deleted` IS NULL AND CONCAT(`firstName`,' ',`lastName`) LIKE CONCAT('%', ?, '%')
            ORDER BY `lastName` LIMIT 10]], { q }) or {}
        for _, r in ipairs(rows) do r.name = r.firstName .. ' ' .. r.lastName r.firstName, r.lastName = nil, nil end
        return rows
    end)
    pcb('billsFor', { rate = 600, burst = 4 }, function(_, d)
        local who = id(d.charId)
        if not who then return false, 'Pick the person' end
        local b = DOJ.billsOf(who)
        for _, f in ipairs(b.fees) do f.reason = nil end
        b.paid = nil
        b.name = DOJ.nameOf(who)
        return b
    end)

    pcb('plea', { rate = 2000, burst = 3 }, function(p, d)
        if d.act ~= 'accept' and d.act ~= 'reject' then return false, 'accept or reject' end
        return DOJ.pleaAct(p, d, true)
    end)

    pcb('petition', { rate = 5000, burst = 2 }, function(p, d)
        return DOJ.petitionCreate(p.charId, d.kind, d.data, d.reason, false, p.charId)
    end)

    pcb('myRecords', { rate = 1000, burst = 3 }, function(p)
        local reports = MySQL.query.await([[SELECT r.`id`,r.`type`,r.`title`,UNIX_TIMESTAMP(r.`createdAt`) AS `createdAt`,
            (SELECT GROUP_CONCAT(CONCAT(g.`code`,' ',g.`title`) SEPARATOR ', ') FROM `es_mdt_report_charges` g WHERE g.`reportId` = r.`id` AND g.`charId` = pp.`charId`) AS `charges`
            FROM `es_mdt_report_people` pp JOIN `es_mdt_reports` r ON r.`id` = pp.`reportId` WHERE pp.`charId` = ? AND pp.`role` = 'suspect' ORDER BY r.`id` DESC LIMIT 60]], { p.charId }) or {}
        local marks = DOJ.courtMarks('report', nil, p.charId)
        local out = {}
        for _, r in ipairs(reports) do if marks[r.id] ~= 'expunged' then r.sealed = marks[r.id] == 'sealed' out[#out + 1] = r end end
        local cases = MySQL.query.await([[SELECT `id`,`number`,`title`,`verdict`,UNIX_TIMESTAMP(`closedAt`) AS `closedAt` FROM `es_doj_cases`
            WHERE `defendantCharId` = ? AND `status` <> 'open' AND `test` = 0 ORDER BY `id` DESC LIMIT 30]], { p.charId }) or {}
        local cm = DOJ.courtMarks('case', nil, p.charId)
        local cs = {}
        for _, k in ipairs(cases) do if cm[k.id] ~= 'expunged' then cs[#cs + 1] = k end end
        return { reports = out, cases = cs }
    end)

    pcb('civil', { rate = 10000, burst = 2 }, function(p, d)
        local who = id(d.defendantCharId)
        if not who or who == p.charId then return false, 'Pick who you are suing' end
        local summary = str(d.summary, 4000)
        if #summary < 20 then return false, 'Say what happened and what you ask for (at least a few sentences)' end
        local open = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM `es_doj_cases` WHERE `plaintiffCharId` = ? AND `status` = 'open'", { p.charId })) or 0
        if open >= 3 then return false, 'You already have 3 open civil cases' end
        local res, why = DOJ.createCase(nil, { kind = 'civil', title = str(d.title, 160), summary = summary, defendantCharId = who, plaintiffCharId = p.charId })
        if not res then return false, why end
        MySQL.update.await('UPDATE `es_doj_cases` SET `createdBy` = ? WHERE `id` = ?', { p.charId, res.id })
        local fee = (Config.Fees or {}).filing or 0
        if fee > 0 then DOJ.addFee(p.charId, 'fee', fee, ('Filing fee: %s'):format(res.number), res.id, p.charId, false, (Config.Fees or {}).dueDays) end
        DOJ.log(res.id, p, 'filed_civil', ('Filed by %s'):format(p.name))
        return res
    end)

    pcb('appeal', { rate = 10000, burst = 2 }, function(p, d)
        local k, why = myCase(p, d.caseId)
        if not k then return false, why end
        if k.defendantCharId ~= p.charId then return false, 'Only the defendant appeals here' end
        if k.status == 'open' or k.kind == 'appeal' then return false, 'Appeal once the case is closed' end
        if MySQL.scalar.await("SELECT 1 FROM `es_doj_cases` WHERE `parentId` = ? AND `status` = 'open' LIMIT 1", { k.id }) then return false, 'An appeal is already open' end
        local reason = str(d.reason, 4000)
        if #reason < 20 then return false, 'Write the grounds for the appeal' end
        local res, e = DOJ.createCase(nil, { kind = 'appeal', title = ('Appeal: %s'):format(k.title):sub(1, 160), summary = reason, defendantCharId = k.defendantCharId,
            mdtCaseId = k.mdtCaseId, parentId = k.id, test = DOJ.isTest(k), importReport = false })
        if not res then return false, e end
        MySQL.update.await('UPDATE `es_doj_cases` SET `prosecutorCharId` = ?, `defenseCharId` = ?, `defenseKind` = ?, `reportId` = ?, `createdBy` = ? WHERE `id` = ?',
            { k.prosecutorCharId, k.defenseCharId, k.defenseKind, k.reportId, p.charId, res.id })
        MySQL.update.await([[INSERT INTO `es_doj_charges` (`caseId`,`penalId`,`code`,`title`,`category`,`count`,`fine`,`months`,`plea`,`disposition`)
            SELECT ?,`penalId`,`code`,`title`,`category`,`count`,`fine`,`months`,`plea`,`disposition` FROM `es_doj_charges` WHERE `caseId` = ?]], { res.id, k.id })
        local fee = (Config.Fees or {}).appeal or 0
        if fee > 0 then DOJ.addFee(p.charId, 'fee', fee, ('Appeal fee: %s'):format(res.number), res.id, p.charId, DOJ.isTest(k), (Config.Fees or {}).dueDays) end
        DOJ.log(k.id, p, 'appealed', ('Appeal %s filed by the defendant'):format(res.number))
        DOJ.tellParties(k, ('Appeal filed: %s'):format(res.number), ('Against %s.'):format(k.number), 'case', p, p.charId)
        return res
    end)

    pcb('lawyers', { rate = 600 }, function() return DOJ.lawyers(true) end)

    pcb('hire', { rate = 5000, burst = 2 }, function(p, d)
        local who = id(d.charId)
        local b = who and DOJ.barOf(who)
        if not b or b.status ~= 'active' then return false, 'Pick a licensed attorney' end
        if who == p.charId then return false, 'You cannot hire yourself' end
        DOJ.notice(who, ('%s wants to hire you'):format(p.name), ('%s%s. Add them under Clients in the DOJ tablet to take the case.'):format(str(d.message, 300) ~= '' and (str(d.message, 300) .. ' — ') or '', p.name), nil, 'lawyer', p.charId)
        return true
    end)

    pcb('fire', { rate = 3000, burst = 2 }, function(p, d)
        local who = id(d.charId)
        local n = who and MySQL.update.await("UPDATE `es_doj_clients` SET `status` = 'ended', `endedAt` = NOW() WHERE `attorneyCharId` = ? AND `clientCharId` = ? AND `status` = 'active'", { who, p.charId }) or 0
        if (tonumber(n) or 0) < 1 then return false, 'Not your lawyer' end
        MySQL.update.await("UPDATE `es_doj_cases` SET `defenseCharId` = NULL, `defenseKind` = 'none' WHERE `defenseCharId` = ? AND `defendantCharId` = ? AND `status` = 'open'", { who, p.charId })
        DOJ.notice(who, ('%s ended your representation'):format(p.name), nil, nil, 'lawyer', p.charId)
        return true
    end)

    pcb('publicDefender', { rate = 10000, burst = 2 }, function(p, d)
        local k, why = myCase(p, d.caseId)
        if not k then return false, why end
        if k.defendantCharId ~= p.charId or k.status ~= 'open' then return false, 'Ask on an open case against you' end
        if k.defenseCharId then return false, 'You already have a lawyer on this case' end
        MySQL.update.await("UPDATE `es_doj_cases` SET `defenseKind` = 'public' WHERE `id` = ?", { k.id })
        DOJ.log(k.id, p, 'pd_requested', 'The defendant asked for a public defender')
        local dep = DOJ.dept()
        local online = DOJ.onlineByChar()
        if dep then
            for _, m in ipairs(DOJ.ED:GetRoster(dep.id) or {}) do
                if online[m.charId] and WC:HasJobPermission(online[m.charId], dep.jobId, 'doj_defend', { onDuty = false }) == true then
                    DOJ.notice(m.charId, ('Public defender needed: %s'):format(k.number), ('%s asked for a public defender.'):format(p.name), k.id, 'case', p.charId, DOJ.isTest(k))
                end
            end
        end
        return true
    end)

    pcb('records', { rate = 600, burst = 4 }, function(_, d)
        local q = str(d.q, 60)
        if #q < 3 then return { cases = {}, businesses = {}, lawyers = {} } end
        local cases = MySQL.query.await([[SELECT k.`id`,k.`number`,k.`kind`,k.`title`,k.`status`,k.`verdict`,UNIX_TIMESTAMP(k.`createdAt`) AS `createdAt`,UNIX_TIMESTAMP(k.`closedAt`) AS `closedAt`
            FROM `es_doj_cases` k WHERE k.`sealed` = 0 AND k.`test` = 0 AND k.`kind` <> 'petition' AND (k.`number` LIKE CONCAT('%', ?, '%') OR k.`title` LIKE CONCAT('%', ?, '%'))
            ORDER BY k.`id` DESC LIMIT 25]], { q, q }) or {}
        local biz = MySQL.query.await([[SELECT `licenseNo`,`name`,`kind`,`status`,UNIX_TIMESTAMP(`expiresAt`) AS `expiresAt` FROM `es_doj_businesses`
            WHERE `test` = 0 AND (`name` LIKE CONCAT('%', ?, '%') OR `licenseNo` LIKE CONCAT('%', ?, '%')) ORDER BY `name` LIMIT 25]], { q, q }) or {}
        local lawyers = {}
        for _, l in ipairs(DOJ.lawyers(false)) do
            if l.name:lower():find(q:lower(), 1, true) or l.number:lower():find(q:lower(), 1, true) then
                lawyers[#lawyers + 1] = { name = l.name, number = l.number, status = l.status, kind = l.kind, firm = l.firm }
            end
        end
        return { cases = cases, businesses = biz, lawyers = lawyers }
    end)

    -- the courthouse window and blip (the client asks once)
    Whip.core:SecureCallback('es_doj:pub:places', { rateLimit = 2000, burst = 3, params = {} }, function()
        local out = {}
        for i, D in ipairs(Config.Courthouse.desks or {}) do out[#out + 1] = { i = i, label = D.label, x = D.coords.x, y = D.coords.y, z = D.coords.z } end
        return { desks = out, label = Config.Courthouse.label, blip = Config.Courthouse.blip, portal = Config.PortalCommand, tablet = Config.Command, key = Config.Key }
    end)
end

AddEventHandler('onResourceStop', function(r)
    if r ~= GetCurrentResourceName() then return end
    for cid in pairs(Svc) do pcall(function() WC:HideBlip('svc:' .. cid) end) end
end)
