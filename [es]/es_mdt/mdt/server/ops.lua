local _ENV = ESAPP('mdt'); -- es_mdt 1.3.0: dispatch (911 / 311 / AddCall), panic, live map, mugshots, announcements, report templates,
-- send-to-jail and the plate checks behind the radar's plate reader.
-- Loaded BEFORE server/main.lua; everything here runs from MDT.registerOps(), which main.lua calls from its
-- Whip.register once its own helpers (MDT.cb, MDT.dutyNow, ...) are in place.
local WC = exports.whip_core
local ED = exports.es_departments
MDT = MDT or {}

local DSP = Config.Dispatch or {}
local PAN = Config.Panic or {}
local MUG = Config.Mugshots or {}
local RAD = Config.Radar or {}
local JAIL = Config.Jail or {}

local function now() return os.time() end

-- ---------------------------------------------------------------- shared bits

--- Everyone on duty right now: list of { source, charId, callsign, name, deptId, deptShort }
local function onDuty()
    local _, idx = MDT.dutyNow()
    local list = {}
    for cid, e in pairs(idx) do
        if e.u.source then
            list[#list + 1] = { source = e.u.source, charId = cid, callsign = e.u.callsign, name = e.u.name,
                deptId = e.g.id, deptShort = e.g.short, color1 = e.g.color1 }
        end
    end
    return list, idx
end

