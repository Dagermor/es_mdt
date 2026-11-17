local _ENV = ESAPP('doj'); -- es_doj warrants: the judges' queue for es_mdt warrants (arrest and search). Officers request in the MDT; a judge
-- signs (approve) or refuses (deny) here. Judges may also issue a warrant themselves and recall one.
local cb, str, int, id = DOJ.cb, DOJ.str, DOJ.int, DOJ.id
local W = Config.Warrants or {}

exports('WarrantsNeedJudge', function() return W.judgeOnly == true end)

local function mdtUp() return GetResourceState('es_mdt') == 'started' end

local SEL = [[SELECT w.`id`,w.`charId`,w.`reportId`,w.`caseId`,w.`reason`,w.`status`,w.`kind`,w.`scope`,w.`requestedBy`,w.`issuedBy`,w.`judgeCharId`,w.`judgeName`,w.`judgeNote`,
    w.`auto`,UNIX_TIMESTAMP(w.`createdAt`) AS `createdAt`,UNIX_TIMESTAMP(w.`expiresAt`) AS `expiresAt`,UNIX_TIMESTAMP(w.`decidedAt`) AS `decidedAt`,
    d.`short` AS `dept`,c.`number` AS `caseNo`
    FROM `es_mdt_warrants` w LEFT JOIN `es_departments` d ON d.`id` = w.`deptId` LEFT JOIN `es_mdt_cases` c ON c.`id` = w.`caseId`]]

