local _ENV = ESAPP('doj'); -- es_doj admin: the dashboard, the court calendar, the penal code (doj_penal), firearm permit applications
-- (es_mdt's, decided by judges and clerks with "Process permits"), and the DOJ activity log.
local cb, str, int, id = DOJ.cb, DOJ.str, DOJ.int, DOJ.id
local CATS = { 'infraction', 'misdemeanor', 'felony' }

local function n(sql, args) return tonumber(MySQL.scalar.await(sql, args or {})) or 0 end

function DOJ.registerAdmin()
    cb('dashboard', { rate = 400, burst = 6 }, function(c)
        local me = c.charId
        local dep = c.dept or DOJ.dept()
        local out = { me = { charId = c.charId, name = c.name, label = c.label, roleName = c.roleName or (c.r.attorney and 'Attorney') or (c.r.leo and c.law and c.law.short) or (c.staff and 'Staff') or '',
            staff = c.staff, viewAs = c.viewAs, onDuty = c.onDuty, readOnly = c.readOnly, bar = c.bar, r = c.r,
            police = (c.law and GetResourceState('es_mdt') == 'started') and { short = c.law.short } or nil },   -- 1.1.0: "Police MDT" button
            dept = dep and { id = dep.id, short = dep.short, name = dep.name, logoVer = dep.logoVer, color1 = dep.color1, color2 = dep.color2 } or nil, counts = {} }
        local k = out.counts
        k.myCases = n("SELECT COUNT(*) FROM `es_doj_cases` WHERE `status` = 'open' AND ? IN (`judgeCharId`,`prosecutorCharId`,`defenseCharId`)", { me })
        k.openCases = n("SELECT COUNT(*) FROM `es_doj_cases` WHERE `status` = 'open' AND `test` = 0")
        k.unassigned = n("SELECT COUNT(*) FROM `es_doj_cases` WHERE `status` = 'open' AND `judgeCharId` IS NULL AND `test` = 0")
        k.today = n("SELECT COUNT(*) FROM `es_doj_hearings` WHERE `status` = 'scheduled' AND `startsAt` >= UTC_DATE() AND `startsAt` < UTC_DATE() + INTERVAL 1 DAY")
        k.warrants = (c.r.warrants or c.r.judge) and DOJ.warrantsWaiting() or 0
        k.petitions = (c.r.clerk or c.r.judge or c.r.seal) and n("SELECT COUNT(*) FROM `es_doj_petitions` WHERE `status` = 'pending'") or 0
        k.pleas = n([[SELECT COUNT(*) FROM `es_doj_pleas` p JOIN `es_doj_cases` k ON k.`id` = p.`caseId` WHERE k.`status` = 'open' AND
            ((p.`status` = 'accepted' AND k.`judgeCharId` = ?) OR (p.`status` = 'offered' AND k.`defenseCharId` = ?))]], { me, me })
        k.motions = n([[SELECT COUNT(*) FROM `es_doj_filings` f JOIN `es_doj_cases` k ON k.`id` = f.`caseId` WHERE f.`status` = 'pending' AND k.`status` = 'open' AND k.`judgeCharId` = ?]], { me })
        k.subpoenas = n([[SELECT COUNT(*) FROM `es_doj_subpoenas` s JOIN `es_doj_cases` k ON k.`id` = s.`caseId` WHERE s.`status` = 'requested' AND k.`judgeCharId` = ?]], { me })
        if c.r.permits and GetResourceState('es_mdt') == 'started' then
            k.permits = n("SELECT COUNT(*) FROM `es_mdt_permit_apps` WHERE `status` = 'pending'")
        end
        k.owed = n("SELECT COALESCE(SUM(`amount`),0) FROM `es_doj_fees` WHERE `status` = 'unpaid' AND `kind` <> 'bail' AND `test` = 0")
        out.hearings = MySQL.query.await([[SELECT h.`id`,h.`caseId`,h.`kind`,h.`title`,UNIX_TIMESTAMP(h.`startsAt`) AS `startsAt`,h.`minutes`,h.`room`,h.`judgeCharId`,k.`number`
            FROM `es_doj_hearings` h LEFT JOIN `es_doj_cases` k ON k.`id` = h.`caseId`
            WHERE h.`status` = 'scheduled' AND h.`startsAt` > NOW() - INTERVAL 2 HOUR AND (h.`judgeCharId` = ? OR ? IN (k.`prosecutorCharId`, k.`defenseCharId`) OR ?)
            AND (k.`id` IS NULL OR k.`sealed` = 0 OR ?) ORDER BY h.`startsAt` LIMIT 8]], { me, me, (c.r.court or c.staff) and 1 or 0, (c.r.judge or c.staff) and 1 or 0 }) or {}
        local ids = {}
        for _, h in ipairs(out.hearings) do ids[#ids + 1] = h.judgeCharId end
        local names = DOJ.namesOf(ids)
        for _, h in ipairs(out.hearings) do h.judge = names[h.judgeCharId or 0] end
        out.recent = MySQL.query.await([[SELECT l.`caseId`,k.`number`,l.`what`,l.`detail`,l.`byLabel`,UNIX_TIMESTAMP(l.`createdAt`) AS `at` FROM `es_doj_log` l
            JOIN `es_doj_cases` k ON k.`id` = l.`caseId` WHERE ? IN (k.`judgeCharId`, k.`prosecutorCharId`, k.`defenseCharId`) AND l.`byCharId` <> ?
            ORDER BY l.`id` DESC LIMIT 10]], { me, me }) or {}
        out.judgeOnly = (Config.Warrants or {}).judgeOnly == true
        return out
    end)

    cb('calendar', { rate = 300, burst = 6 }, function(c, d)
        local from = math.floor(tonumber(d.from) or os.time() - 86400)
        local to = math.floor(tonumber(d.to) or from + 86400 * 7)
        if to < from or to - from > 86400 * 45 then to = from + 86400 * 7 end
        local where, args = { 'h.`startsAt` >= FROM_UNIXTIME(?)', 'h.`startsAt` < FROM_UNIXTIME(?)' }, { from, to }
        if not (c.staff or c.r.judge) then where[#where + 1] = '(k.`id` IS NULL OR k.`sealed` = 0)' end
        if not c.staff then where[#where + 1] = ('(h.`test` = 0 OR h.`createdBy` = %d)'):format(c.charId) end
        local judge = id(d.judgeCharId)
        if judge then where[#where + 1] = 'h.`judgeCharId` = ?' args[#args + 1] = judge end
        if d.mine then where[#where + 1] = '(h.`judgeCharId` = ? OR ? IN (k.`prosecutorCharId`, k.`defenseCharId`))' args[#args + 1] = c.charId args[#args + 1] = c.charId end
        if d.room and d.room ~= '' then where[#where + 1] = 'h.`room` = ?' args[#args + 1] = str(d.room, 60) end
        local rows = MySQL.query.await(([[SELECT h.`id`,h.`caseId`,h.`kind`,h.`title`,UNIX_TIMESTAMP(h.`startsAt`) AS `startsAt`,h.`minutes`,h.`room`,h.`judgeCharId`,h.`status`,h.`outcome`,
            k.`number`,k.`defendantCharId`,k.`title` AS `caseTitle` FROM `es_doj_hearings` h LEFT JOIN `es_doj_cases` k ON k.`id` = h.`caseId`
            WHERE %s ORDER BY h.`startsAt` LIMIT 300]]):format(table.concat(where, ' AND ')), args) or {}
        local ids = {}
        for _, r in ipairs(rows) do ids[#ids + 1] = r.judgeCharId ids[#ids + 1] = r.defendantCharId end
        local names = DOJ.namesOf(ids)
        for _, r in ipairs(rows) do r.judge = names[r.judgeCharId or 0] r.defendant = names[r.defendantCharId or 0] end
        local judges = {}
        local dep = DOJ.dept()
        if dep then
            for _, m in ipairs(DOJ.ED:GetRoster(dep.id) or {}) do
                if m.perms and m.perms.doj_sign or (m.roleName or ''):lower():find('judge') then judges[#judges + 1] = { charId = m.charId, name = m.name } end
            end
        end
        return { rows = rows, from = from, to = to, rooms = Config.Courthouse.rooms, judges = judges }
    end)

    cb('judges', {}, function()
        local out, dep = {}, DOJ.dept()
        if not dep then return out end
        local online = DOJ.onlineByChar()
        for _, m in ipairs(DOJ.ED:GetRoster(dep.id) or {}) do
            out[#out + 1] = { charId = m.charId, name = m.name, roleName = m.roleName, online = online[m.charId] ~= nil }
        end
        return out
    end)

    -- ------------------------------------------------------------ penal code
    cb('penal', { rate = 400, burst = 4 }, function(c, d)
        local all = (c.r.penal or c.staff) and d.all == true
        return MySQL.query.await(("SELECT `id`,`code`,`title`,`category`,`fine`,`months`,`description`,`active` FROM `es_penal_code` %s ORDER BY FIELD(`category`,'infraction','misdemeanor','felony'), `code`")
            :format(all and '' or 'WHERE `active` = 1')) or {}
    end)

    cb('penalSave', { role = 'penal', write = true, rate = 800, burst = 5, why = 'Your rank cannot edit the penal code' }, function(c, d)
        local pid = id(d.id)
        local code = str(d.code, 16):upper()
        local title = str(d.title, 120)
        if not code:match('^[%w%-%.]+$') then return false, 'A code is letters, numbers, dots and dashes (F-101)' end
        if title == '' then return false, 'Give it a title' end
        local cat = DOJ.oneOf(d.category, CATS, nil)
        if not cat then return false, 'Pick a category' end
        local fine = int(d.fine, 0, (Config.Sentence or {}).maxFine or 1000000)
        local months = int(d.months, 0, (Config.Sentence or {}).maxMonths or 300)
        local desc = str(d.description, 500)
        if MySQL.scalar.await('SELECT 1 FROM `es_penal_code` WHERE `code` = ? AND `id` <> ?', { code, pid or 0 }) then return false, 'That code is taken' end
        if pid then
            local old = MySQL.single.await('SELECT `code`,`fine`,`months`,`active` FROM `es_penal_code` WHERE `id` = ?', { pid })
            if not old then return false, 'No such charge' end
            MySQL.update.await('UPDATE `es_penal_code` SET `code` = ?, `title` = ?, `category` = ?, `fine` = ?, `months` = ?, `description` = ?, `active` = ? WHERE `id` = ?',
                { code, title, cat, fine, months, desc ~= '' and desc or nil, d.active == false and 0 or 1, pid })
            DOJ.log(nil, c, 'penal_edit', ('%s %s: $%d → $%d, %d → %d mo%s'):format(code, title, old.fine, fine, old.months, months, (d.active == false and old.active == 1) and ', retired' or ''))
        else
            pid = MySQL.insert.await('INSERT INTO `es_penal_code` (`code`,`title`,`category`,`fine`,`months`,`description`) VALUES (?,?,?,?,?,?)', { code, title, cat, fine, months, desc ~= '' and desc or nil })
            DOJ.log(nil, c, 'penal_add', ('%s %s ($%d, %d mo)'):format(code, title, fine, months))
        end
        TriggerEvent('es_doj:penalChanged')
        DOJ.refresh('penal')
        return { id = pid }
    end)

    -- ------------------------------------------------------------ firearm permits (es_mdt applications)
    local function mdt() return GetResourceState('es_mdt') == 'started' end
    cb('permits', { role = 'permits', why = 'Your rank cannot process permits' }, function(_, d)
        if not mdt() then return false, 'The MDT is not running' end
        local st = DOJ.oneOf(d.status, { 'pending', 'approved', 'denied', 'all' }, 'pending')
        return exports.es_mdt:GetPermitApplications(st) or {}
    end)

    cb('permitPhoto', { role = 'permits', rate = 300, burst = 10 }, function(_, d)
        local img = MySQL.scalar.await('SELECT `photo` FROM `es_mdt_permit_apps` WHERE `id` = ?', { id(d.id) or 0 })
        if type(img) ~= 'string' or img:sub(1, 11) ~= 'data:image/' then return false, 'No photo' end
        return img
    end)

    cb('permitCheck', { role = 'permits' }, function(_, d)
        if not mdt() then return false, 'The MDT is not running' end
        return exports.es_mdt:PermitBackgroundCheck(id(d.charId) or 0)
    end)

    cb('permitDecide', { role = 'permits', write = true, why = 'Your rank cannot process permits' }, function(c, d)
        if not mdt() then return false, 'The MDT is not running' end
        local decision = d.decision == 'approve' and 'approve' or (d.decision == 'deny' and 'deny' or nil)
        if not decision then return false, 'approve or deny' end
        local note = str(d.note, 300)
        if decision == 'deny' and note == '' then return false, 'Say why (they read it)' end
        local ok, why = exports.es_mdt:DecidePermit(id(d.id), decision, note, c.charId, c.label)
        if not ok then return false, why end
        DOJ.log(nil, c, 'permit_' .. decision, ('Permit application #%d %s%s'):format(id(d.id) or 0, decision == 'approve' and 'approved' or 'denied', note ~= '' and (': ' .. note) or ''))
        return true
    end)

    -- ------------------------------------------------------------ the DOJ activity log
    cb('activity', { role = { 'member', 'staff' } }, function(c, d)
        local where, args = {}, {}
        if not (c.staff or c.r.judge or c.r.seal) then where[#where + 1] = '(k.`id` IS NULL OR k.`sealed` = 0)' end
        local q = str(d.q, 60)
        if q ~= '' then where[#where + 1] = "(l.`detail` LIKE CONCAT('%', ?, '%') OR l.`byLabel` LIKE CONCAT('%', ?, '%') OR k.`number` LIKE CONCAT('%', ?, '%'))" args = { q, q, q } end
        if not c.staff then where[#where + 1] = ('(k.`id` IS NULL OR k.`test` = 0 OR k.`createdBy` = %d)'):format(c.charId) end
        return MySQL.query.await(([[SELECT l.`id`,l.`caseId`,k.`number`,l.`what`,l.`detail`,l.`byLabel`,UNIX_TIMESTAMP(l.`createdAt`) AS `at` FROM `es_doj_log` l
            LEFT JOIN `es_doj_cases` k ON k.`id` = l.`caseId` %s %s ORDER BY l.`id` DESC LIMIT 150]]):format(#where > 0 and ('WHERE ' .. table.concat(where, ' AND ')) or '',
            ''), args) or {}
    end)
end
