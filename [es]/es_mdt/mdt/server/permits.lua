local _ENV = ESAPP('mdt'); -- es_mdt 1.8.0: firearm permits. The permit is the MDT's weapon license of Config.Permits.type (es_mdt_weapon_licenses:
-- WHIP has no license system of its own). Law enforcement gets one on hire (origin 'department'); civilians apply at a
-- front desk (or /permit), an automatic background check runs, and anyone holding permits_manage (or the DOJ, through
-- the exports at the bottom) approves or denies it. The fee is taken from the applicant's bank on approval.
-- Loaded BEFORE server/main.lua; runs from MDT.registerPermits().
local ED = exports.es_departments
local WC = exports.whip_core
MDT = MDT or {}

local P = Config.Permits or {}
local TYPE = P.type or 'Firearm'
local LABEL = P.label or 'Firearm permit'

local function now() return os.time() end
local function nameOf(cid)
    if not cid then return nil end
    local r = MySQL.single.await('SELECT `firstName`,`lastName` FROM `characters` WHERE `charId` = ?', { cid })
    return r and ((r.firstName or '') .. ' ' .. (r.lastName or '')) or ('#' .. cid)
end

local LAWTYPES = {}
for _, t in ipairs(P.autoDeptTypes or { 'police', 'sheriff', 'state' }) do LAWTYPES[t] = true end
local function lawDeptOfJob(jobId)
    for _, d in ipairs(ED:GetDepartments() or {}) do if d.jobId == jobId and LAWTYPES[d.type] then return d end end
end

-- ---------------------------------------------------------------- the license row
local function licOf(cid) return MySQL.single.await('SELECT * FROM `es_mdt_weapon_licenses` WHERE `charId` = ? AND `type` = ?', { cid, TYPE }) end

local function logLic(lid, by, action, note)
    MySQL.insert.await('INSERT INTO `es_mdt_weapon_license_log` (`licenseId`,`byCharId`,`action`,`note`) VALUES (?,?,?,NULLIF(?,\'\'))',
        { lid, by, action, tostring(note or ''):sub(1, 300) })
end

--- issue (or re-activate) the permit. origin: 'department' | 'application' | 'manual' | 'court'
local function issue(cid, by, origin, note)
    if not cid or cid >= 900000000 then return false, 'No such person' end   -- FTO test trainees are not characters
    local cur = licOf(cid)
    if cur and cur.status == 'active' then return false, 'They already hold an active ' .. LABEL end
    if cur then
        MySQL.update.await("UPDATE `es_mdt_weapon_licenses` SET `status` = 'active', `issuedBy` = ?, `issuedAt` = NOW(), `updatedBy` = ?, `note` = ?, `origin` = ? WHERE `id` = ?",
            { by, by, note, origin, cur.id })
    else
        MySQL.insert.await("INSERT INTO `es_mdt_weapon_licenses` (`charId`,`type`,`status`,`issuedBy`,`updatedBy`,`note`,`origin`) VALUES (?,?,'active',?,?,?,?)",
            { cid, TYPE, by, by, note, origin })
        cur = licOf(cid)
    end
    if cur then logLic(cur.id, by, 'issue', note) end
    MDT.refresh('weapons')
    return true
end

local function revokeAuto(cid, note)
    local cur = licOf(cid)
    if not cur or cur.status ~= 'active' or cur.origin ~= 'department' then return false end
    MySQL.update.await("UPDATE `es_mdt_weapon_licenses` SET `status` = 'revoked', `updatedBy` = NULL, `note` = ? WHERE `id` = ?", { note, cur.id })
    logLic(cur.id, nil, 'revoke', note)
    MDT.refresh('weapons')
    return true
end

local function stillLaw(cid)
    for _, d in ipairs(ED:GetDepartments() or {}) do
        if LAWTYPES[d.type] then
            for _, m in ipairs(ED:GetRoster(d.id) or {}) do if m.charId == cid then return d end end
        end
    end
end

--- 1.9.0: es_doj court orders on reports: { [reportId] = 'sealed' | 'expunged' } for this person ({} without es_doj)
local function courtMarks(cid)
    if not cid or GetResourceState('es_doj') ~= 'started' then return {} end
    local ok, m = pcall(function() return exports.es_doj:GetCourtMarks('report', nil, cid) end)
    return ok and type(m) == 'table' and m or {}
