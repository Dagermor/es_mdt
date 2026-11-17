local _ENV = ESAPP('mdt'); -- es_mdt 1.7.0: officer profiles (personnel files). es_departments keeps the file and decides who sees what
-- (GetPersonnelFile); this adds the MDT's own numbers (arrests, citations, reports, warrants, calls, evidence, jail)
-- and the officer's photo. Loaded BEFORE server/main.lua; runs from MDT.registerOfficer().
local ED = exports.es_departments
MDT = MDT or {}

local PHOTO_MAX = 420000   -- characters of data URL (~300 KB picture)
local function photoOk(img) return type(img) == 'string' and img:match('^data:image/[a-z]+;base64,') ~= nil and #img <= PHOTO_MAX end

local HAS = {}
local function hasTable(t)
    if HAS[t] == nil then
        HAS[t] = MySQL.single.await('SELECT 1 AS `x` FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?', { t }) ~= nil
    end
    return HAS[t]
end

local function pair(sql, args)
    local r = MySQL.single.await(sql, args) or {}
    return { all = tonumber(r.n) or 0, d30 = tonumber(r.m) or 0 }
end

--- what they did, all time and the last 30 days
local function statsOf(cid)
    local s = {}
    s.reports = pair("SELECT COUNT(*) AS `n`, COALESCE(SUM(`createdAt` > NOW() - INTERVAL 30 DAY),0) AS `m` FROM `es_mdt_reports` WHERE `authorCharId` = ?", { cid })
    s.arrests = pair([[SELECT COUNT(*) AS `n`, COALESCE(SUM(r.`createdAt` > NOW() - INTERVAL 30 DAY),0) AS `m` FROM `es_mdt_report_officers` o
        JOIN `es_mdt_reports` r ON r.`id` = o.`reportId` WHERE r.`type` = 'arrest' AND o.`charId` = ?]], { cid })
    s.citations = pair("SELECT COUNT(*) AS `n`, COALESCE(SUM(`createdAt` > NOW() - INTERVAL 30 DAY),0) AS `m` FROM `es_mdt_fines` WHERE `issuedBy` = ?", { cid })
    s.warrants = pair("SELECT COUNT(*) AS `n`, COALESCE(SUM(`createdAt` > NOW() - INTERVAL 30 DAY),0) AS `m` FROM `es_mdt_warrants` WHERE `issuedBy` = ? AND `status` <> 'requested'", { cid })
    s.calls = pair([[SELECT COUNT(DISTINCT `callId`) AS `n`, COUNT(DISTINCT CASE WHEN `attachedAt` > NOW() - INTERVAL 30 DAY THEN `callId` END) AS `m`
        FROM `es_mdt_call_units` WHERE `charId` = ?]], { cid })
    if hasTable('es_evidence') then
        s.evidence = pair("SELECT COUNT(*) AS `n`, COALESCE(SUM(`collectedAt` > NOW() - INTERVAL 30 DAY),0) AS `m` FROM `es_evidence` WHERE `collectedBy` = ?", { cid })
    end
    if hasTable('es_jail_log') then
        s.jail = pair("SELECT COUNT(*) AS `n`, COALESCE(SUM(`at` > NOW() - INTERVAL 30 DAY),0) AS `m` FROM `es_jail_log` WHERE `what` = 'jailed' AND `byCharId` = ?", { cid })
    end
    return s
end

--- their photo: the one set on their file, else their latest MDT mugshot, else the WHIP character portrait
local function photoOf(cid)
    local r = MySQL.single.await('SELECT `image`, UNIX_TIMESTAMP(`updatedAt`) AS `at` FROM `es_mdt_officer_photos` WHERE `charId` = ?', { cid })
    if r and r.image then return { image = r.image, from = 'photo', at = r.at } end
    r = MySQL.single.await([[SELECT m.`image` FROM `es_mdt_profiles` p JOIN `es_mdt_mugshots` m ON m.`id` = p.`mugshotId` WHERE p.`charId` = ?]], { cid })
    if r and r.image then return { image = r.image, from = 'mugshot' } end
    r = MySQL.single.await('SELECT `image` FROM `character_portraits` WHERE `charId` = ?', { cid })
    if r and r.image then return { image = r.image, from = 'portrait' } end
    return nil
end

local function mayPhoto(c, cid)
    if c.staff or cid == c.charId then return true end
    local ok, why = ED:CanManagePersonnel(c.source, c.dept.id, cid)
    if ok then return true end
    return false, why or 'Only the officer or their supervisor changes this photo'
end

--- 'YYYY-MM-DD' -> unix (end of that day, UTC) or nil
--- 1.7.1: call es_departments and turn a crash into a clear reason (the panel showed "system error")
local function try(what, fn)
    local ok, a, b = pcall(fn)
    if ok then return a, b end
    print(('^1[es_mdt] %s failed: %s^7'):format(what, tostring(a)))
    return false, ('Could not %s right now (server error, logged for the admin)'):format(what)
end

local function dayEnd(s)
    local y, m, d = tostring(s or ''):match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    if not y then return nil end
    local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 23, min = 59, sec = 0 })
    return t
end

