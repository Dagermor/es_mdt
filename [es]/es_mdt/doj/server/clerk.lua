local _ENV = ESAPP('doj'); -- es_doj clerk: court money (fines, fees, bail, restitution; paid through WHIP ChargePlayer), MDT fines paid at the
-- courthouse, petitions (name change, business license, expungement), business licenses and court notices.
local WC, cb, str, int, id = DOJ.WC, DOJ.cb, DOJ.str, DOJ.int, DOJ.id
local F = Config.Fees or {}

local FEE_KINDS = { 'fine', 'fee', 'restitution', 'bail', 'petition', 'copy' }
DOJ.FEE_LABEL = { fine = 'Court fine', fee = 'Court fee', restitution = 'Restitution', bail = 'Bail', petition = 'Filing fee', copy = 'Record copy' }

-- ---------------------------------------------------------------- paying
--- payer = { source, charId, label }. method 'cash' | 'bank'; bond = true pays a bail bond (part, kept by the court).
function DOJ.payFee(payer, feeId, method, bond)
    local f = MySQL.single.await('SELECT * FROM `es_doj_fees` WHERE `id` = ?', { id(feeId) or 0 })
    if not f then return false, 'No such bill' end
    if f.status ~= 'unpaid' then return false, 'That bill is already ' .. f.status end
    method = method == 'cash' and 'cash' or 'bank'
    if bond and f.kind ~= 'bail' then return false, 'A bond is only for bail' end
    if (bond or f.kind == 'bail') and not DOJ.bailOn() then return false, 'This court has no bail' end   -- 2.3.1
    local k = f.caseId and DOJ.caseRow(f.caseId) or nil
    if f.kind == 'bail' and not (k and k.status == 'open' and k.bailStatus == 'set' and k.bailFeeId == f.id) then return false, 'That bail can no longer be paid' end
    local amount = bond and math.ceil(f.amount * ((Config.Bail or {}).bondPercent or 10) / 100) or f.amount
    local test = f.test == 1
    local label = DOJ.FEE_LABEL[f.kind] or 'Court'
    -- claim the bill first (two people paying the same bail at once: one wins, the other is never charged)
    local claimed = MySQL.update.await("UPDATE `es_doj_fees` SET `status` = 'paying' WHERE `id` = ? AND `status` = 'unpaid'", { f.id })
    if (tonumber(claimed) or 0) < 1 then return false, 'That bill is being paid right now' end
    local function unclaim() MySQL.update.await("UPDATE `es_doj_fees` SET `status` = 'unpaid' WHERE `id` = ? AND `status` = 'paying'", { f.id }) end
    local paidSql = { { query = "UPDATE `es_doj_fees` SET `status` = 'paid', `paidAt` = NOW(), `paidBy` = ?, `method` = ? WHERE `id` = ? AND `status` = 'paying'",
        values = { payer.charId, bond and 'bond' or method, f.id } } }
    if test then
        MySQL.update.await(paidSql[1].query, paidSql[1].values)
    else
        local okc, receipt, why = pcall(function() return WC:ChargePlayer(payer.source, amount, { method = method, reason = ('%s #%d%s'):format(bond and 'Bail bond' or label, f.id, k and (' ' .. k.number) or '') }) end)
        if not okc or not receipt then unclaim() return false, okc and why or 'The payment failed' end
        -- the money and the bill land together (WHIP writes the payment in the same transaction)
        local okw = WC:CommitWithAction(paidSql, { source = payer.source })
        if not okw then WC:RefundPlayer(receipt) unclaim() return false, 'Could not save the payment; nothing was taken' end
    end
    -- where the money goes
    if not test then
        if f.mdtFineId and GetResourceState('es_mdt') == 'started' then
            local ok = exports.es_mdt:MarkFinePaid(f.mdtFineId, payer.charId, 'court')
            if not ok then DOJ.deposit(amount, ('%s #%d'):format(label, f.id)) end
        elseif f.kind == 'bail' and not bond then
            -- held: comes back when the case ends (refundBail), or is forfeited to the court
        elseif f.kind == 'restitution' and k and k.kind == 'civil' and k.plaintiffCharId then
            local ok, why = WC:PayPlayer({ charId = k.plaintiffCharId }, amount, { method = 'bank', reason = ('Judgment paid: %s'):format(k.number) })
            if not ok then print(('^1[es_doj] judgment %s: paying the plaintiff failed (%s); kept by the court^7'):format(k.number, tostring(why))) DOJ.deposit(amount, 'Judgment ' .. k.number) end
        else
            DOJ.deposit(amount, ('%s #%d%s'):format(bond and 'Bail bond' or label, f.id, k and (' ' .. k.number) or ''))
        end
    end
    if f.warrantId and GetResourceState('es_mdt') == 'started' then pcall(function() exports.es_mdt:CloseWarrant(f.warrantId, 'served', payer.charId) end) end
    if f.kind == 'petition' then MySQL.update.await('UPDATE `es_doj_petitions` SET `paid` = 1 WHERE `feeId` = ?', { f.id }) DOJ.refresh('petitions') end
    if f.kind == 'bail' and k then DOJ.bailPosted(k, { method = bond and 'bond' or method, amount = amount }, payer) end
    if f.caseId then DOJ.log(f.caseId, payer, 'paid', ('%s #%d paid: $%d (%s)%s'):format(label, f.id, amount, bond and 'bond' or method, payer.charId ~= f.charId and (' by ' .. (payer.label or '?')) or '')) end
    if payer.charId ~= f.charId then DOJ.notice(f.charId, ('%s paid for you'):format(label), ('%s paid $%d.'):format(payer.label or 'Someone', amount), f.caseId, 'payment', payer.charId, test) end
    DOJ.refresh('fees')
    return { amount = amount, method = bond and 'bond' or method, test = test }
