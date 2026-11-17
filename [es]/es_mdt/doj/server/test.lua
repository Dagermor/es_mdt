local _ENV = ESAPP('doj'); -- es_doj /dojtest: staff solo testing. Test rows are flagged (test = 1): test cases name YOU as the defendant, money
-- is never taken (bills show and "pay" for free), nobody is jailed, renamed or given a real warrant.
--   /dojtest role judge|prosecutor|da|defender|pd|clerk|attorney|leo|off   view the tablet as that role
--   /dojtest case        a criminal case against you (2 charges, a hearing in 10 minutes, bail set)
--   /dojtest warrant     an arrest warrant request against you in the MDT (for the judges' queue)
--   /dojtest petition name|business|expunge   a petition from you (clerk / judge queue)
--   /dojtest service [n] n community service tasks for you
--   /dojtest notice      a court notice to you
--   /dojtest clear       remove every test row
local WC, T = DOJ.WC, Config.Test or {}
local TAG = '[TEST] '

local function allowed(source)
    if source == 0 then return true end
    return IsPlayerAceAllowed(source, T.ace or 'es_doj.admin') or IsPlayerAceAllowed(source, 'command') or DOJ.ED:IsStaff(source) == true
end
local function reply(source, text, kind)
    if source == 0 then print('[es_doj] ' .. text) else WC:NotifyPlayer(source, text, kind or 'info', 9000) end
end

local function testCase(source, cid)
    local pen = MySQL.query.await("SELECT `id` FROM `es_penal_code` WHERE `active` = 1 ORDER BY RAND() LIMIT 2") or {}
    local list = {}
    for _, p in ipairs(pen) do list[#list + 1] = { penalId = p.id, count = 1 } end
    local c = DOJ.ctxOf(source) or { charId = cid, label = DOJ.nameOf(cid), source = source, r = {} }
    local res, why = DOJ.createCase(c, { kind = 'criminal', title = TAG .. 'State of San Andreas v. ' .. (DOJ.nameOf(cid) or '?'), summary = 'A test case. Nothing on it is real.',
        defendantCharId = cid, charges = list, test = true })
    if not res then return false, why end
    local at = os.time() + 600
    MySQL.insert.await([[INSERT INTO `es_doj_hearings` (`caseId`,`kind`,`title`,`startsAt`,`minutes`,`room`,`test`,`createdBy`) VALUES (?,?,?,FROM_UNIXTIME(?),30,?,1,?)]],
        { res.id, 'arraignment', 'Arraignment — ' .. res.number, at, Config.Courthouse.rooms[1], cid })
    local fid = DOJ.addFee(cid, 'bail', 5000, 'Bail: ' .. res.number, res.id, cid, true, 0)
    MySQL.update.await("UPDATE `es_doj_cases` SET `stage` = 'arraignment', `bailStatus` = 'set', `bailAmount` = 5000, `bailFeeId` = ? WHERE `id` = ?", { fid, res.id })
    DOJ.refresh('cases')
    return res
end

local function clear()
    local out = {}
    local function del(label, sql, args)
        local n = MySQL.update.await(sql, args or {}) or 0
        if (tonumber(n) or 0) > 0 then out[#out + 1] = ('%d %s'):format(n, label) end
    end
    local caseIds = {}
    for _, r in ipairs(MySQL.query.await('SELECT `id` FROM `es_doj_cases` WHERE `test` = 1') or {}) do caseIds[#caseIds + 1] = r.id end
    if #caseIds > 0 then
        local m = DOJ.marks(#caseIds)
        del('log lines', ('DELETE FROM `es_doj_log` WHERE `caseId` IN (%s)'):format(m), caseIds)
        del('fees', ('DELETE FROM `es_doj_fees` WHERE `caseId` IN (%s)'):format(m), caseIds)
        del('service', ('DELETE FROM `es_doj_service` WHERE `caseId` IN (%s)'):format(m), caseIds)
        del('seals', ("DELETE FROM `es_doj_seals` WHERE `kind` = 'case' AND `refId` IN (%s)"):format(m), caseIds)
    end
    del('cases', 'DELETE FROM `es_doj_cases` WHERE `test` = 1')   -- charges, hearings, filings, pleas, sentences, subpoenas go with them
    del('hearings', 'DELETE FROM `es_doj_hearings` WHERE `test` = 1')
    del('fees', 'DELETE FROM `es_doj_fees` WHERE `test` = 1')
    del('service', 'DELETE FROM `es_doj_service` WHERE `test` = 1')
    del('petitions', 'DELETE FROM `es_doj_petitions` WHERE `test` = 1')
    del('businesses', 'DELETE FROM `es_doj_businesses` WHERE `test` = 1')
    del('notices', 'DELETE FROM `es_doj_notices` WHERE `test` = 1')
    del('seals', 'DELETE FROM `es_doj_seals` WHERE `test` = 1')
    if GetResourceState('es_mdt') == 'started' then
        del('MDT test warrants', "DELETE FROM `es_mdt_warrants` WHERE `reason` LIKE '[TEST]%' AND `status` IN ('requested','active','void','served')")
    end
    DOJ.refresh('cases') DOJ.refresh('warrants')
    return #out > 0 and table.concat(out, ', ') or 'nothing'
end
DOJ.clearTests = clear

function DOJ.registerTest()
    if T.enabled == false then return end
    Whip.command('dojtest', { rateLimit = { burst = 3, everyMs = 1500 }, whileDead = true }, function(source, args)
        if not allowed(source) then return reply(source, 'Staff only', 'error') end
        local sub = (args[1] or ''):lower()
        if sub == 'clear' then
            return reply(source, 'Test rows removed: ' .. clear(), 'success')
        end
        if source == 0 then return reply(source, 'Run that in game (F8 or chat), not the console') end
        local cid = WC:GetCharId(source)
        if not cid then return reply(source, 'No character', 'error') end
        if sub == 'role' then
            local r = (args[2] or ''):lower()
            -- 1.1.0: the attorney roles by their usual names
            r = ({ da = 'prosecutor', ada = 'prosecutor', prosecution = 'prosecutor', pd = 'defender', defense = 'defender', defence = 'defender', publicdefender = 'defender',
                lawyer = 'attorney', private = 'attorney', police = 'leo', cop = 'leo' })[r] or r
            if r == 'off' or r == '' then DOJ.ViewAs[source] = nil DOJ.forget(source) return reply(source, 'DOJ tablet: staff view (everything)', 'success') end
            if not ({ judge = 1, prosecutor = 1, defender = 1, clerk = 1, attorney = 1, leo = 1 })[r] then return reply(source, 'Use: /dojtest role judge|prosecutor (da)|defender (pd)|clerk|attorney (private lawyer)|leo|off', 'error') end
            DOJ.ViewAs[source] = r
            DOJ.forget(source)
            TriggerClientEvent('es_doj:client:refresh', source, 'role')
            return reply(source, ('DOJ tablet: viewing as %s (/dojtest role off to stop)'):format(r), 'success')
        elseif sub == 'case' then
            local res, why = testCase(source, cid)
            return reply(source, res and ('Test case %s filed against you (bail $5,000 set, arraignment in 10 min). /%s or /%s'):format(res.number, Config.Command, Config.PortalCommand) or why, res and 'success' or 'error')
        elseif sub == 'warrant' then
            if GetResourceState('es_mdt') ~= 'started' then return reply(source, 'es_mdt is not running', 'error') end
            local dept
            for _, d in ipairs(DOJ.ED:GetDepartments() or {}) do if d.type == 'police' or d.type == 'sheriff' or d.type == 'state' then dept = d break end end
            if not dept then return reply(source, 'No law department', 'error') end
            local kind = (args[2] == 'search') and 'search' or 'arrest'
            local wid = MySQL.insert.await([[INSERT INTO `es_mdt_warrants` (`deptId`,`charId`,`reason`,`status`,`requestedBy`,`kind`,`scope`,`expiresAt`) VALUES (?,?,?,'requested',?,?,?,NOW() + INTERVAL 1 DAY)]],
                { dept.id, cid, TAG .. 'Test warrant request (nothing real happens if you sign it: it expires in a day)', cid, kind, kind == 'search' and 'Test: the vehicle you drive' or nil })
            TriggerEvent('es_mdt:warrantRequested', wid)
            return reply(source, ('Test %s warrant #%d requested: DOJ tablet → Warrants'):format(kind, wid), 'success')
        elseif sub == 'petition' then
            local k = (args[2] or 'name'):lower()
            local res, why
            if k == 'name' then
                res, why = DOJ.petitionCreate(cid, 'name_change', { firstName = 'Testy', lastName = 'McTestface' }, TAG .. 'Testing the name change desk', true, cid)
            elseif k == 'business' then
                res, why = DOJ.petitionCreate(cid, 'business', { name = 'Test Diner ' .. math.random(100, 999), kind = 'Restaurant', address = 'Vespucci Blvd' }, TAG .. 'Testing', true, cid)
            elseif k == 'expunge' then
                local r = MySQL.single.await('SELECT `reportId` FROM `es_mdt_report_people` WHERE `charId` = ? ORDER BY `reportId` DESC LIMIT 1', { cid })
                local kk = MySQL.single.await("SELECT `id` FROM `es_doj_cases` WHERE `defendantCharId` = ? AND `status` <> 'open' AND `test` = 1 ORDER BY `id` DESC LIMIT 1", { cid })
                res, why = DOJ.petitionCreate(cid, 'expungement', { reports = r and { r.reportId } or {}, cases = kk and { kk.id } or {} }, TAG .. 'Testing expungement', true, cid)
                if not res then why = (why or '') .. ' (you need an MDT report naming you, or a closed test case)' end
            else return reply(source, 'Use: /dojtest petition name|business|expunge', 'error') end
            return reply(source, res and ('Test petition #%d filed (fee $%d, test: pay it free in /%s)'):format(res.id, res.fee, Config.PortalCommand) or why, res and 'success' or 'error')
        elseif sub == 'service' then
            local n = math.max(1, math.min(10, tonumber(args[2]) or 3))
            MySQL.insert.await('INSERT INTO `es_doj_service` (`charId`,`total`,`note`,`createdBy`,`test`) VALUES (?,?,?,?,1)', { cid, n, TAG .. 'Test community service', cid })
            DOJ.serviceChanged(cid)
            return reply(source, ('%d test community service tasks: follow the map'):format(n), 'success')
        elseif sub == 'notice' then
            DOJ.notice(cid, TAG .. 'A test court notice', 'This is what a court notice looks like.', nil, 'notice', cid, true)
            return
        end
        reply(source, 'Use: /dojtest role|case|warrant|petition|service|notice|clear')
    end)
end
