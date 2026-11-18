local _ENV = ESAPP('mdt'); -- es_mdt tables. Every row a department owns cascades away with the department; people rows with the character.
Tables = {}

local DEFS = {
    { 'es_penal_code', [[CREATE TABLE IF NOT EXISTS `es_penal_code` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `code` VARCHAR(16) NOT NULL,
        `title` VARCHAR(120) NOT NULL,
        `category` ENUM('infraction','misdemeanor','felony') NOT NULL DEFAULT 'misdemeanor',
        `fine` INT UNSIGNED NOT NULL DEFAULT 0,
        `months` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
        `description` VARCHAR(500) NULL,
        `active` TINYINT(1) NOT NULL DEFAULT 1,
        `updatedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        UNIQUE KEY `uk_es_penal_code` (`code`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]], {
        { id = '002_license', statements = {
            "UPDATE `es_penal_code` SET `title` = 'Driving without a license' WHERE `code` = 'M-202' AND `title` = 'Driving without a licence'",
        } },
    } },
    { 'es_mdt_reports', [[CREATE TABLE IF NOT EXISTS `es_mdt_reports` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `deptId` INT UNSIGNED NOT NULL,
        `type` VARCHAR(16) NOT NULL DEFAULT 'incident',
        `title` VARCHAR(120) NOT NULL,
        `body` TEXT NULL,
        `location` VARCHAR(120) NULL,
        `authorCharId` INT UNSIGNED NOT NULL,
        `caseId` INT UNSIGNED NULL,
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `updatedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_es_rep_dept` (`deptId`, `createdAt`),
        KEY `idx_es_rep_author` (`authorCharId`),
        KEY `idx_es_rep_case` (`caseId`),
        CONSTRAINT `fk_es_rep_dept` FOREIGN KEY (`deptId`) REFERENCES `es_departments` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]], {
        -- 1.5.0: a report can belong to a case
        { id = '002_case', statements = {
            { sql = 'ALTER TABLE `es_mdt_reports` ADD COLUMN `caseId` INT UNSIGNED NULL', unless = { column = { 'es_mdt_reports', 'caseId' } } },
            { sql = 'ALTER TABLE `es_mdt_reports` ADD KEY `idx_es_rep_case` (`caseId`)', unless = { index = { 'es_mdt_reports', 'idx_es_rep_case' } } },
        } },
    } },
    { 'es_mdt_report_people', [[CREATE TABLE IF NOT EXISTS `es_mdt_report_people` (
        `reportId` INT UNSIGNED NOT NULL,
        `charId` INT UNSIGNED NOT NULL,
        `role` ENUM('suspect','victim','witness','other') NOT NULL DEFAULT 'suspect',
        PRIMARY KEY (`reportId`, `charId`),
        KEY `idx_es_rpp_char` (`charId`),
        CONSTRAINT `fk_es_rpp_rep` FOREIGN KEY (`reportId`) REFERENCES `es_mdt_reports` (`id`) ON DELETE CASCADE,
        CONSTRAINT `fk_es_rpp_char` FOREIGN KEY (`charId`) REFERENCES `characters` (`charId`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_mdt_report_officers', [[CREATE TABLE IF NOT EXISTS `es_mdt_report_officers` (
        `reportId` INT UNSIGNED NOT NULL,
        `charId` INT UNSIGNED NOT NULL,
        `primary` TINYINT(1) NOT NULL DEFAULT 0,
        PRIMARY KEY (`reportId`, `charId`),
        KEY `idx_es_rpo_char` (`charId`),
        CONSTRAINT `fk_es_rpo_rep` FOREIGN KEY (`reportId`) REFERENCES `es_mdt_reports` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_mdt_report_charges', [[CREATE TABLE IF NOT EXISTS `es_mdt_report_charges` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `reportId` INT UNSIGNED NOT NULL,
        `charId` INT UNSIGNED NOT NULL,
        `penalId` INT UNSIGNED NULL,
        `code` VARCHAR(16) NOT NULL,
        `title` VARCHAR(120) NOT NULL,
        `category` VARCHAR(16) NOT NULL,
        `count` TINYINT UNSIGNED NOT NULL DEFAULT 1,
        `fine` INT UNSIGNED NOT NULL DEFAULT 0,
        `months` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
        `baseFine` INT UNSIGNED NULL,
        `baseMonths` SMALLINT UNSIGNED NULL,
        PRIMARY KEY (`id`),
        KEY `idx_es_rpc_rep` (`reportId`),
        KEY `idx_es_rpc_char` (`charId`),
        CONSTRAINT `fk_es_rpc_rep` FOREIGN KEY (`reportId`) REFERENCES `es_mdt_reports` (`id`) ON DELETE CASCADE,
        CONSTRAINT `fk_es_rpc_char` FOREIGN KEY (`charId`) REFERENCES `characters` (`charId`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]], {
        { id = '002_charge_base', statements = {
            { sql = 'ALTER TABLE `es_mdt_report_charges` ADD COLUMN `baseFine` INT UNSIGNED NULL', unless = { column = { 'es_mdt_report_charges', 'baseFine' } } },
            { sql = 'ALTER TABLE `es_mdt_report_charges` ADD COLUMN `baseMonths` SMALLINT UNSIGNED NULL', unless = { column = { 'es_mdt_report_charges', 'baseMonths' } } },
        } },
    } },
    { 'es_mdt_warrants', [[CREATE TABLE IF NOT EXISTS `es_mdt_warrants` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `deptId` INT UNSIGNED NOT NULL,
        `charId` INT UNSIGNED NOT NULL,
        `reportId` INT UNSIGNED NULL,
        `reason` VARCHAR(500) NOT NULL,
        `status` ENUM('requested','active','served','void') NOT NULL DEFAULT 'active',
        `requestedBy` INT UNSIGNED NOT NULL,
        `issuedBy` INT UNSIGNED NULL,
        `closedBy` INT UNSIGNED NULL,
        `expiresAt` DATETIME NULL,
        `fineId` INT UNSIGNED NULL,
        `auto` TINYINT(1) NOT NULL DEFAULT 0,
        `bolosPosted` TINYINT(1) NOT NULL DEFAULT 0,
        `caseId` INT UNSIGNED NULL,
        `kind` VARCHAR(10) NOT NULL DEFAULT 'arrest',
        `scope` VARCHAR(300) NULL,
        `judgeCharId` INT UNSIGNED NULL,
        `judgeName` VARCHAR(80) NULL,
        `judgeNote` VARCHAR(300) NULL,
        `decidedAt` DATETIME NULL,
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `updatedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        UNIQUE KEY `uk_es_war_fine` (`fineId`),
        KEY `idx_es_war_status` (`status`),
        KEY `idx_es_war_char` (`charId`),
        KEY `idx_es_war_case` (`caseId`),
        CONSTRAINT `fk_es_war_dept` FOREIGN KEY (`deptId`) REFERENCES `es_departments` (`id`) ON DELETE CASCADE,
        CONSTRAINT `fk_es_war_char` FOREIGN KEY (`charId`) REFERENCES `characters` (`charId`) ON DELETE CASCADE,
        CONSTRAINT `fk_es_war_rep` FOREIGN KEY (`reportId`) REFERENCES `es_mdt_reports` (`id`) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]], {
        { id = '002_auto_fine', statements = {
            { sql = 'ALTER TABLE `es_mdt_warrants` ADD COLUMN `fineId` INT UNSIGNED NULL', unless = { column = { 'es_mdt_warrants', 'fineId' } } },
            { sql = 'ALTER TABLE `es_mdt_warrants` ADD COLUMN `auto` TINYINT(1) NOT NULL DEFAULT 0', unless = { column = { 'es_mdt_warrants', 'auto' } } },
            { sql = 'ALTER TABLE `es_mdt_warrants` ADD UNIQUE KEY `uk_es_war_fine` (`fineId`)', unless = { index = { 'es_mdt_warrants', 'uk_es_war_fine' } } },
        } },
        -- 1.3.6: an active warrant posts its BOLOs once (closing one by hand does not bring it back)
        { id = '003_bolos_posted', statements = {
            { sql = 'ALTER TABLE `es_mdt_warrants` ADD COLUMN `bolosPosted` TINYINT(1) NOT NULL DEFAULT 0', unless = { column = { 'es_mdt_warrants', 'bolosPosted' } } },
        } },
        -- 1.5.0: a warrant can belong to a case
        { id = '004_case', statements = {
            { sql = 'ALTER TABLE `es_mdt_warrants` ADD COLUMN `caseId` INT UNSIGNED NULL', unless = { column = { 'es_mdt_warrants', 'caseId' } } },
            { sql = 'ALTER TABLE `es_mdt_warrants` ADD KEY `idx_es_war_case` (`caseId`)', unless = { index = { 'es_mdt_warrants', 'idx_es_war_case' } } },
        } },
        -- 1.9.0: arrest or search warrants, and the judge's decision (es_doj)
        { id = '005_judge', statements = {
            { sql = "ALTER TABLE `es_mdt_warrants` ADD COLUMN `kind` VARCHAR(10) NOT NULL DEFAULT 'arrest'", unless = { column = { 'es_mdt_warrants', 'kind' } } },
            { sql = 'ALTER TABLE `es_mdt_warrants` ADD COLUMN `scope` VARCHAR(300) NULL', unless = { column = { 'es_mdt_warrants', 'scope' } } },
            { sql = 'ALTER TABLE `es_mdt_warrants` ADD COLUMN `judgeCharId` INT UNSIGNED NULL', unless = { column = { 'es_mdt_warrants', 'judgeCharId' } } },
            { sql = 'ALTER TABLE `es_mdt_warrants` ADD COLUMN `judgeName` VARCHAR(80) NULL', unless = { column = { 'es_mdt_warrants', 'judgeName' } } },
            { sql = 'ALTER TABLE `es_mdt_warrants` ADD COLUMN `judgeNote` VARCHAR(300) NULL', unless = { column = { 'es_mdt_warrants', 'judgeNote' } } },
            { sql = 'ALTER TABLE `es_mdt_warrants` ADD COLUMN `decidedAt` DATETIME NULL', unless = { column = { 'es_mdt_warrants', 'decidedAt' } } },
        } },
    } },
    { 'es_mdt_bolos', [[CREATE TABLE IF NOT EXISTS `es_mdt_bolos` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `deptId` INT UNSIGNED NOT NULL,
        `kind` ENUM('person','vehicle','weapon') NOT NULL DEFAULT 'vehicle',
        `serial` VARCHAR(32) NULL,
        `charId` INT UNSIGNED NULL,
        `plate` VARCHAR(10) NULL,
        `title` VARCHAR(120) NOT NULL,
        `description` VARCHAR(1000) NULL,
        `status` ENUM('active','closed') NOT NULL DEFAULT 'active',
        `createdBy` INT UNSIGNED NOT NULL,
        `closedBy` INT UNSIGNED NULL,
        `expiresAt` DATETIME NULL,
        `lastX` FLOAT NULL,
        `lastY` FLOAT NULL,
        `lastSeenAt` DATETIME NULL,
        `warrantId` INT UNSIGNED NULL,
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_es_bolo_status` (`status`),
        KEY `idx_es_bolo_warrant` (`warrantId`),
        KEY `idx_es_bolo_plate` (`plate`),
        KEY `idx_es_bolo_serial` (`serial`),
        CONSTRAINT `fk_es_bolo_dept` FOREIGN KEY (`deptId`) REFERENCES `es_departments` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]], {
        { id = '002_weapon', statements = {
            "ALTER TABLE `es_mdt_bolos` MODIFY `kind` ENUM('person','vehicle','weapon') NOT NULL DEFAULT 'vehicle'",
            { sql = 'ALTER TABLE `es_mdt_bolos` ADD COLUMN `serial` VARCHAR(32) NULL', unless = { column = { 'es_mdt_bolos', 'serial' } } },
            { sql = 'ALTER TABLE `es_mdt_bolos` ADD KEY `idx_es_bolo_serial` (`serial`)', unless = { index = { 'es_mdt_bolos', 'idx_es_bolo_serial' } } },
        } },
        { id = '003_last_seen', statements = {
            { sql = 'ALTER TABLE `es_mdt_bolos` ADD COLUMN `lastX` FLOAT NULL', unless = { column = { 'es_mdt_bolos', 'lastX' } } },
            { sql = 'ALTER TABLE `es_mdt_bolos` ADD COLUMN `lastY` FLOAT NULL', unless = { column = { 'es_mdt_bolos', 'lastY' } } },
            { sql = 'ALTER TABLE `es_mdt_bolos` ADD COLUMN `lastSeenAt` DATETIME NULL', unless = { column = { 'es_mdt_bolos', 'lastSeenAt' } } },
        } },
        -- 1.3.6: BOLOs a warrant posted (closed with it)
        { id = '004_warrant_link', statements = {
            { sql = 'ALTER TABLE `es_mdt_bolos` ADD COLUMN `warrantId` INT UNSIGNED NULL', unless = { column = { 'es_mdt_bolos', 'warrantId' } } },
            { sql = 'ALTER TABLE `es_mdt_bolos` ADD KEY `idx_es_bolo_warrant` (`warrantId`)', unless = { index = { 'es_mdt_bolos', 'idx_es_bolo_warrant' } } },
        } },
    } },
    { 'es_mdt_fines', [[CREATE TABLE IF NOT EXISTS `es_mdt_fines` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `deptId` INT UNSIGNED NOT NULL,
        `charId` INT UNSIGNED NOT NULL,
        `reportId` INT UNSIGNED NULL,
        `amount` INT UNSIGNED NOT NULL,
        `reason` VARCHAR(200) NULL,
        `status` ENUM('unpaid','paid','void') NOT NULL DEFAULT 'unpaid',
        `issuedBy` INT UNSIGNED NOT NULL,
        `paidAt` DATETIME NULL,
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_es_fine_char` (`charId`, `status`),
        UNIQUE KEY `uk_es_fine_report` (`reportId`, `charId`),
        CONSTRAINT `fk_es_fine_dept` FOREIGN KEY (`deptId`) REFERENCES `es_departments` (`id`) ON DELETE CASCADE,
        CONSTRAINT `fk_es_fine_char` FOREIGN KEY (`charId`) REFERENCES `characters` (`charId`) ON DELETE CASCADE,
        CONSTRAINT `fk_es_fine_rep` FOREIGN KEY (`reportId`) REFERENCES `es_mdt_reports` (`id`) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_mdt_report_log', [[CREATE TABLE IF NOT EXISTS `es_mdt_report_log` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `reportId` INT UNSIGNED NOT NULL,
        `byCharId` INT UNSIGNED NOT NULL,
        `what` VARCHAR(32) NOT NULL,
        `detail` VARCHAR(500) NOT NULL,
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_es_rlog_rep` (`reportId`, `id`),
        CONSTRAINT `fk_es_rlog_rep` FOREIGN KEY (`reportId`) REFERENCES `es_mdt_reports` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    -- every earlier version of an edited report, and every deleted report, in full (no FK: it outlives the report)
    { 'es_mdt_report_audit', [[CREATE TABLE IF NOT EXISTS `es_mdt_report_audit` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `reportId` INT UNSIGNED NOT NULL,
        `deptId` INT UNSIGNED NULL,
        `byCharId` INT UNSIGNED NOT NULL,
        `what` VARCHAR(16) NOT NULL,
        `title` VARCHAR(120) NULL,
        `snapshot` MEDIUMTEXT NULL,
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_es_raud_rep` (`reportId`, `id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    -- weapons: the registry (serial = whip_gunny's item serial, kept for the Evidence phase: casings match it)
    { 'es_mdt_weapons', [[CREATE TABLE IF NOT EXISTS `es_mdt_weapons` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `serial` VARCHAR(32) NOT NULL,
        `item` VARCHAR(64) NOT NULL,
        `label` VARCHAR(80) NULL,
        `ownerCharId` INT UNSIGNED NULL,
        `origin` VARCHAR(16) NOT NULL DEFAULT 'officer',   -- how it got on the registry: shop / given / officer
        `status` ENUM('registered','stolen','seized','destroyed') NOT NULL DEFAULT 'registered',
        `notes` TEXT NULL,
        `registeredBy` INT UNSIGNED NULL,
        `registeredAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `updatedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        UNIQUE KEY `uk_es_wpn_serial` (`serial`),
        KEY `idx_es_wpn_owner` (`ownerCharId`),
        KEY `idx_es_wpn_status` (`status`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_mdt_weapon_log', [[CREATE TABLE IF NOT EXISTS `es_mdt_weapon_log` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `weaponId` INT UNSIGNED NOT NULL,
        `byCharId` INT UNSIGNED NULL,
        `what` VARCHAR(24) NOT NULL,
        `detail` VARCHAR(500) NULL,
        `reportId` INT UNSIGNED NULL,
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_es_wlog_wpn` (`weaponId`, `id`),
        CONSTRAINT `fk_es_wlog_wpn` FOREIGN KEY (`weaponId`) REFERENCES `es_mdt_weapons` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_mdt_report_weapons', [[CREATE TABLE IF NOT EXISTS `es_mdt_report_weapons` (
        `reportId` INT UNSIGNED NOT NULL,
        `serial` VARCHAR(32) NOT NULL,
        `role` ENUM('seized','used','found','evidence') NOT NULL DEFAULT 'evidence',
        PRIMARY KEY (`reportId`, `serial`),
        KEY `idx_es_rpw_serial` (`serial`),
        CONSTRAINT `fk_es_rpw_rep` FOREIGN KEY (`reportId`) REFERENCES `es_mdt_reports` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_mdt_weapon_licenses', [[CREATE TABLE IF NOT EXISTS `es_mdt_weapon_licenses` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `charId` INT UNSIGNED NOT NULL,
        `type` VARCHAR(32) NOT NULL,
        `status` ENUM('active','suspended','revoked') NOT NULL DEFAULT 'active',
        `issuedBy` INT UNSIGNED NULL,
        `issuedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `updatedBy` INT UNSIGNED NULL,
        `updatedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        `note` VARCHAR(300) NULL,
        `origin` VARCHAR(16) NULL,
        PRIMARY KEY (`id`),
        UNIQUE KEY `uk_es_wlic` (`charId`, `type`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]], {
        -- 1.8.0: where a permit came from (department = auto on hire, application, manual, court)
        { id = '002_origin', statements = {
            { sql = 'ALTER TABLE `es_mdt_weapon_licenses` ADD COLUMN `origin` VARCHAR(16) NULL', unless = { column = { 'es_mdt_weapon_licenses', 'origin' } } },
        } },
    } },
    -- 1.8.0: firearm permit applications (civilians apply, permits_manage / DOJ decide)
    { 'es_mdt_permit_apps', [[CREATE TABLE IF NOT EXISTS `es_mdt_permit_apps` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `charId` INT UNSIGNED NOT NULL,
        `type` VARCHAR(32) NOT NULL,
        `reason` VARCHAR(500) NOT NULL,
        `status` ENUM('pending','processing','approved','denied','cancelled') NOT NULL DEFAULT 'pending',
        `fee` INT UNSIGNED NOT NULL DEFAULT 0,
        `paid` INT UNSIGNED NOT NULL DEFAULT 0,
        `checkJson` TEXT NULL,
        `photo` MEDIUMTEXT NULL,
        `via` VARCHAR(40) NULL,
        `decidedBy` INT UNSIGNED NULL,
        `decidedByLabel` VARCHAR(80) NULL,
        `decisionNote` VARCHAR(300) NULL,
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `decidedAt` TIMESTAMP NULL,
        PRIMARY KEY (`id`),
        KEY `idx_es_pa_status` (`status`, `id`),
        KEY `idx_es_pa_char` (`charId`),
        CONSTRAINT `fk_es_pa_char` FOREIGN KEY (`charId`) REFERENCES `characters` (`charId`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_mdt_weapon_license_log', [[CREATE TABLE IF NOT EXISTS `es_mdt_weapon_license_log` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `licenseId` INT UNSIGNED NOT NULL,
        `byCharId` INT UNSIGNED NULL,
        `action` VARCHAR(16) NOT NULL,
        `note` VARCHAR(300) NULL,
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_es_wll_lic` (`licenseId`, `id`),
        CONSTRAINT `fk_es_wll_lic` FOREIGN KEY (`licenseId`) REFERENCES `es_mdt_weapon_licenses` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    -- 1.3.0: dispatch calls (911 / 311 / panic / other scripts), the units on each, their notes
    { 'es_mdt_calls', [[CREATE TABLE IF NOT EXISTS `es_mdt_calls` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `kind` VARCHAR(16) NOT NULL DEFAULT '911',
        `priority` TINYINT UNSIGNED NOT NULL DEFAULT 2,
        `status` ENUM('active','closed') NOT NULL DEFAULT 'active',
        `title` VARCHAR(120) NULL,
        `message` VARCHAR(500) NULL,
        `callerCharId` INT UNSIGNED NULL,
        `callerName` VARCHAR(80) NULL,
        `callerPhone` VARCHAR(20) NULL,
        `street` VARCHAR(120) NULL,
        `x` FLOAT NULL, `y` FLOAT NULL, `z` FLOAT NULL,
        `deptId` INT UNSIGNED NULL,
        `outcome` VARCHAR(40) NULL,
        `closeNote` VARCHAR(500) NULL,
        `closedBy` INT UNSIGNED NULL,
        `closedAt` DATETIME NULL,
        `sourceLabel` VARCHAR(40) NULL,
        `everAttached` TINYINT(1) NOT NULL DEFAULT 0,
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_es_call_status` (`status`, `id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]], {
        -- 2.0.3: where a call came from (in the CREATE above too: a new table records this as done without running it)
        { id = '002_source_label', statements = {
            { sql = 'ALTER TABLE `es_mdt_calls` ADD COLUMN `sourceLabel` VARCHAR(40) NULL AFTER `closedAt`', unless = { column = { 'es_mdt_calls', 'sourceLabel' } } },
        } },
        -- 2.0.4: did a unit ever attach (kept after a detach: picks the auto-close outcome); calls closed before outcomes
        -- were required read 'Closed'
        { id = '003_call_close', statements = {
            { sql = 'ALTER TABLE `es_mdt_calls` ADD COLUMN `everAttached` TINYINT(1) NOT NULL DEFAULT 0 AFTER `sourceLabel`', unless = { column = { 'es_mdt_calls', 'everAttached' } } },
            'UPDATE `es_mdt_calls` c SET c.`everAttached` = 1 WHERE EXISTS (SELECT 1 FROM `es_mdt_call_units` u WHERE u.`callId` = c.`id`)',
            "UPDATE `es_mdt_calls` SET `outcome` = 'Closed' WHERE `status` = 'closed' AND (`outcome` IS NULL OR `outcome` = '')",
        } },
    } },
    { 'es_mdt_call_units', [[CREATE TABLE IF NOT EXISTS `es_mdt_call_units` (
        `callId` INT UNSIGNED NOT NULL,
        `charId` INT UNSIGNED NOT NULL,
        `attachedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`callId`, `charId`),
        KEY `idx_es_cu_char` (`charId`),
        CONSTRAINT `fk_es_cu_call` FOREIGN KEY (`callId`) REFERENCES `es_mdt_calls` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_mdt_call_notes', [[CREATE TABLE IF NOT EXISTS `es_mdt_call_notes` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `callId` INT UNSIGNED NOT NULL,
        `byCharId` INT UNSIGNED NULL,
        `note` VARCHAR(500) NOT NULL,
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_es_cn_call` (`callId`, `id`),
        CONSTRAINT `fk_es_cn_call` FOREIGN KEY (`callId`) REFERENCES `es_mdt_calls` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    -- mugshots (data URLs), the profile photo is es_mdt_profiles.mugshotId
    { 'es_mdt_mugshots', [[CREATE TABLE IF NOT EXISTS `es_mdt_mugshots` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `charId` INT UNSIGNED NOT NULL,
        `image` MEDIUMTEXT NOT NULL,
        `origin` VARCHAR(12) NOT NULL DEFAULT 'camera',
        `takenBy` INT UNSIGNED NULL,
        `reportId` INT UNSIGNED NULL,
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_es_mug_char` (`charId`, `id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_mdt_announcements', [[CREATE TABLE IF NOT EXISTS `es_mdt_announcements` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `deptId` INT UNSIGNED NULL,
        `title` VARCHAR(120) NOT NULL,
        `body` TEXT NULL,
        `pinned` TINYINT(1) NOT NULL DEFAULT 0,
        `removed` TINYINT(1) NOT NULL DEFAULT 0,
        `createdBy` INT UNSIGNED NOT NULL,
        `expiresAt` DATETIME NULL,
        `level` VARCHAR(10) NOT NULL DEFAULT 'normal',
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_es_ann_dept` (`deptId`, `removed`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]], {
        -- 2.0.4: priority: normal / important / urgent
        { id = '002_ann_level', statements = {
            { sql = "ALTER TABLE `es_mdt_announcements` ADD COLUMN `level` VARCHAR(10) NOT NULL DEFAULT 'normal' AFTER `expiresAt`", unless = { column = { 'es_mdt_announcements', 'level' } } },
        } },
    } },
    { 'es_mdt_templates', [[CREATE TABLE IF NOT EXISTS `es_mdt_templates` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `deptId` INT UNSIGNED NOT NULL,
        `name` VARCHAR(60) NOT NULL,
        `type` VARCHAR(24) NOT NULL DEFAULT 'incident',
        `title` VARCHAR(120) NULL,
        `body` TEXT NULL,
        `createdBy` INT UNSIGNED NOT NULL,
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_es_tpl_dept` (`deptId`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    -- plate reader hits (bolo / stolen / warrant), for the record and the BOLO's last-seen point
    { 'es_mdt_plate_hits', [[CREATE TABLE IF NOT EXISTS `es_mdt_plate_hits` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `plate` VARCHAR(10) NOT NULL,
        `kinds` VARCHAR(60) NOT NULL,
        `detail` VARCHAR(300) NULL,
        `charId` INT UNSIGNED NULL,
        `x` FLOAT NULL, `y` FLOAT NULL,
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_es_ph_plate` (`plate`, `id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_mdt_profiles', [[CREATE TABLE IF NOT EXISTS `es_mdt_profiles` (
        `charId` INT UNSIGNED NOT NULL,
        `notes` TEXT NULL,
        `flags` JSON NULL,
        `mugshotId` INT UNSIGNED NULL,
        `updatedBy` INT UNSIGNED NULL,
        `updatedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`charId`),
        CONSTRAINT `fk_es_prof_char` FOREIGN KEY (`charId`) REFERENCES `characters` (`charId`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]], {
        { id = '002_mugshot', statements = {
            { sql = 'ALTER TABLE `es_mdt_profiles` ADD COLUMN `mugshotId` INT UNSIGNED NULL', unless = { column = { 'es_mdt_profiles', 'mugshotId' } } },
        } },
    } },
    { 'es_mdt_vehicle_notes', [[CREATE TABLE IF NOT EXISTS `es_mdt_vehicle_notes` (
        `vehicleId` INT UNSIGNED NOT NULL,
        `notes` TEXT NULL,
        `flags` JSON NULL,
        `updatedBy` INT UNSIGNED NULL,
        `updatedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`vehicleId`),
        CONSTRAINT `fk_es_vnote_veh` FOREIGN KEY (`vehicleId`) REFERENCES `vehicles` (`vehicleId`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    -- 1.5.0: cases (investigations) tie reports, evidence, photos, warrants and suspects together
    { 'es_mdt_cases', [[CREATE TABLE IF NOT EXISTS `es_mdt_cases` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `number` VARCHAR(20) NOT NULL,
        `title` VARCHAR(120) NOT NULL,
        `status` ENUM('open','closed','archived') NOT NULL DEFAULT 'open',
        `deptId` INT UNSIGNED NULL,
        `leadCharId` INT UNSIGNED NULL,
        `notes` TEXT NULL,
        `createdBy` INT UNSIGNED NULL,
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `closedAt` DATETIME NULL,
        `archivedAt` DATETIME NULL,
        `updatedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        UNIQUE KEY `uk_es_case_no` (`number`),
        KEY `idx_es_case_status` (`status`, `id`),
        KEY `idx_es_case_lead` (`leadCharId`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_mdt_case_officers', [[CREATE TABLE IF NOT EXISTS `es_mdt_case_officers` (
        `caseId` INT UNSIGNED NOT NULL,
        `charId` INT UNSIGNED NOT NULL,
        `addedBy` INT UNSIGNED NULL,
        `addedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`caseId`, `charId`),
        KEY `idx_es_caseo_char` (`charId`),
        CONSTRAINT `fk_es_caseo_case` FOREIGN KEY (`caseId`) REFERENCES `es_mdt_cases` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_mdt_case_suspects', [[CREATE TABLE IF NOT EXISTS `es_mdt_case_suspects` (
        `caseId` INT UNSIGNED NOT NULL,
        `charId` INT UNSIGNED NOT NULL,
        `note` VARCHAR(200) NULL,
        `addedBy` INT UNSIGNED NULL,
        `addedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`caseId`, `charId`),
        KEY `idx_es_cases_char` (`charId`),
        CONSTRAINT `fk_es_cases_case` FOREIGN KEY (`caseId`) REFERENCES `es_mdt_cases` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_mdt_case_log', [[CREATE TABLE IF NOT EXISTS `es_mdt_case_log` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `caseId` INT UNSIGNED NOT NULL,
        `what` VARCHAR(24) NOT NULL,
        `detail` VARCHAR(255) NULL,
        `byCharId` INT UNSIGNED NULL,
        `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_es_casel_case` (`caseId`, `id`),
        CONSTRAINT `fk_es_casel_case` FOREIGN KEY (`caseId`) REFERENCES `es_mdt_cases` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    -- 1.11.0: optional whip_evidence locker. Our copy of each uploaded entry (their snapshot as JSON), photo copies
    -- (their photos expire outside a case locker) and which entries are attached to which report. Empty when unused.
    { 'es_mdt_wev_entries', [[CREATE TABLE IF NOT EXISTS `es_mdt_wev_entries` (
        `caseId` INT UNSIGNED NOT NULL,
        `ref` VARCHAR(80) NOT NULL,
        `kind` VARCHAR(20) NOT NULL DEFAULT '',
        `data` LONGTEXT NULL,
        `gone` TINYINT(1) NOT NULL DEFAULT 0,
        `uploadedBy` INT UNSIGNED NULL,
        `uploadedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `updatedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`caseId`, `ref`),
        KEY `idx_es_wev_ref` (`ref`),
        CONSTRAINT `fk_es_wev_case` FOREIGN KEY (`caseId`) REFERENCES `es_mdt_cases` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_mdt_wev_photos', [[CREATE TABLE IF NOT EXISTS `es_mdt_wev_photos` (
        `photoId` VARCHAR(64) NOT NULL,
        `image` MEDIUMTEXT NOT NULL,
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`photoId`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_mdt_wev_report', [[CREATE TABLE IF NOT EXISTS `es_mdt_wev_report` (
        `reportId` INT UNSIGNED NOT NULL,
        `caseId` INT UNSIGNED NOT NULL,
        `ref` VARCHAR(80) NOT NULL,
        `addedBy` INT UNSIGNED NULL,
        `addedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`reportId`, `ref`),
        KEY `idx_es_wevr_entry` (`caseId`, `ref`),
        CONSTRAINT `fk_es_wevr_entry` FOREIGN KEY (`caseId`, `ref`) REFERENCES `es_mdt_wev_entries` (`caseId`, `ref`) ON DELETE CASCADE,
        CONSTRAINT `fk_es_wevr_rep` FOREIGN KEY (`reportId`) REFERENCES `es_mdt_reports` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
}

function Tables.ensure()
    for _, t in ipairs(DEFS) do
        local ok, why = EsSchema.ensure(t[1], t[2], t[3] or {})
        if not ok then return false, ('%s: %s'):format(t[1], tostring(why)) end
    end
    return true
end

-- for the schema tests (EsSchema, server/schema.lua, checks every table against its CREATE at each start)
Tables.DEFS = DEFS

--- The starter penal code, once (an empty table only)
function Tables.seedPenal()
    local row = MySQL.single.await('SELECT COUNT(*) AS `n` FROM `es_penal_code`')
    if not row or (tonumber(row.n) or 0) > 0 then return end
    for _, p in ipairs(Config.PenalSeed) do
        MySQL.insert.await('INSERT IGNORE INTO `es_penal_code` (`code`,`title`,`category`,`fine`,`months`) VALUES (?,?,?,?,?)',
            { p[1], p[2], p[3], p[4], p[5] })
    end
end
