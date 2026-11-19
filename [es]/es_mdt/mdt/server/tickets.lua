local _ENV = ESAPP('mdt'); -- es_mdt 2.1.0: roadside tickets (citations, parking tickets, warnings), invoices and contests.
--
-- A ticket is written at the roadside (/ticket, or a controller button) without opening the MDT. The officer picks the
-- person, or for a parking ticket the vehicle, from who and what is close (the server checks the distance again), and the
-- charges from the penal code (the fines come from the penal code here, never from the page). A person is asked to sign:
--   signed            = accepted. It must be paid.
--   refused / no answer in Config.Tickets.signSeconds / logged off = UNSIGNED. It can be contested (Config.Tickets.contests).
-- Parking tickets have nobody to sign (unsigned: the owner may contest). Warnings carry no fine and no signature.
-- The money is an invoice (Config.Invoices, es_mdt_fines with a due date): paid in the court portal, or taken from the
-- bank on the due day. Both sides get a paper copy (the es_mdt_citation item) and the recipient a text (texts.lua).
--
-- A contest pauses the invoice (the due date stops, no warrant, no collection). The issuing officer is asked for a
-- statement; a judge rules: dismiss (the invoice is voided), reduce (a new amount) or uphold (the remaining time runs
-- again). No ruling within Config.Tickets.contestLapseDays: dismissed in the citizen's favour, the DOJ warned
-- contestWarnDays before. Loaded BEFORE server/main.lua; runs from MDT.registerTickets().
local WC = exports.whip_core
MDT = MDT or {}

local ITEM = 'es_mdt_citation'
local KIND = { citation = 'Citation', parking = 'Parking ticket', warning = 'Written warning' }
local PREFIX = { citation = 'C', parking = 'P', warning = 'W' }

