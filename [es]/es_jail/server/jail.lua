-- es_jail jail: sentences (from the MDT's Process arrest, or /jail), the clock (counts while the inmate is on),
-- belongings boxed up and handed back at the gate, prison jobs that cut time, escapes (dispatch + warrant in es_mdt),
-- and the exports es_mdt reads.

local WC = exports.whip_core
local J, PR, JB, ES = Config.Jail, Config.Prison, Config.Jobs, Config.Escape

local Serving = {}   -- [charId] = { source, remaining, total, cut, jobs, out, grace, job = { key, i }, dirty }
JL.Serving = Serving

local function now() return os.time() end
local function spm() return math.max(1, tonumber(J.secondsPerMonth) or 60) end
local function fmt(sec)
    sec = math.max(0, math.floor(sec or 0))
    local h, m, s = sec // 3600, (sec % 3600) // 60, sec % 60
    if h > 0 then return ('%dh %02dm'):format(h, m) end
    return ('%d:%02d'):format(m, s)
end
JL.fmt = fmt

local function inside(p)
    if not p then return true end
    if p.z < (PR.zoneMinZ or -1000) or p.z > (PR.zoneMaxZ or 3000) then return false end
    local poly, x, y, inn = PR.zone, p.x, p.y, false
    local j = #poly
    for i = 1, #poly do
        local xi, yi, xj, yj = poly[i][1], poly[i][2], poly[j][1], poly[j][2]
        if ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi) then inn = not inn end
        j = i
    end
    return inn
end
JL.insidePrison = inside

