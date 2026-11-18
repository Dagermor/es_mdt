-- es_mdt 2.0.0: the jail bridge. The MDT and the court talk to ONE jail interface; behind it is es_jail, any jail
-- script that registers itself (exports.es_mdt:RegisterJailProvider), a jail script reached through its exports
-- (Config.Jail.custom, no code needed), or nothing: then a sentence is still recorded in the MDT and announced.
-- Developers: see README.md, "Jail integration for developers".
EsJail = {}

local SELF = GetCurrentResourceName()
local Registered = {}   -- [resource] = provider table (functions from that resource)
local Order = {}        -- registration order, newest last

local function cfg()
    local mdt = ESPART('mdt')
    return (mdt and mdt.Config and mdt.Config.Jail) or {}
end
local function started(res) return type(res) == 'string' and GetResourceState(res) == 'started' end
local function wc() return exports.whip_core end

--- The server id of a character that is online, or nil
local function sourceOf(charId)
    charId = tonumber(charId)
    if not charId then return nil end
    for _, s in ipairs(GetPlayers()) do
        local ok, cid = pcall(function() return wc():GetCharId(tonumber(s)) end)
        if ok and tonumber(cid) == charId then return tonumber(s) end
    end
    return nil
end
EsJail.sourceOf = sourceOf

-- ---------------------------------------------------------------- built-in providers
local ES_JAIL = {
    label = 'es_jail',
    available = function() return started('es_jail') end,
    jail = function(info) return exports.es_jail:Jail(info.charId, info.months, info.reportId, info.byCharId) end,
    release = function(charId, info) return exports.es_jail:Release(charId, info and info.byCharId, info and info.reason) end,
    isJailed = function(charId) return exports.es_jail:IsJailed(charId) end,
    inmates = function(recentDays) return exports.es_jail:GetInmates(recentDays) end,
}

--- Config.Jail.custom: a jail script reached through its own exports, described in the config
local function customProvider()
    local c = cfg().custom
    if type(c) ~= 'table' or type(c.resource) ~= 'string' then return nil end
    local function args(spec, info)
        local per = tonumber(c.minutesPerMonth) or 1
        local unit = c.timeUnit or 'months'
        local time = info.months
        if unit == 'minutes' then time = info.months * per
        elseif unit == 'seconds' then time = info.months * per * 60 end
        local v = {
            target = (c.target == 'charId') and info.charId or info.source, charId = info.charId, source = info.source,
            time = time, months = info.months, minutes = info.months * per, seconds = info.months * per * 60,
            reason = info.reason, reportId = info.reportId, officerCharId = info.byCharId, officerSource = info.bySource,
        }
        local out = {}
        for i, k in ipairs(spec.args or { 'target' }) do out[i] = v[k] end
        return out, #(spec.args or { 'target' })
    end
    local function call(spec, info)
        if type(spec) ~= 'table' or type(spec.export) ~= 'string' then return false, 'not set up in Config.Jail.custom' end
        if c.target ~= 'charId' and not info.source then return false, 'They must be in the city for ' .. c.resource end
        local a, n = args(spec, info)
        local e = exports[c.resource]
        local ok, r1, r2 = pcall(function() return e[spec.export](e, table.unpack(a, 1, n)) end)
        if not ok then return false, tostring(r1) end
        if r1 == false then return false, r2 end
        return true
    end
    return {
        label = c.label or c.resource,
        available = function() return started(c.resource) end,
        jail = function(info) return call(c.jail, info) end,
        release = c.release and function(charId, info)
            info = info or {}
            info.charId, info.source, info.months = charId, info.source or sourceOf(charId), 0
            return call(c.release, info)
        end or nil,
        isJailed = c.isJailed and function(charId)
            local info = { charId = charId, source = sourceOf(charId), months = 0 }
            if c.target ~= 'charId' and not info.source then return nil end
            local a, n = args(c.isJailed, info)
            local e = exports[c.resource]
            local ok, r = pcall(function() return e[c.isJailed.export](e, table.unpack(a, 1, n)) end)
            return ok and r and true or false
        end or nil,
    }