function MDT.registerOfficer()
    local ok, why = Whip.core:EnsureTable('es_mdt_officer_photos', [[CREATE TABLE IF NOT EXISTS `es_mdt_officer_photos` (
        `charId` INT UNSIGNED NOT NULL,
        `image` MEDIUMTEXT NOT NULL,
        `origin` VARCHAR(12) NOT NULL DEFAULT 'upload',
        `updatedBy` INT UNSIGNED NULL,
        `updatedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`charId`),
        CONSTRAINT `fk_es_ophoto_char` FOREIGN KEY (`charId`) REFERENCES `characters` (`charId`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]], {})
    if not ok then print(('^1[es_mdt] officer photos table: %s^7'):format(tostring(why))) end
    local cb, id, str, int = MDT.cb, MDT.id, MDT.str, MDT.int

    cb('officerProfile', { rate = 400, burst = 6 }, function(c, d)
        local cid = id(d.charId) or c.charId
        local f, fwhy = try('open that profile', function() return ED:GetPersonnelFile(c.source, c.dept.id, cid) end)
        if not f then return false, fwhy end
        f.stats = statsOf(cid)
        f.photo = photoOf(cid)
        f.me = c.charId
        f.readOnly = c.readOnly
        if f.can then
            local okp = mayPhoto(c, cid)
            f.can.photo = okp and not c.readOnly
            if c.readOnly then f.can.entries, f.can.certs = false, false end
        end
        return f
    end)

    -- mode: upload (data URL made in the page, already shrunk) | link | roll (their camera roll) | clear
    cb('officerPhoto', { write = true, rate = 2500, burst = 3 }, function(c, d)
        local cid = id(d.charId)
        if not cid then return false, 'Pick an officer' end
        local okp, pwhy = mayPhoto(c, cid)
        if not okp then return false, pwhy end
        local img, origin
        if d.mode == 'clear' then
            MySQL.update.await('DELETE FROM `es_mdt_officer_photos` WHERE `charId` = ?', { cid })
            MDT.refresh('personnel')
            return { cleared = true }
        elseif d.mode == 'upload' then
            img, origin = d.image, 'upload'
        elseif d.mode == 'link' then
            local url = str(d.url, 500)
            local okc, cwhy = Fetch.check(url)
            if not okc then return false, cwhy end
            local got, err = Fetch.get(url)
            if not got then return false, err end
            img, origin = got, 'link'
        elseif d.mode == 'roll' then
            if GetResourceState('es_evidence') ~= 'started' then return false, 'The camera roll (es_evidence) is not running' end
            img, origin = exports.es_evidence:RollImage(c.charId, id(d.photoId) or 0), 'roll'
            if not img then return false, 'That photo is not in your camera roll' end
        else
            return false, 'Pick a picture'
        end
        if not photoOk(img) then return false, ('That picture is too big (%d KB); a profile photo can be %d KB at most'):format(
            math.ceil(#tostring(img or '') * 3 / 4 / 1024), math.floor(PHOTO_MAX * 3 / 4 / 1024)) end
        MySQL.update.await([[INSERT INTO `es_mdt_officer_photos` (`charId`,`image`,`origin`,`updatedBy`) VALUES (?,?,?,?)
            ON DUPLICATE KEY UPDATE `image` = VALUES(`image`), `origin` = VALUES(`origin`), `updatedBy` = VALUES(`updatedBy`)]], { cid, img, origin, c.charId })
        MDT.log(c, 'officer_photo', { charId = cid, origin = origin })
        MDT.refresh('personnel')
        return { image = img }
    end)

    cb('personnelAdd', { write = true, rate = 1500, burst = 3 }, function(c, d)
        return try('add that to the record', function() return ED:AddPersonnelEntry(c.source, c.dept.id, id(d.charId) or 0, { kind = str(d.kind, 12), title = str(d.title, 100),
            body = type(d.body) == 'string' and d.body:sub(1, 1000) or '', visibility = d.visibility == 'supervisors' and 'supervisors' or 'officer', days = int(d.days, 0, 365) }) end)
    end)
    cb('personnelRemove', { write = true, rate = 1000, burst = 3 }, function(c, d)
        return try('remove that entry', function() return ED:RemovePersonnelEntry(c.source, c.dept.id, id(d.id) or 0) end)
    end)

    cb('certs', { rate = 500, burst = 4 }, function(c)
        local r, why = try('load the certifications', function() return ED:GetCerts(c.dept.id) end)
        if not r then return false, why end
        r.canEdit = ED:CanEditCerts(c.source, c.dept.id) == true and not c.readOnly
        r.supervisor = c.staff or c.perms.personnel_manage == true
        if r.supervisor or r.canEdit then r.alerts = ED:GetCertAlerts(c.dept.id) or {} end
        local dd = ED:GetDepartment(c.dept.id) or {}
        r.ranks = dd.ranks or {}
        return r
    end)
    cb('certsSave', { write = true, rate = 1500, burst = 2 }, function(c, d)
        if type(d.list) ~= 'table' then return false, 'Nothing to save' end
        return try('save the certifications', function() return ED:SaveCerts(c.source, c.dept.id, d.list) end)
    end)
    cb('certGrant', { write = true, rate = 1000, burst = 4 }, function(c, d)
        local noExp = d.noExpiry == true
        local exp = (not noExp) and dayEnd(d.expires) or nil
        if not noExp and not exp then return false, 'Pick an expiry date, or tick "No expiry"' end
        return try('grant that certification', function() return ED:GrantCert(c.source, c.dept.id, id(d.charId) or 0, id(d.certId) or 0, { note = str(d.note, 300), expiresAt = exp, noExpiry = noExp }) end)
    end)
    cb('certRevoke', { write = true, rate = 1000, burst = 4 }, function(c, d)
        return try('revoke that certification', function() return ED:RevokeCert(c.source, c.dept.id, id(d.holderId) or 0, str(d.note, 300)) end)
    end)
end