end

--- An MDT fine paid at the courthouse (the court takes the money; es_mdt marks it paid and pays the department)
function DOJ.payMdtFine(payer, fineId, method)
    if GetResourceState('es_mdt') ~= 'started' then return false, 'The MDT is not running' end
    local f = MySQL.single.await("SELECT `id`,`charId`,`amount`,`status` FROM `es_mdt_fines` WHERE `id` = ?", { id(fineId) or 0 })
    if not f or f.status ~= 'unpaid' then return false, 'That fine is not owing' end
    -- 2.1.0: a contested ticket waits for the judge (the payment is paused)
    if MySQL.scalar.await('SELECT `contested` FROM `es_mdt_fines` WHERE `id` = ?', { f.id }) == 1 then return false, 'That ticket is contested: wait for the ruling' end
    local receipt, why = WC:ChargePlayer(payer.source, f.amount, { method = method == 'cash' and 'cash' or 'bank', reason = ('Police fine #%d (paid at court)'):format(f.id) })
    if not receipt then return false, why end
    local ok, err = exports.es_mdt:MarkFinePaid(f.id, payer.charId, 'court')
    if not ok then WC:RefundPlayer(receipt) return false, err end
    if payer.charId ~= f.charId then DOJ.notice(f.charId, 'Police fine paid for you', ('%s paid fine #%d ($%d).'):format(payer.label or 'Someone', f.id, f.amount), nil, 'payment', payer.charId) end
    return { amount = f.amount }
end

