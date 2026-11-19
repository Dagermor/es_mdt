-- es_jobs: our tables (whip_core EnsureTable: made once, migrations recorded).
ESJ = ESJ or {}

local TABLES = {
    { 'es_jobs_businesses', [[CREATE TABLE IF NOT EXISTS `es_jobs_businesses` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `jobId` INT UNSIGNED NOT NULL,
        `name` VARCHAR(48) NOT NULL,
        `short` VARCHAR(12) NOT NULL,
        `color` VARCHAR(7) NOT NULL DEFAULT '#4f8ff7',
        `blurb` VARCHAR(200) NULL,
        `logo` MEDIUMTEXT NULL,
        `logoVer` INT UNSIGNED NOT NULL DEFAULT 0,
        `ownerCharId` INT UNSIGNED NULL,
        `createdBy` INT UNSIGNED NULL,
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        UNIQUE KEY `uq_es_jobs_biz_job` (`jobId`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_jobs_stations', [[CREATE TABLE IF NOT EXISTS `es_jobs_stations` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `name` VARCHAR(48) NOT NULL,
        `jobs` TEXT NOT NULL,
        `blip` TEXT NULL,
        `spots` LONGTEXT NOT NULL,
        `rev` INT UNSIGNED NOT NULL DEFAULT 1,
        `updatedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        `updatedBy` INT UNSIGNED NULL,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_jobs_station_history', [[CREATE TABLE IF NOT EXISTS `es_jobs_station_history` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `stationId` INT UNSIGNED NOT NULL,
        `name` VARCHAR(48) NOT NULL,
        `snapshot` LONGTEXT NOT NULL,
        `action` VARCHAR(40) NOT NULL,
        `byCharId` INT UNSIGNED NULL,
        `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_es_jobs_hist_station` (`stationId`, `id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_jobs_pay', [[CREATE TABLE IF NOT EXISTS `es_jobs_pay` (
        `roleId` INT UNSIGNED NOT NULL,
        `jobId` INT UNSIGNED NOT NULL,
        `amount` INT UNSIGNED NOT NULL,
        PRIMARY KEY (`roleId`),
        KEY `idx_es_jobs_pay_job` (`jobId`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_jobs_ledger', [[CREATE TABLE IF NOT EXISTS `es_jobs_ledger` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `jobId` INT UNSIGNED NOT NULL,
        `kind` VARCHAR(16) NOT NULL,
        `amount` INT NOT NULL,
        `charId` INT UNSIGNED NULL,
        `note` VARCHAR(120) NULL,
        `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_es_jobs_ledger_job` (`jobId`, `id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_jobs_lockers', [[CREATE TABLE IF NOT EXISTS `es_jobs_lockers` (
        `charId` INT UNSIGNED NOT NULL,
        `containerId` INT UNSIGNED NOT NULL,
        PRIMARY KEY (`charId`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
}

function ESJ.ensureTables()
    for _, t in ipairs(TABLES) do
        local ok, why = Whip.core:EnsureTable(t[1], t[2], {})
        if not ok then return false, ('%s: %s'):format(t[1], tostring(why)) end
    end
    return true
end
