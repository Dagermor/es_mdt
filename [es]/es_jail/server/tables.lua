-- es_jail tables (created / migrated with WHIP's EnsureTable on every start)
Tables = {}

local DEFS = {
    -- one row per character who has been jailed; status serving | escaped | released
    { 'es_jail_inmates', [[CREATE TABLE IF NOT EXISTS `es_jail_inmates` (
        `charId` INT UNSIGNED NOT NULL,
        `status` VARCHAR(10) NOT NULL DEFAULT 'serving',
        `months` INT UNSIGNED NOT NULL DEFAULT 0,
        `total` INT UNSIGNED NOT NULL DEFAULT 0,
        `remaining` INT UNSIGNED NOT NULL DEFAULT 0,
        `cut` INT UNSIGNED NOT NULL DEFAULT 0,
        `jobs` INT UNSIGNED NOT NULL DEFAULT 0,
        `reportId` INT UNSIGNED NULL,
        `reason` VARCHAR(255) NULL,
        `jailedBy` INT UNSIGNED NULL,
        `items` LONGTEXT NULL,
        `pendingOut` TINYINT(1) NOT NULL DEFAULT 0,
        `jailedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `releasedAt` TIMESTAMP NULL,
        `escapedAt` TIMESTAMP NULL,
        `updatedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`charId`),
        KEY `idx_es_jail_status` (`status`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { 'es_jail_log', [[CREATE TABLE IF NOT EXISTS `es_jail_log` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `charId` INT UNSIGNED NOT NULL,
        `what` VARCHAR(20) NOT NULL,
        `detail` VARCHAR(255) NULL,
        `byCharId` INT UNSIGNED NULL,
        `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_es_jail_log_char` (`charId`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
}

function Tables.ensure()
    for _, t in ipairs(DEFS) do
        local ok, why = Whip.core:EnsureTable(t[1], t[2], t[3] or {})
        if not ok then return false, ('%s: %s'):format(t[1], tostring(why)) end
    end
    return true
end