end
local function notExpunged(marksMap, col)
    local ids = {}
    for rid, mode in pairs(marksMap) do if mode == 'expunged' and tonumber(rid) then ids[#ids + 1] = math.floor(tonumber(rid)) end end
    if #ids == 0 then return '' end
    return (' AND %s NOT IN (%s)'):format(col, table.concat(ids, ','))
end

-- ---------------------------------------------------------------- background check (automatic, at apply and again at review)
local function check(cid)
    local days = P.recentArrestDays or 30
    local w = MySQL.single.await("SELECT COUNT(*) AS `n` FROM `es_mdt_warrants` WHERE `charId` = ? AND `status` = 'active' AND `kind` = 'arrest'", { cid }) or {}
    local marks = courtMarks(cid)   -- 1.9.0: expunged reports do not count
    local f = MySQL.single.await(([[SELECT COUNT(*) AS `n`, UNIX_TIMESTAMP(MAX(r.`createdAt`)) AS `last` FROM `es_mdt_report_charges` c
        JOIN `es_mdt_reports` r ON r.`id` = c.`reportId` WHERE c.`charId` = ? AND c.`category` = 'felony'%s]]):format(notExpunged(marks, 'c.`reportId`')), { cid }) or {}
    local a = MySQL.single.await(([[SELECT COUNT(DISTINCT r.`id`) AS `n` FROM `es_mdt_reports` r JOIN `es_mdt_report_people` p ON p.`reportId` = r.`id`
        WHERE p.`charId` = ? AND p.`role` = 'suspect' AND r.`type` = 'arrest' AND r.`createdAt` > NOW() - INTERVAL ? DAY%s]]):format(notExpunged(marks, 'r.`id`')), { cid, days }) or {}
    local jailed = false
    do   -- 2.0.0: the jail bridge (es_jail or any jail script; escaped counts too when the MDT recorded it)
        local ok, j = pcall(EsJail.isJailed, cid)
        jailed = ok and j or false
        if not jailed and MySQL.single.await("SELECT 1 AS `x` FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'es_jail_inmates'") then
            jailed = MySQL.single.await("SELECT 1 AS `x` FROM `es_jail_inmates` WHERE `charId` = ? AND `status` = 'escaped'", { cid }) ~= nil
        end
    end
    -- es_doj (when running) adds court convictions
    local doj = nil
    if GetResourceState('es_doj') == 'started' then
        local ok, r = pcall(function() return exports.es_doj:GetRecordSummary(cid) end)
        if ok and type(r) == 'table' then doj = r end
    end
    local out = { warrants = tonumber(w.n) or 0, felonies = tonumber(f.n) or 0, lastFelony = tonumber(f.last), arrests = tonumber(a.n) or 0,
        arrestDays = days, jailed = jailed, convictions = doj and tonumber(doj.felonyConvictions) or nil, at = now(), flags = {} }
    if out.warrants > 0 then out.flags[#out.flags + 1] = ('%d active warrant%s'):format(out.warrants, out.warrants == 1 and '' or 's') end
    if out.jailed then out.flags[#out.flags + 1] = 'Serving a jail sentence or escaped' end
    if out.felonies > 0 then out.flags[#out.flags + 1] = ('%d felony charge%s on record'):format(out.felonies, out.felonies == 1 and '' or 's') end
    if (out.convictions or 0) > 0 then out.flags[#out.flags + 1] = ('%d felony conviction%s (court)'):format(out.convictions, out.convictions == 1 and '' or 's') end
    if out.arrests > 0 then out.flags[#out.flags + 1] = ('%d arrest%s in the last %d days'):format(out.arrests, out.arrests == 1 and '' or 's', days) end
    out.clear = #out.flags == 0
    return out
end

-- ---------------------------------------------------------------- applications
local function appRow(r)
    if not r then return nil end
    local ok, ck = pcall(json.decode, r.checkJson or 'null')
    r.check = ok and ck or nil
    r.checkJson = nil
    return r
end

local SEL = [[SELECT a.`id`,a.`charId`,a.`type`,a.`reason`,a.`status`,a.`fee`,a.`paid`,a.`checkJson`,(a.`photo` IS NOT NULL) AS `hasPhoto`,a.`decidedBy`,a.`decidedByLabel`,a.`decisionNote`,
    UNIX_TIMESTAMP(a.`createdAt`) AS `createdAt`, UNIX_TIMESTAMP(a.`decidedAt`) AS `decidedAt`, c.`firstName`, c.`lastName`, DATE_FORMAT(c.`dateOfBirth`,'%Y-%m-%d') AS `dob`
    FROM `es_mdt_permit_apps` a JOIN `characters` c ON c.`charId` = a.`charId`]]

local function apply(cid, reason, viaLabel, photo)
    reason = tostring(reason or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 500)
    if #reason < (P.reasonMin or 10) then return false, ('Say why you want a %s (at least %d letters)'):format(LABEL, P.reasonMin or 10) end
    if P.requirePhoto ~= false and not photo then return false, 'Add a photo of yourself' end
    local lic = licOf(cid)
    if lic and lic.status == 'active' then return false, 'You already hold an active ' .. LABEL end
    if lic and lic.status == 'suspended' then return false, 'Your ' .. LABEL .. ' is suspended: ask the police to reinstate it' end
    if MySQL.single.await("SELECT 1 AS `x` FROM `es_mdt_permit_apps` WHERE `charId` = ? AND `status` = 'pending'", { cid }) then
        return false, 'You already have an application waiting for review'
    end
    local cool = tonumber(P.reapplyDays) or 1
    local last = MySQL.single.await("SELECT UNIX_TIMESTAMP(`decidedAt`) AS `t` FROM `es_mdt_permit_apps` WHERE `charId` = ? AND `status` = 'denied' ORDER BY `id` DESC LIMIT 1", { cid })
    if last and last.t and cool > 0 and now() - last.t < cool * 86400 then
        return false, ('Your last application was denied. You can apply again in %d hour(s)'):format(math.ceil((cool * 86400 - (now() - last.t)) / 3600))
    end
    local ck = check(cid)
    local id = MySQL.insert.await('INSERT INTO `es_mdt_permit_apps` (`charId`,`type`,`reason`,`fee`,`checkJson`,`photo`,`via`) VALUES (?,?,?,?,?,?,?)',
        { cid, TYPE, reason, math.max(0, math.floor(tonumber(P.fee) or 0)), json.encode(ck), photo, tostring(viaLabel or 'desk'):sub(1, 40) })
    if not id then return false, 'Could not file the application' end
    MDT.refresh('permits')
    -- reviewers online hear of it
    for _, d in ipairs(ED:GetDepartments() or {}) do
        if LAWTYPES[d.type] or d.type == 'doj' then
            for _, m in ipairs(ED:GetRoster(d.id) or {}) do
                if m.source and ED:Can(m.source, d.id, 'permits_manage', { onDuty = true }) == true then
                    WC:NotifyPlayer(m.source, ('New %s application #%d from %s. MDT → Permits'):format(LABEL, id, nameOf(cid)), 'info', 8000)
                end
            end
        end
    end
    return { id = id, fee = P.fee or 0, clear = ck.clear }
end

local function statusOf(cid)
    local lic = licOf(cid)
    local apps = MySQL.query.await(SEL .. ' WHERE a.`charId` = ? ORDER BY a.`id` DESC LIMIT 5', { cid }) or {}
    for i, a in ipairs(apps) do apps[i] = appRow(a) a.check = nil end   -- the applicant never sees the check itself
    return { license = lic and { status = lic.status, origin = lic.origin, issuedAt = lic.issuedAt } or nil, apps = apps, label = LABEL, fee = P.fee or 0 }
end

--- decide: by = charId (or nil), byLabel = who it shows as ("Sgt. Doe, LSPD" / "Judge Doe"), payDept = dept id for the fee
local function decide(id, decision, note, by, byLabel, payDept)
    note = tostring(note or ''):sub(1, 300)
    local a = appRow(MySQL.single.await(SEL .. ' WHERE a.`id` = ?', { tonumber(id) or 0 }))
    if not a then return false, 'No such application' end
    if a.status ~= 'pending' then return false, ('That application was already %s'):format(a.status) end
    if by and a.charId == by and not (P.selfReview) then return false, 'You cannot review your own application' end
    if decision == 'deny' then
        if #note < 3 then return false, 'Say why it is denied' end
        local n = MySQL.update.await("UPDATE `es_mdt_permit_apps` SET `status` = 'denied', `decidedBy` = ?, `decidedByLabel` = ?, `decisionNote` = ?, `decidedAt` = NOW() WHERE `id` = ? AND `status` = 'pending'",
            { by, byLabel, note, a.id }) or 0
        if n == 0 then return false, 'Someone else decided it a moment ago' end
        MDT.notifyChar(a.charId, ('Your %s application #%d was denied: %s'):format(LABEL, a.id, note), 'error')
        MDT.refresh('permits')
        return true
    elseif decision ~= 'approve' then return false, 'Approve or deny' end
    -- claim it first (two reviewers at once: only one wins), then charge, then issue
    local n = MySQL.update.await("UPDATE `es_mdt_permit_apps` SET `status` = 'processing' WHERE `id` = ? AND `status` = 'pending'", { a.id }) or 0
    if n == 0 then return false, 'Someone else is deciding it right now' end
    local fee = tonumber(a.fee) or 0
    local paid = 0
    if fee > 0 then
        local acct = WC:GetDefaultBankAccount({ charId = a.charId })
        local ok, why = false, 'They have no bank account'
        if acct then ok, why = WC:BankSystemWithdraw(acct.accountId, fee, { reason = ('%s fee (application #%d)'):format(LABEL, a.id) }) end
        if not ok then
            MySQL.update.await("UPDATE `es_mdt_permit_apps` SET `status` = 'pending' WHERE `id` = ?", { a.id })
            return false, ('The applicant cannot pay the $%d fee: %s'):format(fee, tostring(why or 'refused'))
        end
        paid = fee
        local d = payDept and ED:GetDepartment(payDept)
        local jaccts = d and WC:GetJobBankAccounts(d.jobId) or {}
        if P.feeToDepartment ~= false and jaccts[1] then
            local okd = pcall(function() return assert(WC:BankSystemDeposit(jaccts[1].accountId, fee, { reason = ('%s fee #%d'):format(LABEL, a.id) })) end)
            if okd then TriggerEvent('es_mdt:server:deptIncome', d.jobId, fee, 'permit', ('%s fee #%d'):format(LABEL, a.id), a.charId) end
        end
    end
    local ok, why = issue(a.charId, by, 'application', ('Application #%d approved by %s%s'):format(a.id, byLabel or 'a reviewer', note ~= '' and (': ' .. note) or ''))
    if not ok then
        MySQL.update.await("UPDATE `es_mdt_permit_apps` SET `status` = 'pending' WHERE `id` = ?", { a.id })
        return false, why
    end
    -- 1.8.0: the application photo becomes their MDT photo (a new mugshot; the old ones stay in the photo history)
    local ph = MySQL.single.await('SELECT `photo` FROM `es_mdt_permit_apps` WHERE `id` = ?', { a.id })
    if ph and type(ph.photo) == 'string' and ph.photo:sub(1, 11) == 'data:image/' then
        local mid = MySQL.insert.await('INSERT INTO `es_mdt_mugshots` (`charId`,`image`,`origin`,`takenBy`) VALUES (?,?,?,?)', { a.charId, ph.photo, 'permit', by })
        if mid then
            MySQL.update.await([[INSERT INTO `es_mdt_profiles` (`charId`,`mugshotId`,`updatedBy`) VALUES (?,?,?)
                ON DUPLICATE KEY UPDATE `mugshotId` = VALUES(`mugshotId`), `updatedBy` = VALUES(`updatedBy`)]], { a.charId, mid, by })
            MDT.refresh('people')
        end
    end
    MySQL.update.await("UPDATE `es_mdt_permit_apps` SET `status` = 'approved', `paid` = ?, `decidedBy` = ?, `decidedByLabel` = ?, `decisionNote` = NULLIF(?,''), `decidedAt` = NOW() WHERE `id` = ?",
        { paid, by, byLabel, note, a.id })
    MDT.notifyChar(a.charId, ('Your %s was approved%s.'):format(LABEL, paid > 0 and (' ($%d fee taken from your bank)'):format(paid) or ''), 'success')
    MDT.refresh('permits')
    return true
end

local function list(status)
    local where, args = '', {}
    if status and status ~= 'all' then where = ' WHERE a.`status` = ?' args = { status == 'pending' and 'pending' or status } end
    local rows = MySQL.query.await(SEL .. where .. ' ORDER BY a.`status` = \'pending\' DESC, a.`id` DESC LIMIT 100', args) or {}
    local ids = {}
    for i, r in ipairs(rows) do rows[i] = appRow(r) ids[#ids + 1] = r.decidedBy end
    local nm = MDT.namesOf(ids)
    local pend = {}
    for _, r in ipairs(rows) do if r.status == 'pending' and #pend < 40 then pend[#pend + 1] = r.id end end
    local photos = {}
    if #pend > 0 then
        for _, x in ipairs(MySQL.query.await(('SELECT `id`,`photo` FROM `es_mdt_permit_apps` WHERE `id` IN (%s)'):format(MDT.marks(#pend)), pend) or {}) do photos[x.id] = x.photo end
    end
    for _, r in ipairs(rows) do
        r.photo = photos[r.id]
        r.name = (r.firstName or '') .. ' ' .. (r.lastName or '')
        r.decidedByName = r.decidedByLabel or (r.decidedBy and nm[r.decidedBy]) or nil
    end
    return rows
end

-- for weapon lists: [charId] = 'active'|'suspended'|'revoked'|nil (permit only)
function MDT.permitMap(ids)
    local out = {}
    if #ids == 0 then return out end
    local marks = {}
    for i = 1, #ids do marks[i] = '?' end
    local args = { TYPE }
    for _, x in ipairs(ids) do args[#args + 1] = x end
    for _, r in ipairs(MySQL.query.await(('SELECT `charId`,`status` FROM `es_mdt_weapon_licenses` WHERE `type` = ? AND `charId` IN (%s)'):format(table.concat(marks, ',')), args) or {}) do
        out[r.charId] = r.status
    end
    return out
end
MDT.permitType, MDT.permitLabel = TYPE, LABEL

-- ---------------------------------------------------------------- automatic: hired / fired
local function onHired(e)
    if P.autoOnHire == false or type(e) ~= 'table' or not e.charId then return end
    local d = lawDeptOfJob(e.jobId)
    if not d then return end
    local cur = licOf(e.charId)
    if cur and cur.status == 'active' then return end
    if cur and cur.status == 'suspended' and P.autoOverridesSuspension ~= true then return end
    issue(e.charId, nil, 'department', ('Issued: department, auto (%s)'):format(d.short))
    MDT.notifyChar(e.charId, ('%s: you were issued a %s.'):format(d.short, LABEL), 'success')
end
local function onFired(e)
    if P.revokeAutoOnFire == false or type(e) ~= 'table' or not e.charId then return end
    local d = lawDeptOfJob(e.jobId)
    if not d then return end
    SetTimeout(1500, function()   -- the roster is up to date by then
        if stillLaw(e.charId) then return end
        if revokeAuto(e.charId, ('Left %s (department permit ends)'):format(d.short)) then
            MDT.notifyChar(e.charId, ('Your department-issued %s ended when you left %s. Apply at a front desk for your own.'):format(LABEL, d.short), 'warning')
        end
    end)
end

function MDT.registerPermits()
    -- a 'processing' left behind by a crash goes back to the queue
    MySQL.update.await("UPDATE `es_mdt_permit_apps` SET `status` = 'pending' WHERE `status` = 'processing'")

    local cb, id, str = MDT.cb, MDT.id, MDT.str

    -- the review queue (MDT → Permits)
    -- who may approve / deny: permits_manage AND rank level >= Config.Permits.decideLevel (Sergeant, 60). Everyone with
    -- the MDT sees the queue; staff always may.
    local function mayDecide(c)
        if c.staff then return true end
        if not c.perms.permits_manage then return false, 'Your rank cannot decide permit applications' end
        if (tonumber(c.myLevel) or 0) < (tonumber(P.decideLevel) or 60) then return false, ('Only Sergeant and above (rank level %d+) approve or deny permits'):format(tonumber(P.decideLevel) or 60) end
        return true
    end
    cb('permits', { rate = 400, burst = 6 }, function(c, d)
        local st = ({ pending = 1, approved = 1, denied = 1, all = 1 })[d.status] and d.status or 'pending'
        local rows = list(st)
        local pend = MySQL.single.await("SELECT COUNT(*) AS `n` FROM `es_mdt_permit_apps` WHERE `status` = 'pending'") or {}
        local can, why = mayDecide(c)
        return { list = rows, pending = tonumber(pend.n) or 0, label = LABEL, fee = P.fee or 0, canDecide = can and not c.readOnly, whyNot = (not can) and why or (c.readOnly and 'You are off duty: clock on to decide') or nil }
    end)
    cb('permitPhoto', { rate = 150, burst = 20 }, function(c, d)
        local r = MySQL.single.await('SELECT `id`,`photo` FROM `es_mdt_permit_apps` WHERE `id` = ?', { id(d.id) or 0 })
        return r and { id = r.id, image = r.photo } or false
    end)
    cb('permitRecheck', { rate = 1000, burst = 3 }, function(c, d)
        local can, why = mayDecide(c)
        if not can then return false, why end
        local a = MySQL.single.await('SELECT `charId`,`status` FROM `es_mdt_permit_apps` WHERE `id` = ?', { id(d.id) or 0 })
        if not a then return false, 'No such application' end
        local ck = check(a.charId)
        if a.status == 'pending' then MySQL.update.await('UPDATE `es_mdt_permit_apps` SET `checkJson` = ? WHERE `id` = ?', { json.encode(ck), id(d.id) }) end
        return ck
    end)
    cb('permitDecide', { write = true, rate = 1000, burst = 3 }, function(c, d)
        local can, why = mayDecide(c)
        if not can then return false, why end
        local label = ('%s%s, %s'):format(c.dept.roleName and (c.dept.roleName .. ' ') or '', c.name or '?', c.dept.short or '')
        local ok2, why2 = decide(id(d.id), d.decision == 'approve' and 'approve' or 'deny', str(d.note, 300), c.charId, label, c.dept.id)
        if ok2 then MDT.log(c, 'permit', ('%s #%s %s'):format(d.decision, tostring(d.id), str(d.note, 100))) end
        return ok2, why2
    end)

    -- civilians: the front desk prompt and /permit
    -- d = { reason, desk (0 = /permit), mode = upload|link|roll, image (data URL, resized in the page), url, photoId }
    Whip.core:SecureCallback('es_mdt:permitApply', { rateLimit = 5000, burst = 2, sheet = 'light', params = { { 'd', 'any' } } }, function(source, player, d)
        d = type(d) == 'table' and d or {}
        if P.enabled == false then return false, 'Permit applications are closed' end
        local cid = player and player.charId or WC:GetCharId(source)
        if not cid then return false, 'No character' end
        local desk = math.floor(tonumber(d.desk) or 0)
        local D = (P.desks or {})[desk]
        if desk > 0 then
            if not D then return false, 'No such desk' end
            local ped = GetPlayerPed(source)
            if not ped or ped == 0 or #(GetEntityCoords(ped) - D.coords) > 8.0 then return false, 'Walk up to the desk' end
        elseif P.command == false then return false, 'Apply at a police front desk' end
        local photo
        if d.mode == 'upload' then
            photo = type(d.image) == 'string' and d.image or nil
        elseif d.mode == 'link' then
            local url = MDT.str(d.url, 500)
            local okc, cwhy = Fetch.check(url)
            if not okc then return false, cwhy end
            local got, err = Fetch.get(url)
            if not got then return false, err end
            photo = got
        elseif d.mode == 'roll' then
            if GetResourceState('es_evidence') ~= 'started' then return false, 'The camera roll is not available' end
            photo = exports.es_evidence:RollImage(cid, MDT.id(d.photoId) or 0)
            if not photo then return false, 'That photo is not in your camera roll' end
        end
        if photo and not (type(photo) == 'string' and photo:match('^data:image/[a-z]+;base64,') and #photo <= (P.photoMax or 420000)) then
            return false, 'That picture cannot be used (a PNG, JPG or WebP, about 300 KB at most)'
        end
        local r, why2 = apply(cid, d.reason, D and D.label or 'command', photo)
        if r then CreateThread(function() WC:LogActivity(source, 'es_mdt_permit_apply', { detail = ('#%d'):format(r.id) }) end) end
        return r, why2
    end)
    -- the applicant's own camera roll (pictures they took with the camera item)
    Whip.core:SecureCallback('es_mdt:permitRoll', { rateLimit = 1000, burst = 3, sheet = 'light', params = { { 'd', 'any' } } }, function(source, player, d)
        local cid = player and player.charId or WC:GetCharId(source)
        if not cid or GetResourceState('es_evidence') ~= 'started' then return {} end
        d = type(d) == 'table' and d or {}
        if MDT.id(d.id) then
            local img = exports.es_evidence:RollImage(cid, MDT.id(d.id))
            return img and { id = MDT.id(d.id), image = img } or false
        end
        return exports.es_evidence:Roll(cid) or {}
    end)
    Whip.core:SecureCallback('es_mdt:permitStatus', { rateLimit = 1500, burst = 3, sheet = 'light', params = {} }, function(source, player)
        local cid = player and player.charId or WC:GetCharId(source)
        if not cid then return false, 'No character' end
        return statusOf(cid)
    end)
    Whip.core:SecureCallback('es_mdt:permitDesks', { rateLimit = 2000, burst = 3, params = {} }, function()
        local out = {}
        for i, D in ipairs(P.desks or {}) do out[#out + 1] = { i = i, label = D.label, x = D.coords.x, y = D.coords.y, z = D.coords.z } end
        return { desks = out, enabled = P.enabled ~= false, label = LABEL, fee = P.fee or 0, command = P.command ~= false }
    end)

    AddEventHandler('whip_core:job:hired', function(e) if GetInvokingResource() == 'whip_core' then CreateThread(function() onHired(e) end) end end)
    AddEventHandler('whip_core:job:fired', function(e) if GetInvokingResource() == 'whip_core' then CreateThread(function() onFired(e) end) end end)

    -- everyone already in a law department gets theirs (once per start; issuing twice is a no-op)
    CreateThread(function()
        Wait(15000)
        if P.autoOnHire == false then return end
        local n = 0
        for _, d in ipairs(ED:GetDepartments() or {}) do
            if LAWTYPES[d.type] then
                for _, m in ipairs(ED:GetRoster(d.id) or {}) do
                    local cur = licOf(m.charId)
                    if not cur or cur.status == 'revoked' then
                        if issue(m.charId, nil, 'department', ('Issued: department, auto (%s)'):format(d.short)) then n = n + 1 end
                    end
                end
            end
        end
        if n > 0 then print(('[es_mdt] issued %d department %s(s) to current members'):format(n, LABEL)) end
    end)
end

-- ---------------------------------------------------------------- exports (es_doj: judges and clerks process applications)
exports('GetPermitApplications', function(status) return list(status or 'pending') end)
exports('GetPermitStatus', function(charId) return statusOf(tonumber(charId) or 0) end)
exports('PermitBackgroundCheck', function(charId) return check(tonumber(charId) or 0) end)
--- decision 'approve'|'deny'; by = charId of the judge/clerk; byLabel = 'Judge Doe'
exports('DecidePermit', function(appId, decision, note, by, byLabel)
    return decide(appId, decision, note, tonumber(by), byLabel and tostring(byLabel):sub(1, 80) or nil, nil)
end)
exports('IssuePermit', function(charId, by, origin, note)
    return issue(tonumber(charId) or 0, tonumber(by), tostring(origin or 'manual'):sub(1, 16), note and tostring(note):sub(1, 300) or nil)
end)
exports('HasPermit', function(charId) local l = licOf(tonumber(charId) or 0) return l ~= nil and l.status == 'active' end)