local function sourcesOf(list) local out = {} for _, x in ipairs(list) do out[#out + 1] = x.source end return out end

local function coordsOf(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return nil end
    local v = GetEntityCoords(ped)
    return { x = v.x + 0.0, y = v.y + 0.0, z = v.z + 0.0 }, GetEntityHeading(ped)
end

local function dist2(a, b) local dx, dy = a.x - b.x, a.y - b.y return math.sqrt(dx * dx + dy * dy) end

local function phoneOf(cid)
    if not cid then return nil end
    local r = MySQL.single.await('SELECT `phoneNumber` FROM `phone_numbers` WHERE `charId` = ? AND `retiredAt` IS NULL LIMIT 1', { cid })
    return r and r.phoneNumber or nil
end

local function plateKey(p) return (type(p) == 'string' and p or ''):upper():gsub('[^A-Z0-9]', ''):sub(1, 10) end

-- ---------------------------------------------------------------- dispatch calls

local KINDS = { ['911'] = true, ['311'] = true, panic = true, alert = true, officer = true }

--- Files a call and tells every on-duty unit. d = { kind, priority (1-3), title, message, street, coords {x,y,z},
--- callerCharId, callerName, callerPhone, deptId, blip = false }. Returns the call id or false, why.
local function addCall(d)
    if type(d) ~= 'table' then return false, 'A call is a table' end
    local str, int = MDT.str, MDT.int
    local kind = KINDS[d.kind] and d.kind or 'alert'
    local c = type(d.coords) == 'table' or type(d.coords) == 'vector3' or type(d.coords) == 'vector4'
    local x, y, z
    if c then x, y, z = tonumber(d.coords.x), tonumber(d.coords.y), tonumber(d.coords.z) end
    local pri = int(d.priority or (kind == 'panic' and 1 or kind == '311' and 3 or 2), 1, 3)
    local title = str(d.title, 120)
    if title == '' then title = kind == '911' and '911 call' or kind == '311' and '311 call' or 'Alert' end
    local cid = MySQL.insert.await([[INSERT INTO `es_mdt_calls` (`kind`,`priority`,`title`,`message`,`callerCharId`,`callerName`,`callerPhone`,`street`,`x`,`y`,`z`,`deptId`)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?)]], { kind, pri, title, str(d.message, 500), tonumber(d.callerCharId), str(d.callerName, 80),
        str(d.callerPhone, 20), str(d.street, 120), x, y, z, tonumber(d.deptId) })
    if not cid then return false, 'The call could not be saved' end
    local list = onDuty()
    local payload = { id = cid, kind = kind, priority = pri, title = title, message = str(d.message, 200), street = str(d.street, 120),
        x = x, y = y, z = z, callerName = str(d.callerName, 80), callerPhone = str(d.callerPhone, 20) }
    for _, u in ipairs(list) do TriggerClientEvent('es_mdt:client:call', u.source, payload) end
    if x and y and d.blip ~= false and #list > 0 then
        local b = DSP.blip or {}
        WC:ShowBlip({ people = sourcesOf(list) }, 'call:' .. cid, { coords = vector3(x, y, z or 0.0),
            label = ('#%d %s'):format(cid, title):sub(1, 40), sprite = b.sprite or 280, color = b.color or 1, flash = pri == 1 })
        SetTimeout((b.seconds or 120) * 1000, function() WC:HideBlip('call:' .. cid) end)
    end
    MDT.refresh('calls')
    return cid
end
MDT.addCall = addCall
exports('AddCall', function(data)
    local ok, a, b = pcall(addCall, data)
    if not ok then return false, 'The call could not be filed' end
    return a, b
end)

local function unitsOfCalls(ids)
    local out = {}
    if #ids == 0 then return out end
    local rows = MySQL.query.await(('SELECT `callId`,`charId` FROM `es_mdt_call_units` WHERE `callId` IN (%s) ORDER BY `attachedAt`'):format(MDT.marks(#ids)), ids) or {}
    local cids = {}
    for _, r in ipairs(rows) do cids[#cids + 1] = r.charId end
    local names = MDT.namesOf(cids)
    local _, idx = MDT.dutyNow()
    for _, r in ipairs(rows) do
        out[r.callId] = out[r.callId] or {}
        local e = idx[r.charId]
        local t = MDT.Teams[MDT.TeamOf[r.charId] or 0]
        local st = t and t.status or (MDT.Units[r.charId] or {}).status or 'available'
        table.insert(out[r.callId], { charId = r.charId, name = names[r.charId] or ('#' .. r.charId),
            callsign = e and e.u.callsign or nil, deptShort = e and e.g.short or nil, color1 = e and e.g.color1 or nil, status = st })
    end
    return out
end

local CALL_COLS = [[`id`,`kind`,`priority`,`status`,`title`,`message`,`callerName`,`callerPhone`,`street`,`x`,`y`,`deptId`,`outcome`,`closeNote`,
    `closedBy`,UNIX_TIMESTAMP(`closedAt`) AS `closedAt`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt`]]

local function callsList(status, limit)
    local rows = MySQL.query.await(('SELECT %s, (SELECT COUNT(*) FROM `es_mdt_call_notes` n WHERE n.`callId` = c.`id`) AS `notes` FROM `es_mdt_calls` c WHERE `status` = ? ORDER BY %s LIMIT ?')
        :format(CALL_COLS, status == 'active' and '`priority`, `id` DESC' or '`id` DESC'), { status, limit }) or {}
    local ids = {}
    for _, r in ipairs(rows) do ids[#ids + 1] = r.id r.notes = tonumber(r.notes) or 0 end
    local u = unitsOfCalls(ids)
    for _, r in ipairs(rows) do r.units = u[r.id] or {} end
    return rows
end

--- Me plus my paired partner (they attach together)
local function meAndPartner(c)
    local out = { c.charId }
    local t = MDT.Teams[MDT.TeamOf[c.charId] or 0]
    if t then out[#out + 1] = t.lead == c.charId and t.partner or t.lead end
    return out
end

--- 1.3.2: tell every on-duty unit's popup who is on a call now / that it closed
local function tellUnits(cid)
    local u = unitsOfCalls({ cid })[cid] or {}
    local signs = {}
    for _, x in ipairs(u) do signs[#signs + 1] = (x.callsign or x.name) .. (x.status == 'scene' and ' ✓' or x.status == 'enroute' and ' →' or '') end
    for _, o in ipairs(onDuty()) do TriggerClientEvent('es_mdt:client:callUnits', o.source, { id = cid, units = signs }) end
end
local function tellClosed(cid, outcome)
    for _, o in ipairs(onDuty()) do TriggerClientEvent('es_mdt:client:callClosed', o.source, { id = cid, outcome = outcome }) end
end
--- the partner's game (when online and on duty) follows the attach / detach too
local function tellPartner(c, who, ev, data)
    if #who < 2 then return end
    local _, idx = MDT.dutyNow()
    local e = idx[who[2]]
    if e and e.u.source and e.u.source ~= c.source then TriggerClientEvent(ev, e.u.source, data) end
end

--- 1.3.5: unit status follows the call (En route on attach, On scene on arrival, Available on detach / close)
local AUTO = DSP.autoStatus or {}
local MOVING = { enroute = true, scene = true }
local function statusOf(charId)
    local t = MDT.Teams[MDT.TeamOf[charId] or 0]
    if t then return t.status or 'available' end
    return (MDT.Units[charId] or {}).status or 'available'
end
local function setStatus(charId, status)
    local t = MDT.Teams[MDT.TeamOf[charId] or 0]
    if t then t.status, t.at = status, now() else MDT.Units[charId] = { status = status, at = now() } end
end
--- back to Available, but only from En route / On scene (a Busy or Break the officer set stays)
local function freeUnits(charIds)
    if AUTO.clearOnLeave == false then return end
    local changed = false
    for _, x in ipairs(charIds) do
        if MOVING[statusOf(x)] then setStatus(x, 'available') changed = true end
    end
    if changed then MDT.refresh('units') end
end

-- ---------------------------------------------------------------- panic

local PanicCool = {}

local function panic(c, street)
    local _, idx = MDT.dutyNow()
    local me = idx[c.charId]
    if not me then return false, 'Only an officer on duty can press panic' end
    if (PanicCool[c.charId] or 0) > now() then return false, 'Panic was just pressed' end
    PanicCool[c.charId] = now() + (PAN.cooldown or 15)
    local pos = coordsOf(c.source)
    if not pos then return false, 'Your position could not be read' end
    local secs = PAN.seconds or 90
    MDT.Panic[c.charId] = now() + secs
    local who = ('%s %s'):format(me.u.callsign or '', me.u.name or ''):gsub('^%s+', '')
    local callId = addCall({ kind = 'panic', priority = 1, title = ('PANIC · %s'):format(who), street = street, coords = pos,
        message = ('Officer %s (%s) pressed the panic button'):format(who, me.g.short or ''), callerCharId = c.charId,
        callerName = me.u.name, deptId = me.g.id, blip = false })
    local list = onDuty()
    local b = PAN.blip or {}
    WC:ShowBlip({ people = sourcesOf(list) }, 'panic:' .. c.charId, { coords = vector3(pos.x, pos.y, pos.z),
        label = ('PANIC %s'):format(me.u.callsign or ''):sub(1, 40), sprite = b.sprite or 161, color = b.color or 1, flash = true, scale = 1.2 })
    local payload = { charId = c.charId, callsign = me.u.callsign, name = me.u.name, deptShort = me.g.short, street = MDT.str(street, 120),
        x = pos.x, y = pos.y, callId = callId, seconds = secs }
    for _, u in ipairs(list) do TriggerClientEvent('es_mdt:client:panic', u.source, payload) end
    SetTimeout(secs * 1000, function()
        if (MDT.Panic[c.charId] or 0) <= now() then
            MDT.Panic[c.charId] = nil
            WC:HideBlip('panic:' .. c.charId)
            MDT.refresh('units')
        end
    end)
    MDT.refresh('units')
    MDT.log(c, 'panic', { callId = callId, street = street })
    return { callId = callId }
end

-- ---------------------------------------------------------------- plates (ALPR)

local PlateCache = {}   -- [key] = { at, res }
local HitSeen = {}      -- ['charId:key'] = os.time() last logged
MDT.clearPlateCache = function() for k in pairs(PlateCache) do PlateCache[k] = nil end end   -- 1.3.6: new / closed BOLOs show at once

--- What the MDT knows about a plate. { plate, level = 'high'|'low'|nil, hits = { {kind, level, text} }, vehicleId, owner, label, boloId }
local function checkPlate(plate)
    local key = plateKey(plate)
    if #key < 1 then return nil end
    local hit = PlateCache[key]
    if hit and now() - hit.at < (RAD.recheckSec or 60) then return hit.res end
    local lv = RAD.hits or {}
    local function lvl(k, def) if lv[k] == nil then return def end return lv[k] end
    local res = { plate = key, hits = {} }
    local v = MySQL.single.await([[SELECT v.`vehicleId`, v.`plate`, v.`ownerCharId`, COALESCE(k.`displayName`, v.`model`) AS `label`, n.`flags`
        FROM `vehicles` v LEFT JOIN `vehicle_catalog` k ON k.`model` = v.`model` LEFT JOIN `es_mdt_vehicle_notes` n ON n.`vehicleId` = v.`vehicleId`
        WHERE REPLACE(v.`plate`,' ','') = ? LIMIT 1]], { key })
    local b = MySQL.single.await([[SELECT `id`,`title` FROM `es_mdt_bolos` WHERE `kind` = 'vehicle' AND `status` = 'active'
        AND (`expiresAt` IS NULL OR `expiresAt` > NOW()) AND REPLACE(`plate`,' ','') = ? ORDER BY `id` DESC LIMIT 1]], { key })
    if b then
        res.boloId = b.id
        res.hits[#res.hits + 1] = { kind = 'bolo', level = lvl('bolo', 'high'), text = 'BOLO: ' .. (b.title or ('#' .. b.id)) }
    end
    if v then
        res.vehicleId, res.label = v.vehicleId, v.label
        for _, f in ipairs(MDT.flagsOf(v.flags)) do
            if tostring(f):lower() == 'stolen' then res.hits[#res.hits + 1] = { kind = 'stolen', level = lvl('stolen', 'high'), text = 'Reported stolen' } end
        end
        if v.ownerCharId then
            res.owner = MDT.namesOf({ v.ownerCharId })[v.ownerCharId]
            local w = MySQL.single.await("SELECT COUNT(*) AS `n` FROM `es_mdt_warrants` WHERE `charId` = ? AND `status` = 'active' AND `kind` = 'arrest'", { v.ownerCharId })
            if w and (tonumber(w.n) or 0) > 0 then
                res.hits[#res.hits + 1] = { kind = 'warrant', level = lvl('warrant', 'high'), text = ('Owner %s has an active warrant'):format(res.owner or '') }
            end
        end
    else
        res.hits[#res.hits + 1] = { kind = 'unregistered', level = lvl('unregistered', 'low'), text = 'Not registered' }
    end
    local kept = {}
    for _, h in ipairs(res.hits) do if h.level == 'high' or h.level == 'low' then kept[#kept + 1] = h end end
    res.hits = kept
    for _, h in ipairs(res.hits) do
        if h.level == 'high' then res.level = 'high' elseif h.level == 'low' and not res.level then res.level = 'low' end
    end
    PlateCache[key] = { at = now(), res = res }
    return res
end
MDT.checkPlate = checkPlate
exports('CheckPlate', function(plate) local ok, r = pcall(checkPlate, plate) return ok and r or nil end)

--- An officer's reader saw a plate: log the high hits once per 5 min and move the BOLO's last-seen point
local function plateSeen(charId, res, pos)
    if not res or res.level ~= 'high' then return end
    local k = charId .. ':' .. res.plate
    if (HitSeen[k] or 0) > now() - 300 then return end
    HitSeen[k] = now()
    local kinds, texts = {}, {}
    for _, h in ipairs(res.hits) do if h.level == 'high' then kinds[#kinds + 1] = h.kind texts[#texts + 1] = h.text end end
    MySQL.insert.await('INSERT INTO `es_mdt_plate_hits` (`plate`,`kinds`,`detail`,`charId`,`x`,`y`) VALUES (?,?,?,?,?,?)',
        { res.plate, table.concat(kinds, ','):sub(1, 60), table.concat(texts, ' · '):sub(1, 300), charId, pos and pos.x, pos and pos.y })
    if res.boloId and pos then
        MySQL.update.await('UPDATE `es_mdt_bolos` SET `lastX` = ?, `lastY` = ?, `lastSeenAt` = NOW() WHERE `id` = ?', { pos.x, pos.y, res.boloId })
        MDT.refresh('bolos')
    end
end

--- On duty in a police / sheriff / state department (the radar's rule)
local function lawOnDuty(source)
    local types = RAD.lawTypes or { police = true, sheriff = true, state = true }
    for _, d in ipairs(ED:GetPlayerDepartments(source) or {}) do
        if d.onDuty and types[d.type] then return true end
    end
    return false
end

-- ---------------------------------------------------------------- map

local MapCache = { at = 0 }
local function mapData()
    if GetGameTimer() - MapCache.at < 1500 and MapCache.data then return MapCache.data end
    local _, idx = MDT.dutyNow()
    local units = {}
    local t = now()
    for cid, e in pairs(idx) do
        if e.u.source then
            local pos, hd = coordsOf(e.u.source)
            if pos then
                local ped = GetPlayerPed(e.u.source)
                units[#units + 1] = { charId = cid, callsign = e.u.callsign, name = e.u.name, status = e.u.status, deptShort = e.g.short,
                    color1 = e.g.color1, x = pos.x, y = pos.y, h = hd, car = GetVehiclePedIsIn(ped, false) ~= 0,
                    panic = (MDT.Panic[cid] or 0) > t or nil }
            end
        end
    end
    local calls = MySQL.query.await("SELECT `id`,`kind`,`priority`,`title`,`street`,`x`,`y`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt` FROM `es_mdt_calls` WHERE `status` = 'active' AND `x` IS NOT NULL ORDER BY `id` DESC LIMIT 60") or {}
    local bolos = MySQL.query.await([[SELECT `id`,`kind`,`charId`,`plate`,`title`,`lastX` AS `x`,`lastY` AS `y`,UNIX_TIMESTAMP(`lastSeenAt`) AS `seenAt` FROM `es_mdt_bolos`
        WHERE `status` = 'active' AND `lastX` IS NOT NULL AND `lastSeenAt` > NOW() - INTERVAL 2 HOUR ORDER BY `lastSeenAt` DESC LIMIT 30]]) or {}
    MapCache = { at = GetGameTimer(), data = { units = units, calls = calls, bolos = bolos, at = t } }
    return MapCache.data
end

-- ---------------------------------------------------------------- mugshots

-- A stored mugshot is at most ~300 KB (about 400 000 characters of data URL): it travels to officers in one callback
-- answer, like the character portrait does. Links may point at pictures up to 2 MB, but what is kept must fit.
local MUG_MAX = math.floor((MUG.storeBytes or 300 * 1024) * 4 / 3) + 64
local function mugOk(img)
    return type(img) == 'string' and img:match('^data:image/[a-z]+;base64,') ~= nil and #img <= MUG_MAX
end

local function saveMug(c, charId, img, origin, reportId)
    local mid = MySQL.insert.await('INSERT INTO `es_mdt_mugshots` (`charId`,`image`,`origin`,`takenBy`,`reportId`) VALUES (?,?,?,?,?)',
        { charId, img, origin, c.charId, reportId })
    if not mid then return false, 'The mugshot could not be saved' end
    MySQL.update.await([[INSERT INTO `es_mdt_profiles` (`charId`,`mugshotId`,`updatedBy`) VALUES (?,?,?)
        ON DUPLICATE KEY UPDATE `mugshotId` = VALUES(`mugshotId`), `updatedBy` = VALUES(`updatedBy`)]], { charId, mid, c.charId })
    MDT.log(c, 'mugshot', { charId = charId, mugshotId = mid, origin = origin })
    MDT.refresh('people')
    return { id = mid, image = img }
end

--- The suspect's server id when they are online and close enough (yourself always, for testing)
local function suspectNear(c, charId, doing)
    if charId == c.charId then return c.source end
    local src = MDT.onlineByChar()[charId]
    if not src then return false, doing and 'That person is not in the city right now.' or 'That person is not in the city right now. Use a link instead.' end
    local a, b = coordsOf(c.source), coordsOf(src)
    if not a or not b or dist2(a, b) > (MUG.range or 6.0) then return false, ('Stand within %d m of them to %s'):format(math.floor(MUG.range or 6), doing or 'take a mugshot') end
    return src
end
MDT.suspectNear = suspectNear   -- 1.5.3: fingerprints (server/evidence.lua) use the same rule

-- ---------------------------------------------------------------- announcements & templates

local function announcementsFor(c, limit)
    local rows = MySQL.query.await([[SELECT `id`,`deptId`,`title`,`body`,`pinned`,`createdBy`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt`,
        UNIX_TIMESTAMP(`expiresAt`) AS `expiresAt` FROM `es_mdt_announcements` WHERE `removed` = 0 AND (`deptId` = ? OR `deptId` IS NULL)
        AND (`expiresAt` IS NULL OR `expiresAt` > NOW()) ORDER BY `pinned` DESC, `id` DESC LIMIT ?]], { c.dept.id, limit }) or {}
    local ids = {}
    for _, r in ipairs(rows) do ids[#ids + 1] = r.createdBy end
    local names = MDT.namesOf(ids)
    local short = MDT.deptShort()
    for _, r in ipairs(rows) do
        r.by = names[r.createdBy] or ('#' .. r.createdBy)
        r.pinned = r.pinned == 1 or r.pinned == true
        r.all = r.deptId == nil
        r.deptShort = r.deptId and short[r.deptId] and short[r.deptId].short or 'ALL'
        r.canEdit = c.staff or (c.perms.announce and r.deptId == c.dept.id)
    end
    return rows
end

local function canTemplates(c) return c.staff or c.perms.announce or MDT.isHighCommand(c) or (c.rights and c.rights.canManage) end

local function templatesFor(c)
    local out = {}
    for i, t in ipairs(Config.ReportTemplates or {}) do
        out[#out + 1] = { key = t.key or ('b' .. i), name = t.name, type = t.type, title = t.title, body = t.body, builtIn = true }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    local edit = canTemplates(c)
    for _, r in ipairs(MySQL.query.await('SELECT `id`,`name`,`type`,`title`,`body` FROM `es_mdt_templates` WHERE `deptId` = ? ORDER BY `name`', { c.dept.id }) or {}) do
        r.key = 'c' .. r.id
        r.canEdit = edit
        out[#out + 1] = r
    end
    return out, edit
end

MDT.dashboardExtra = function(c, out)
    out.announcements = announcementsFor(c, 6)
    out.calls = callsList('active', 6)
    out.canAnnounce = c.perms.announce == true or c.staff
end

-- ---------------------------------------------------------------- callbacks

function MDT.registerOps()
    local cb, str, int, id = MDT.cb, MDT.str, MDT.int, MDT.id

    -- 911 / 311 from any player (not the MDT: no department needed)
    local Dial = {}
    Whip.core:SecureCallback('es_mdt:dial', { rateLimit = 3000, burst = 2, sheet = 'light', params = { { 'd', 'any' } } }, function(source, _, d)
        d = type(d) == 'table' and d or {}
        local cid = WC:GetCharId(source)
        if not cid then return false, 'No character' end
        if (Dial[cid] or 0) > now() then return false, ('Wait %d s before calling again'):format(Dial[cid] - now()) end
        local msg = str(d.message, 400)
        if #msg < 3 then return false, 'Say what is happening' end
        Dial[cid] = now() + (DSP.cooldownSec or 30)
        local pos = coordsOf(source)
        local kind = d.kind == '311' and '311' or '911'
        local name = MDT.namesOf({ cid })[cid]
        local callId = addCall({ kind = kind, priority = kind == '311' and 3 or 2, title = kind == '311' and '311 · non-emergency' or '911 · emergency',
            message = msg, street = str(d.street, 120), coords = pos, callerCharId = cid, callerName = name, callerPhone = phoneOf(cid) })
        if not callId then return false, 'Dispatch did not answer, try again' end
        return { id = callId, units = #onDuty() }
    end)

    -- the radar may run here (law department, on duty)
    Whip.core:SecureCallback('es_mdt:radarAllowed', { rateLimit = 2000, burst = 3, sheet = 'light' }, function(source)
        return lawOnDuty(source)
    end)
    Whip.core:SecureCallback('es_mdt:radarPlates', { rateLimit = 400, burst = 6, sheet = 'light', params = { { 'd', 'any' } } }, function(source, _, d)
        d = type(d) == 'table' and d or {}
        if not lawOnDuty(source) then return false, 'Off duty' end
        local cid = WC:GetCharId(source)
        local pos = coordsOf(source)
        local out = {}
        local n = 0
        for _, p in ipairs(type(d.plates) == 'table' and d.plates or {}) do
            n = n + 1
            if n > 2 then break end
            local res = checkPlate(p)
            if res then
                out[res.plate] = res
                if cid then plateSeen(cid, res, pos) end
            end
        end
        return out
    end)

    -- dispatch board
    cb('calls', { rate = 300, burst = 6 }, function(c, d)
        local status = d.status == 'closed' and 'closed' or 'active'
        local rows = callsList(status, status == 'closed' and 50 or 100)
        local names = {}
        for _, r in ipairs(rows) do if r.closedBy then names[#names + 1] = r.closedBy end end
        names = MDT.namesOf(names)
        for _, r in ipairs(rows) do r.closedByName = r.closedBy and names[r.closedBy] or nil end
        return { calls = rows, outcomes = DSP.outcomes or {}, now = now() }
    end)

    cb('call', { rate = 300, burst = 6 }, function(c, d)
        local cid = id(d.id)
        local r = cid and MySQL.single.await(('SELECT %s FROM `es_mdt_calls` WHERE `id` = ?'):format(CALL_COLS), { cid })
        if not r then return false, 'No such call' end
        r.units = unitsOfCalls({ cid })[cid] or {}
        r.notesList = MySQL.query.await('SELECT `id`,`byCharId`,`note`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt` FROM `es_mdt_call_notes` WHERE `callId` = ? ORDER BY `id`', { cid }) or {}
        local ids = {}
        for _, n in ipairs(r.notesList) do ids[#ids + 1] = n.byCharId end
        if r.closedBy then ids[#ids + 1] = r.closedBy end
        local names = MDT.namesOf(ids)
        for _, n in ipairs(r.notesList) do n.by = n.byCharId and names[n.byCharId] or 'Dispatch' end
        r.closedByName = r.closedBy and names[r.closedBy] or nil
        r.attached = false
        for _, u in ipairs(r.units) do if u.charId == c.charId then r.attached = true end end
        r.canClose = r.status == 'active' and (r.attached or c.staff or (c.myLevel or 0) >= 60 or MDT.isHighCommand(c))
        r.now = now()
        return r
    end)

    cb('callCreate', { write = true, rate = 2000, burst = 2 }, function(c, d)
        if not c.onDuty and not c.staff then return false, 'Go on duty to log a call' end
        local title = str(d.title, 120)
        if #title < 3 then return false, 'Give the call a title' end
        local pos = coordsOf(c.source)
        local cid = addCall({ kind = 'officer', priority = int(d.priority, 1, 3), title = title, message = str(d.message, 500),
            street = str(d.street, 120), coords = pos, callerCharId = c.charId, callerName = c.name, deptId = c.dept.id })
        if not cid then return false, 'The call could not be saved' end
        MySQL.insert.await('INSERT IGNORE INTO `es_mdt_call_units` (`callId`,`charId`) VALUES (?,?)', { cid, c.charId })
        MDT.log(c, 'call_create', { callId = cid })
        MDT.refresh('calls')
        return { id = cid }
    end)

    cb('callAttach', { write = true, rate = 500, burst = 4 }, function(c, d)
        local cid = id(d.id)
        local r = cid and MySQL.single.await('SELECT `id`,`status`,`x`,`y`,`z` FROM `es_mdt_calls` WHERE `id` = ?', { cid })
        if not r then return false, 'No such call' end
        if r.status ~= 'active' then return false, 'That call is closed' end
        if not c.onDuty then return false, 'Go on duty to attach' end
        local who = meAndPartner(c)
        for _, x in ipairs(who) do MySQL.insert.await('INSERT IGNORE INTO `es_mdt_call_units` (`callId`,`charId`) VALUES (?,?)', { cid, x }) end
        MySQL.insert.await('INSERT INTO `es_mdt_call_notes` (`callId`,`byCharId`,`note`) VALUES (?,?,?)', { cid, c.charId, #who > 1 and 'Attached with partner' or 'Attached' })
        if d.route and r.x then WC:SetPlayerWaypoint(c.source, vector3(r.x, r.y, r.z or 0.0)) end
        MDT.log(c, 'call_attach', { callId = cid, from = d.from == 'popup' and 'popup' or 'mdt' })
        if AUTO.enroute ~= false then
            for _, x in ipairs(who) do setStatus(x, 'enroute') end
            MDT.refresh('units')
        end
        MDT.refresh('calls')
        tellUnits(cid)
        tellPartner(c, who, 'es_mdt:client:attached', { id = cid, x = r.x, y = r.y, z = r.z, by = c.name, arrive = AUTO.arrive ~= false and (AUTO.arriveRadius or 40) or nil })
        return { units = #who, x = r.x, y = r.y, z = r.z, arrive = AUTO.arrive ~= false and (AUTO.arriveRadius or 40) or nil }
    end)

    cb('callDetach', { write = true, rate = 500, burst = 4 }, function(c, d)
        local cid = id(d.id)
        if not cid then return false, 'No such call' end
        local who = meAndPartner(c)
        MySQL.update.await(('DELETE FROM `es_mdt_call_units` WHERE `callId` = ? AND `charId` IN (%s)'):format(MDT.marks(#who)), { cid, table.unpack(who) })
        MySQL.insert.await('INSERT INTO `es_mdt_call_notes` (`callId`,`byCharId`,`note`) VALUES (?,?,?)', { cid, c.charId, 'Detached' })
        freeUnits(who)
        MDT.refresh('calls')
        tellUnits(cid)
        tellPartner(c, who, 'es_mdt:client:detached', { id = cid, by = c.name })
        return true
    end)

    cb('callRoute', { rate = 500, burst = 4 }, function(c, d)
        local cid = id(d.id)
        local r = cid and MySQL.single.await('SELECT `x`,`y`,`z` FROM `es_mdt_calls` WHERE `id` = ?', { cid })
        if not r or not r.x then return false, 'That call has no location' end
        WC:SetPlayerWaypoint(c.source, vector3(r.x, r.y, r.z or 0.0))
        return true
    end)

    -- 1.3.5: the unit reached the call (the client sees it first; the server checks the position itself)
    cb('callArrive', { write = true, rate = 2000, burst = 2 }, function(c, d)
        if AUTO.arrive == false then return false, 'Off' end
        local cid = id(d.id)
        local r = cid and MySQL.single.await('SELECT `id`,`status`,`x`,`y` FROM `es_mdt_calls` WHERE `id` = ?', { cid })
        if not r or r.status ~= 'active' then return false, 'That call is closed' end
        if not r.x then return false, 'That call has no location' end
        if not c.onDuty then return false, 'Off duty' end
        local on = MySQL.single.await('SELECT 1 AS `x` FROM `es_mdt_call_units` WHERE `callId` = ? AND `charId` = ?', { cid, c.charId })
        if not on then return false, 'You are not on that call' end
        local pos = coordsOf(c.source)
        local radius = AUTO.arriveRadius or 40
        if not pos or dist2(pos, r) > radius * 1.5 + 10 then return false, 'Not there yet' end
        local who = meAndPartner(c)
        if statusOf(c.charId) == 'scene' then return { already = true } end
        setStatus(c.charId, 'scene')
        local _, idx = MDT.dutyNow()
        local me = idx[c.charId]
        local sign = me and me.u.callsign or nil
        local label = sign and ('%s (%s)'):format(sign, c.name) or c.name
        MySQL.insert.await('INSERT INTO `es_mdt_call_notes` (`callId`,`byCharId`,`note`) VALUES (?,?,?)', { cid, c.charId, ('Unit %s arrived'):format(label) })
        MDT.log(c, 'call_arrive', { callId = cid })
        MDT.refresh('units')
        MDT.refresh('calls')
        tellUnits(cid)
        tellPartner(c, who, 'es_mdt:client:arrived', { id = cid, by = c.name })
        return { arrived = true }
    end)

    cb('callNote', { write = true, rate = 800, burst = 4 }, function(c, d)
        local cid = id(d.id)
        local note = str(d.note, 500)
        if not cid then return false, 'No such call' end
        if #note < 2 then return false, 'Write a note' end
        MySQL.insert.await('INSERT INTO `es_mdt_call_notes` (`callId`,`byCharId`,`note`) VALUES (?,?,?)', { cid, c.charId, note })
        MDT.refresh('calls')
        return true
    end)

    cb('callClose', { write = true, rate = 800, burst = 4 }, function(c, d)
        local cid = id(d.id)
        local r = cid and MySQL.single.await('SELECT `id`,`status` FROM `es_mdt_calls` WHERE `id` = ?', { cid })
        if not r then return false, 'No such call' end
        if r.status ~= 'active' then return false, 'Already closed' end
        local on = MySQL.single.await('SELECT 1 AS `x` FROM `es_mdt_call_units` WHERE `callId` = ? AND `charId` = ?', { cid, c.charId })
        if not (on or c.staff or (c.myLevel or 0) >= 60 or MDT.isHighCommand(c)) then return false, 'Attach to the call to close it' end
        local outcome = str(d.outcome, 40)
        if outcome == '' then return false, 'Pick an outcome' end
        MySQL.update.await("UPDATE `es_mdt_calls` SET `status` = 'closed', `outcome` = ?, `closeNote` = ?, `closedBy` = ?, `closedAt` = NOW() WHERE `id` = ?",
            { outcome, str(d.note, 500), c.charId, cid })
        local onIt = {}
        for _, u in ipairs(MySQL.query.await('SELECT `charId` FROM `es_mdt_call_units` WHERE `callId` = ?', { cid }) or {}) do onIt[#onIt + 1] = u.charId end
        freeUnits(onIt)
        WC:HideBlip('call:' .. cid)
        MDT.log(c, 'call_close', { callId = cid, outcome = outcome })
        MDT.refresh('calls')
        tellClosed(cid, outcome)
        return true
    end)

    cb('panic', { rate = 1000, burst = 2, whileDead = true }, function(c, d) return panic(c, d.street) end)   -- a downed officer can still press it

    cb('mapData', { rate = 1000, burst = 4 }, function(c)
        if not (c.onDuty or c.staff) then return false, 'The live map is for officers on duty' end
        return mapData()
    end)

    -- mugshots
    cb('mugshotPrep', { perm = 'mdt_reports_write', write = true, rate = 1500, burst = 3 }, function(c, d)
        local cid = id(d.charId)
        if not cid then return false, 'Pick a person' end
        local src, why = suspectNear(c, cid)
        if not src then return false, why end
        return { source = src }
    end)

    cb('mugshotTake', { perm = 'mdt_reports_write', write = true, rate = 3000, burst = 2 }, function(c, d)
        local cid = id(d.charId)
        if not cid then return false, 'Pick a person' end
        local src, why = suspectNear(c, cid)
        if not src then return false, why end
        local img, err = WC:RequestScreenshot(c.source, { format = 'jpg', quality = MUG.quality or 0.85, width = MUG.width or 640 })
        if not img then return false, err or 'The camera did not answer' end
        if type(img) == 'string' and #img > MUG_MAX then   -- a busy scene: once more, smaller
            img, err = WC:RequestScreenshot(c.source, { format = 'jpg', quality = 0.6, width = 960 })
            if not img then return false, err or 'The camera did not answer' end
        end
        if not mugOk(img) then return false, 'The picture came back too big or broken' end
        return saveMug(c, cid, img, 'camera', id(d.reportId))
    end)

    cb('mugshotLink', { perm = 'mdt_reports_write', write = true, rate = 3000, burst = 2 }, function(c, d)
        local cid = id(d.charId)
        if not cid then return false, 'Pick a person' end
        local url = str(d.url, 500)
        local ok, why = Fetch.check(url)
        if not ok then return false, why end
        local img, err = Fetch.get(url)
        if not img then return false, err end
        if not mugOk(img) then return false, ('That picture is %d KB; a mugshot can be %d KB at most (or use the camera)'):format(
            math.ceil(#img * 3 / 4 / 1024), math.floor((MUG.storeBytes or 300 * 1024) / 1024)) end
        return saveMug(c, cid, img, 'link', id(d.reportId))
    end)

    -- 1.4.0: a photo from the officer's own camera roll (es_evidence: whip_core's camera item)
    cb('mugshotRoll', { perm = 'mdt_reports_write', write = true, rate = 2000, burst = 2 }, function(c, d)
        local cid, pid = id(d.charId), id(d.photoId)
        if not cid then return false, 'Pick a person' end
        if not pid then return false, 'Pick a photo' end
        if GetResourceState('es_evidence') ~= 'started' then return false, 'The camera roll (es_evidence) is not running' end
        local img = exports.es_evidence:RollImage(c.charId, pid)
        if not img then return false, 'That photo is not in your camera roll' end
        if not mugOk(img) then return false, 'That photo is too big for a mugshot' end
        return saveMug(c, cid, img, 'roll', id(d.reportId))
    end)

    cb('mugshots', { rate = 300, burst = 6 }, function(c, d)
        local cid = id(d.charId)
        if not cid then return false, 'Pick a person' end
        local rows = MySQL.query.await('SELECT `id`,`origin`,`takenBy`,`reportId`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt` FROM `es_mdt_mugshots` WHERE `charId` = ? ORDER BY `id` DESC LIMIT 30', { cid }) or {}
        local p = MySQL.single.await('SELECT `mugshotId` FROM `es_mdt_profiles` WHERE `charId` = ?', { cid })
        local ids = {}
        for _, r in ipairs(rows) do ids[#ids + 1] = r.takenBy end
        local names = MDT.namesOf(ids)
        for _, r in ipairs(rows) do r.by = r.takenBy and names[r.takenBy] or nil r.profile = p and p.mugshotId == r.id or false end
        return rows
    end)

    cb('mugshot', { rate = 150, burst = 12 }, function(c, d)
        local mid = id(d.id)
        local r = mid and MySQL.single.await('SELECT `id`,`image` FROM `es_mdt_mugshots` WHERE `id` = ?', { mid })
        if not r then return false, 'No such mugshot' end
        return r
    end)

    cb('mugshotProfile', { perm = 'mdt_reports_write', write = true, rate = 800, burst = 3 }, function(c, d)
        local mid, cid = id(d.id), id(d.charId)
        local r = mid and MySQL.single.await('SELECT `charId` FROM `es_mdt_mugshots` WHERE `id` = ?', { mid })
        if not r or r.charId ~= cid then return false, 'No such mugshot' end
        MySQL.update.await([[INSERT INTO `es_mdt_profiles` (`charId`,`mugshotId`,`updatedBy`) VALUES (?,?,?)
            ON DUPLICATE KEY UPDATE `mugshotId` = VALUES(`mugshotId`), `updatedBy` = VALUES(`updatedBy`)]], { cid, mid, c.charId })
        MDT.log(c, 'mugshot_profile', { charId = cid, mugshotId = mid })
        MDT.refresh('people')
        return true
    end)

    -- announcements
    cb('announcements', { rate = 300, burst = 6 }, function(c)
        return { list = announcementsFor(c, 40), canAnnounce = c.perms.announce == true or c.staff, canAll = c.staff }
    end)

    cb('announceSave', { perm = 'announce', write = true, rate = 2000, burst = 2 }, function(c, d)
        local title = str(d.title, 120)
        if #title < 3 then return false, 'Give it a title' end
        local hours = int(d.hours, 0, 24 * 90)
        local all = d.all == true and c.staff
        local aid = MySQL.insert.await(('INSERT INTO `es_mdt_announcements` (`deptId`,`title`,`body`,`pinned`,`createdBy`,`expiresAt`) VALUES (?,?,?,?,?,%s)')
            :format(hours > 0 and 'NOW() + INTERVAL ? HOUR' or 'NULL'),
            hours > 0 and { not all and c.dept.id or nil, title, str(d.body, 2000), d.pinned and 1 or 0, c.charId, hours }
            or { not all and c.dept.id or nil, title, str(d.body, 2000), d.pinned and 1 or 0, c.charId })
        if not aid then return false, 'It could not be posted' end
        local payload = { id = aid, title = title, by = c.name, deptShort = all and 'ALL' or c.dept.short }
        local seen = {}
        for _, d2 in ipairs(all and (ED:GetDepartments() or {}) or { c.dept }) do
            for _, u in ipairs(ED:GetOnDuty(d2.id) or {}) do
                if u.source and not seen[u.source] then seen[u.source] = true TriggerClientEvent('es_mdt:client:announce', u.source, payload) end
            end
        end
        MDT.log(c, 'announce', { id = aid, all = all })
        MDT.refresh('announce')
        return { id = aid }
    end)

    cb('announceAct', { perm = 'announce', write = true, rate = 800, burst = 4 }, function(c, d)
        local aid = id(d.id)
        local r = aid and MySQL.single.await('SELECT `id`,`deptId`,`pinned` FROM `es_mdt_announcements` WHERE `id` = ? AND `removed` = 0', { aid })
        if not r then return false, 'No such announcement' end
        if not c.staff and r.deptId ~= c.dept.id then return false, 'That belongs to another department' end
        if d.act == 'pin' then
            MySQL.update.await('UPDATE `es_mdt_announcements` SET `pinned` = 1 - `pinned` WHERE `id` = ?', { aid })
        elseif d.act == 'remove' then
            MySQL.update.await('UPDATE `es_mdt_announcements` SET `removed` = 1 WHERE `id` = ?', { aid })
        else return false, 'Unknown action' end
        MDT.log(c, 'announce_' .. d.act, { id = aid })
        MDT.refresh('announce')
        return true
    end)

    -- report templates
    cb('templates', { rate = 300, burst = 6 }, function(c)
        local list, edit = templatesFor(c)
        return { list = list, canEdit = edit }
    end)

    cb('templateSave', { write = true, rate = 1000, burst = 3 }, function(c, d)
        if not canTemplates(c) then return false, 'Only leaders can manage templates' end
        local name = str(d.name, 60)
        if #name < 2 then return false, 'Name the template' end
        local okType = false
        for _, t in ipairs(Config.ReportTypes) do if t.key == d.type then okType = true end end
        local typ = okType and d.type or 'incident'
        local tid = id(d.id)
        if tid then
            local n = MySQL.update.await('UPDATE `es_mdt_templates` SET `name` = ?, `type` = ?, `title` = ?, `body` = ? WHERE `id` = ? AND `deptId` = ?',
                { name, typ, str(d.title, 120), str(d.body, 6000), tid, c.dept.id })
            if (tonumber(n) or 0) == 0 then return false, 'No such template' end
        else
            local cnt = MySQL.single.await('SELECT COUNT(*) AS `n` FROM `es_mdt_templates` WHERE `deptId` = ?', { c.dept.id })
            if cnt and (tonumber(cnt.n) or 0) >= 40 then return false, 'A department can keep 40 templates' end
            tid = MySQL.insert.await('INSERT INTO `es_mdt_templates` (`deptId`,`name`,`type`,`title`,`body`,`createdBy`) VALUES (?,?,?,?,?,?)',
                { c.dept.id, name, typ, str(d.title, 120), str(d.body, 6000), c.charId })
        end
        MDT.log(c, 'template_save', { id = tid })
        return { id = tid }
    end)

    cb('templateDelete', { write = true, rate = 1000, burst = 3 }, function(c, d)
        if not canTemplates(c) then return false, 'Only leaders can manage templates' end
        local tid = id(d.id)
        local n = tid and MySQL.update.await('DELETE FROM `es_mdt_templates` WHERE `id` = ? AND `deptId` = ?', { tid, c.dept.id })
        if (tonumber(n) or 0) == 0 then return false, 'No such template' end
        MDT.log(c, 'template_delete', { id = tid })
        return true
    end)

    -- 2.0.0: jail through the jail bridge (server/jail.lua): es_jail, any registered jail script, or none
    cb('jailStatus', { rate = 500, burst = 4 }, function()
        local p, name = EsJail.provider()
        return { installed = p ~= nil, provider = name }
    end)

    -- 1.5.5: the Jail tab (es_jail): who is inside, who ran, who just walked out
    cb('jailList', { rate = 500, burst = 4 }, function(c)
        local ok, rows, name, live = pcall(EsJail.inmates, 3)
        if not ok then return false, 'The jail did not answer' end
        for _, r in ipairs(rows or {}) do
            if not r.name then r.name = MDT.namesOf({ r.charId })[r.charId] or ('#' .. tostring(r.charId)) end
            if r.jailedBy and not r.byName then r.byName = MDT.namesOf({ r.jailedBy })[r.jailedBy] end
        end
        return { installed = name ~= nil, provider = name, live = live, rows = rows or {}, canRelease = (c.staff or c.perms.jail_manage) and true or false,
            perMonth = 0 }
    end)
    cb('jailRelease', { write = true, rate = 1500, burst = 2 }, function(c, d)
        if not (c.staff or c.perms.jail_manage) then return false, 'Your rank cannot release inmates' end
        local cid = id(d.charId)
        if not cid then return false, 'Who?' end
        local ok, res, why = pcall(EsJail.release, cid, c.charId, 'released from the MDT')
        if not ok or not res then return false, why or 'Could not release them' end
        MDT.log(c, 'jail_release', { charId = cid })
        return true
    end)

    cb('sendToJail', { perm = 'mdt_reports_write', write = true, rate = 2000, burst = 2 }, function(c, d)
        local rid, cid = id(d.reportId), id(d.charId)
        if not rid or not cid then return false, 'Pick the report and the suspect' end
        local r = MySQL.single.await('SELECT `id`,`deptId`,`type` FROM `es_mdt_reports` WHERE `id` = ?', { rid })
        if not r or not MDT.canSeeReport(c, r) then return false, 'No such report' end
        local m = MySQL.single.await('SELECT COALESCE(SUM(`months` * `count`), 0) AS `m` FROM `es_mdt_report_charges` WHERE `reportId` = ? AND `charId` = ?', { rid, cid })
        local months = m and tonumber(m.m) or 0
        if months <= 0 then return false, 'No jail time on this report for that person' end
        local charges = MySQL.query.await('SELECT `code`,`title`,`count` FROM `es_mdt_report_charges` WHERE `reportId` = ? AND `charId` = ?', { rid, cid }) or {}
        local ok, res = pcall(EsJail.send, { charId = cid, months = months, reportId = rid, origin = 'mdt', byCharId = c.charId, bySource = c.source,
            reason = ('Report #%d'):format(rid), charges = charges })
        if not ok then return false, 'The jail did not answer' end
        if res.provider and not res.ok then return false, res.why or 'The jail did not take them' end
        MDT.log(c, 'jail', { reportId = rid, charId = cid, months = months, provider = res.provider })
        return { installed = res.provider ~= nil, jailed = res.ok, recorded = true, provider = res.provider, months = months }
    end)

    -- old calls close themselves
    CreateThread(function()
        while true do
            Wait(5 * 60 * 1000)
            local rows = MySQL.query.await("SELECT `id` FROM `es_mdt_calls` WHERE `status` = 'active' AND `createdAt` < NOW() - INTERVAL ? MINUTE", { DSP.callTTLMin or 120 }) or {}
            for _, r in ipairs(rows) do
                MySQL.update.await("UPDATE `es_mdt_calls` SET `status` = 'closed', `outcome` = 'Expired', `closedAt` = NOW() WHERE `id` = ? AND `status` = 'active'", { r.id })
                WC:HideBlip('call:' .. r.id)
                local onIt = {}
                for _, u in ipairs(MySQL.query.await('SELECT `charId` FROM `es_mdt_call_units` WHERE `callId` = ?', { r.id }) or {}) do onIt[#onIt + 1] = u.charId end
                freeUnits(onIt)
                tellClosed(r.id, 'Expired')
            end
            if #rows > 0 then MDT.refresh('calls') end
            local t = now()
            for k, v in pairs(HitSeen) do if v < t - 600 then HitSeen[k] = nil end end
            for k, v in pairs(PlateCache) do if t - v.at > 600 then PlateCache[k] = nil end end
        end
    end)
end