local function TK() return type(Config.Tickets) == 'table' and Config.Tickets or {} end
local function INV() return type(Config.Invoices) == 'table' and Config.Invoices or {} end
local function contestsOn()
    if TK().contests == false then return false end
    return GetResourceState('es_doj') == 'started'   -- the DOJ part (es_mdt's own; reported started while it runs)
end
local function money(n) return ('$%s'):format(tostring(math.floor(tonumber(n) or 0)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')) end
local function dateOf(ts) return ts and os.date('%d %b %Y', ts) or '?' end

local function nameOf(cid)
    if not cid then return nil end
    local n = MDT.namesOf and MDT.namesOf({ cid }) or {}
    return n[cid] or ('#' .. cid)
end

--- where the player stands (server side) or nil
local function posOf(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end
local function dist(a, b) return a and b and #(vector3(a.x, a.y, a.z) - vector3(b.x, b.y, b.z)) or math.huge end

-- ---------------------------------------------------------------- reading a ticket
local function chargesOf(raw)
    local ok, t = pcall(json.decode, raw or '[]')
    return ok and type(t) == 'table' and t or {}
end

local function ticketRow(tid)
    local t = MySQL.single.await([[SELECT t.*, UNIX_TIMESTAMP(t.`createdAt`) AS `at`, UNIX_TIMESTAMP(t.`signedAt`) AS `signedTs`,
        d.`short` AS `dept`, d.`name` AS `deptName`, f.`status` AS `fineStatus`, f.`amount` AS `fineAmount`, UNIX_TIMESTAMP(f.`dueAt`) AS `dueAt`,
        f.`contested`, f.`pausedSecs`, UNIX_TIMESTAMP(f.`paidAt`) AS `paidAt`
        FROM `es_mdt_tickets` t LEFT JOIN `es_departments` d ON d.`id` = t.`deptId` LEFT JOIN `es_mdt_fines` f ON f.`id` = t.`fineId`
        WHERE t.`id` = ?]], { tid })
    if not t then return nil end
    t.charges = chargesOf(t.charges)
    t.kindLabel = KIND[t.kind] or t.kind
    t.person = t.charId and nameOf(t.charId) or nil
    t.createdAt = nil t.signedAt = nil
    local k = MySQL.single.await([[SELECT `id`,`reason`,`statement`,`statementBy`,UNIX_TIMESTAMP(`statementAt`) AS `statementAt`,`status`,`ruling`,`reducedTo`,
        `rulingNote`,`judgeName`,UNIX_TIMESTAMP(`ruledAt`) AS `ruledAt`,UNIX_TIMESTAMP(`lapseAt`) AS `lapseAt`,UNIX_TIMESTAMP(`createdAt`) AS `at`
        FROM `es_mdt_ticket_contests` WHERE `ticketId` = ?]], { tid })
    t.contest = k
    t.contestable = t.status == 'issued' and t.sign ~= 'signed' and t.kind ~= 'warning' and t.fineStatus == 'unpaid' and not k and contestsOn()
    return t
end
MDT.ticketRow = ticketRow

--- what a ticket says, for a text
local function ticketLine(t)
    local what = {}
    for _, ch in ipairs(t.charges or {}) do what[#what + 1] = (ch.count or 1) > 1 and ('%s x%d'):format(ch.title, ch.count) or ch.title end
    return table.concat(what, ', ')
end

-- ---------------------------------------------------------------- the paper (an item both sides carry)
local function givePaper(src, t, copy, charId)
    if TK().paper == false or not src then return end
    CreateThread(function()
        -- the online map was read before the database waits: still the same character on that source?
        if charId and WC:GetCharId(src) ~= charId then return end
        WC:AddItem(src, ITEM, 1, { ticketId = t.id, number = t.number, kind = t.kindLabel, total = t.total > 0 and money(t.total) or 'No fine',
            copy = copy }, { reason = 'es_mdt ticket ' .. t.number })
    end)
end

-- ---------------------------------------------------------------- filing (after the signature, or at once)
local Sign = {}      -- [token] = { ticketId, src, charId, c, expires, officerSrc }
local BySrc = {}     -- [recipient source] = token

--- file it: sign = 'signed' | 'unsigned' | 'none' (parking) | 'na' (warning). The invoice, the papers, the text.
local function finalize(tid, c, sign, why)
    local n = MySQL.update.await("UPDATE `es_mdt_tickets` SET `sign` = ?, `signedAt` = IF(? = 'signed', NOW(), NULL) WHERE `id` = ? AND `sign` = 'pending'",
        { sign, sign, tid })
    if (tonumber(n) or 0) < 1 then return nil end
    local t = ticketRow(tid)
    if not t then return nil end
    if t.total > 0 and t.kind ~= 'warning' and t.charId then
        local r = MDT.issueFine(c, t.charId, t.total, ('%s %s'):format(t.kindLabel, t.number), nil, { kind = t.kind, ticketId = t.id, quiet = true })
        if type(r) == 'table' and r.id then
            MySQL.update.await('UPDATE `es_mdt_tickets` SET `fineId` = ? WHERE `id` = ?', { r.id, t.id })
            if r.paid then MySQL.update.await("UPDATE `es_mdt_tickets` SET `status` = 'paid' WHERE `id` = ?", { t.id }) end
        end
        t = ticketRow(tid)
    end
    local online = MDT.onlineByChar()
    givePaper(online[t.officerCharId], t, 'Officer copy', t.officerCharId)
    if t.charId and t.kind ~= 'parking' then givePaper(online[t.charId], t, 'Your copy', t.charId) end
    if t.charId then
        local lines = { ('%s %s from %s'):format(t.kindLabel, t.number, t.dept or 'the police') }
        lines[#lines + 1] = ticketLine(t) ~= '' and ticketLine(t) or nil
        if t.plate then lines[#lines + 1] = ('Vehicle %s%s'):format(t.plate, t.vehicleLabel and (' (' .. t.vehicleLabel .. ')') or '') end
        if t.kind == 'warning' then lines[#lines + 1] = 'A warning: nothing to pay.'
        elseif t.fineStatus == 'paid' then lines[#lines + 1] = ('%s paid.'):format(money(t.total))
        elseif t.fineStatus == 'unpaid' then
            lines[#lines + 1] = ('%s due %s. Pay at /%s (Payments)%s.'):format(money(t.total), dateOf(t.dueAt), ((ESPART('doj') or {}).Config or {}).PortalCommand or 'court',
                INV().autoCollect ~= false and ', or it is taken from your bank on that day' or '')
            if t.sign ~= 'signed' and contestsOn() then lines[#lines + 1] = 'Not signed: you may contest it before then in the court portal.' end
        end
        MDT.text(t.charId, table.concat(lines, '\n'), { kind = 'ticket', title = ('%s %s'):format(t.kindLabel, t.number), online = online })
    end
    MDT.refresh('tickets')
    MDT.refresh('fines')
    TriggerEvent('es_mdt:ticket:issued', { ticketId = t.id, number = t.number, kind = t.kind, charId = t.charId, vehicleId = t.vehicleId, plate = t.plate, total = t.total,
        sign = t.sign, fineId = t.fineId, officerCharId = t.officerCharId, deptId = t.deptId })
    if c and c.source then pcall(MDT.log, c, 'ticket', ('%s %s char %s $%d %s%s'):format(t.kindLabel, t.number, tostring(t.charId), t.total, sign, why and (' (' .. why .. ')') or '')) end
    return t
end

local function signDone(token, signed, why)
    local s = Sign[token]
    if not s then return end
    Sign[token] = nil
    if BySrc[s.src] == token then BySrc[s.src] = nil end
    TriggerClientEvent('es_mdt:client:tkSignClose', s.src, token)
    local t = finalize(s.ticketId, s.c, signed and 'signed' or 'unsigned', why)
    if s.officerSrc and t then TriggerClientEvent('es_mdt:client:tkSigned', s.officerSrc, { id = t.id, sign = t.sign, why = why }) end
end

AddEventHandler('playerDropped', function()
    local tok = BySrc[source]
    if tok then signDone(tok, false, 'logged off') end
end)

-- ---------------------------------------------------------------- invoices: reminders, the due day, the bank
local function invoiceSweep()
    if INV().enabled == false then return end
    local online = MDT.onlineByChar()
    local hrs = math.max(0, tonumber(INV().reminderHours) or 24)
    if hrs > 0 then
        local due = MySQL.query.await([[SELECT `id`,`charId`,`amount`,`reason`,UNIX_TIMESTAMP(`dueAt`) AS `dueAt` FROM `es_mdt_fines`
            WHERE `status` = 'unpaid' AND `contested` = 0 AND `dueAt` IS NOT NULL AND `remindedAt` IS NULL AND `dueAt` > NOW() AND `dueAt` <= NOW() + INTERVAL ? HOUR LIMIT 100]], { hrs }) or {}
        for _, f in ipairs(due) do
            MySQL.update.await('UPDATE `es_mdt_fines` SET `remindedAt` = NOW() WHERE `id` = ?', { f.id })
            MDT.text(f.charId, ('Reminder: %s (%s) is due %s. Pay it at /%s.'):format(money(f.amount), f.reason or ('fine #' .. f.id), os.date('%d %b %H:%M', f.dueAt),
                ((ESPART('doj') or {}).Config or {}).PortalCommand or 'court'), { kind = 'invoice', title = 'Payment reminder', online = online })
        end
    end
    local late = MySQL.query.await([[SELECT `id`,`deptId`,`charId`,`amount`,`reason`,`status`,`issuedBy` FROM `es_mdt_fines`
        WHERE `status` = 'unpaid' AND `contested` = 0 AND `dueAt` IS NOT NULL AND `dueAt` <= NOW() AND `collectTriedAt` IS NULL LIMIT 100]]) or {}
    local days = tonumber(Config.UnpaidFineWarrantDays) or 0
    for _, f in ipairs(late) do
        MySQL.update.await('UPDATE `es_mdt_fines` SET `collectTriedAt` = NOW() WHERE `id` = ?', { f.id })
        local ok = false
        if INV().autoCollect ~= false then ok = MDT.payFine(f) end
        if not ok then
            MDT.text(f.charId, ('%s (%s) is overdue: your bank could not cover it. Pay it at /%s%s.'):format(money(f.amount), f.reason or ('fine #' .. f.id),
                ((ESPART('doj') or {}).Config or {}).PortalCommand or 'court',
                days > 0 and (' within %d day(s), or a warrant is issued'):format(days) or ''), { kind = 'invoice', title = 'Payment overdue', online = online })
        end
    end
end

-- a paid fine (bank on the due day, the court portal, an officer's "mark paid"): its ticket follows, the payer is told
function MDT.onFinePaid(fineId, how)
    local f = MySQL.single.await('SELECT `id`,`charId`,`amount`,`reason`,`ticketId`,`impoundId` FROM `es_mdt_fines` WHERE `id` = ?', { fineId })
    if not f then return end
    if f.ticketId then MySQL.update.await("UPDATE `es_mdt_tickets` SET `status` = 'paid' WHERE `id` = ? AND `status` = 'issued'", { f.ticketId }) MDT.refresh('tickets') end
    if f.impoundId and MDT.onImpoundFeePaid then pcall(MDT.onImpoundFeePaid, f.impoundId, f) end
    TriggerEvent('es_mdt:fine:paid', { fineId = f.id, charId = f.charId, amount = f.amount, ticketId = f.ticketId, impoundId = f.impoundId, how = how })
    MDT.text(f.charId, ('Payment received: %s for %s%s. Thank you.'):format(money(f.amount), f.reason or ('fine #' .. f.id), how == 'bank' and ' (from your bank)' or ''),
        { kind = 'invoice', title = 'Payment received' })
end

-- a new invoice from the MDT (a report's fines, a custom fine): the person is told what and when
function MDT.onInvoice(fineId)
    local f = MySQL.single.await([[SELECT f.`id`,f.`charId`,f.`amount`,f.`reason`,UNIX_TIMESTAMP(f.`dueAt`) AS `dueAt`,d.`short` AS `dept` FROM `es_mdt_fines` f
        LEFT JOIN `es_departments` d ON d.`id` = f.`deptId` WHERE f.`id` = ?]], { fineId })
    if not f then return end
    MDT.text(f.charId, ('Fine from %s: %s (%s), due %s. Pay it at /%s%s.'):format(f.dept or 'the police', money(f.amount), f.reason or ('#' .. f.id), dateOf(f.dueAt),
        ((ESPART('doj') or {}).Config or {}).PortalCommand or 'court', INV().autoCollect ~= false and ', or it is taken from your bank on that day' or ''),
        { kind = 'invoice', title = 'Police fine ' .. money(f.amount) })
end

-- ---------------------------------------------------------------- contests
local function lapseDays() return math.max(1, math.floor(tonumber(TK().contestLapseDays) or 5)) end

--- the citizen contests an unsigned ticket (court portal). p = { source, charId }
function MDT.contestTicket(p, tid, reason)
    if not contestsOn() then return false, 'Tickets cannot be contested on this server: they must be paid' end
    reason = tostring(reason or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 1000)
    if #reason < 10 then return false, 'Say why you contest it (10 letters at least)' end
    local t = ticketRow(tonumber(tid) or 0)
    if not t or t.charId ~= p.charId then return false, 'Not your ticket' end
    if t.sign == 'signed' then return false, 'You signed this ticket: it can only be paid' end
    if not t.contestable then return false, t.contest and 'You already contested it' or 'This ticket can no longer be contested' end
    if t.dueAt and t.dueAt <= os.time() then return false, 'It is past its due date' end
    local cid = MySQL.insert.await('INSERT INTO `es_mdt_ticket_contests` (`ticketId`,`charId`,`reason`,`lapseAt`) VALUES (?,?,?,NOW() + INTERVAL ? DAY)',
        { t.id, p.charId, reason, lapseDays() })
    if not cid then return false, 'Could not file it' end
    -- the deadline stops: what is left of it comes back after an uphold / reduce
    MySQL.update.await([[UPDATE `es_mdt_fines` SET `contested` = 1, `pausedSecs` = GREATEST(0, TIMESTAMPDIFF(SECOND, NOW(), `dueAt`)), `dueAt` = NULL
        WHERE `id` = ? AND `status` = 'unpaid']], { t.fineId })
    MDT.text(t.officerCharId, ('%s %s (%s) was contested. File your statement: MDT > Tickets.'):format(t.kindLabel, t.number, t.person or 'a citizen'),
        { kind = 'contest', title = 'Ticket contested: ' .. t.number })
    MDT.text(p.charId, ('Your contest of %s %s is filed. The payment is paused until a judge rules (at the latest in %d days; no ruling by then and it is dismissed).')
        :format(t.kindLabel, t.number, lapseDays()), { kind = 'contest', title = 'Contest filed: ' .. t.number })
    MDT.refresh('tickets')
    if MDT.dojRefresh then pcall(MDT.dojRefresh) end
    return { id = cid }
end

--- the officer's (or a supervisor's) statement
local function fileStatement(c, tid, text)
    text = tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 1000)
    if #text < 10 then return false, 'Write the statement (10 letters at least)' end
    local t = ticketRow(tid)
    if not t or not t.contest or t.contest.status ~= 'open' then return false, 'That ticket has no open contest' end
    if not (t.officerCharId == c.charId or c.staff or c.perms.canManage or MDT.isHighCommand(c)) then return false, 'Only the issuing officer or a supervisor files the statement' end
    MySQL.update.await('UPDATE `es_mdt_ticket_contests` SET `statement` = ?, `statementBy` = ?, `statementAt` = NOW() WHERE `id` = ?', { text, c.name, t.contest.id })
    MDT.refresh('tickets')
    if MDT.dojRefresh then pcall(MDT.dojRefresh) end
    return true
end

--- the ruling. j = { charId, name }. ruling = 'dismiss' | 'reduce' | 'uphold' | 'lapsed'
function MDT.ruleContest(j, contestId, ruling, amount, note)
    local k = MySQL.single.await('SELECT * FROM `es_mdt_ticket_contests` WHERE `id` = ?', { tonumber(contestId) or 0 })
    if not k or k.status ~= 'open' then return false, 'That contest is not open' end
    local t = ticketRow(k.ticketId)
    if not t then return false, 'No such ticket' end
    note = tostring(note or ''):sub(1, 500)
    local newAmt
    if ruling == 'reduce' then
        newAmt = math.floor(tonumber(amount) or -1)
        if newAmt < 1 or newAmt >= (t.fineAmount or t.total) then return false, ('A reduced fine is between $1 and %s'):format(money((t.fineAmount or t.total) - 1)) end
    elseif ruling ~= 'dismiss' and ruling ~= 'uphold' and ruling ~= 'lapsed' then return false, 'dismiss, reduce or uphold' end
    local n = MySQL.update.await([[UPDATE `es_mdt_ticket_contests` SET `status` = 'ruled', `ruling` = ?, `reducedTo` = ?, `rulingNote` = NULLIF(?, ''),
        `judgeCharId` = ?, `judgeName` = ?, `ruledAt` = NOW() WHERE `id` = ? AND `status` = 'open']], { ruling, newAmt, note, j and j.charId, j and j.name, k.id })
    if (tonumber(n) or 0) < 1 then return false, 'Someone ruled on it just now' end
    local back = 'GREATEST(COALESCE(`pausedSecs`, 0), 86400)'   -- what was left of the time, at least a day
    if ruling == 'dismiss' or ruling == 'lapsed' then
        if t.fineId then
            MySQL.update.await("UPDATE `es_mdt_fines` SET `status` = 'void', `contested` = 0 WHERE `id` = ? AND `status` = 'unpaid'", { t.fineId })
            MDT.closeAutoWarrant(t.fineId, 'void')
        end
        MySQL.update.await("UPDATE `es_mdt_tickets` SET `status` = 'dismissed' WHERE `id` = ?", { t.id })
    elseif ruling == 'reduce' then
        MySQL.update.await(('UPDATE `es_mdt_fines` SET `amount` = ?, `contested` = 0, `dueAt` = NOW() + INTERVAL %s SECOND, `remindedAt` = NULL, `collectTriedAt` = NULL WHERE `id` = ? AND `status` = \'unpaid\''):format(back), { newAmt, t.fineId })
        MySQL.update.await('UPDATE `es_mdt_tickets` SET `total` = ? WHERE `id` = ?', { newAmt, t.id })
    else
        MySQL.update.await(('UPDATE `es_mdt_fines` SET `contested` = 0, `dueAt` = NOW() + INTERVAL %s SECOND, `remindedAt` = NULL, `collectTriedAt` = NULL WHERE `id` = ? AND `status` = \'unpaid\''):format(back), { t.fineId })
    end
    local t2 = ticketRow(t.id)
    local what = ({ dismiss = 'DISMISSED: you owe nothing.', lapsed = 'DISMISSED: the court did not rule in time, so it is decided in your favour. You owe nothing.',
        reduce = ('REDUCED to %s, due %s.'):format(money(newAmt), dateOf(t2 and t2.dueAt)),
        uphold = ('UPHELD: %s is due %s.'):format(money(t.fineAmount or t.total), dateOf(t2 and t2.dueAt)) })[ruling]
    MDT.text(t.charId, ('Your contest of %s %s: %s%s'):format(t.kindLabel, t.number, what, note ~= '' and ('\n' .. note) or ''),
        { kind = 'contest', title = ('Contest ruling: %s'):format(t.number) })
    local past = ({ dismiss = 'dismissed', lapsed = 'dismissed (no ruling in time)', reduce = ('reduced to %s'):format(money(newAmt)), uphold = 'upheld' })[ruling]
    MDT.text(t.officerCharId, ('Contest of %s %s: %s.'):format(t.kindLabel, t.number, past), { kind = 'contest', title = 'Contest ruled: ' .. t.number })
    TriggerEvent('es_mdt:contest:ruled', { contestId = k.id, ticketId = t.id, number = t.number, ruling = ruling, amount = newAmt, charId = t.charId, judgeCharId = j and j.charId or nil })
    MDT.refresh('tickets')
    MDT.refresh('fines')
    if MDT.dojRefresh then pcall(MDT.dojRefresh) end
    return true
end

--- open contests (the DOJ tablet)
function MDT.contestList(status)
    local rows = MySQL.query.await([[SELECT k.`id`,k.`ticketId`,k.`status`,k.`ruling`,k.`reason`,k.`statement`,k.`statementBy`,UNIX_TIMESTAMP(k.`lapseAt`) AS `lapseAt`,
        UNIX_TIMESTAMP(k.`createdAt`) AS `at`,UNIX_TIMESTAMP(k.`ruledAt`) AS `ruledAt`,k.`judgeName`,k.`reducedTo`,k.`rulingNote`,
        t.`number`,t.`kind`,t.`total`,t.`officerName`,t.`charId`,t.`plate`,t.`charges`,t.`location`,t.`notes`,t.`sign`,UNIX_TIMESTAMP(t.`createdAt`) AS `issuedAt`,d.`short` AS `dept`
        FROM `es_mdt_ticket_contests` k JOIN `es_mdt_tickets` t ON t.`id` = k.`ticketId` LEFT JOIN `es_departments` d ON d.`id` = t.`deptId`
        WHERE k.`status` = ? ORDER BY ]] .. (status == 'open' and 'k.`lapseAt`' or 'k.`ruledAt` DESC') .. ' LIMIT 100', { status == 'open' and 'open' or 'ruled' }) or {}
    local ids = {}
    for _, r in ipairs(rows) do ids[#ids + 1] = r.charId end
    local names = MDT.namesOf(ids)
    for _, r in ipairs(rows) do
        r.person = names[r.charId] or ('#' .. tostring(r.charId))
        r.charges = chargesOf(r.charges)
        r.kindLabel = KIND[r.kind] or r.kind
    end
    return rows
end

local function contestSweep()
    -- the DOJ is warned contestWarnDays before a contest lapses
    local warn = math.max(0, tonumber(TK().contestWarnDays) or 1)
    local soon = MySQL.query.await([[SELECT k.`id`,t.`number`,UNIX_TIMESTAMP(k.`lapseAt`) AS `lapseAt` FROM `es_mdt_ticket_contests` k JOIN `es_mdt_tickets` t ON t.`id` = k.`ticketId`
        WHERE k.`status` = 'open' AND k.`warnedAt` IS NULL AND k.`lapseAt` <= NOW() + INTERVAL ? DAY]], { warn }) or {}
    for _, k in ipairs(soon) do
        MySQL.update.await('UPDATE `es_mdt_ticket_contests` SET `warnedAt` = NOW() WHERE `id` = ?', { k.id })
        if MDT.dojWarn then pcall(MDT.dojWarn, ('Ticket contest %s lapses %s: rule on it (DOJ tablet > Ticket contests) or it is dismissed.'):format(k.number, os.date('%d %b %H:%M', k.lapseAt))) end
    end
    local gone = MySQL.query.await("SELECT `id` FROM `es_mdt_ticket_contests` WHERE `status` = 'open' AND `lapseAt` <= NOW() LIMIT 50") or {}
    for _, k in ipairs(gone) do MDT.ruleContest(nil, k.id, 'lapsed', nil, '') end
end

-- ---------------------------------------------------------------- the roadside form
local function allowedCats()
    local out = {}
    for _, c in ipairs(TK().categories or { 'infraction', 'misdemeanor' }) do out[c] = true end
    return out
end

local function penalFor()
    local cats = allowedCats()
    local rows = MySQL.query.await("SELECT `id`,`code`,`title`,`category`,`fine`,`description` FROM `es_penal_code` WHERE `active` = 1 ORDER BY FIELD(`category`,'infraction','misdemeanor','felony'), `code`") or {}
    local out = {}
    for _, r in ipairs(rows) do if cats[r.category] then out[#out + 1] = r end end
    return out
end

--- vehicles near the officer: the page names them by netId (the client sees them); the server checks each one
local function vehiclesNear(c, netIds, range)
    local at = posOf(c.source)
    local out, seen = {}, {}
    for _, nid in ipairs(type(netIds) == 'table' and netIds or {}) do
        nid = tonumber(nid)
        if nid and not seen[nid] and #out < 12 then
            seen[nid] = true
            local ent = NetworkGetEntityFromNetworkId(nid)
            if ent and ent ~= 0 and DoesEntityExist(ent) and GetEntityType(ent) == 2 then
                local d = dist(GetEntityCoords(ent), at)
                if d <= range + 2.0 then
                    local v = WC:GetVehicle({ netId = nid }, { occupants = true })
                    local plate = v and v.plate or (GetVehicleNumberPlateText(ent) or ''):gsub('^%s+', ''):gsub('%s+$', '')
                    out[#out + 1] = { netId = nid, vehicleId = v and v.vehicleId or nil, plate = plate, label = v and (v.displayName or v.model) or nil,
                        owned = v and not v.session and v.owner and (v.owner.charId or 0) > 0 or false,
                        ownerCharId = v and v.owner and (v.owner.charId or 0) > 0 and v.owner.charId or nil,
                        owner = v and v.owner and (v.owner.charId or 0) > 0 and nameOf(v.owner.charId) or nil,
                        occupied = v and type(v.occupants) == 'table' and next(v.occupants) ~= nil or false,
                        session = (not v) or v.session == true, temp = v and v.temp == true or false, dist = math.floor(d * 10) / 10 }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end
MDT.vehiclesNear = vehiclesNear

local function peopleNear(c, range)
    local at = posOf(c.source)
    if not at then return {} end
    local out = {}
    for _, src in ipairs(WC:GetPlayersInRange(at, range) or {}) do
        src = tonumber(src)
        if src and src ~= c.source then
            local cid = WC:GetCharId(src)
            local p = posOf(src)
            local d = dist(p, at)
            if cid and d <= range then
                local ped = GetPlayerPed(src)
                local veh = ped and GetVehiclePedIsIn(ped, false) or 0
                out[#out + 1] = { charId = cid, name = nameOf(cid), dist = math.floor(d * 10) / 10, inVehicle = veh ~= 0,
                    netId = veh ~= 0 and NetworkGetNetworkIdFromEntity(veh) or nil }
            end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end

local function newNumber(kind, tid) return ('%s-%05d'):format(PREFIX[kind] or 'T', tid) end

function MDT.registerTickets()
    local cb, str, int, id = MDT.cb, MDT.str, MDT.int, MDT.id

    if TK().paper ~= false then
        WC:RegisterItem(ITEM, { name = 'Police ticket', desc = 'A ticket from the police: use it to read it.', weight = 0.01, type = 'misc',
            stack = false, usable = true, image = 'html/img/items/es_mdt_citation.webp',
            metaFields = { { key = 'number', label = 'Number', format = 'uppercase' }, { key = 'kind', label = 'Kind' }, { key = 'total', label = 'Fine' }, { key = 'copy', label = 'Copy' } } })
        WC:RegisterUseHandler(ITEM, function(source, _, slotData)
            local m = slotData and slotData.metadata or {}
            local t = tonumber(m.ticketId) and ticketRow(tonumber(m.ticketId))
            if not t then WC:NotifyPlayer(source, 'The ticket is unreadable', 'error') return false end
            TriggerClientEvent('es_mdt:client:tkPaper', source, t)
            return false   -- keep it
        end)
    end

    -- the form: who and what is close, the charges this form may hold, the settings it needs
    cb('tkForm', { perm = 'tickets_issue', write = true, rate = 800, burst = 4 }, function(c, d)
        if TK().enabled == false then return false, 'Roadside tickets are turned off' end
        local range = tonumber(TK().range) or 12.0
        return { people = peopleNear(c, range), vehicles = vehiclesNear(c, d.netIds, range), penal = penalFor(),
            maxCharges = math.max(1, math.floor(tonumber(TK().maxCharges) or 6)), signSeconds = tonumber(TK().signSeconds) or 45,
            contests = contestsOn(), dueDays = INV().enabled ~= false and (tonumber(INV().dueDays) or 3) or nil, officer = c.name, dept = c.dept.short or c.dept.name,
            kinds = { { id = 'citation', label = KIND.citation }, { id = 'parking', label = KIND.parking }, { id = 'warning', label = KIND.warning } } }
    end)

    cb('tkIssue', { perm = 'tickets_issue', write = true, rate = 3000, burst = 2 }, function(c, d)
        if TK().enabled == false then return false, 'Roadside tickets are turned off' end
        local kind = KIND[d.kind] and d.kind or nil
        if not kind then return false, 'Pick citation, parking ticket or warning' end
        local range = (tonumber(TK().range) or 12.0) + 3.0
        local at = posOf(c.source)
        local charId, recipSrc, veh
        if kind == 'parking' then
            veh = vehiclesNear(c, { d.netId }, range)[1]
            if not veh then return false, 'That vehicle is not close to you any more' end
            if not veh.ownerCharId then return false, 'Nobody owns that vehicle: there is no one to send a parking ticket to (tow it instead)' end
            charId = veh.ownerCharId
        else
            charId = id(d.charId)
            recipSrc = charId and MDT.onlineByChar()[charId]
            if not recipSrc or dist(posOf(recipSrc), at) > range then return false, 'That person is not close to you any more' end
            if charId == c.charId then return false, 'You cannot ticket yourself' end
            if d.netId then veh = vehiclesNear(c, { d.netId }, range)[1] end
        end
        -- the charges, priced from the penal code here
        local byId = {}
        for _, p in ipairs(penalFor()) do byId[p.id] = p end
        local charges, total, n = {}, 0, 0
        for _, x in ipairs(type(d.charges) == 'table' and d.charges or {}) do
            local p = byId[tonumber(type(x) == 'table' and x.id or x) or 0]
            if p then
                local cnt = int(type(x) == 'table' and x.count or 1, 1, 5)
                n = n + 1
                if n > math.max(1, math.floor(tonumber(TK().maxCharges) or 6)) then return false, 'Too many charges on one ticket' end
                charges[#charges + 1] = { penalId = p.id, code = p.code, title = p.title, category = p.category, fine = kind == 'warning' and 0 or p.fine, count = cnt }
                total = total + (kind == 'warning' and 0 or p.fine * cnt)
            end
        end
        if #charges == 0 then return false, 'Add at least one charge' end
        total = math.min(total, Config.FineMax or total)
        local tmp = ('T%d%d'):format(os.time() % 100000, math.random(1000, 9999))
        local tid = MySQL.insert.await([[INSERT INTO `es_mdt_tickets` (`number`,`kind`,`deptId`,`officerCharId`,`officerName`,`charId`,`vehicleId`,`plate`,`vehicleLabel`,
            `location`,`charges`,`total`,`notes`) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,NULLIF(?, ''))]],
            { tmp, kind, c.dept.id, c.charId, c.name, charId, veh and veh.vehicleId or nil, veh and veh.plate or nil, veh and veh.label or nil,
              str(d.location, 120), json.encode(charges), total, str(d.notes, 500) })
        if not tid then return false, 'Could not save the ticket' end
        local number = newNumber(kind, tid)
        MySQL.update.await('UPDATE `es_mdt_tickets` SET `number` = ? WHERE `id` = ?', { number, tid })
        local cs = { source = c.source, charId = c.charId, name = c.name, dept = c.dept }
        if kind == 'citation' then
            if BySrc[recipSrc] then return false, 'They are being asked to sign another ticket right now' end
            local token = ('%d:%d'):format(tid, math.random(100000, 999999))
            local secs = math.max(10, math.min(180, math.floor(tonumber(TK().signSeconds) or 45)))
            Sign[token] = { ticketId = tid, src = recipSrc, charId = charId, c = cs, officerSrc = c.source, expires = os.time() + secs }
            BySrc[recipSrc] = token
            TriggerClientEvent('es_mdt:client:tkSign', recipSrc, { token = token, seconds = secs, ticket = ticketRow(tid), contests = contestsOn() })
            SetTimeout(secs * 1000 + 1500, function() if Sign[token] then signDone(token, false, 'no answer') end end)
            return { id = tid, number = number, total = total, signing = true, seconds = secs }
        end
        local t = finalize(tid, cs, kind == 'parking' and 'none' or 'na')
        return { id = tid, number = number, total = total, signing = false, ticket = t }
    end)

    -- the officer's overlay asks how the signing went (also pushed with es_mdt:client:tkSigned)
    cb('tkStatus', { rate = 300, burst = 10 }, function(c, d)
        local t = ticketRow(id(d.id) or 0)
        if not t or (t.officerCharId ~= c.charId and not c.staff) then return false, 'Not your ticket' end
        return t
    end)

    -- the MDT: Tickets (mine, the department's, contested), a person's or a vehicle's
    cb('tickets', { rate = 300, burst = 6 }, function(c, d)
        local where, args = { '1=1' }, {}
        if id(d.charId) then where[#where + 1] = 't.`charId` = ?' args[#args + 1] = id(d.charId)
        elseif id(d.vehicleId) then where[#where + 1] = 't.`vehicleId` = ?' args[#args + 1] = id(d.vehicleId)
        else
            if d.scope == 'mine' then where[#where + 1] = 't.`officerCharId` = ?' args[#args + 1] = c.charId
            elseif not c.staff then where[#where + 1] = 't.`deptId` = ?' args[#args + 1] = c.dept.id end
            if d.filter == 'contested' then where[#where + 1] = "k.`status` = 'open'"
            elseif d.filter == 'unpaid' then where[#where + 1] = "f.`status` = 'unpaid'"
            elseif d.filter == 'unsigned' then where[#where + 1] = "t.`sign` IN ('unsigned','none')" end
            local q = str(d.q, 40)
            if q ~= '' then where[#where + 1] = '(t.`number` LIKE ? OR t.`plate` LIKE ? OR t.`officerName` LIKE ?)' local l = '%' .. q:gsub('[%%_\\]', '\\%0') .. '%' args[#args + 1] = l args[#args + 1] = l args[#args + 1] = l end
        end
        local rows = MySQL.query.await(([[SELECT t.`id`,t.`number`,t.`kind`,t.`charId`,t.`plate`,t.`vehicleLabel`,t.`total`,t.`sign`,t.`status`,t.`officerName`,t.`officerCharId`,t.`location`,
            UNIX_TIMESTAMP(t.`createdAt`) AS `at`,f.`status` AS `fineStatus`,UNIX_TIMESTAMP(f.`dueAt`) AS `dueAt`,k.`status` AS `contest`,k.`statement` IS NOT NULL AS `hasStatement`,d.`short` AS `dept`
            FROM `es_mdt_tickets` t LEFT JOIN `es_mdt_fines` f ON f.`id` = t.`fineId` LEFT JOIN `es_mdt_ticket_contests` k ON k.`ticketId` = t.`id`
            LEFT JOIN `es_departments` d ON d.`id` = t.`deptId` WHERE %s ORDER BY t.`id` DESC LIMIT 150]]):format(table.concat(where, ' AND ')), args) or {}
        local ids = {}
        for _, r in ipairs(rows) do ids[#ids + 1] = r.charId end
        local names = MDT.namesOf(ids)
        for _, r in ipairs(rows) do r.person = r.charId and names[r.charId] or nil r.kindLabel = KIND[r.kind] or r.kind r.hasStatement = r.hasStatement == 1 or r.hasStatement == true end
        local open = MySQL.scalar.await([[SELECT COUNT(*) FROM `es_mdt_ticket_contests` k JOIN `es_mdt_tickets` t ON t.`id` = k.`ticketId`
            WHERE k.`status` = 'open' AND k.`statement` IS NULL AND t.`officerCharId` = ?]], { c.charId }) or 0
        return { rows = rows, needStatement = tonumber(open) or 0, contests = contestsOn(), canIssue = c.perms.tickets_issue == true }
    end)

    cb('ticket', { rate = 300, burst = 6 }, function(c, d)
        local t = ticketRow(id(d.id) or 0)
        if not t then return false, 'No such ticket' end
        if not c.staff and t.deptId ~= c.dept.id and t.charId == nil then return false, 'That ticket belongs to another department' end
        t.canStatement = t.contest and t.contest.status == 'open' and (t.officerCharId == c.charId or c.staff or c.perms.canManage or MDT.isHighCommand(c)) or false
        t.canVoid = t.status == 'issued' and t.fineStatus ~= 'paid' and (t.officerCharId == c.charId or c.staff or c.perms.canManage) or false
        return t
    end)

    cb('tkStatement', { write = true, rate = 2000, burst = 2 }, function(c, d) return fileStatement(c, id(d.id) or 0, d.text) end)

    cb('tkVoid', { write = true, rate = 2000, burst = 2 }, function(c, d)
        local t = ticketRow(id(d.id) or 0)
        if not t then return false, 'No such ticket' end
        if not (t.officerCharId == c.charId or c.staff or c.perms.canManage) then return false, 'Only who issued it or a supervisor can void it' end
        if t.status ~= 'issued' or t.fineStatus == 'paid' then return false, 'It cannot be voided now' end
        local why = str(d.reason, 200)
        if #why < 3 then return false, 'Say why it is voided' end
        if t.fineId then MySQL.update.await("UPDATE `es_mdt_fines` SET `status` = 'void', `contested` = 0 WHERE `id` = ? AND `status` = 'unpaid'", { t.fineId }) MDT.closeAutoWarrant(t.fineId, 'void') end
        MySQL.update.await("UPDATE `es_mdt_tickets` SET `status` = 'void', `notes` = CONCAT(COALESCE(`notes`, ''), ?) WHERE `id` = ?", { '\n[Voided by ' .. c.name .. ': ' .. why .. ']', t.id })
        MySQL.update.await("UPDATE `es_mdt_ticket_contests` SET `status` = 'ruled', `ruling` = 'dismiss', `rulingNote` = 'Voided by the police', `ruledAt` = NOW() WHERE `ticketId` = ? AND `status` = 'open'", { t.id })
        if t.charId then MDT.text(t.charId, ('%s %s was voided by the police. You owe nothing for it.'):format(t.kindLabel, t.number), { kind = 'ticket', title = 'Ticket voided: ' .. t.number }) end
        MDT.log(c, 'ticket_void', t.number .. ': ' .. why)
        MDT.refresh('tickets') MDT.refresh('fines')
        return true
    end)

    -- the recipient's answer (any player: not an MDT call)
    Whip.core:SecureCallback('es_mdt:tkSignAnswer', { rateLimit = 500, burst = 4, params = { { 'd', 'any' } } }, function(source, _, d)
        d = type(d) == 'table' and d or {}
        local tok = type(d.token) == 'string' and d.token or ''
        local s = Sign[tok]
        if not s or s.src ~= source then return false, 'That ticket is no longer waiting for you' end
        signDone(tok, d.signed == true, d.signed == true and nil or 'refused')
        return true
    end)

    -- a restart mid-signature: those tickets are filed unsigned
    CreateThread(function()
        Wait(15000)
        local left = MySQL.query.await("SELECT `id`,`deptId`,`officerCharId`,`officerName` FROM `es_mdt_tickets` WHERE `sign` = 'pending' AND `createdAt` < NOW() - INTERVAL 3 MINUTE") or {}
        for _, t in ipairs(left) do finalize(t.id, { charId = t.officerCharId, name = t.officerName, dept = { id = t.deptId } }, 'unsigned', 'restart') end
        while true do
            local ok, err = pcall(invoiceSweep)
            if not ok then print(('^3[es_mdt] invoices: %s^7'):format(tostring(err))) end
            ok, err = pcall(contestSweep)
            if not ok then print(('^3[es_mdt] ticket contests: %s^7'):format(tostring(err))) end
            Wait(math.max(1, tonumber(INV().checkMinutes) or 5) * 60000)
        end
    end)
end

-- ---------------------------------------------------------------- for other scripts (docs/HOOKS.md)
exports('GetTickets', function(charId)
    return MySQL.query.await([[SELECT t.`id`,t.`number`,t.`kind`,t.`total`,t.`sign`,t.`status`,UNIX_TIMESTAMP(t.`createdAt`) AS `at`,f.`status` AS `fineStatus`,UNIX_TIMESTAMP(f.`dueAt`) AS `dueAt`
        FROM `es_mdt_tickets` t LEFT JOIN `es_mdt_fines` f ON f.`id` = t.`fineId` WHERE t.`charId` = ? ORDER BY t.`id` DESC LIMIT 50]], { tonumber(charId) or 0 }) or {}
end)
exports('GetTicket', function(ticketId) return ticketRow(tonumber(ticketId) or 0) end)
exports('GetInvoices', function(charId)
    return MySQL.query.await([[SELECT `id`,`kind`,`amount`,`reason`,`status`,`contested`,`ticketId`,`impoundId`,UNIX_TIMESTAMP(`dueAt`) AS `dueAt`,UNIX_TIMESTAMP(`createdAt`) AS `at`
        FROM `es_mdt_fines` WHERE `charId` = ? AND `status` = 'unpaid' ORDER BY `id`]], { tonumber(charId) or 0 }) or {}
end)