end

--- The provider in use now (table) and its name, or nil
--- real minutes per sentence month for sentences only the MDT keeps (no jail script, or one with no inmate list)
local function recMin() return math.max(0.01, tonumber(cfg().recordMinutesPerMonth) or 1) end

function EsJail.provider()
    local want = cfg().provider or 'auto'
    if want == 'none' then return nil end
    if want == 'es_jail' then return ES_JAIL.available() and ES_JAIL or nil, 'es_jail' end
    if want == 'custom' then
        local p = customProvider()
        return p and p.available() and p or nil, p and p.label
    end
    if want ~= 'auto' then   -- a registered provider by resource name
        local p = Registered[want]
        return (p and started(want)) and p or nil, want
    end
    for i = #Order, 1, -1 do
        local res = Order[i]
        if Registered[res] and started(res) then return Registered[res], res end
    end
    if ES_JAIL.available() then return ES_JAIL, 'es_jail' end
    local p = customProvider()
    if p and p.available() then return p, p.label end
    return nil
end

-- ---------------------------------------------------------------- the MDT's own record (every sentence, any jail)
local function ensureTable()
    return EsSchema.ensure('es_mdt_jail_sentences', [[CREATE TABLE IF NOT EXISTS `es_mdt_jail_sentences` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `charId` INT UNSIGNED NOT NULL,
        `months` INT UNSIGNED NOT NULL DEFAULT 0,
        `origin` VARCHAR(16) NOT NULL DEFAULT 'mdt',
        `reportId` INT UNSIGNED NULL,
        `courtCase` VARCHAR(32) NULL,
        `reason` VARCHAR(255) NULL,
        `provider` VARCHAR(64) NULL,
        `status` VARCHAR(12) NOT NULL DEFAULT 'sent',
        `note` VARCHAR(255) NULL,
        `byCharId` INT UNSIGNED NULL,
        `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `endedAt` TIMESTAMP NULL,
        PRIMARY KEY (`id`),
        KEY `idx_es_mdt_jail_char` (`charId`, `status`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]], {})
end
Whip.register(function()
    local ok, why = ensureTable()
    if not ok then Whip.startProblem('jail sentences table: %s', tostring(why)) end
end)

local function record(info, provider, status, note)
    return MySQL.insert.await([[INSERT INTO `es_mdt_jail_sentences` (`charId`,`months`,`origin`,`reportId`,`courtCase`,`reason`,`provider`,`status`,`note`,`byCharId`)
        VALUES (?,?,?,?,?,?,?,?,?,?)]], { info.charId, info.months or 0, info.origin or 'mdt', info.reportId, info.courtCase,
        info.reason and tostring(info.reason):sub(1, 255) or nil, provider, status, note and tostring(note):sub(1, 255) or nil, info.byCharId })
end
local function closeOpen(charId, status, note)
    MySQL.update.await([[UPDATE `es_mdt_jail_sentences` SET `status` = ?, `note` = COALESCE(?, `note`), `endedAt` = CURRENT_TIMESTAMP
        WHERE `charId` = ? AND `status` IN ('sent','recorded','escaped')]], { status, note, charId })
end

-- ---------------------------------------------------------------- what the MDT and the court call
--- info: { charId, months, reason?, charges?, reportId?, courtCase?, origin = 'mdt'|'court', byCharId?, bySource? }
--- -> { ok = jailed by a jail script, provider = name|nil, why = text|nil, recorded = true }
function EsJail.send(info)
    info.charId, info.months = tonumber(info.charId), math.max(0, math.floor(tonumber(info.months) or 0))
    info.source = info.source or sourceOf(info.charId)
    local p, name = EsJail.provider()
    local ok, why = false, nil
    if p then
        local okc, a, b = pcall(p.jail, info)
        if not okc then ok, why = false, tostring(a) else ok, why = a ~= false and a ~= nil, b end
        if a == nil and okc then ok = true end   -- a provider that returns nothing took them
    else
        why = 'No jail script is connected'
    end
    record(info, name, p and (ok and 'sent' or 'not_sent') or 'recorded', not ok and why or nil)   -- 'recorded': no jail script, the MDT keeps the time
    local result = { ok = ok, provider = name, why = why, recorded = true }
    TriggerEvent('es_mdt:jail:sent', info, result)
    return result
end

--- -> ok, why
function EsJail.release(charId, byCharId, reason)
    charId = tonumber(charId)
    local p = EsJail.provider()
    local ok, why = true, nil
    if p and p.release then
        local okc, a, b = pcall(p.release, charId, { byCharId = byCharId, reason = reason })
        if not okc then return false, tostring(a) end
        ok, why = a ~= false, b
    elseif p then
        return false, 'This jail script cannot release from the MDT'
    end
    if ok then
        closeOpen(charId, 'released', reason)
        TriggerEvent('es_mdt:jail:released', charId, { byCharId = byCharId, reason = reason, origin = 'mdt' })
    end
    return ok, why
end

--- -> jailed (bool), secondsLeft|nil. Without a provider that can say: the MDT's own record.
function EsJail.isJailed(charId)
    charId = tonumber(charId)
    if not charId then return false end
    local p = EsJail.provider()
    if p and p.isJailed then
        local ok, a, b = pcall(p.isJailed, charId)
        if ok and a ~= nil then return a and true or false, b end
    end
    local left = MySQL.scalar.await([[SELECT MAX(IF(`status` = 'escaped', 0, GREATEST(0, `months` * ? * 60 - TIMESTAMPDIFF(SECOND, `at`, NOW()))))
        FROM `es_mdt_jail_sentences` WHERE `charId` = ? AND (`status` = 'escaped'
        OR (`status` IN ('sent','recorded') AND `at` + INTERVAL (`months` * ?) MINUTE > NOW()))]], { recMin(), charId, recMin() })
    if left == nil then return false, nil end
    return true, tonumber(left)
end

--- Rows for the MDT's Jail tab (es_jail's fields; the MDT's own record when the jail script has no list)
function EsJail.inmates(recentDays)
    local p, name = EsJail.provider()
    if p and p.inmates then
        local ok, rows = pcall(p.inmates, recentDays)
        if ok and type(rows) == 'table' then return rows, name, true end
    end
    -- the MDT keeps the time itself here: Config.Jail.recordMinutesPerMonth real minutes per month (es_jail's fields)
    local m = recMin()
    local rows = MySQL.query.await([[SELECT * FROM (SELECT `charId`, `months`, `reportId`, `reason`, `byCharId` AS `jailedBy`, UNIX_TIMESTAMP(`at`) AS `jailedAt`,
            CASE WHEN `status` = 'escaped' THEN 'escaped'
                 WHEN `status` IN ('sent','recorded') AND `at` + INTERVAL (`months` * ?) MINUTE > NOW() THEN 'serving'
                 ELSE 'released' END AS `status`,
            `months` * ? * 60 AS `total`,
            GREATEST(0, `months` * ? * 60 - TIMESTAMPDIFF(SECOND, `at`, IFNULL(`endedAt`, NOW()))) AS `remaining`,
            IF(`status` = 'escaped', UNIX_TIMESTAMP(`endedAt`), NULL) AS `escapedAt`,
            UNIX_TIMESTAMP(IF(`status` IN ('sent','recorded'), `at` + INTERVAL (`months` * ?) MINUTE, `endedAt`)) AS `releasedAt`
        FROM `es_mdt_jail_sentences` WHERE `status` <> 'not_sent') x
        WHERE x.`status` <> 'released' OR x.`releasedAt` > UNIX_TIMESTAMP(NOW() - INTERVAL ? DAY)
        ORDER BY FIELD(x.`status`,'escaped','serving','released'), x.`jailedAt` DESC LIMIT 200]], { m, m, m, m, tonumber(recentDays) or 3 }) or {}
    return rows, name, false
end

-- ---------------------------------------------------------------- for jail scripts
--- exports.es_mdt:RegisterJailProvider({ label, jail = fn(info), release = fn(charId, info), isJailed = fn(charId),
---   inmates = fn(recentDays) }) -> true | false, why. Only `jail` is required. Gone when that resource stops.
exports('RegisterJailProvider', function(def)
    local res = GetInvokingResource()
    if not res or res == SELF then return false, 'Call it from your jail resource' end
    if type(def) ~= 'table' or def.jail == nil then return false, 'A provider needs at least jail = function(info)' end
    Registered[res] = { label = def.label or res, jail = def.jail, release = def.release, isJailed = def.isJailed, inmates = def.inmates,
        available = function() return started(res) end }
    for i = #Order, 1, -1 do if Order[i] == res then table.remove(Order, i) end end
    Order[#Order + 1] = res
    print(('[es_mdt] jail provider registered: %s'):format(res))
    return true
end)
exports('UnregisterJailProvider', function()
    local res = GetInvokingResource()
    if res then Registered[res] = nil end
    return true
end)
exports('GetJailProvider', function() local _, name = EsJail.provider() return name end)
AddEventHandler('onResourceStop', function(res) if Registered[res] then Registered[res] = nil print(('[es_mdt] jail provider gone: %s'):format(res)) end end)

--- The jail let someone out (time served, a judge, an admin): the MDT's record closes. -> true
exports('ReportJailRelease', function(charId, info)
    charId = tonumber(charId)
    if not charId then return false end
    info = type(info) == 'table' and info or {}
    closeOpen(charId, 'released', info.reason)
    pcall(function() exports[SELF]:ServeEscapeWarrants(charId, tonumber(info.byCharId)) end)
    TriggerEvent('es_mdt:jail:released', charId, { reason = info.reason, byCharId = info.byCharId, origin = GetInvokingResource() })
    return true
end)

--- Someone escaped: the MDT's record says so, a warrant (and a BOLO) go out and dispatch hears about it.
--- info: { reason?, warrant = true, warrantDays = 7, bolo = true, alert = true, coords = vector3?, byCharId? } -> warrantId|nil
exports('ReportJailEscape', function(charId, info)
    charId = tonumber(charId)
    if not charId then return false end
    info = type(info) == 'table' and info or {}
    MySQL.update.await("UPDATE `es_mdt_jail_sentences` SET `status` = 'escaped', `endedAt` = CURRENT_TIMESTAMP WHERE `charId` = ? AND `status` = 'sent'", { charId })
    local wid = nil
    if info.warrant ~= false then
        local ok, res = pcall(function()
            return exports[SELF]:EscapeWarrant(charId, info.reason or 'Escaped from jail', tonumber(info.warrantDays) or 7, tonumber(info.byCharId), info.bolo ~= false)
        end)
        if ok then wid = res end
    end
    if info.alert ~= false then
        pcall(function()
            local c = info.coords
            exports[SELF]:AddCall({ kind = 'alert', priority = 1, title = info.title or 'Prison break', message = info.reason or 'An inmate escaped',
                street = info.street, coords = c and { x = c.x, y = c.y, z = c.z } or nil })
        end)
    end
    TriggerEvent('es_mdt:jail:escaped', charId, { reason = info.reason, warrantId = wid, origin = GetInvokingResource() })
    return wid
end)

--- The same three as plain server events, for scripts that prefer events (server side only)
AddEventHandler('es_mdt:jail:reportRelease', function(charId, info) if GetInvokingResource() then exports[SELF]:ReportJailRelease(charId, info) end end)
AddEventHandler('es_mdt:jail:reportEscape', function(charId, info) if GetInvokingResource() then exports[SELF]:ReportJailEscape(charId, info) end end)

-- For the parts of this resource (the court reads it through EsJail too) and other resources
exports('JailSend', function(info) return EsJail.send(type(info) == 'table' and info or {}) end)
exports('JailRelease', function(charId, byCharId, reason) return EsJail.release(charId, byCharId, reason) end)
exports('JailIsJailed', function(charId) return EsJail.isJailed(charId) end)