--- What a person owes the court and the police (portal, clerk)
function DOJ.billsOf(cid)
    local fees = MySQL.query.await([[SELECT f.`id`,f.`kind`,f.`amount`,f.`reason`,f.`status`,f.`caseId`,f.`test`,k.`number`,UNIX_TIMESTAMP(f.`dueAt`) AS `dueAt`,UNIX_TIMESTAMP(f.`createdAt`) AS `createdAt`
        FROM `es_doj_fees` f LEFT JOIN `es_doj_cases` k ON k.`id` = f.`caseId` WHERE f.`charId` = ? AND f.`status` = 'unpaid' ORDER BY f.`id`]], { cid }) or {}
    for _, f in ipairs(fees) do
        f.label = DOJ.FEE_LABEL[f.kind] or f.kind
        f.test = f.test == 1
        if f.kind == 'bail' then f.bond = math.ceil(f.amount * ((Config.Bail or {}).bondPercent or 10) / 100) end
    end
    local fines = GetResourceState('es_mdt') == 'started' and MySQL.query.await([[SELECT f.`id`,f.`amount`,f.`reason`,f.`reportId`,d.`short` AS `dept`,UNIX_TIMESTAMP(f.`createdAt`) AS `createdAt`,
        f.`kind`,f.`ticketId`,f.`contested`,UNIX_TIMESTAMP(f.`dueAt`) AS `dueAt`
        FROM `es_mdt_fines` f LEFT JOIN `es_departments` d ON d.`id` = f.`deptId` WHERE f.`charId` = ? AND f.`status` = 'unpaid' ORDER BY f.`id`]], { cid }) or {}
    local paid = MySQL.query.await([[SELECT `id`,`kind`,`amount`,`reason`,`status`,`method`,UNIX_TIMESTAMP(`paidAt`) AS `paidAt` FROM `es_doj_fees`
        WHERE `charId` = ? AND `status` IN ('paid','refunded') ORDER BY `paidAt` DESC LIMIT 15]], { cid }) or {}
    for _, f in ipairs(paid) do f.label = DOJ.FEE_LABEL[f.kind] or f.kind end
    if not DOJ.bailOn() then   -- 2.3.1: bail bills (old ones stay in the table) are not shown or paid
        local a, b = {}, {}
        for _, f in ipairs(fees) do if f.kind ~= 'bail' then f.bond = nil a[#a + 1] = f end end
        for _, f in ipairs(paid) do if f.kind ~= 'bail' and f.method ~= 'bond' then b[#b + 1] = f end end
        return { fees = a, fines = fines, paid = b }
    end
    return { fees = fees, fines = fines, paid = paid, bondPercent = (Config.Bail or {}).bondPercent or 10 }
end

-- ---------------------------------------------------------------- petitions
local PET = {
    name_change = { label = 'Legal name change', fee = function() return F.nameChange or 0 end, role = { 'clerk', 'judge' } },
    business    = { label = 'Business license', fee = function() return F.businessLicense or 0 end, role = { 'clerk', 'judge' } },
    expungement = { label = 'Record expungement', fee = function() return F.expungement or 0 end, role = { 'judge', 'seal' } },
}
DOJ.PET = PET

local function nameOk(s) return #s >= 2 and #s <= 30 and s:match('^[%a][%a %-]*[%a]$') ~= nil and select(2, s:gsub('%a', '')) >= 2 end

--- Who files: charId. data per kind. Returns { id, fee } | false, why
function DOJ.petitionCreate(charId, kind, data, reason, test, byCharId)
    local P = PET[kind]
    if not P then return false, 'Pick what you are asking for' end
    data = type(data) == 'table' and data or {}
    reason = str(reason, 1000)
    if MySQL.scalar.await("SELECT 1 FROM `es_doj_petitions` WHERE `charId` = ? AND `kind` = ? AND `status` = 'pending' LIMIT 1", { charId, kind }) then
        return false, 'You already have one of these waiting'
    end
    local clean = {}
    if kind == 'name_change' then
        clean.firstName, clean.lastName = str(data.firstName, 30), str(data.lastName, 30)
        if not (nameOk(clean.firstName) and nameOk(clean.lastName)) then return false, 'Names use letters, spaces and hyphens (2 to 30 letters each)' end
        local cd = (Config.NameChange or {}).cooldownDays or 30
        if cd > 0 and not test and MySQL.scalar.await("SELECT 1 FROM `es_doj_petitions` WHERE `charId` = ? AND `kind` = 'name_change' AND `status` = 'approved' AND `test` = 0 AND `decidedAt` > NOW() - INTERVAL ? DAY LIMIT 1", { charId, cd }) then
            return false, ('You changed your name in the last %d days'):format(cd)
        end
        if reason == '' then return false, 'Say why you want the change' end
        local cur = DOJ.nameOf(charId)
        clean.oldName = cur
        if cur == clean.firstName .. ' ' .. clean.lastName then return false, 'That is already your name' end
    elseif kind == 'business' then
        clean.name, clean.kind, clean.address = str(data.name, 80), str(data.kind, 40), str(data.address, 160)
        if #clean.name < 3 then return false, 'Name the business' end
        if MySQL.scalar.await("SELECT 1 FROM `es_doj_businesses` WHERE LOWER(`name`) = LOWER(?) AND `status` IN ('active','suspended') LIMIT 1", { clean.name }) then return false, 'A business with that name is already licensed' end
    elseif kind == 'expungement' then
        clean.reports, clean.cases = {}, {}
        for _, x in ipairs(type(data.reports) == 'table' and data.reports or {}) do
            x = id(x)
            if x and #clean.reports < 20 and MySQL.scalar.await('SELECT 1 FROM `es_mdt_report_people` WHERE `reportId` = ? AND `charId` = ?', { x, charId }) then clean.reports[#clean.reports + 1] = x end
        end
        for _, x in ipairs(type(data.cases) == 'table' and data.cases or {}) do
            x = id(x)
            if x and #clean.cases < 20 and MySQL.scalar.await("SELECT 1 FROM `es_doj_cases` WHERE `id` = ? AND `defendantCharId` = ? AND `status` <> 'open'", { x, charId }) then clean.cases[#clean.cases + 1] = x end
        end
        if #clean.reports + #clean.cases == 0 then return false, 'Pick the records (only closed cases can be expunged)' end
        if reason == '' then return false, 'Say why the court should clear them' end
    end
    local fee = P.fee()
    local pid = MySQL.insert.await([[INSERT INTO `es_doj_petitions` (`kind`,`charId`,`dataJson`,`reason`,`fee`,`paid`,`test`,`createdBy`) VALUES (?,?,?,?,?,?,?,?)]],
        { kind, charId, json.encode(clean), reason, fee, fee == 0 and 1 or 0, test and 1 or 0, byCharId or charId })
    if fee > 0 then
        local fid = DOJ.addFee(charId, 'petition', fee, ('%s #%d'):format(P.label, pid), nil, byCharId or charId, test, 0)
        MySQL.update.await('UPDATE `es_doj_petitions` SET `feeId` = ? WHERE `id` = ?', { fid, pid })
    end
    DOJ.refresh('petitions')
    return { id = pid, fee = fee }
end

local function petitionRow(pid)
    local p = MySQL.single.await([[SELECT `id`,`kind`,`charId`,`dataJson`,`reason`,`status`,`fee`,`paid`,`feeId`,`decidedBy`,`decidedByLabel`,`decisionNote`,`test`,
        UNIX_TIMESTAMP(`createdAt`) AS `createdAt`,UNIX_TIMESTAMP(`decidedAt`) AS `decidedAt` FROM `es_doj_petitions` WHERE `id` = ?]], { pid })
    if not p then return nil end
    local ok, dd = pcall(json.decode, p.dataJson or '{}')
    p.data = ok and type(dd) == 'table' and dd or {}
    p.dataJson = nil
    p.paid, p.test = p.paid == 1, p.test == 1
    p.label = PET[p.kind] and PET[p.kind].label or p.kind
    return p
end
DOJ.petitionRow = petitionRow

local function licenseNo()
    local n = (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM `es_doj_businesses`')) or 0) + 1
    for _ = 1, 50 do
        local no = ('BL-%s-%04d'):format(os.date('%Y'), n)
        if not MySQL.scalar.await('SELECT 1 FROM `es_doj_businesses` WHERE `licenseNo` = ?', { no }) then return no end
        n = n + 1
    end
    return ('BL-%s-%d'):format(os.date('%Y'), os.time())
end

function DOJ.petitionDecide(c, d)
    local p = petitionRow(id(d.id) or 0)
    if not p then return false, 'No such petition' end
    if p.status ~= 'pending' then return false, 'Already ' .. p.status end
    local P = PET[p.kind]
    local may = c.staff
    for _, r in ipairs(P.role) do if c.r[r] then may = true end end
    if not may then return false, p.kind == 'expungement' and 'Only a judge grants an expungement' or 'Only the clerk or a judge decides this' end
    local decision = d.decision == 'approve' and 'approved' or (d.decision == 'deny' and 'denied' or nil)
    if not decision then return false, 'approve or deny' end
    local note = str(d.note, 300)
    if decision == 'denied' and note == '' then return false, 'Say why (they read it)' end
    if decision == 'approved' and not p.paid and not p.test then
        if d.waive and (c.r.judge or c.staff) then
            if p.feeId then MySQL.update.await("UPDATE `es_doj_fees` SET `status` = 'void' WHERE `id` = ? AND `status` = 'unpaid'", { p.feeId }) end
        else
            return false, ('The $%d fee is not paid yet%s'):format(p.fee, (c.r.judge or c.staff) and ' (a judge may waive it)' or '')
        end
    end
    local n = MySQL.update.await("UPDATE `es_doj_petitions` SET `status` = ?, `decidedBy` = ?, `decidedByLabel` = ?, `decisionNote` = ?, `decidedAt` = NOW() WHERE `id` = ? AND `status` = 'pending'",
        { decision, c.charId, c.label, note ~= '' and note or nil, p.id })
    if (tonumber(n) or 0) < 1 then return false, 'Someone decided it first' end
    local result
    if decision == 'approved' then
        if p.kind == 'name_change' then
            if p.test then result = 'test: no rename'
            else
                local ok, full, old = WC:RenameCharacter({ charId = p.charId }, p.data.firstName, p.data.lastName)
                if not ok then
                    MySQL.update.await("UPDATE `es_doj_petitions` SET `status` = 'pending', `decidedBy` = NULL, `decidedByLabel` = NULL, `decisionNote` = NULL, `decidedAt` = NULL WHERE `id` = ?", { p.id })
                    return false, 'The rename was refused: ' .. tostring(full)
                end
                result = ('%s is now %s'):format(tostring(old or p.data.oldName or '?'), tostring(full))
            end
        elseif p.kind == 'business' then
            local years = F.businessYears or 1
            local no = licenseNo()
            MySQL.insert.await([[INSERT INTO `es_doj_businesses` (`licenseNo`,`name`,`kind`,`ownerCharId`,`address`,`issuedBy`,`expiresAt`,`petitionId`,`test`)
                VALUES (?,?,?,?,?,?,IF(? > 0, NOW() + INTERVAL ? YEAR, NULL),?,?)]], { no, p.data.name, p.data.kind, p.charId, p.data.address, c.charId, years, years, p.id, p.test and 1 or 0 })
            result = ('License %s'):format(no)
        elseif p.kind == 'expungement' then
            for _, rid in ipairs(p.data.reports or {}) do DOJ.applySeal(c, 'report', rid, p.charId, 'expunged', 'Expungement petition #' .. p.id, p.id, p.test) end
            for _, kid in ipairs(p.data.cases or {}) do DOJ.applySeal(c, 'case', kid, p.charId, 'expunged', 'Expungement petition #' .. p.id, p.id, p.test) end
            result = ('%d record(s) expunged'):format(#(p.data.reports or {}) + #(p.data.cases or {}))
        end
    else
        if p.feeId then MySQL.update.await("UPDATE `es_doj_fees` SET `status` = 'void' WHERE `id` = ? AND `status` = 'unpaid'", { p.feeId }) end
    end
    DOJ.log(nil, c, 'petition_' .. decision, ('%s #%d (%s): %s%s'):format(P.label, p.id, DOJ.nameOf(p.charId) or ('#' .. p.charId), decision, result and (' — ' .. result) or ''))
    DOJ.notice(p.charId, ('%s %s'):format(P.label, decision), (decision == 'approved' and (result or 'Granted') or note) .. (decision == 'approved' and note ~= '' and ('. ' .. note) or ''), nil, 'petition', c.charId, p.test)
    DOJ.refresh('petitions')
    return { result = result }
end

-- ---------------------------------------------------------------- the clerk's desk
function DOJ.registerClerk()
    cb('fees', { role = { 'clerk', 'cases', 'judge', 'prosecutor' } }, function(_, d)
        local where, args = {}, {}
        local st = DOJ.oneOf(d.status, { 'unpaid', 'paid', 'overdue', 'all' }, 'unpaid')
        if st == 'overdue' then where[#where + 1] = "f.`status` = 'unpaid' AND f.`dueAt` < NOW()"
        elseif st ~= 'all' then where[#where + 1] = 'f.`status` = ?' args[#args + 1] = st end
        local who = id(d.charId)
        if who then where[#where + 1] = 'f.`charId` = ?' args[#args + 1] = who end
        if not DOJ.bailOn() then where[#where + 1] = "f.`kind` <> 'bail'" end   -- 2.3.1: old bail rows stay, unseen
        local rows = MySQL.query.await(([[SELECT f.`id`,f.`charId`,f.`kind`,f.`amount`,f.`reason`,f.`status`,f.`method`,f.`caseId`,f.`test`,f.`warrantId`,k.`number`,
            UNIX_TIMESTAMP(f.`dueAt`) AS `dueAt`,UNIX_TIMESTAMP(f.`paidAt`) AS `paidAt`,UNIX_TIMESTAMP(f.`createdAt`) AS `createdAt`
            FROM `es_doj_fees` f LEFT JOIN `es_doj_cases` k ON k.`id` = f.`caseId` %s ORDER BY f.`id` DESC LIMIT 150]]):format(#where > 0 and ('WHERE ' .. table.concat(where, ' AND ')) or ''), args) or {}
        local ids = {}
        for _, r in ipairs(rows) do ids[#ids + 1] = r.charId end
        local names = DOJ.namesOf(ids)
        local total = 0
        for _, r in ipairs(rows) do
            r.name = names[r.charId] r.label = DOJ.FEE_LABEL[r.kind] or r.kind r.test = r.test == 1
            if r.status == 'unpaid' then total = total + r.amount end
        end
        return { rows = rows, total = total }
    end)

    cb('feeCreate', { role = { 'clerk', 'judge' }, write = true, rate = 1500, burst = 4 }, function(c, d)
        local who = id(d.charId)
        if not who or not DOJ.charExists(who) then return false, 'Pick the person' end
        local kind = DOJ.oneOf(d.kind, { 'fee', 'fine', 'restitution', 'copy' }, 'fee')
        if kind == 'fine' and not (c.r.judge or c.staff) then return false, 'Only a judge imposes a fine' end
        local amount = int(d.amount, 0, (Config.Sentence or {}).maxFine or 1000000)
        if amount < 1 then return false, 'Enter the amount' end
        local reason = str(d.reason, 200)
        if reason == '' then return false, 'Say what it is for' end
        local k = id(d.caseId) and DOJ.caseRow(d.caseId) or nil
        local fid = DOJ.addFee(who, kind, amount, reason, k and k.id or nil, c.charId, k and DOJ.isTest(k), F.dueDays)
        if k then DOJ.log(k.id, c, 'fee', ('%s $%d: %s'):format(DOJ.FEE_LABEL[kind], amount, reason)) end
        DOJ.notice(who, ('%s: $%d'):format(DOJ.FEE_LABEL[kind], amount), ('%s. Pay at the courthouse (/%s, Payments).'):format(reason, Config.PortalCommand or 'court'), k and k.id or nil, 'payment', c.charId, k and DOJ.isTest(k))
        return { id = fid }
    end)

    cb('feeVoid', { role = { 'clerk', 'judge' }, write = true }, function(c, d)
        local f = MySQL.single.await('SELECT `id`,`charId`,`kind`,`amount`,`status`,`caseId`,`warrantId` FROM `es_doj_fees` WHERE `id` = ?', { id(d.id) or 0 })
        if not f then return false, 'No such bill' end
        if f.status ~= 'unpaid' then return false, 'Only an unpaid bill can be waived' end
        if (f.kind == 'fine' or f.kind == 'restitution' or f.kind == 'bail') and not (c.r.judge or c.staff) then return false, 'Only a judge waives a fine or restitution' end
        local reason = str(d.reason, 200)
        if reason == '' then return false, 'Say why' end
        MySQL.update.await("UPDATE `es_doj_fees` SET `status` = 'void' WHERE `id` = ? AND `status` = 'unpaid'", { f.id })
        if f.warrantId and GetResourceState('es_mdt') == 'started' then pcall(function() exports.es_mdt:CloseWarrant(f.warrantId, 'void', c.charId) end) end
        DOJ.log(f.caseId, c, 'fee_void', ('%s #%d ($%d) waived: %s'):format(DOJ.FEE_LABEL[f.kind] or f.kind, f.id, f.amount, reason))
        DOJ.notice(f.charId, ('%s waived'):format(DOJ.FEE_LABEL[f.kind] or 'Bill'), ('$%d: %s'):format(f.amount, reason), f.caseId, 'payment', c.charId)
        DOJ.refresh('fees')
        return true
    end)

    cb('petitions', { role = { 'clerk', 'judge', 'seal', 'cases' } }, function(_, d)
        local st = DOJ.oneOf(d.status, { 'pending', 'approved', 'denied', 'all' }, 'pending')
        local where, args = {}, {}
        if st ~= 'all' then where[#where + 1] = '`status` = ?' args[#args + 1] = st end
        if PET[d.kind] then where[#where + 1] = '`kind` = ?' args[#args + 1] = d.kind end
        local rows = MySQL.query.await(([[SELECT `id` FROM `es_doj_petitions` %s ORDER BY `id` %s LIMIT 100]]):format(#where > 0 and ('WHERE ' .. table.concat(where, ' AND ')) or '',
            st == 'pending' and 'ASC' or 'DESC'), args) or {}
        local out, ids = {}, {}
        for _, r in ipairs(rows) do local p = petitionRow(r.id) if p then out[#out + 1] = p ids[#ids + 1] = p.charId end end
        local names = DOJ.namesOf(ids)
        for _, p in ipairs(out) do p.name = names[p.charId] end
        return out
    end)

    cb('petition', { role = { 'clerk', 'judge', 'seal', 'cases' } }, function(c, d)
        local p = petitionRow(id(d.id) or 0)
        if not p then return false, 'No such petition' end
        p.name = DOJ.nameOf(p.charId)
        if p.kind == 'expungement' then
            p.reports, p.cases = {}, {}
            for _, rid in ipairs(p.data.reports or {}) do
                local r = MySQL.single.await([[SELECT r.`id`,r.`type`,r.`title`,UNIX_TIMESTAMP(r.`createdAt`) AS `createdAt`,
                    (SELECT GROUP_CONCAT(g.`code` SEPARATOR ', ') FROM `es_mdt_report_charges` g WHERE g.`reportId` = r.`id` AND g.`charId` = ?) AS `charges` FROM `es_mdt_reports` r WHERE r.`id` = ?]], { p.charId, rid })
                if r then p.reports[#p.reports + 1] = r end
            end
            for _, kid in ipairs(p.data.cases or {}) do
                local k = DOJ.caseRow(kid)
                if k then p.cases[#p.cases + 1] = { id = k.id, number = k.number, title = k.title, verdict = k.verdict, closedAt = k.closedAt } end
            end
            p.record = DOJ.recordSummary(p.charId)
        end
        p.canDecide = not c.readOnly
        return p
    end)

    cb('petitionDecide', { write = true }, function(c, d) return DOJ.petitionDecide(c, d) end)

    cb('businesses', {}, function(_, d)
        local q = str(d.q, 60)
        local where, args = {}, {}
        if q ~= '' then
            where[#where + 1] = [[(b.`name` LIKE CONCAT('%', ?, '%') OR b.`licenseNo` LIKE CONCAT('%', ?, '%') OR b.`ownerCharId` IN
                (SELECT `charId` FROM `characters` WHERE CONCAT(`firstName`,' ',`lastName`) LIKE CONCAT('%', ?, '%')))]]
            args = { q, q, q }
        end
        if DOJ.oneOf(d.status, { 'active', 'suspended', 'revoked', 'expired' }, nil) then
            if d.status == 'expired' then where[#where + 1] = "b.`status` = 'active' AND b.`expiresAt` < NOW()"
            else where[#where + 1] = 'b.`status` = ?' args[#args + 1] = d.status end
        end
        local rows = MySQL.query.await(([[SELECT b.`id`,b.`licenseNo`,b.`name`,b.`kind`,b.`ownerCharId`,b.`address`,b.`status`,b.`note`,b.`test`,
            UNIX_TIMESTAMP(b.`issuedAt`) AS `issuedAt`,UNIX_TIMESTAMP(b.`expiresAt`) AS `expiresAt` FROM `es_doj_businesses` b %s ORDER BY b.`name` LIMIT 150]])
            :format(#where > 0 and ('WHERE ' .. table.concat(where, ' AND ')) or ''), args) or {}
        local ids = {}
        for _, r in ipairs(rows) do ids[#ids + 1] = r.ownerCharId end
        local names = DOJ.namesOf(ids)
        for _, r in ipairs(rows) do r.owner = names[r.ownerCharId] r.expired = r.expiresAt and r.expiresAt < os.time() or false r.test = r.test == 1 end
        return rows
    end)

    cb('businessAct', { role = { 'clerk', 'judge' }, write = true }, function(c, d)
        local b = MySQL.single.await('SELECT `id`,`name`,`licenseNo`,`ownerCharId`,`status` FROM `es_doj_businesses` WHERE `id` = ?', { id(d.id) or 0 })
        if not b then return false, 'No such license' end
        local act = d.act
        local note = str(d.note, 300)
        if act == 'suspend' or act == 'revoke' then
            if note == '' then return false, 'Say why' end
            MySQL.update.await('UPDATE `es_doj_businesses` SET `status` = ?, `note` = ? WHERE `id` = ?', { act == 'suspend' and 'suspended' or 'revoked', note, b.id })
        elseif act == 'reinstate' then
            MySQL.update.await("UPDATE `es_doj_businesses` SET `status` = 'active', `note` = ? WHERE `id` = ?", { note ~= '' and note or nil, b.id })
        elseif act == 'renew' then
            local years = math.max(1, F.businessYears or 1)
            MySQL.update.await("UPDATE `es_doj_businesses` SET `status` = 'active', `expiresAt` = GREATEST(COALESCE(`expiresAt`, NOW()), NOW()) + INTERVAL ? YEAR WHERE `id` = ?", { years, b.id })
        elseif act == 'edit' then
            local name, kind, addr = str(d.name, 80), str(d.kind, 40), str(d.address, 160)
            if #name < 3 then return false, 'Name the business' end
            MySQL.update.await('UPDATE `es_doj_businesses` SET `name` = ?, `kind` = ?, `address` = ? WHERE `id` = ?', { name, kind, addr, b.id })
        else return false, 'suspend, revoke, reinstate, renew or edit' end
        DOJ.log(nil, c, 'business_' .. act, ('%s (%s)%s'):format(b.name, b.licenseNo, note ~= '' and (': ' .. note) or ''))
        if act ~= 'edit' then DOJ.notice(b.ownerCharId, ('Business license %s: %s'):format(b.licenseNo, act), note, nil, 'license', c.charId) end
        DOJ.refresh('businesses')
        return true
    end)

    cb('businessCreate', { role = { 'clerk', 'judge' }, write = true, rate = 2000, burst = 3 }, function(c, d)
        local who = id(d.charId)
        if not who or not DOJ.charExists(who) then return false, 'Pick the owner' end
        local name, kind, addr = str(d.name, 80), str(d.kind, 40), str(d.address, 160)
        if #name < 3 then return false, 'Name the business' end
        if MySQL.scalar.await("SELECT 1 FROM `es_doj_businesses` WHERE LOWER(`name`) = LOWER(?) AND `status` IN ('active','suspended') LIMIT 1", { name }) then return false, 'A business with that name is already licensed' end
        local years = F.businessYears or 1
        local no = licenseNo()
        local bid = MySQL.insert.await([[INSERT INTO `es_doj_businesses` (`licenseNo`,`name`,`kind`,`ownerCharId`,`address`,`issuedBy`,`expiresAt`,`note`)
            VALUES (?,?,?,?,?,?,IF(? > 0, NOW() + INTERVAL ? YEAR, NULL),?)]], { no, name, kind, who, addr, c.charId, years, years, str(d.note, 300) })
        DOJ.log(nil, c, 'business_issued', ('%s (%s) to %s'):format(name, no, DOJ.nameOf(who) or ('#' .. who)))
        DOJ.notice(who, ('Business license issued: %s'):format(no), name, nil, 'license', c.charId)
        DOJ.refresh('businesses')
        return { id = bid, licenseNo = no }
    end)

    cb('noticeSend', { role = { 'clerk', 'judge', 'cases', 'prosecutor', 'defender' }, write = true, rate = 1500, burst = 4 }, function(c, d)
        local who = id(d.charId)
        if not who or not DOJ.charExists(who) then return false, 'Pick the person' end
        local title = str(d.title, 160)
        if title == '' then return false, 'Give it a title' end
        local k = id(d.caseId) and DOJ.caseRow(d.caseId) or nil
        local nid = DOJ.notice(who, title, str(d.body, 1000), k and k.id or nil, 'notice', c.charId, k and DOJ.isTest(k))
        if k then DOJ.log(k.id, c, 'notice', ('Notice to %s: %s'):format(DOJ.nameOf(who) or ('#' .. who), title)) end
        return { id = nid }
    end)
end