local function decorate(rows)
    local ids = {}
    for _, r in ipairs(rows) do ids[#ids + 1] = r.charId ids[#ids + 1] = r.requestedBy end
    local names = DOJ.namesOf(ids)
    for _, r in ipairs(rows) do
        r.name = names[r.charId] or ('#' .. r.charId)
        r.requestedByName = (r.requestedBy or 0) > 0 and (names[r.requestedBy] or ('#' .. r.requestedBy)) or (r.auto == 1 and 'Automatic' or 'System')
        r.expired = r.expiresAt and r.expiresAt < os.time() or false
    end
    return rows
end

--- How many wait for a judge (dashboard badge)
function DOJ.warrantsWaiting()
    if not mdtUp() then return 0 end
    return tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM `es_mdt_warrants` WHERE `status` = 'requested'")) or 0
end

function DOJ.registerWarrants()
    cb('warrants', { role = { 'warrants', 'judge', 'leo', 'member' } }, function(c, d)
        local st = DOJ.oneOf(d.status, { 'requested', 'active', 'decided', 'mine', 'all' }, 'requested')
        local where, args = {}, {}
        if st == 'requested' then where[#where + 1] = "w.`status` = 'requested'"
        elseif st == 'active' then where[#where + 1] = "w.`status` = 'active'"
        elseif st == 'decided' then where[#where + 1] = 'w.`decidedAt` IS NOT NULL'
        elseif st == 'mine' then where[#where + 1] = '(w.`judgeCharId` = ? OR w.`requestedBy` = ?)' args[#args + 1] = c.charId args[#args + 1] = c.charId end
        -- police who are not judges see the ones they asked for
        if not (c.r.warrants or c.r.judge or c.r.member) then where[#where + 1] = 'w.`requestedBy` = ?' args[#args + 1] = c.charId end
        local who = id(d.charId)
        if who then where[#where + 1] = 'w.`charId` = ?' args[#args + 1] = who end
        if d.kind == 'search' or d.kind == 'arrest' then where[#where + 1] = 'w.`kind` = ?' args[#args + 1] = d.kind end
        local sql = SEL .. (#where > 0 and (' WHERE ' .. table.concat(where, ' AND ')) or '')
            .. (st == 'decided' and ' ORDER BY w.`decidedAt` DESC' or ' ORDER BY w.`id` DESC') .. ' LIMIT 100'
        return { rows = decorate(MySQL.query.await(sql, args) or {}), judgeOnly = W.judgeOnly == true, waiting = DOJ.warrantsWaiting() }
    end)

    cb('warrant', { role = { 'warrants', 'judge', 'leo', 'member' } }, function(c, d)
        local w = MySQL.single.await(SEL .. ' WHERE w.`id` = ?', { id(d.id) or 0 })
        if not w then return false, 'No such warrant' end
        if not (c.r.warrants or c.r.judge or c.r.member) and w.requestedBy ~= c.charId then return false, 'Not yours to read' end
        decorate({ w })
        -- what the judge reads before signing: the report it rests on and the person's record
        if w.reportId then
            w.report = MySQL.single.await('SELECT `id`,`type`,`title`,`body`,`location`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt` FROM `es_mdt_reports` WHERE `id` = ?', { w.reportId })
            w.charges = DOJ.reportCharges(w.reportId, w.charId)
        end
        w.record = DOJ.recordSummary and DOJ.recordSummary(w.charId, { cases = true }) or nil
        w.others = MySQL.query.await("SELECT `id`,`kind`,`reason`,`status` FROM `es_mdt_warrants` WHERE `charId` = ? AND `id` <> ? AND `status` IN ('active','requested') ORDER BY `id` DESC LIMIT 10", { w.charId, w.id }) or {}
        return w
    end)

    cb('warrantDecide', { role = 'warrants', write = true, why = 'Only a judge signs warrants' }, function(c, d)
        if not mdtUp() then return false, 'The MDT is not running' end
        local decision = d.decision == 'approve' and 'approve' or (d.decision == 'deny' and 'deny' or nil)
        if not decision then return false, 'approve or deny' end
        if decision == 'deny' and not c.r.deny then return false, 'Your role cannot deny warrants' end
        local note = str(d.note, 300)
        if decision == 'deny' and note == '' then return false, 'Say why (the officer reads it)' end
        local days = int(d.days, 0, 90)
        local w = MySQL.single.await('SELECT `expiresAt` FROM `es_mdt_warrants` WHERE `id` = ?', { id(d.id) or 0 })
        if decision == 'approve' and days == 0 and w and not w.expiresAt then days = W.defaultDays or 7 end
        local ok, why = exports.es_mdt:DecideWarrant(id(d.id), decision, c.charId, c.label, note, days)
        if not ok then return false, why end
        DOJ.log(nil, c, 'warrant_' .. decision, ('Warrant #%d %s%s'):format(id(d.id), decision == 'approve' and 'signed' or 'denied', note ~= '' and (': ' .. note) or ''))
        DOJ.refresh('warrants')
        return true
    end)

    cb('warrantIssue', { role = 'warrants', write = true, rate = 3000, burst = 2, why = 'Only a judge issues warrants' }, function(c, d)
        if not mdtUp() then return false, 'The MDT is not running' end
        local who = id(d.charId)
        if not who or not DOJ.charExists(who) then return false, 'Pick the person' end
        local reason = str(d.reason, 500)
        if reason == '' then return false, 'Give the reason' end
        local kind = d.kind == 'search' and 'search' or 'arrest'
        local scope = str(d.scope, 300)
        if kind == 'search' and scope == '' then return false, 'Say what may be searched' end
        local k = id(d.courtCaseId) and DOJ.caseRow(d.courtCaseId)
        local wid, why = exports.es_mdt:IssueWarrant({ charId = who, reason = reason, kind = kind, scope = scope ~= '' and scope or nil, days = int(d.days or W.defaultDays or 7, 0, 90),
            byCharId = c.charId, byName = c.label, caseId = k and k.mdtCaseId or nil })
        if not wid then return false, why end
        DOJ.log(k and k.id or nil, c, 'warrant_issued', ('%s warrant #%s for %s: %s'):format(kind == 'search' and 'Search' or 'Arrest', tostring(wid), DOJ.nameOf(who) or ('#' .. who), reason))
        DOJ.refresh('warrants')
        return { id = wid }
    end)

    cb('warrantRecall', { role = 'warrants', write = true, why = 'Only a judge recalls warrants' }, function(c, d)
        if not mdtUp() then return false, 'The MDT is not running' end
        local note = str(d.note, 300)
        local ok, why = exports.es_mdt:CloseWarrant(id(d.id), 'void', c.charId)
        if not ok then return false, why end
        DOJ.log(nil, c, 'warrant_recalled', ('Warrant #%d recalled%s'):format(id(d.id) or 0, note ~= '' and (': ' .. note) or ''))
        DOJ.refresh('warrants')
        return true
    end)
end

-- es_mdt says a warrant now waits: the judges on duty (and online staff) hear of it
AddEventHandler('es_mdt:warrantRequested', function(wid)
    if W.notifyJudges == false then return end
    local w = MySQL.single.await('SELECT `id`,`charId`,`kind` FROM `es_mdt_warrants` WHERE `id` = ?', { tonumber(wid) or 0 })
    if not w then return end
    local who = DOJ.nameOf(w.charId) or ('#' .. w.charId)
    local d = DOJ.dept()
    local text = ('⚖ %s warrant #%d for %s waits for a judge (/%s → Warrants)'):format(w.kind == 'search' and 'Search' or 'Arrest', w.id, who, Config.Command or 'doj')
    for src in pairs(DOJ.WC:GetPlayers({ light = true }) or {}) do
        src = tonumber(src)
        local judge = d and DOJ.WC:HasJobPermission(src, d.jobId, 'doj_sign', { onDuty = true }) == true
        if judge or DOJ.ED:IsStaff(src) == true then DOJ.WC:NotifyPlayer(src, text, 'info', 9000) end
    end
    DOJ.refresh('warrants')
end)
