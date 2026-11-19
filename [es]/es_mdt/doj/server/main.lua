local _ENV = ESAPP('doj'); -- es_doj start: tables, every callback, the courthouse, and the background jobs (hearing reminders, overdue court
-- fines become warrants, expired business licenses).
local WC = DOJ.WC

local function reminders()
    local mins = Config.HearingReminderMinutes or 15
    if mins <= 0 then return end
    local rows = MySQL.query.await([[SELECT h.`id`,h.`caseId`,h.`title`,h.`room`,UNIX_TIMESTAMP(h.`startsAt`) AS `startsAt`,h.`judgeCharId`,h.`test`
        FROM `es_doj_hearings` h WHERE h.`status` = 'scheduled' AND h.`reminded` = 0 AND h.`startsAt` <= NOW() + INTERVAL ? MINUTE AND h.`startsAt` > NOW() - INTERVAL 5 MINUTE]], { mins }) or {}
    if #rows == 0 then return end
    local online = DOJ.onlineByChar()
    for _, h in ipairs(rows) do
        MySQL.update.await('UPDATE `es_doj_hearings` SET `reminded` = 1 WHERE `id` = ?', { h.id })
        local who = { h.judgeCharId }
        local k = h.caseId and DOJ.caseRow(h.caseId)
        if k then for _, x in ipairs({ k.defendantCharId, k.plaintiffCharId, k.prosecutorCharId, k.defenseCharId }) do who[#who + 1] = x end end
        for _, s in ipairs(MySQL.query.await("SELECT `charId` FROM `es_doj_subpoenas` WHERE `hearingId` = ? AND `status` IN ('issued','served')", { h.id }) or {}) do who[#who + 1] = s.charId end
        local seen = {}
        local mins2 = math.max(0, math.floor((h.startsAt - os.time()) / 60))
        for _, cid in ipairs(who) do
            if cid and not seen[cid] and online[cid] then
                seen[cid] = true
                WC:NotifyPlayer(online[cid], ('⚖ %s in %d min — %s, %s'):format(h.title or 'Your hearing', mins2, h.room or 'courtroom', Config.Courthouse.label), 'info', 12000)
            end
        end
    end
end

local function overdue()
    if ((Config.Fees or {}).dueDays or 0) <= 0 or GetResourceState('es_mdt') ~= 'started' then return end
    local rows = MySQL.query.await([[SELECT f.`id`,f.`charId`,f.`kind`,f.`amount`,f.`caseId`,k.`number` FROM `es_doj_fees` f LEFT JOIN `es_doj_cases` k ON k.`id` = f.`caseId`
        WHERE f.`status` = 'unpaid' AND f.`test` = 0 AND f.`warrantId` IS NULL AND f.`kind` IN ('fine','restitution') AND f.`dueAt` IS NOT NULL AND f.`dueAt` < NOW() LIMIT 20]]) or {}
    for _, f in ipairs(rows) do
        local ok, wid = pcall(function() return exports.es_mdt:IssueWarrant({ charId = f.charId, reason = ('Failure to pay a court %s: $%d%s (bill #%d). Paying it at the courthouse serves this warrant.')
            :format(f.kind == 'fine' and 'fine' or 'restitution order', f.amount, f.number and (' in ' .. f.number) or '', f.id), days = 30, byName = 'Superior Court' }) end)
        if ok and wid then
            MySQL.update.await('UPDATE `es_doj_fees` SET `warrantId` = ? WHERE `id` = ?', { wid, f.id })
            if f.caseId then DOJ.log(f.caseId, nil, 'fee_warrant', ('Bill #%d overdue: MDT warrant #%s'):format(f.id, tostring(wid))) end
            DOJ.notice(f.charId, 'Warrant: unpaid court bill', ('Bill #%d ($%d) is overdue and a warrant was issued. Pay it at the courthouse (/%s) to clear it.'):format(f.id, f.amount, Config.PortalCommand or 'court'), f.caseId, 'warrant')
        else
            MySQL.update.await('UPDATE `es_doj_fees` SET `warrantId` = 0 WHERE `id` = ?', { f.id })   -- tried; do not try every minute
        end
    end
end

local function expiries()
    MySQL.update.await("UPDATE `es_doj_businesses` SET `status` = 'expired' WHERE `status` = 'active' AND `expiresAt` IS NOT NULL AND `expiresAt` < NOW()")
end

Whip.register(function()
    local ok, why = DOJ.ensureTables()
    if not ok then Whip.startProblem('tables: %s', tostring(why)) return end
    MySQL.update.await("UPDATE `es_doj_fees` SET `status` = 'unpaid' WHERE `status` = 'paying'")   -- a payment cut off by a stop
    DOJ.registerCases()
    DOJ.registerWarrants()
    DOJ.registerRecords()
    DOJ.registerClerk()
    DOJ.registerBar()
    DOJ.registerAdmin()
    DOJ.registerPortal()
    if DOJ.registerContests then DOJ.registerContests() end   -- 2.1.0
    DOJ.registerTest()

    -- the courthouse on everyone's map
    local B = Config.Courthouse.blip or {}
    for i, D in ipairs(Config.Courthouse.desks or {}) do
        WC:ShowBlip('everyone', 'es_doj:court:' .. i, { coords = D.coords, label = Config.Courthouse.label, sprite = B.sprite or 419, color = B.color or 5, scale = B.scale or 0.8, shortRange = true })
    end

    -- anyone serving community service who is online now
    for _, s in ipairs(GetPlayers()) do
        local cid = WC:GetCharId(tonumber(s))
        if cid then CreateThread(function() DOJ.serviceChanged(cid) end) end
    end

    CreateThread(function()
        local tick = 0
        while true do
            Wait(60000)
            tick = tick + 1
            local okr, e1 = pcall(reminders)
            if not okr then print('^3[es_doj] reminders: ' .. tostring(e1) .. '^7') end
            if tick % 10 == 1 then
                local oko, e2 = pcall(overdue)
                if not oko then print('^3[es_doj] overdue fines: ' .. tostring(e2) .. '^7') end
                pcall(expiries)
            end
        end
    end)

    -- 1.1.0: DA and public defender ranks hold a bar license (once es_departments is up)
    CreateThread(function()
        Wait(15000)
        local okA, n = pcall(DOJ.syncAttorneys)
        if not okA then print('^3[es_doj] attorneys: ' .. tostring(n) .. '^7') end
    end)

    local d = DOJ.dept()
    local open = MySQL.scalar.await("SELECT COUNT(*) FROM `es_doj_cases` WHERE `status` = 'open' AND `test` = 0") or 0
    print(('[es_doj] ready: %d open case(s); DOJ department: %s; warrants judge-only: %s'):format(open, d and d.short or 'none yet (es_departments makes it)',
        tostring((Config.Warrants or {}).judgeOnly == true)))
end)
