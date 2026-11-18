local _ENV = ESAPP('mdt'); -- es_mdt 1.3.0: dispatch (911 / 311 / AddCall), panic, live map, mugshots, announcements, report templates,
-- send-to-jail and the plate checks behind the radar's plate reader.
-- Loaded BEFORE server/main.lua; everything here runs from MDT.registerOps(), which main.lua calls from its
-- Whip.register once its own helpers (MDT.cb, MDT.dutyNow, ...) are in place.
local WC = exports.whip_core
local ED = exports.es_departments
MDT = MDT or {}

local DSP = Config.Dispatch or {}
local PAN = Config.Panic or {}
local BKP = DSP.backup or {}     -- 2.0.6
local ESC = DSP.escalate or {}   -- 2.0.6
local ALR = DSP.alerts or {}     -- 2.0.6
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
                deptId = e.g.id, deptShort = e.g.short, deptType = e.g.type, color1 = e.g.color1 }
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

--- 2.0.4: the call and panic blips on duty maps: kept here so they follow the duty list (someone going off duty loses
--- them, someone coming on gets the ones still up). [id] = { spec, gen }
local DutyBlips = {}
local blipGen = 0
local routedDuty   -- 2.0.6: below (who a call's audience reaches)
local function showDutyBlip(id, spec, secs, list, aud)
    blipGen = blipGen + 1
    local gen = blipGen
    DutyBlips[id] = { spec = spec, gen = gen, aud = aud }
    WC:ShowBlip({ people = sourcesOf(list or onDuty()) }, id, spec)
    if secs then
        SetTimeout(secs * 1000, function()
            local b = DutyBlips[id]
            if b and b.gen == gen then DutyBlips[id] = nil pcall(function() WC:HideBlip(id) end) end
        end)
    end
end
local function hideDutyBlip(id)
    DutyBlips[id] = nil
    pcall(function() WC:HideBlip(id) end)
end
--- every duty blip again, to who is on duty now (whip_core takes it off anyone no longer in the list)
local function repushDutyBlips()
    if next(DutyBlips) == nil then return end
    local all = onDuty()
    for id, b in pairs(DutyBlips) do
        -- 2.0.6: each blip to the groups its call went to
        local people = sourcesOf(b.aud and routedDuty(b.aud) or all)
        pcall(function()
            -- nobody on duty: down for now (kept here, so it comes back to whoever clocks on while it is still live)
            if #people == 0 then WC:HideBlip(id) else WC:ShowBlip({ people = people }, id, b.spec) end
        end)
    end
end
MDT.repushDutyBlips = repushDutyBlips

local KINDS = { ['911'] = true, ['311'] = true, panic = true, alert = true, officer = true,
    medical = true, shots = true, theft = true, backup = true }   -- 2.0.6: the last four
local KIND_TITLE = { ['911'] = '911 call', ['311'] = '311 call', panic = 'Officer down', officer = 'Officer call', alert = 'Alert',
    medical = 'Medical call', shots = 'Shots fired', theft = 'Vehicle theft', backup = 'Backup requested' }

-- ---------------------------------------------------------------- 2.0.6: routing (Config.Dispatch.routing)
-- A call goes to GROUPS of departments ('law', 'ems'), by its kind. A group is a list of department TYPES. Saved on the call
-- as `audience` ('law,ems'); NULL (calls from before 2.0.6) = every unit on duty, as before.
local ROUTE = DSP.routing or {}
local DEF_GROUPS = { law = { 'police', 'sheriff', 'state' }, ems = { 'ems' } }
local DEF_ROUTES = { ['911'] = { 'law', 'ems' }, ['311'] = { 'law' }, medical = { 'ems' }, panic = { 'law', 'ems' },
    backup = { 'law' }, shots = { 'law' }, theft = { 'law' }, officer = { 'law' }, alert = { 'law' } }
local function groupsCfg() return type(ROUTE.groups) == 'table' and next(ROUTE.groups) and ROUTE.groups or DEF_GROUPS end
--- the group a department type is in ('law', 'ems', ...), or nil (DOJ: no group, no calls)
local function groupOfType(t)
    if not t then return nil end
    for g, types in pairs(groupsCfg()) do
        if type(types) == 'table' then for _, x in ipairs(types) do if x == t then return g end end end
    end
    return nil
end
MDT.groupOfType = groupOfType
local function asList(v) if type(v) == 'string' then return { v } end return type(v) == 'table' and v or nil end
--- 'law,ems': the groups a call of this kind goes to (want = a group or list of groups that overrides the kind's), only
--- groups with at least one department on this server. None (no EMS department yet): Config.Dispatch.routing.fallback
--- ('law'); fallback = false: nil = every unit on duty.
local function audienceFor(kind, want)
    local list = asList(want) or (type(ROUTE.kinds) == 'table' and asList(ROUTE.kinds[kind])) or DEF_ROUTES[kind] or { 'law' }
    local have = {}
    for _, d in ipairs(ED:GetDepartments() or {}) do if d.type then have[d.type] = true end end
    local G, out, seen = groupsCfg(), {}, {}
    for _, g in ipairs(list) do
        if type(g) == 'string' and not seen[g] and type(G[g]) == 'table' then
            for _, t in ipairs(G[g]) do if have[t] then out[#out + 1] = g seen[g] = true break end end
        end
    end
    if #out == 0 then
        local fb = ROUTE.fallback
        if fb == nil then fb = 'law' end
        if type(fb) ~= 'string' or fb == '' or type(G[fb]) ~= 'table' then return nil end
        out[1] = fb
    end
    return table.concat(out, ','):sub(1, 40)
end
MDT.audienceFor = audienceFor
local function inAudience(aud, deptType)
    if aud == nil or aud == '' then return true end
    local g = groupOfType(deptType)
    if not g then return false end
    for x in aud:gmatch('[^,]+') do if x == g then return true end end
    return false
end
--- the on-duty units a call's audience reaches
routedDuty = function(aud)
    local list, idx = onDuty()
    if aud == nil or aud == '' then return list, idx end
    local out = {}
    for _, u in ipairs(list) do if inAudience(aud, u.deptType) then out[#out + 1] = u end end
    return out, idx
end
MDT.routedDuty = routedDuty
local CallAud = {}   -- [callId] = audience | false (everyone); filled when filed, read from the row after a restart
local function audOf(cid)
    local a = CallAud[cid]
    if a == nil then
        local r = MySQL.single.await('SELECT `audience` FROM `es_mdt_calls` WHERE `id` = ?', { cid })
        a = r and r.audience or false
        CallAud[cid] = a
    end
    return a or nil
end

--- 2.0.1: x, y, z from vector3 / vector4 / { x, y, z } / { [1], [2], [3] }; nil when there are none (or they are not numbers)
local function xyzOf(c)
    local t = type(c)
    if t ~= 'vector3' and t ~= 'vector4' and t ~= 'table' then return nil end
    local x, y, z
    if t == 'table' and c.x == nil and c[1] ~= nil then x, y, z = tonumber(c[1]), tonumber(c[2]), tonumber(c[3])
    else x, y, z = tonumber(c.x), tonumber(c.y), tonumber(c.z) end
    if not x or not y or x ~= x or y ~= y or math.abs(x) > 20000 or math.abs(y) > 20000 then return nil end
    if z and (z ~= z or math.abs(z) > 5000) then z = nil end
    return x + 0.0, y + 0.0, z and z + 0.0 or nil
end

--- Files a call and tells every on-duty unit. Returns the call id, or false, why.
--- d = { kind ('911'|'311'|'panic'|'alert'|'officer', else 'alert'), priority|prio (1-3),
---   title, message|desc|description, street|location, coords|pos|position (vector3/vector4/{x,y,z}),
---   callerCharId|charId, callerName|name|caller, callerPhone|phone, deptId,
---   blip = false, sprite, color, blipTime (seconds) }
--- 2.0.1: the aliases and coord forms are new; every 2.0.0 call works unchanged. A missing title falls back to the
--- kind's label, never to the caller's name.
--- 2.0.3: where a call came from ('es_jail', 'external:client', 'test'), up to 40 characters; nil when none.
--- Admins only: printed in the server console and kept in `es_mdt_calls`.`sourceLabel`, never sent to a client.
local function labelOf(d)
    local v = d.sourceLabel
    if v == nil then v = d.source end
    if v == nil then v = d.from end
    if v == nil then v = d.resource end
    if type(v) ~= 'string' then return nil end
    v = MDT.str(v, 40)
    return v ~= '' and v or nil
end

local function addCall(d)
    if type(d) ~= 'table' then return false, 'A call is a table' end
    local str, int = MDT.str, MDT.int
    local kind = KINDS[d.kind] and d.kind or 'alert'
    local x, y, z = xyzOf(d.coords or d.pos or d.position)
    local pri = int(d.priority or d.prio or (kind == 'panic' and 1 or kind == '311' and 3 or 2), 1, 3)
    local title = str(d.title, 120)
    if title == '' then title = KIND_TITLE[kind] or 'Call' end
    local message = d.message or d.desc or d.description
    local street = d.street or d.location
    local callerName = d.callerName or d.name or d.caller
    local callerPhone = d.callerPhone or d.phone
    local callerCharId = tonumber(d.callerCharId or d.charId)
    local via = labelOf(d)
    -- 2.0.6: who it goes to (d.groups = 'ems' / { 'law', 'ems' } overrides the kind's route; d.audience is es_mdt's own)
    local aud
    if type(d.audience) == 'string' and d.audience ~= '' then aud = str(d.audience, 40) else aud = audienceFor(kind, d.groups) end
    local parentId = tonumber(d.parentId)
    local cid = MySQL.insert.await([[INSERT INTO `es_mdt_calls` (`kind`,`priority`,`title`,`message`,`callerCharId`,`callerName`,`callerPhone`,`street`,`x`,`y`,`z`,`deptId`,`sourceLabel`,`audience`,`parentId`)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)]], { kind, pri, title, str(message, 500), callerCharId, str(callerName, 80),
        str(callerPhone, 20), str(street, 120), x, y, z, tonumber(d.deptId), via, aud, parentId })
    if not cid then return false, 'The call could not be saved' end
    CallAud[cid] = aud or false
    -- 2.0.3: the source is for admins only (this console and the sourceLabel column); it never goes to a client or the MDT
    if via then print(('[es_mdt] call #%d (%s, P%d) filed by %s'):format(cid, kind, pri, via)) end
    local list = routedDuty(aud)
    local payload = { id = cid, kind = kind, priority = pri, title = title, message = str(message, 200), street = str(street, 120),
        x = x, y = y, z = z, callerName = str(callerName, 80), callerPhone = str(callerPhone, 20), parentId = parentId, units = {} }
    for _, u in ipairs(list) do TriggerClientEvent('es_mdt:client:call', u.source, payload) end
    if x and y and d.blip ~= false then   -- 2.0.6: kept even with nobody on duty (whoever clocks on gets it)
        local b = DSP.blip or {}
        showDutyBlip('call:' .. cid, { coords = vector3(x, y, z or 0.0),
            label = ('#%d %s'):format(cid, title):sub(1, 40), sprite = math.tointeger(tonumber(d.sprite)) or b.sprite or 280,
            color = math.tointeger(tonumber(d.color)) or b.color or 1, flash = pri == 1 }, int(d.blipTime or b.seconds or 120, 5, 1800), list, aud)
    end
    MDT.refresh('calls')
    return cid
end
MDT.addCall = addCall

local SELF = GetCurrentResourceName()
--- The resource that called an export (nil for es_mdt itself), the label when a call names none
local function invoker()
    local r = GetInvokingResource()
    if not r or r == SELF then return nil end
    return r
end

--- exports.es_mdt:AddCall(d) -> callId | false, why   (the table above)
exports('AddCall', function(data)
    if type(data) == 'table' and data.sourceLabel == nil and data.source == nil and data.from == nil and data.resource == nil then
        local by = invoker()
        if by then local c = {} for k, v in pairs(data) do c[k] = v end c.sourceLabel = by data = c end
    end
    local ok, a, b = pcall(addCall, data)
    if not ok then print(('^3[es_mdt] AddCall failed: %s^7'):format(tostring(a))) return false, 'The call could not be filed' end
    return a, b
end)

--- exports.es_mdt:NotifyDispatch(title, message, coords?, priority?, sourceLabel?, extra?) -> callId | false, why
--- The short form: an 'alert' call. extra = any other AddCall fields (street, kind, callerName, blip, ...).
--- 2.0.1's (title, message, coords, priority, extra) still works: a table 5th argument is extra.
exports('NotifyDispatch', function(title, message, coords, priority, a5, a6)
    local label, extra = nil, nil
    if type(a5) == 'table' then extra = a5 elseif type(a5) == 'string' then label, extra = a5, a6 end
    local d = {}
    if type(extra) == 'table' then for k, v in pairs(extra) do d[k] = v end end
    if label then d.sourceLabel = label
    elseif d.sourceLabel == nil and d.source == nil and d.from == nil and d.resource == nil then d.sourceLabel = invoker() end
    d.title, d.message, d.coords = title, message, coords or d.coords
    d.priority = priority or d.priority or 2
    d.kind = d.kind or 'alert'
    local ok, a, b = pcall(addCall, d)
    if not ok then print(('^3[es_mdt] NotifyDispatch failed: %s^7'):format(tostring(a))) return false, 'The call could not be filed' end
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
    `closedBy`,UNIX_TIMESTAMP(`closedAt`) AS `closedAt`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt`,`audience`,`parentId`,`escalations`]]

--- 2.0.6: the calls a viewer's MDT lists: their group's (and the 2.0.4 ones), every call for staff, a department in no group
--- (DOJ) or routing.shared = true
local function viewerFilter(c)
    if not c or c.staff or ROUTE.shared == true then return '', {} end
    local g = groupOfType(c.dept and c.dept.type)
    if not g then return '', {} end
    return ' AND (`audience` IS NULL OR FIND_IN_SET(?, `audience`) > 0)', { g }
end
MDT.viewerFilter = viewerFilter

local function callsList(status, limit, c)
    local where, args = viewerFilter(c)
    local params = { status }
    for _, a in ipairs(args) do params[#params + 1] = a end
    params[#params + 1] = limit
    local rows = MySQL.query.await(('SELECT %s, (SELECT COUNT(*) FROM `es_mdt_call_notes` n WHERE n.`callId` = c.`id`) AS `notes` FROM `es_mdt_calls` c WHERE `status` = ?%s ORDER BY %s LIMIT ?')
        :format(CALL_COLS, where, status == 'active' and '`priority`, `id` DESC' or '`id` DESC'), params) or {}
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
--- 2.0.6: the card's unit list is { cs = callsign, name, st = status, dept } per unit (it was callsign text), to the call's audience
local function cardUnits(u)
    local out = {}
    for _, x in ipairs(u or {}) do out[#out + 1] = { cs = x.callsign, name = x.name, st = x.status, dept = x.deptShort } end
    return out
end
MDT.cardUnits = cardUnits
local function tellUnits(cid)
    local units = cardUnits(unitsOfCalls({ cid })[cid])
    for _, o in ipairs(routedDuty(audOf(cid))) do TriggerClientEvent('es_mdt:client:callUnits', o.source, { id = cid, units = units }) end
end
local function tellClosed(cid, outcome)
    for _, o in ipairs(routedDuty(audOf(cid))) do TriggerClientEvent('es_mdt:client:callClosed', o.source, { id = cid, outcome = outcome }) end
end

--- 2.0.3: a call is closed or gone: its map blip goes for everyone at once (not only when the blip's time runs out),
--- and a panic call takes its PANIC blip and the officer's panic flag with it.
local PanicCall = {}   -- [charId] = the call id of their last panic
local function callGone(cid)
    cid = tonumber(cid)
    if not cid then return end
    hideDutyBlip('call:' .. cid)
    for charId, pc in pairs(PanicCall) do
        if pc == cid then
            PanicCall[charId] = nil
            if MDT.Panic then MDT.Panic[charId] = nil end
            hideDutyBlip('panic:' .. charId)
            MDT.refresh('units')
        end
    end
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
    -- 2.0.6: an 'Officer down' P1 (Config.Panic.title), to the groups Config.Dispatch.routing gives 'panic' (law + EMS).
    -- No health / dead / ragdoll check anywhere: a downed or dead officer can press it (the callback is whileDead), and
    -- the position is the body's.
    local who = ('%s %s'):format(me.u.callsign or '', me.u.name or ''):gsub('^%s+', '')
    local aud = audienceFor('panic')
    local callId = addCall({ kind = 'panic', priority = 1, title = ('%s · %s'):format(MDT.str(PAN.title, 40) ~= '' and MDT.str(PAN.title, 40) or 'OFFICER DOWN', who),
        street = street, coords = pos, audience = aud,
        message = ('Officer %s (%s) pressed the panic button'):format(who, me.g.short or ''), callerCharId = c.charId,
        callerName = me.u.name, deptId = me.g.id, blip = false })
    if callId then PanicCall[c.charId] = callId end
    local list = routedDuty(aud)
    local b = PAN.blip or {}
    showDutyBlip('panic:' .. c.charId, { coords = vector3(pos.x, pos.y, pos.z),
        label = ('PANIC %s'):format(me.u.callsign or ''):sub(1, 40), sprite = b.sprite or 161, color = b.color or 1, flash = true, scale = 1.2 }, nil, list, aud)
    local payload = { charId = c.charId, callsign = me.u.callsign, name = me.u.name, deptShort = me.g.short, street = MDT.str(street, 120),
        x = pos.x, y = pos.y, callId = callId, seconds = secs }
    for _, u in ipairs(list) do TriggerClientEvent('es_mdt:client:panic', u.source, payload) end
    SetTimeout(secs * 1000, function()
        if (MDT.Panic[c.charId] or 0) <= now() then
            MDT.Panic[c.charId] = nil
            hideDutyBlip('panic:' .. c.charId)
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
-- ---------------------------------------------------------------- 2.0.3: closing a call, test calls

--- 2.0.4: what an officer picks when closing a call (Config.Dispatch.outcomes: plain strings, or { label, color, icon, note })
local DEFAULT_OUTCOMES = {
    { label = 'Resolved', color = '#22c55e', icon = '✔' }, { label = 'Handled on scene', color = '#14b8a6', icon = '⚑' },
    { label = 'Unfounded', color = '#6b7fd7', icon = '∅' }, { label = 'No contact', color = '#f59e0b', icon = '☏' },
    { label = 'Suspect gone', color = '#f97316', icon = '➜' }, { label = 'Other', color = '#a855f7', icon = '✎', note = 'required' },
}
local AUTO_NONE, AUTO_TIMEOUT = 'Auto-closed – no response', 'Auto-closed (timeout)'
MDT.AUTO_NONE, MDT.AUTO_TIMEOUT = AUTO_NONE, AUTO_TIMEOUT
local function hexColor(v) return type(v) == 'string' and v:match('^#%x%x%x%x?%x?%x?$') and #v ~= 5 and v or nil end
local function outcomeList()
    local out = {}
    for _, o in ipairs(DSP.outcomes or {}) do
        local label = type(o) == 'string' and o or type(o) == 'table' and o.label or nil
        label = type(label) == 'string' and MDT.str(label, 40) or ''
        if label ~= '' then
            local t = type(o) == 'table' and o or {}
            out[#out + 1] = { label = label, color = hexColor(t.color), icon = type(t.icon) == 'string' and t.icon:sub(1, 8) or nil,
                note = (t.note == 'required' or (t.note == nil and label:lower() == 'other')) and 'required' or nil }
        end
    end
    if #out == 0 then out = DEFAULT_OUTCOMES end
    return out
end
MDT.outcomeList = outcomeList
--- the configured outcome an officer picked (any case), or nil
local function pickOutcome(v)
    v = type(v) == 'string' and v:lower():gsub('^%s+', ''):gsub('%s+$', '') or ''
    for _, o in ipairs(outcomeList()) do if o.label:lower() == v then return o end end
    return nil
end

--- Close a call from any path (MDT button, auto-close, CloseCall export, /mdttestcall clear): the row, the units on it,
--- its blips, every on-duty popup, the MDT lists. -> true | false, why
--- 2.0.4: silent = true (auto-close, test clean-up): no popup / toast / sound for anyone; the blip, GPS route and card
--- still go (es_mdt:client:callGone) and the MDT lists still update.
local function closeCall(cid, outcome, note, byCharId, onlyIf, silent)
    cid = tonumber(cid)
    if not cid then return false, 'No such call' end
    local str = MDT.str
    outcome = str(outcome, 40); if outcome == '' then outcome = 'Closed' end
    local n = MySQL.update.await(("UPDATE `es_mdt_calls` SET `status` = 'closed', `outcome` = ?, `closeNote` = NULLIF(?, ''), `closedBy` = ?, `closedAt` = NOW() WHERE `id` = ? AND `status` = 'active'%s")
        :format(onlyIf or ''), { outcome, str(note, 500), tonumber(byCharId), cid })
    if (tonumber(n) or 0) < 1 then return false, 'That call is not active' end
    local onIt = {}
    for _, u in ipairs(MySQL.query.await('SELECT `charId` FROM `es_mdt_call_units` WHERE `callId` = ?', { cid }) or {}) do onIt[#onIt + 1] = u.charId end
    freeUnits(onIt)
    callGone(cid)
    MDT.refresh('calls')
    if not silent then tellClosed(cid, outcome) end
    -- everyone (on duty or not any more): drop a GPS route still pointing at this call, quietly
    TriggerClientEvent('es_mdt:client:callGone', -1, { id = cid })
    return true
end
MDT.closeCall = closeCall

--- 2.0.4: auto-close. Every active call older than Config.Dispatch.autoCloseMinutes is closed SILENTLY (no popup, toast or
--- sound; blip, GPS route and card go; the call stays in the history with its outcome and a note):
---   * no unit on it now           -> closed at autoCloseMinutes (or at callTTLMin when autoCloseMinutes = 0)
---   * a unit on it now            -> left open (it is being worked) unless autoCloseAttached = true; callTTLMin is the hard cap
---   * a PANIC call with a unit on -> never
--- Outcome: 'Auto-closed – no response' when no unit ever attached, 'Auto-closed (timeout)' when one did (even if it left).
--- -> how many calls it closed
local NO_UNITS = ' AND NOT EXISTS (SELECT 1 FROM `es_mdt_call_units` u WHERE u.`callId` = `es_mdt_calls`.`id`)'
local function autoCloseSweep()
    local mins = tonumber(DSP.autoCloseMinutes)
    if mins == nil then mins = 15 end
    local cap = tonumber(DSP.callTTLMin) or 120
    if mins <= 0 and cap <= 0 then return 0 end
    local oldest = (mins > 0 and cap > 0) and math.min(mins, cap) or (mins > 0 and mins or cap)
    local rows = MySQL.query.await([[SELECT c.`id`, c.`kind`, c.`everAttached`, TIMESTAMPDIFF(SECOND, c.`createdAt`, NOW()) AS `age`,
        (SELECT COUNT(*) FROM `es_mdt_call_units` u WHERE u.`callId` = c.`id`) AS `onIt`
        FROM `es_mdt_calls` c WHERE c.`status` = 'active' AND c.`createdAt` <= NOW() - INTERVAL ? MINUTE]], { oldest }) or {}
    local closed = 0
    for _, r in ipairs(rows) do
        local age = (tonumber(r.age) or 0) / 60
        local onIt = (tonumber(r.onIt) or 0) > 0
        local close
        if onIt then
            close = r.kind ~= 'panic' and ((DSP.autoCloseAttached == true and mins > 0 and age >= mins) or (cap > 0 and age >= cap))
        else
            close = (mins > 0 and age >= mins) or (cap > 0 and age >= cap)
        end
        if close then
            local ever = onIt or r.everAttached == true or tonumber(r.everAttached) == 1   -- oxmysql reads TINYINT(1) as a boolean
            local outcome = ever and AUTO_TIMEOUT or AUTO_NONE
            local note = ('Closed automatically after %d min%s'):format(math.floor(age + 0.5), ever and '' or ' (no unit attached)')
            -- a unit attaching right now keeps an unattended call open (the guard is in the UPDATE itself)
            if closeCall(r.id, outcome, note, nil, not onIt and NO_UNITS or nil, true) then
                closed = closed + 1
                print(('[es_mdt] call #%d auto-closed: %s'):format(r.id, outcome))
            end
        end
    end
    return closed
end
MDT.autoCloseSweep = autoCloseSweep

--- 2.0.4: an officer leaves duty (clock off, log out or disconnect: WHIP's clockedOff covers all three). Off the active calls
--- they were on (a note says why), off the call / panic blips, and their own game drops the call's GPS route and card.
local function unitGone(charId, source)
    charId = tonumber(charId)
    if not charId then return end
    local _, idx = MDT.dutyNow()
    if idx[charId] then return end   -- still on duty in another department
    local rows = MySQL.query.await([[SELECT u.`callId` FROM `es_mdt_call_units` u JOIN `es_mdt_calls` c ON c.`id` = u.`callId`
        WHERE u.`charId` = ? AND c.`status` = 'active']], { charId }) or {}
    for _, r in ipairs(rows) do
        MySQL.update.await('DELETE FROM `es_mdt_call_units` WHERE `callId` = ? AND `charId` = ?', { r.callId, charId })
        MySQL.insert.await('INSERT INTO `es_mdt_call_notes` (`callId`,`byCharId`,`note`) VALUES (?,?,?)', { r.callId, charId, 'Detached (went off duty)' })
        tellUnits(r.callId)
    end
    if #rows > 0 then MDT.refresh('calls') end
    repushDutyBlips()
    if source and GetPlayerName(source) then TriggerClientEvent('es_mdt:client:offDuty', source) end
end
MDT.unitGone = unitGone
AddEventHandler('whip_core:job:clockedOff', function(e)
    if type(e) ~= 'table' then return end
    local cid, src = e.charId, tonumber(e.source)
    SetTimeout(250, function() local ok, err = pcall(unitGone, cid, src) if not ok then print(('^3[es_mdt] off-duty clean-up failed: %s^7'):format(tostring(err))) end end)
end)
AddEventHandler('whip_core:job:clockedOn', function() SetTimeout(250, function() pcall(repushDutyBlips) end) end)

--- exports.es_mdt:CloseCall(callId, outcome?, note?) -> true | false, why   (outcome defaults to 'Closed')
exports('CloseCall', function(cid, outcome, note)
    local ok, a, b = pcall(closeCall, cid, outcome, note, nil)
    if not ok then print(('^3[es_mdt] CloseCall failed: %s^7'):format(tostring(a))) return false, 'The call could not be closed' end
    return a, b
end)

local TEST_SPOT = { x = 195.17, y = -933.77, z = 30.69, street = 'Legion Square' }
--- A clearly marked TEST call (label 'test') near the player, or at Legion Square. -> callId | false, why
local function testCall(kind, priority, source)
    kind = KINDS[kind] and kind or 'alert'
    local pos, street = nil, TEST_SPOT.street
    if source and source > 0 then
        pos = coordsOf(source)
        street = 'Near ' .. (GetPlayerName(source) or ('player ' .. source))
    end
    pos = pos or { x = TEST_SPOT.x, y = TEST_SPOT.y, z = TEST_SPOT.z }
    return addCall({ kind = kind, priority = tonumber(priority), title = 'TEST · ' .. (KIND_TITLE[kind] or 'Call'),
        message = 'Test call: no response needed. Remove with /mdttestcall clear.', street = street, coords = pos,
        callerName = 'Dispatch test', sourceLabel = 'test' })
end

--- exports.es_mdt:TestCall(kind?, priority?) -> callId | false, why
exports('TestCall', function(kind, priority)
    local ok, a, b = pcall(testCall, kind, priority, nil)
    if not ok then print(('^3[es_mdt] TestCall failed: %s^7'):format(tostring(a))) return false, 'The test call could not be filed' end
    return a, b
end)

--- Close and delete every test call (label 'test'). -> how many
local function clearTestCalls()
    local rows = MySQL.query.await("SELECT `id`,`status` FROM `es_mdt_calls` WHERE `sourceLabel` = 'test'") or {}
    for _, r in ipairs(rows) do
        if r.status == 'active' then closeCall(r.id, 'Test removed', nil, nil, " AND `sourceLabel` = 'test'", true) end
        callGone(r.id)
    end
    if #rows > 0 then
        MySQL.update.await("DELETE FROM `es_mdt_calls` WHERE `sourceLabel` = 'test'")
        MDT.refresh('calls')
    end
    return #rows
end
MDT.clearTestCalls = clearTestCalls

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

-- ---------------------------------------------------------------- 2.0.6: request backup

local BackupCool = {}
--- An officer on duty asks for backup: a 'backup' call at THEIR position (not the call's), linked to the call they are on
--- (callId; they must be attached) or on its own (callId nil). P1 when the call is a panic or P1, else Config.Dispatch.backup.priority.
--- It goes where the call went (or by the 'backup' route); a note on the call says so. -> { id, priority, units } | false, why
local function requestBackup(c, callId, street)
    if BKP.enabled == false then return false, 'Backup requests are off' end
    local _, idx = MDT.dutyNow()
    local me = idx[c.charId]
    if not me then return false, 'Go on duty to request backup' end
    if (BackupCool[c.charId] or 0) > now() then return false, ('Backup was just requested, wait %d s'):format(BackupCool[c.charId] - now()) end
    local r
    if callId then
        r = MySQL.single.await('SELECT `id`,`kind`,`priority`,`status`,`title`,`street`,`audience` FROM `es_mdt_calls` WHERE `id` = ?', { callId })
        if not r then return false, 'No such call' end
        if r.status ~= 'active' then return false, 'That call is closed' end
        local on = MySQL.single.await('SELECT 1 AS `x` FROM `es_mdt_call_units` WHERE `callId` = ? AND `charId` = ?', { callId, c.charId })
        if not on then return false, 'Attach to the call to request backup on it' end
    end
    local pos = coordsOf(c.source)
    if not pos then return false, 'Your position could not be read' end
    local urgent = r and (r.kind == 'panic' or tonumber(r.priority) == 1)
    local pri = MDT.int(urgent and (BKP.urgentPriority or 1) or (BKP.priority or 2), 1, 3)
    BackupCool[c.charId] = now() + math.max(5, tonumber(BKP.cooldown) or 45)
    local who = ('%s %s'):format(me.u.callsign or '', me.u.name or ''):gsub('^%s+', '')
    street = MDT.str(street, 120)
    if street == '' and r then street = r.street or '' end
    local title = r and ('Backup · #%d %s'):format(r.id, r.title or '') or ('Backup · %s'):format(who)
    local newId, why = addCall({ kind = 'backup', priority = pri, title = MDT.str(title, 120), street = street, coords = pos,
        message = ('%s (%s) requests backup%s'):format(who, me.g.short or '', r and (' on call #' .. r.id) or ''),
        callerCharId = c.charId, callerName = me.u.name, deptId = me.g.id, parentId = r and r.id or nil,
        audience = r and r.audience or nil })   -- none: the 'backup' route
    if not newId then BackupCool[c.charId] = nil return false, why end
    if r then
        MySQL.insert.await('INSERT INTO `es_mdt_call_notes` (`callId`,`byCharId`,`note`) VALUES (?,?,?)',
            { r.id, c.charId, ('Backup requested (P%d) · call #%d'):format(pri, newId) })
    end
    MDT.log(c, 'call_backup', { callId = r and r.id or nil, backupId = newId, priority = pri })
    MDT.refresh('calls')
    return { id = newId, priority = pri, units = #routedDuty(audOf(newId)) }
end
MDT.requestBackup = requestBackup

-- ---------------------------------------------------------------- 2.0.6: shots fired / vehicle theft
-- From the game (es_mdt:server:autoAlert: Config.Dispatch.alerts, chance, cooldowns, on-duty law exempt) or from other
-- scripts (exports ShotsFired / VehicleTheft: always filed). One call per area: a second report near an active one of the
-- same kind, while it is fresh, adds a note to it (at most every 30 s) instead of a new call.
local DEF_QUIET = { { x = 13.5, y = -1097.4, r = 20.0 }, { x = 821.5, y = -2163.6, r = 20.0 } }   -- the Ammu-Nation ranges
local function quietZone(pos)
    for _, z in ipairs(type(ALR.quietZones) == 'table' and ALR.quietZones or DEF_QUIET) do
        local zx, zy = tonumber(z.x or z[1]), tonumber(z.y or z[2])
        if zx and zy and dist2(pos, { x = zx, y = zy }) <= (tonumber(z.r or z.radius) or 20) then return true end
    end
    return false
end
local function nearbyAlert(kind, pos)
    local area = ALR.area or {}
    local radius, secs = tonumber(area.radius) or 150, tonumber(area.seconds) or 120
    if radius <= 0 or secs <= 0 then return nil end
    local rows = MySQL.query.await([[SELECT `id`,`x`,`y` FROM `es_mdt_calls` WHERE `status` = 'active' AND `kind` = ? AND `x` IS NOT NULL
        AND `createdAt` >= NOW() - INTERVAL ? SECOND ORDER BY `id` DESC LIMIT 20]], { kind, math.floor(secs) }) or {}
    for _, r in ipairs(rows) do if dist2(pos, r) <= radius then return r.id end end
    return nil
end
local MoreNoted = {}
--- -> callId, merged (true when it went onto an existing call) | false, why
local function autoAlert(kind, pos, info)
    info = info or {}
    local cfg = ALR[kind] or {}
    if not pos then return false, 'No position' end
    if quietZone(pos) then return false, 'Quiet zone' end
    local near = nearbyAlert(kind, pos)
    if near then
        if (MoreNoted[near] or 0) < now() - 30 then
            MoreNoted[near] = now()
            local more = kind == 'shots' and 'More shots reported nearby'
                or ('Another vehicle theft reported nearby%s'):format(info.plate and info.plate ~= '' and (' · plate ' .. info.plate) or '')
            MySQL.insert.await('INSERT INTO `es_mdt_call_notes` (`callId`,`byCharId`,`note`) VALUES (?,?,?)', { near, nil, more })
            MDT.refresh('calls')
        end
        return near, true
    end
    local title = MDT.str(cfg.title, 60)
    if title == '' then title = KIND_TITLE[kind] end
    local msg
    if kind == 'shots' then msg = 'Gunshots heard in the area'
    else
        local plate, model = info.plate or '', MDT.str(info.model, 40)
        msg = ('%s seen being stolen%s'):format(model ~= '' and model or 'A vehicle', plate ~= '' and (' · plate ' .. plate) or '')
    end
    return addCall({ kind = kind, priority = MDT.int(cfg.priority or (kind == 'shots' and 2 or 3), 1, 3), title = title, message = msg,
        street = info.street, coords = pos, callerName = 'Witness', sourceLabel = info.label,
        blipTime = tonumber(cfg.blipSeconds) or nil, color = kind == 'theft' and 47 or nil })
end
MDT.autoAlert = autoAlert

--- exports.es_mdt:ShotsFired(coords, opts?) -> callId, merged | false, why   opts = { street }
exports('ShotsFired', function(coords, opts)
    local x, y, z = xyzOf(coords)
    if not x then return false, 'Give coords (vector3 or { x, y, z })' end
    opts = type(opts) == 'table' and opts or {}
    local ok, a, b = pcall(autoAlert, 'shots', { x = x, y = y, z = z }, { street = type(opts.street) == 'string' and opts.street or nil,
        label = invoker() or 'export:ShotsFired' })
    if not ok then print(('^3[es_mdt] ShotsFired failed: %s^7'):format(tostring(a))) return false, 'The alert could not be filed' end
    return a, b
end)
--- exports.es_mdt:VehicleTheft(coords, plate?, model?, opts?) -> callId, merged | false, why   opts = { street }
exports('VehicleTheft', function(coords, plate, model, opts)
    local x, y, z = xyzOf(coords)
    if not x then return false, 'Give coords (vector3 or { x, y, z })' end
    opts = type(opts) == 'table' and opts or {}
    local ok, a, b = pcall(autoAlert, 'theft', { x = x, y = y, z = z }, { street = type(opts.street) == 'string' and opts.street or nil,
        plate = plateKey(plate), model = type(model) == 'string' and model or nil, label = invoker() or 'export:VehicleTheft' })
    if not ok then print(('^3[es_mdt] VehicleTheft failed: %s^7'):format(tostring(a))) return false, 'The alert could not be filed' end
    return a, b
end)

-- ---------------------------------------------------------------- 2.0.6: priority escalation
--- An active call with NO unit on it for Config.Dispatch.escalate.minutes (since it came in or last went up) goes up one
--- priority (P3 -> P2 -> P1, never past escalate.top, never a panic). The MDT lists update quietly; with realert = true the
--- units it was routed to get a soft re-alert (es_mdt:client:callEscalated). -> how many went up
local function escalateSweep()
    if ESC.enabled == false then return 0 end
    local mins = tonumber(ESC.minutes) or 5
    if mins <= 0 then return 0 end
    local top = math.max(1, math.min(3, math.floor(tonumber(ESC.top) or 1)))
    local rows = MySQL.query.await([[SELECT c.`id`, c.`priority`, c.`kind`, c.`title`, c.`street`, c.`x`, c.`y`, c.`z`, c.`audience`
        FROM `es_mdt_calls` c WHERE c.`status` = 'active' AND c.`kind` <> 'panic' AND c.`priority` > ?
        AND NOT EXISTS (SELECT 1 FROM `es_mdt_call_units` u WHERE u.`callId` = c.`id`)
        AND COALESCE(c.`escalatedAt`, c.`createdAt`) <= NOW() - INTERVAL ? MINUTE]], { top, mins }) or {}
    local n = 0
    for _, r in ipairs(rows) do
        local from = tonumber(r.priority) or 3
        local to = math.max(top, from - 1)
        local done = MySQL.update.await([[UPDATE `es_mdt_calls` SET `priority` = ?, `escalations` = `escalations` + 1, `escalatedAt` = NOW()
            WHERE `id` = ? AND `status` = 'active' AND `priority` = ?]] .. NO_UNITS, { to, r.id, from })
        if (tonumber(done) or 0) > 0 then
            n = n + 1
            CallAud[r.id] = r.audience or false
            MySQL.insert.await('INSERT INTO `es_mdt_call_notes` (`callId`,`byCharId`,`note`) VALUES (?,?,?)',
                { r.id, nil, ('Escalated P%d → P%d: no unit after %d min'):format(from, to, mins) })
            print(('[es_mdt] call #%d escalated P%d -> P%d (no unit)'):format(r.id, from, to))
            local list = routedDuty(r.audience)
            local b = DutyBlips['call:' .. r.id]
            if b and to == 1 and not b.spec.flash then
                b.spec.flash = true
                pcall(function() WC:ShowBlip({ people = sourcesOf(list) }, 'call:' .. r.id, b.spec) end)
            end
            if ESC.realert ~= false then
                local payload = { id = r.id, priority = to, from = from, title = r.title, street = r.street, x = r.x, y = r.y, z = r.z, kind = r.kind }
                for _, u in ipairs(list) do TriggerClientEvent('es_mdt:client:callEscalated', u.source, payload) end
            end
        end
    end
    if n > 0 then MDT.refresh('calls') end
    return n
end
MDT.escalateSweep = escalateSweep

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

--- 2.0.4: priority: normal / important / urgent
local ANN_LEVEL = { normal = true, important = true, urgent = true }
local function annLevel(v) return ANN_LEVEL[v] and v or 'normal' end
local function announcementsFor(c, limit, onlyUrgentHours)
    local extra, args = '', { c.dept.id }
    if onlyUrgentHours then extra = " AND `level` = 'urgent' AND `createdAt` > NOW() - INTERVAL ? HOUR" args[#args + 1] = onlyUrgentHours end
    args[#args + 1] = limit
    local rows = MySQL.query.await(([[SELECT `id`,`deptId`,`title`,`body`,`pinned`,`level`,`createdBy`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt`,
        UNIX_TIMESTAMP(`expiresAt`) AS `expiresAt` FROM `es_mdt_announcements` WHERE `removed` = 0 AND (`deptId` = ? OR `deptId` IS NULL)
        AND (`expiresAt` IS NULL OR `expiresAt` > NOW())%s ORDER BY `pinned` DESC, (`level` = 'urgent') DESC, `id` DESC LIMIT ?]]):format(extra), args) or {}
    local ids = {}
    for _, r in ipairs(rows) do ids[#ids + 1] = r.createdBy end
    local names = MDT.namesOf(ids)
    local short = MDT.deptShort()
    for _, r in ipairs(rows) do
        r.by = names[r.createdBy] or ('#' .. r.createdBy)
        r.pinned = r.pinned == 1 or r.pinned == true
        r.level = annLevel(r.level)
        r.all = r.deptId == nil
        r.deptShort = r.deptId and short[r.deptId] and short[r.deptId].short or 'ALL'
        r.canEdit = c.staff or (c.perms.announce and r.deptId == c.dept.id)
    end
    return rows
end

--- 2.0.4: urgent announcements still fresh (Config.Announcements.urgentFreshHours, default 12): shown once to an on-duty
--- member when their MDT opens (the page remembers which ones they have seen)
function MDT.urgentAnnouncements(c)
    if not (c and c.dept and c.onDuty) then return {} end
    local h = tonumber((Config.Announcements or {}).urgentFreshHours) or 12
    if h <= 0 then return {} end
    local ok, rows = pcall(announcementsFor, c, 5, h)
    return ok and rows or {}
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
    out.calls = callsList('active', 6, c)
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
        -- 2.0.6: 'medical' (Config.Dispatch.medical command) goes to EMS by the routing
        local kind = (d.kind == '311' or d.kind == 'medical') and d.kind or '911'
        local name = MDT.namesOf({ cid })[cid]
        local callId = addCall({ kind = kind, priority = kind == '311' and 3 or 2,
            title = kind == '311' and '311 · non-emergency' or kind == 'medical' and '911 · medical' or '911 · emergency',
            message = msg, street = str(d.street, 120), coords = pos, callerCharId = cid, callerName = name, callerPhone = phoneOf(cid) })
        if not callId then return false, 'Dispatch did not answer, try again' end
        return { id = callId, units = #routedDuty(audOf(callId)) }
    end)

    -- 2.0.1: es_mdt:server:externalCall, for CLIENT scripts that want to file a call (server scripts use the exports).
    -- Only a player on duty in a department, or in one of Config.Dispatch.external.jobs; never a panic; rate limited;
    -- the caller is always the sender (name, phone and character come from the server, not from the data).
    local EXT = DSP.external or {}
    if EXT.enabled ~= false then
        local okKinds = {}
        for _, k in ipairs(EXT.kinds or { '911', '311', 'alert', 'officer' }) do if KINDS[k] and k ~= 'panic' then okKinds[k] = true end end
        local okJobs = {}
        for _, j in ipairs(EXT.jobs or {}) do okJobs[j] = true end
        local perMin = math.max(1, math.floor(tonumber(EXT.perMinute) or 5))
        ExtSent = {}   -- [source] = { times sent in the last minute } (reset when whip_core re-registers)
        local Sent = ExtSent
        if not ExtDropHooked then ExtDropHooked = true AddEventHandler('playerDropped', function() if ExtSent then ExtSent[source] = nil end end) end
        local function allowed(source)
            if EXT.onDuty ~= false then
                for _, d in ipairs(ED:GetPlayerDepartments(source) or {}) do if d.onDuty then return true end end
            end
            if next(okJobs) then
                local job = WC:GetPlayerJob(source)
                if job and okJobs[job.key] then return true end
            end
            return false
        end
        Whip.core:SecureEvent('es_mdt:server:externalCall', { rateLimit = math.max(1, math.floor(tonumber(EXT.cooldownSec) or 10)) * 1000, burst = 1,
            sheet = 'light', params = { { 'data', 'any' } } }, function(source, _, data)
            if type(data) ~= 'table' then return false, 'A call is a table' end
            if not allowed(source) then return false, 'Only units on duty can file calls this way' end
            if data.kind == 'panic' then return false, 'Use the panic button for a panic' end
            local t, list = now(), Sent[source] or {}
            local keep = {}
            for _, at in ipairs(list) do if t - at < 60 then keep[#keep + 1] = at end end
            if #keep >= perMin then Sent[source] = keep return false, 'Too many calls, wait a minute' end
            keep[#keep + 1] = t; Sent[source] = keep
            local s = function(v) return type(v) == 'string' and v or nil end
            local cid = WC:GetCharId(source)
            local x, y, z = xyzOf(data.coords or data.pos or data.position)
            local pos = (x and { x = x, y = y, z = z }) or coordsOf(source)
            local callId, why = addCall({
                kind = okKinds[data.kind] and data.kind or 'alert',
                priority = MDT.int(data.priority or data.prio or 2, 1, 3),
                title = MDT.str(s(data.title), 120), message = MDT.str(s(data.message or data.desc or data.description), 500),
                street = MDT.str(s(data.street or data.location), 120), coords = pos,
                callerCharId = cid, callerName = cid and MDT.namesOf({ cid })[cid] or nil, callerPhone = phoneOf(cid),
                blip = data.blip ~= false,
                sourceLabel = 'external:client',   -- set here; any label in the data is ignored (a client cannot prove its resource)
            })
            if not callId then return false, why end
            print(('[es_mdt] externalCall #%d from %s (%s)'):format(callId, tostring(source), GetPlayerName(source) or '?'))
        end)
    end

    -- 2.0.3: /mdttestcall [kind] [priority] | /mdttestcall clear   (server console, or staff: es_mdt.departments.manage)
    Whip.command('mdttestcall', { rateLimit = { burst = 2, everyMs = 3000 }, whileDead = true }, function(source, args)
        local function reply(msg, kind)
            if source == 0 then print('[es_mdt] ' .. msg) else WC:NotifyPlayer(source, msg, kind or 'inform') end
        end
        if source ~= 0 and not (ED:IsStaff(source) == true) then return reply('Staff only (es_mdt.departments.manage)', 'error') end
        local a1 = (args[1] or ''):lower()
        if a1 == 'clear' then return reply(('Test calls removed: %d'):format(clearTestCalls()), 'success') end
        local kind, pri = a1, args[2]
        if tonumber(a1) and not KINDS[a1] then kind, pri = 'alert', a1 end   -- /mdttestcall 1
        if kind == '' then kind = 'alert' end
        if not KINDS[kind] then return reply('Kinds: 911, 311, alert, officer, panic', 'error') end
        local cid, why = testCall(kind, pri, source)
        if not cid then return reply(why or 'The test call could not be filed', 'error') end
        reply(('TEST call #%d filed (%s). /mdttestcall clear removes test calls.'):format(cid, kind), 'success')
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
        local rows = callsList(status, status == 'closed' and 50 or 100, c)
        local names = {}
        for _, r in ipairs(rows) do if r.closedBy then names[#names + 1] = r.closedBy end end
        names = MDT.namesOf(names)
        for _, r in ipairs(rows) do r.closedByName = r.closedBy and names[r.closedBy] or nil end
        return { calls = rows, outcomes = outcomeList(), now = now() }
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
        -- 2.0.6: backup (attached officers), the linked calls
        r.canBackup = r.status == 'active' and r.attached and c.onDuty and BKP.enabled ~= false
        if r.parentId then
            local p = MySQL.single.await('SELECT `id`,`title`,`status` FROM `es_mdt_calls` WHERE `id` = ?', { r.parentId })
            r.parent = p
        end
        r.backups = MySQL.query.await("SELECT `id`,`priority`,`status`,`street`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt` FROM `es_mdt_calls` WHERE `parentId` = ? AND `kind` = 'backup' ORDER BY `id`", { cid }) or {}
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
        MySQL.update.await('UPDATE `es_mdt_calls` SET `everAttached` = 1 WHERE `id` = ?', { cid })
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
        MySQL.update.await('UPDATE `es_mdt_calls` SET `everAttached` = 1 WHERE `id` = ?', { cid })   -- 2.0.4: kept after a detach
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
        return { id = cid, x = r.x, y = r.y }   -- 2.0.4: the client remembers it, to clear it when the call closes
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
        -- 2.0.4: one of the configured outcomes; a note when it asks for one (Other)
        local pick = pickOutcome(d.outcome)
        if not pick then return false, 'Pick an outcome' end
        local outcome, note = pick.label, str(d.note, 500)
        if pick.note == 'required' and #note < 3 then return false, ('Add a note for "%s"'):format(outcome) end
        local ok, why = closeCall(cid, outcome, note, c.charId)
        if not ok then return false, why end
        MDT.log(c, 'call_close', { callId = cid, outcome = outcome })
        return true
    end)

    cb('panic', { rate = 1000, burst = 2, whileDead = true }, function(c, d) return panic(c, d.street) end)   -- a downed officer can still press it

    -- 2.0.6: request backup (the MDT call, the /backup command; a downed officer can still ask)
    cb('callBackup', { write = true, rate = 2000, burst = 2, whileDead = true }, function(c, d)
        return requestBackup(c, id(d.id), d.street)
    end)

    -- 2.0.6: the game saw shots / a theft (the position is the server's, never the report's)
    local AlertCool = {}
    if not AlertDropHooked then AlertDropHooked = true AddEventHandler('playerDropped', function() if AlertCoolRef then AlertCoolRef['shots:' .. source] = nil AlertCoolRef['theft:' .. source] = nil end end) end
    AlertCoolRef = AlertCool
    Whip.core:SecureEvent('es_mdt:server:autoAlert', { rateLimit = 3000, burst = 2, sheet = 'light', params = { { 'd', 'any' } } }, function(source, _, d)
        if type(d) ~= 'table' then return false, 'Bad report' end
        local kind = (d.kind == 'shots' or d.kind == 'theft') and d.kind or nil
        if not kind then return false, 'Bad report' end
        local cfg = ALR[kind] or {}
        if cfg.enabled == false then return end
        if ALR.exemptLaw ~= false and lawOnDuty(source) then return end
        local key = kind .. ':' .. source
        if (AlertCool[key] or 0) > now() then return end
        local pos = coordsOf(source)
        if not pos then return end
        AlertCool[key] = now() + math.max(5, tonumber(cfg.cooldown) or (kind == 'shots' and 45 or 90))
        local chance = tonumber(cfg.chance)
        if chance == nil then chance = 1 end
        if math.random() > chance then return end
        local plate, model
        if kind == 'theft' then
            plate, model = plateKey(d.plate), str(d.model, 40)
            -- the owner taking their own car is not a theft
            local cid = WC:GetCharId(source)
            if plate ~= '' and cid and MySQL.single.await("SELECT 1 AS `x` FROM `vehicles` WHERE REPLACE(`plate`,' ','') = ? AND `ownerCharId` = ? LIMIT 1", { plate, cid }) then return end
        end
        autoAlert(kind, pos, { street = str(d.street, 120), plate = plate, model = model, label = 'auto:' .. kind })
    end)

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
        local level = annLevel(d.level)
        local body = str(d.body, 2000)
        local aid = MySQL.insert.await(('INSERT INTO `es_mdt_announcements` (`deptId`,`title`,`body`,`pinned`,`level`,`createdBy`,`expiresAt`) VALUES (?,?,?,?,?,?,%s)')
            :format(hours > 0 and 'NOW() + INTERVAL ? HOUR' or 'NULL'),
            hours > 0 and { not all and c.dept.id or nil, title, body, d.pinned and 1 or 0, level, c.charId, hours }
            or { not all and c.dept.id or nil, title, body, d.pinned and 1 or 0, level, c.charId })
        if not aid then return false, 'It could not be posted' end
        local payload = { id = aid, title = title, by = c.name, deptShort = all and 'ALL' or c.dept.short, level = level,
            body = level ~= 'normal' and str(body, 160) or nil, createdAt = now() }
        local seen = {}
        for _, d2 in ipairs(all and (ED:GetDepartments() or {}) or { c.dept }) do
            for _, u in ipairs(ED:GetOnDuty(d2.id) or {}) do
                if u.source and not seen[u.source] then seen[u.source] = true TriggerClientEvent('es_mdt:client:announce', u.source, payload) end
            end
        end
        MDT.log(c, 'announce', { id = aid, all = all, level = level })
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
    -- 2.0.4: the auto-close sweep (silent; see autoCloseSweep), and the caches' clean-up every 5 minutes
    CreateThread(function()
        local every = math.max(15, tonumber(DSP.sweepSeconds) or 60)
        local lastClean = now()
        while true do
            Wait(every * 1000)
            local ok, err = pcall(autoCloseSweep)
            if not ok then print(('^3[es_mdt] auto-close sweep failed: %s^7'):format(tostring(err))) end
            ok, err = pcall(escalateSweep)   -- 2.0.6: after the auto-close (a call closing now is not re-alerted)
            if not ok then print(('^3[es_mdt] escalation sweep failed: %s^7'):format(tostring(err))) end
            local t = now()
            if t - lastClean >= 300 then
                lastClean = t
                for k, v in pairs(HitSeen) do if v < t - 600 then HitSeen[k] = nil end end
                for k, v in pairs(PlateCache) do if t - v.at > 600 then PlateCache[k] = nil end end
            end
        end
    end)
end