local function arriveSpot() local a = PR.arrive return a[math.random(#a)] end

local function hud(cid)
    local s = Serving[cid]
    if not s or not s.source then return end
    local job = s.job and JB[s.job.key]
    TriggerClientEvent('es_jail:state', s.source, {
        remaining = s.remaining, total = s.total, cut = s.cut, jobs = s.jobs,
        job = job and { key = s.job.key, label = job.label, verb = job.verb, spot = job.spots[s.job.i], seconds = job.seconds, cut = job.cut } or false,
    })
end

local function save(cid)
    local s = Serving[cid]
    if not s then return end
    s.dirty = false
    MySQL.update('UPDATE `es_jail_inmates` SET `remaining` = ?, `cut` = ?, `jobs` = ? WHERE `charId` = ? AND `status` = \'serving\'',
        { math.max(0, math.floor(s.remaining)), s.cut, s.jobs, cid })
end

-- ---------------------------------------------------------------- belongings
local KEEP = {}
for _, k in ipairs(J.keep or {}) do KEEP[k] = true end

local function readItems(cid)
    local r = MySQL.single.await('SELECT `items` FROM `es_jail_inmates` WHERE `charId` = ?', { cid })
    local ok, list = pcall(json.decode, r and r.items or '[]')
    return ok and type(list) == 'table' and list or {}
end

local function confiscate(source, cid)
    if J.confiscate == false then return 0 end
    local list = readItems(cid)
    local n = 0
    for _, sub in ipairs({ 'player', 'accessory' }) do
        local store = WC:StoreRead({ kind = 'player', id = source, sub = sub })
        if store and store.items then
            for slot, it in pairs(store.items) do
                if it and it.item and not KEEP[it.item] then
                    local took = WC:StoreTake({ kind = 'player', id = source, sub = sub, slot = tonumber(slot) }, nil, 'jailed: belongings boxed up')
                    if took then
                        list[#list + 1] = { item = it.item, amount = it.amount or 1, metadata = it.metadata }
                        n = n + 1
                        -- written as we go: a crash halfway never loses what was already taken
                        MySQL.update.await('UPDATE `es_jail_inmates` SET `items` = ? WHERE `charId` = ?', { json.encode(list), cid })
                    end
                end
            end
        end
    end
    return n
end

local function giveBack(source, cid)
    local list = readItems(cid)
    if #list == 0 then return 0 end
    MySQL.update.await('UPDATE `es_jail_inmates` SET `items` = NULL WHERE `charId` = ?', { cid })
    local back, left = 0, {}
    for _, it in ipairs(list) do
        local where, why = false, 'they left'
        if WC:GetCharId(source) == cid then where, why = WC:AddItem(source, it.item, it.amount or 1, type(it.metadata) == 'table' and next(it.metadata) and it.metadata or nil,
            { reason = 'jail: belongings returned' }) end
        if where then back = back + 1
        else
            left[#left + 1] = it
            print(('[es_jail] could not return %sx %s to char %d: %s'):format(it.amount or 1, it.item, cid, tostring(why)))
        end
    end
    if #left > 0 then MySQL.update.await('UPDATE `es_jail_inmates` SET `items` = ? WHERE `charId` = ?', { json.encode(left), cid }) end
    return back
end

-- ---------------------------------------------------------------- in / out
local function teleport(source, v4, why)
    TriggerClientEvent('es_jail:teleport', source, { x = v4.x, y = v4.y, z = v4.z, w = v4.w or 0.0 }, why)
end

--- Start (or resume) serving for an online inmate
local function begin(source, cid, row, fresh)
    JL.uncuffQuiet(source)
    Serving[cid] = { source = source, remaining = tonumber(row.remaining) or 0, total = tonumber(row.total) or 0,
        cut = tonumber(row.cut) or 0, jobs = tonumber(row.jobs) or 0, grace = now() + 30 }
    local at = JL.pedCoords(source)
    if fresh or not inside(at) then teleport(source, arriveSpot(), 'in') end
    if fresh then
        local n = confiscate(source, cid)
        JL.notify(source, ('You were sentenced to %s at %s.%s'):format(fmt(row.remaining), PR.name,
            n > 0 and (' Your belongings (%d) are boxed up until you get out.'):format(n) or ''), 'warning', 10000)
    else
        JL.notify(source, ('%s left on your sentence'):format(fmt(row.remaining)), 'info', 6000)
    end
    hud(cid)
end

local function finishOut(source, cid, why)
    teleport(source, PR.release, 'out')
    local n = giveBack(source, cid)
    if Config.Breakout.resetOnRelease ~= false then JL.resetEscapes(source) end
    TriggerClientEvent('es_jail:state', source, false)
    MySQL.update('UPDATE `es_jail_inmates` SET `pendingOut` = 0 WHERE `charId` = ?', { cid })
    JL.notify(source, (why == 'served' and 'You served your time. You are free to go.' or 'You have been released.') ..
        (n > 0 and ' Your belongings were handed back.' or ''), 'success', 8000)
end

local function release(cid, why, byCharId)
    cid = tonumber(cid)
    local row = cid and MySQL.single.await('SELECT `status` FROM `es_jail_inmates` WHERE `charId` = ?', { cid })
    if not row or row.status == 'released' then return false, 'They are not in jail' end
    if row.status == 'escaped' and GetResourceState('es_mdt') == 'started' then
        pcall(function() exports.es_mdt:ServeEscapeWarrants(cid, byCharId) end)
    end
    local s = Serving[cid]
    Serving[cid] = nil
    if s and s.jobTag then WC:ReleaseTag(s.jobTag) s.jobTag = nil end   -- 1.0.4: a job bar (and its prop) ends with the sentence
    MySQL.update.await("UPDATE `es_jail_inmates` SET `status` = 'released', `remaining` = 0, `releasedAt` = NOW(), `pendingOut` = 1 WHERE `charId` = ?", { cid })
    JL.log(cid, 'released', why, byCharId)
    local src = s and s.source or JL.onlineByChar()[cid]
    if src then finishOut(src, cid, why) end
    TriggerEvent('es_jail:changed', cid, 'released')
    return true
end
JL.release = release

local function escape(cid)
    local s = Serving[cid]
    if not s then return end
    Serving[cid] = nil
    if s.jobTag then WC:ReleaseTag(s.jobTag) s.jobTag = nil end
    MySQL.update.await("UPDATE `es_jail_inmates` SET `status` = 'escaped', `remaining` = ?, `escapedAt` = NOW() WHERE `charId` = ?", { math.max(0, math.floor(s.remaining)), cid })
    local name = JL.nameOf(cid)
    JL.log(cid, 'escaped', ('%s left'):format(fmt(s.remaining)))
    JL.activity(s.source, 'escape', ('char %d, %s left'):format(cid, fmt(s.remaining)))
    TriggerClientEvent('es_jail:state', s.source, false)
    JL.notify(s.source, 'You broke out of prison. Every cop in the city knows.', 'error', 8000)
    TriggerEvent('es_jail:changed', cid, 'escaped')
    if GetResourceState('es_mdt') ~= 'started' then return end
    local at = JL.pedCoords(s.source) or PR.center
    if ES.dispatch ~= false then
        pcall(function()
            exports.es_mdt:AddCall({ kind = 'alert', priority = 1, title = ('Prison break: %s'):format(name),
                message = ('%s escaped from %s with %s left to serve.'):format(name, PR.name, fmt(s.remaining)),
                street = PR.name, coords = { x = at.x, y = at.y, z = at.z } })
        end)
    end
    if ES.warrant ~= false then
        local by = MySQL.scalar.await('SELECT `jailedBy` FROM `es_jail_inmates` WHERE `charId` = ?', { cid })
        -- 1.0.4: and a person BOLO with it (es_mdt 1.5.6 adds the photo): where they went over the fence
        local dx, dy = at.x - PR.center.x, at.y - PR.center.y
        local dirs = { 'north', 'north-east', 'east', 'south-east', 'south', 'south-west', 'west', 'north-west' }
        local ang = (math.deg(math.atan(dx, dy)) + 360.0) % 360.0      -- 0 = north, clockwise
        local side = dirs[math.floor((ang + 22.5) / 45.0) % 8 + 1]
        local bolo = { title = ('Escaped inmate: %s'):format(name),
            description = ('Escaped %s with %s left to serve. Last seen going over the %s fence (%d, %d).'):format(PR.name, fmt(s.remaining), side, math.floor(at.x), math.floor(at.y)),
            coords = { x = at.x, y = at.y } }
        local ok, res, why = pcall(function() return exports.es_mdt:EscapeWarrant(cid, ('Escaped from %s with %s left to serve'):format(PR.name, fmt(s.remaining)), ES.warrantDays or 7, by, bolo) end)
        if not ok or not res then print(('[es_jail] no escape warrant for char %d: %s'):format(cid, tostring(ok and why or res))) end
    end
end

--- Jail a character for `months` (online now, or the moment they log in)
local function jail(cid, months, reportId, byCharId, reason)
    cid, months = tonumber(cid), tonumber(months)
    if not cid then return false, 'Who?' end
    if not months or months < (J.minMonths or 1) then return false, 'No jail time' end
    months = math.min(math.floor(months), J.maxMonths or 300)
    local add = months * spm()
    local row = MySQL.single.await('SELECT `status`,`remaining`,`total`,`months` FROM `es_jail_inmates` WHERE `charId` = ?', { cid })
    local s = Serving[cid]
    local fresh = true
    if row and row.status == 'serving' then
        fresh = false
        local rem = (s and s.remaining or tonumber(row.remaining) or 0) + add
        MySQL.update.await('UPDATE `es_jail_inmates` SET `months` = `months` + ?, `total` = `total` + ?, `remaining` = ?, `reportId` = COALESCE(?, `reportId`) WHERE `charId` = ?',
            { months, add, rem, reportId, cid })
        if s then s.remaining, s.total = rem, s.total + add hud(cid) JL.notify(s.source, ('%s added to your sentence'):format(fmt(add)), 'warning', 7000) end
        JL.log(cid, 'jailed', ('+%d months (report %s)'):format(months, tostring(reportId or '-')), byCharId)
        TriggerEvent('es_jail:changed', cid, 'serving')
        return true, { seconds = rem, added = add, online = s ~= nil }
    end
    if row and row.status == 'escaped' and GetResourceState('es_mdt') == 'started' then
        pcall(function() exports.es_mdt:ServeEscapeWarrants(cid, byCharId) end)
    end
    local extra = (row and row.status == 'escaped') and ((tonumber(row.remaining) or 0) + (ES.addMonths or 0) * spm()) or 0
    local total = add + extra
    MySQL.query.await([[INSERT INTO `es_jail_inmates` (`charId`,`status`,`months`,`total`,`remaining`,`cut`,`jobs`,`reportId`,`reason`,`jailedBy`,`jailedAt`,`releasedAt`,`escapedAt`,`pendingOut`)
        VALUES (?, 'serving', ?, ?, ?, 0, 0, ?, ?, ?, NOW(), NULL, NULL, 0)
        ON DUPLICATE KEY UPDATE `status` = 'serving', `months` = VALUES(`months`), `total` = VALUES(`total`), `remaining` = VALUES(`remaining`), `cut` = 0, `jobs` = 0,
        `reportId` = VALUES(`reportId`), `reason` = VALUES(`reason`), `jailedBy` = VALUES(`jailedBy`), `jailedAt` = NOW(), `releasedAt` = NULL, `escapedAt` = NULL, `pendingOut` = 0]],
        { cid, months, total, total, reportId, reason and JL.str(reason, 255) or nil, byCharId })
    JL.log(cid, 'jailed', ('%d months%s (report %s)'):format(months, extra > 0 and (' + %s from the escape'):format(fmt(extra)) or '', tostring(reportId or '-')), byCharId)
    local src = JL.onlineByChar()[cid]
    if src then
        CreateThread(function() begin(src, cid, { remaining = total, total = total, cut = 0, jobs = 0 }, true) end)
    end
    TriggerEvent('es_jail:changed', cid, 'serving')
    return true, { seconds = total, online = src ~= nil }
end
JL.jail = jail

-- ---------------------------------------------------------------- the clock and the walls
CreateThread(function()
    local tick = math.max(2, J.tickSeconds or 10)
    local sinceSave = 0
    while true do
        Wait(tick * 1000)
        sinceSave = sinceSave + tick
        for cid, s in pairs(Serving) do
            if not s.source or not GetPlayerName(s.source) or WC:GetCharId(s.source) ~= cid then
                save(cid) Serving[cid] = nil
            else
                s.remaining = s.remaining - tick
                s.dirty = true
                if s.remaining <= 0 then
                    CreateThread(function() release(cid, 'served') end)
                else
                    hud(cid)
                end
            end
        end
        if sinceSave >= (J.saveSeconds or 30) then
            sinceSave = 0
            for cid, s in pairs(Serving) do if s.dirty then save(cid) end end
        end
    end
end)

-- 1.0.1: the fence. Checked every second; outside (or above / below it) for Config.Prison.escapeGrace seconds in a
-- row is an escape. Downed inmates and the first 30 s after a teleport never count.
CreateThread(function()
    while true do
        Wait(1000)
        local t = now()
        for cid, s in pairs(Serving) do
            if s.source and GetPlayerName(s.source) then
                if t <= (s.grace or 0) or WC:IsPlayerDead(s.source) or inside(JL.pedCoords(s.source)) then
                    s.outSince = nil
                else
                    s.outSince = s.outSince or t
                    if t - s.outSince >= (PR.escapeGrace or 5) and not s.escaping then
                        s.escaping = true
                        CreateThread(function() escape(cid) end)
                    end
                end
            end
        end
    end
end)

-- respawned at the hospital: straight back inside
AddEventHandler('whip_core:player:revived', function(e)
    if not e or e.how ~= 'respawned' then return end
    local s = e.charId and Serving[e.charId]
    if not s then return end
    s.grace = now() + 30
    s.outSince = nil
    -- 1.1.0: wake in the prison infirmary (Config.Prison.infirmary, else the yard); the sentence kept running
    local inf = PR.infirmary
    local spot = (type(inf) == 'table' and #inf > 0) and inf[math.random(#inf)] or arriveSpot()
    if s.job then s.job = nil end
    teleport(s.source, spot, 'in')
    hud(e.charId)
    WC:NotifyPlayer(s.source, ('You woke up in the prison infirmary. Your sentence kept running: %d min left.'):format(math.ceil((s.remaining or 0) / 60)), 'info', 8000)
end)

-- ---------------------------------------------------------------- jobs
local function pickSpot(key, not_i)
    local spots = JB[key].spots
    if #spots == 1 then return 1 end
    local i
    repeat i = math.random(#spots) until i ~= not_i
    return i
end

local function registerJobs()
    local keys = {}
    for k, v in pairs(JB) do if type(v) == 'table' and v.spots then keys[#keys + 1] = k end end

    WC:SecureEvent('es_jail:job', { rateLimit = 1000, burst = 2, params = { { 'job', 'enum', keys } },
        near = { at = function() return PR.board end, range = 6.0, message = 'Go to the job board' } }, function(source, player, key)
        local s = Serving[player.charId]
        if not s then return false, 'Only inmates work here' end
        s.job = { key = key, i = pickSpot(key) }
        hud(player.charId)
        JL.notify(source, ('%s: head to the marked spot'):format(JB[key].label), 'info', 4000)
    end)

    WC:SecureEvent('es_jail:jobStop', { rateLimit = 800, burst = 2 }, function(source, player)
        local s = Serving[player.charId]
        if not s or not s.job then return false end
        s.job = nil
        hud(player.charId)
    end)

    WC:SecureEvent('es_jail:jobDo', { rateLimit = 1500, burst = 1 }, function(source, player)
        local cid = player.charId
        local s = Serving[cid]
        if not s or not s.job then return false end
        local key, i = s.job.key, s.job.i
        local job = JB[key]
        local spot = job.spots[i]
        local at = JL.pedCoords(source)
        if not at or #(at - spot) > 3.0 then return false, 'Go to the marked spot' end
        -- 1.0.4: the job's prop (WHIP makes it and takes it away when the bar ends: done, cancelled, death); the run tag
        -- lets release / escape end the bar (and the prop) at once
        local tag = ('es_jail:job:%d:%d'):format(cid, GetGameTimer())
        s.jobTag = tag
        local done = WC:Progress(source, { label = job.verb .. '...', duration = math.floor((job.seconds or 8) * 1000), anim = job.anim,
            prop = job.prop, near = { coords = spot, range = 3.0 }, tag = tag })
        if s.jobTag == tag then s.jobTag = nil end
        s = Serving[cid]
        if not done or not s or not s.job or s.job.key ~= key or s.job.i ~= i then return false end
        local cut = math.max(0, math.min(job.cut or 0, math.floor(s.remaining) - (JB.floor or 30)))
        s.remaining = s.remaining - cut
        s.cut, s.jobs, s.dirty = s.cut + cut, s.jobs + 1, true
        s.job.i = pickSpot(key, i)
        hud(cid)
        JL.notify(source, cut > 0 and ('Good work: %s off your time'):format(fmt(cut)) or 'Good work (that is as short as your time gets)', 'success', 3500)
    end)
end

-- ---------------------------------------------------------------- staff commands
local function canManage(source)
    if source == 0 then return true end
    return JL.isStaff(source) or JL.officer(source, Config.Perms.manage) and true or false
end
local function reply(source, text, kind)
    if source == 0 then print('[es_jail] ' .. text) else JL.notify(source, text, kind or 'info', 7000) end
end
local function targetCid(arg)
    local n = tonumber(arg)
    if not n then return nil end
    if GetPlayerName(n) then return WC:GetCharId(n), n end
    return nil
end

local function registerCommands()
    Whip.command('jail', { rateLimit = { burst = 3, everyMs = 1500 }, whileDead = true }, function(source, args)
        if not canManage(source) then return reply(source, 'You cannot jail people', 'error') end
        local cid = targetCid(args[1])
        local months = tonumber(args[2])
        if not cid or not months then return reply(source, 'Use: /jail <server id> <months> [reason]', 'error') end
        local by = source ~= 0 and WC:GetCharId(source) or nil
        local ok, res = jail(cid, months, nil, by, table.concat(args, ' ', 3))
        if not ok then return reply(source, res or 'Could not jail them', 'error') end
        reply(source, ('%s jailed: %s to serve'):format(JL.nameOf(cid), fmt(res.seconds)), 'success')
    end)

    Whip.command('unjail', { rateLimit = { burst = 3, everyMs = 1500 }, whileDead = true }, function(source, args)
        if not canManage(source) then return reply(source, 'You cannot release people', 'error') end
        local cid = targetCid(args[1])
        if not cid and args[1] and args[1]:match('^c%d+$') then cid = tonumber(args[1]:sub(2)) end
        if not cid then return reply(source, 'Use: /unjail <server id>  (or c<charId> when they are offline)', 'error') end
        local ok, why = release(cid, 'released by staff', source ~= 0 and WC:GetCharId(source) or nil)
        reply(source, ok and (JL.nameOf(cid) .. ' released') or why, ok and 'success' or 'error')
    end)

    Whip.command('jailtime', { rateLimit = { burst = 3, everyMs = 1500 }, whileDead = true }, function(source, args)
        if args[1] then
            if not canManage(source) then return reply(source, 'You can only check your own time', 'error') end
            local cid = targetCid(args[1])
            if not cid then return reply(source, 'Use: /jailtime [server id]', 'error') end
            local s = Serving[cid]
            if s then return reply(source, ('%s: %s left (%s cut by %d jobs)'):format(JL.nameOf(cid), fmt(s.remaining), fmt(s.cut), s.jobs)) end
            local r = MySQL.single.await('SELECT `status`,`remaining` FROM `es_jail_inmates` WHERE `charId` = ?', { cid })
            return reply(source, r and ('%s: %s (%s left)'):format(JL.nameOf(cid), r.status, fmt(r.remaining)) or (JL.nameOf(cid) .. ' has never been jailed'))
        end
        if source == 0 then return end
        local s = Serving[WC:GetCharId(source)]
        reply(source, s and ('%s left on your sentence (%s cut by %d jobs)'):format(fmt(s.remaining), fmt(s.cut), s.jobs) or 'You are not in jail')
    end)
end

-- ---------------------------------------------------------------- exports (es_mdt reads these)
exports('Jail', function(charId, months, reportId, byCharId)
    local ok, a, b = pcall(jail, charId, months, tonumber(reportId), tonumber(byCharId), reportId and ('Report #' .. tostring(reportId)) or nil)
    if not ok then print('[es_jail] Jail failed: ' .. tostring(a)) return false, 'The jail could not take them' end
    return a, b
end)
exports('Release', function(charId, byCharId, why)
    local ok, a, b = pcall(release, charId, why or 'released', tonumber(byCharId))
    if not ok then return false, 'Could not release them' end
    return a, b
end)
exports('IsJailed', function(charId)
    charId = tonumber(charId)
    if Serving[charId] then return true, Serving[charId].remaining end
    local r = charId and MySQL.single.await("SELECT `remaining` FROM `es_jail_inmates` WHERE `charId` = ? AND `status` = 'serving'", { charId })
    return r ~= nil, r and r.remaining or nil
end)
exports('IsCuffed', function(source) local st = JL.isCuffed(tonumber(source)) return st and st.mode or false end)

--- Everyone serving or on the run (and the last `recent` released): for the MDT
exports('GetInmates', function(recent)
    local rows = MySQL.query.await([[SELECT `charId`,`status`,`months`,`total`,`remaining`,`cut`,`jobs`,`reportId`,`reason`,`jailedBy`,
        (`items` IS NOT NULL AND `items` <> '[]') AS `hasItems`,
        UNIX_TIMESTAMP(`jailedAt`) AS `jailedAt`, UNIX_TIMESTAMP(`releasedAt`) AS `releasedAt`, UNIX_TIMESTAMP(`escapedAt`) AS `escapedAt`
        FROM `es_jail_inmates` WHERE `status` IN ('serving','escaped') OR (`releasedAt` > NOW() - INTERVAL ? DAY)
        ORDER BY FIELD(`status`,'escaped','serving','released'), `jailedAt` DESC LIMIT 200]], { tonumber(recent) or 3 }) or {}
    local ids = {}
    for _, r in ipairs(rows) do ids[#ids + 1] = r.charId if r.jailedBy then ids[#ids + 1] = r.jailedBy end end
    local names = JL.names(ids)
    for _, r in ipairs(rows) do
        local s = Serving[r.charId]
        if s then r.remaining, r.cut, r.jobs = math.max(0, math.floor(s.remaining)), s.cut, s.jobs end
        r.online = s ~= nil
        r.name = names[r.charId] or ('#' .. r.charId)
        r.byName = r.jailedBy and (names[r.jailedBy] or ('#' .. r.jailedBy)) or nil
        r.hasItems = r.hasItems == 1 or r.hasItems == true
    end
    return rows
end)

-- ---------------------------------------------------------------- login / restart
local function loaded(source)
    local cid = WC:GetCharId(source)
    if not cid then return end
    JL.cuffsLoaded(source)
    local row = MySQL.single.await('SELECT `status`,`remaining`,`total`,`cut`,`jobs`,`pendingOut`,`items` FROM `es_jail_inmates` WHERE `charId` = ?', { cid })
    if not row then return end
    if row.status == 'serving' then
        local fresh = row.items == nil and (tonumber(row.total) or 0) == (tonumber(row.remaining) or 0)
        begin(source, cid, row, fresh)
    elseif row.status == 'released' and (row.pendingOut == 1 or row.pendingOut == true) then
        finishOut(source, cid, 'released')
    end
end

AddEventHandler('whip_core:player:loaded', function(e)
    if not e or not e.source or e.phantom then return end
    CreateThread(function() Wait(2500) loaded(e.source) end)
end)
AddEventHandler('whip_core:player:logout', function(e)
    local cid = e and e.charId
    if cid and Serving[cid] then save(cid) Serving[cid] = nil end
end)
AddEventHandler('onResourceStop', function(r)
    if r ~= GetCurrentResourceName() then return end
    for cid, s in pairs(Serving) do
        MySQL.update.await('UPDATE `es_jail_inmates` SET `remaining` = ?, `cut` = ?, `jobs` = ? WHERE `charId` = ?', { math.max(0, math.floor(s.remaining)), s.cut, s.jobs, cid })
    end
end)

Whip.register(function()
    local ok, why = Tables.ensure()
    if not ok then Whip.startProblem('tables: %s', tostring(why)) return end
    JL.registerItems()
    JL.registerCuffs()
    JL.registerTest()
    registerJobs()
    registerCommands()
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        CreateThread(function() loaded(src) end)
    end
    local n = MySQL.scalar.await("SELECT COUNT(*) FROM `es_jail_inmates` WHERE `status` = 'serving'") or 0
    print(('[es_jail] ready: %d serving'):format(n))
end)
