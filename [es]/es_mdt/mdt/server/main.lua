local _ENV = ESAPP('mdt'); -- es_mdt server. Who you are in the MDT comes from es_departments: your department, rank and its permissions.
--   Reports belong to a department; warrants and BOLOs are shared by every department; fines go to the
--   issuing department's job account. Off duty the MDT opens read-only (Config.OffDutyReadOnly).
--   Every call is a SecureCallback 'es_mdt:<name>' with one table argument, checked by hand below.

local WC = exports.whip_core
local ED = exports.es_departments

local Units = {}   -- [charId] = { status, at }
local Pick  = {}   -- [source] = deptId the player chose in the switcher
local Cache = {}   -- [source] = { at, ctx }
-- 2.0.10: a player's MDT context (department, permissions, rights) is kept 30 s. It is dropped at once when WHIP says
-- their job changed (clock on / off, hired, fired, rank) and for everyone when a job or department is edited.
local CTX_MS = 30000
local function dropAllCtx() for k in pairs(Cache) do Cache[k] = nil end end
local dutyDrop   -- 2.0.10: drops the 1 s on-duty list (set below, used by the job events above it)

local PERMS = { 'mdt_view', 'mdt_reports_write', 'mdt_reports_delete', 'warrants_request', 'warrants_issue', 'fines_issue',
    'bolo_manage', 'fto_train', 'fto_manage', 'loa_manage', 'canHire', 'canFire', 'canPromote', 'canDemote', 'canManage',
    'weapons_register', 'weapons_manage', 'licenses_manage', 'announce', 'evidence_collect', 'evidence_lab', 'evidence_manage', 'cases_create', 'cases_close', 'jail_cuff', 'jail_manage', 'personnel_manage', 'permits_manage',
    -- 2.1.0: roadside tickets and impound (added to every law department's permission list by departments/server/main.lua)
    'tickets_issue', 'impound_vehicle', 'impound_hold', 'impound_override', 'impound_lot' }

-- ---------------------------------------------------------------- helpers

local function trim(s) return (type(s) == 'string' and (s:gsub('^%s+', ''):gsub('%s+$', ''))) or '' end
local function str(v, max) return trim(type(v) == 'string' and v or (type(v) == 'number' and tostring(v) or '')):gsub('[%c]', function(ch) return (ch == '\n' or ch == '\t') and ch or '' end):sub(1, max) end
local function int(v, lo, hi) v = math.floor(tonumber(v) or 0) if v < lo then v = lo end if v > hi then v = hi end return v end
local function id(v) v = tonumber(v) return (v and v >= 1 and v == math.floor(v) and v < 4294967295) and v or nil end
--- training item keys from the page: short word strings only, 200 at most
local function keyList(v)
    local out = {}
    if type(v) ~= 'table' then return out end
    for _, k in ipairs(v) do
        if type(k) == 'string' and #k <= 16 and k:match('^[%w_]+$') and #out < 200 then out[#out + 1] = k end
    end
    return out
end

local function marks(n) local m = {} for i = 1, n do m[i] = '?' end return table.concat(m, ',') end

local function namesOf(ids)
    local uniq, list = {}, {}
    for _, x in ipairs(ids) do if x and not uniq[x] then uniq[x] = true list[#list + 1] = x end end
    if #list == 0 then return {} end
    local out = {}
    for i = 1, #list, 200 do
        local part = {}
        for j = i, math.min(i + 199, #list) do part[#part + 1] = list[j] end
        for k, v in pairs(WC:GetCharacterNames(part) or {}) do out[tonumber(k) or k] = v end
    end
    return out
end

local function deptShort()
    local out = {}
    for _, d in ipairs(ED:GetDepartments() or {}) do out[d.id] = d end
    return out
end

local function log(c, what, detail)
    CreateThread(function() WC:LogActivity(c.source, 'es_mdt_' .. what, { detail = detail }) end)
end

--- 2.0.10: "this list changed, look again" goes only to who can be looking: on-duty units, and anyone who used the MDT in
--- the last 75 s (an open MDT asks the server something at least every 30 s), not to every player on the server.
local Seen = {}   -- [source] = GetGameTimer() of their last MDT request
local SEEN_MS = 75000
local function refresh(what)
    local ok, _, idx = pcall(function() return MDT.dutyNow() end)
    if not ok or type(idx) ~= 'table' then return TriggerClientEvent('es_mdt:client:refresh', -1, what) end
    local now, sent = GetGameTimer(), {}
    for _, e in pairs(idx) do
        local src = tonumber(e.u and e.u.source)
        if src and not sent[src] then sent[src] = true TriggerClientEvent('es_mdt:client:refresh', src, what) end
    end
    for src, at in pairs(Seen) do
        if now - at > SEEN_MS then Seen[src] = nil
        elseif not sent[src] then sent[src] = true TriggerClientEvent('es_mdt:client:refresh', src, what) end
    end
end

--- [charId] = source for everyone loaded
local function onlineByChar()
    local out = {}
    for src, p in pairs(WC:GetPlayers({ light = true }) or {}) do
        if type(p) == 'table' and p.charId then out[p.charId] = tonumber(src) end
    end
    return out
end

local function notifyChar(charId, text, kind, online)
    local src = (online or onlineByChar())[charId]
    if src then WC:NotifyPlayer(src, text, kind or 'info', 8000) end
end

--- Members of a department holding a job permission (charIds)
local function holdersOf(dept, perm)
    local out = {}
    for _, m in ipairs(ED:GetRoster(dept.id) or {}) do
        if m.owner or WC:HasJobPermission({ charId = m.charId }, dept.jobId, perm, { onDuty = false }) == true then out[#out + 1] = m.charId end
    end
    return out
end

-- ---------------------------------------------------------------- paired units (two officers, one unit)
-- Teams[id] = { id, type = 'patrol'|'fto', lead, partner, status, at, startedAt, fto, trainee, deptId, names, calls, src }
-- TeamOf[charId] = id. Invites[toCharId] = { from, mode = 'invite'|'join', type, at }. Rides[ftoCharId] = { ride, ... }
-- (ride-alongs that ended and still need their notes). All in memory: a restart ends every unit.
local Teams, TeamOf, Invites, Rides = {}, {}, {}, {}
local Panic = {}   -- [charId] = os.time() the panic alarm ends (1.3.0)
local teamSeq, rideSeq = 0, 0
local INVITE_TTL = 90

local function inviteFor(charId)
    local iv = Invites[charId]
    if iv and os.time() - iv.at > INVITE_TTL then Invites[charId] = nil iv = nil end
    return iv
end

--- End a unit. why: 'left' | 'offduty' | 'dropped' | 'gone'; by = the charId it is about
local function dissolve(tid, why, by)
    local t = Teams[tid]
    if not t then return end
    Teams[tid] = nil
    local online = onlineByChar()
    for _, cid in ipairs({ t.lead, t.partner }) do
        if TeamOf[cid] == tid then TeamOf[cid] = nil end
        Units[cid] = { status = t.status, at = os.time() }
        if cid ~= by then
            local who = t.names[by] or 'Your partner'
            local text = why == 'left' and ('%s left the unit') or why == 'offduty' and ('%s went off duty: the unit ended')
                or why == 'dropped' and ('%s disconnected: the unit ended') or 'Your unit ended'
            notifyChar(cid, text:format(who), 'inform', online)
        end
    end
    if t.type == 'fto' and t.fto and t.trainee then
        rideSeq = rideSeq + 1
        local ride = { id = rideSeq, deptId = t.deptId, traineeCharId = t.trainee, traineeName = t.names[t.trainee],
            minutes = math.max(1, math.floor((os.time() - t.startedAt) / 60 + 0.5)), startedAt = t.startedAt, endedAt = os.time() }
        Rides[t.fto] = Rides[t.fto] or {}
        table.insert(Rides[t.fto], ride)
        local src = online[t.fto]
        if src then
            WC:NotifyPlayer(src, ('Ride-along with %s ended (%d min). Write it up in the MDT: Training.'):format(ride.traineeName or 'your trainee', ride.minutes), 'inform', 10000)
            TriggerClientEvent('es_mdt:client:ride', src, ride)
        end
    end
    refresh('units')
end

local function dissolveOf(charId, why)
    local tid = TeamOf[charId]
    if tid then dissolve(tid, why, charId) end
end

-- ---------------------------------------------------------------- who is asking

local function ctxOf(source)
    local hit = Cache[source]
    if hit and GetGameTimer() - hit.at < CTX_MS then return hit.ctx end   -- 2.0.10: 30 s (was 3), dropped at once on any change below
    local charId = WC:GetCharId(source)
    if not charId then return false, 'No character' end
    local staff = ED:IsStaff(source) == true
    local list = ED:GetPlayerDepartments(source) or {}
    if #list == 0 and staff then
        for _, d in ipairs(ED:GetDepartments() or {}) do list[#list + 1] = d end
    end
    if #list == 0 then return false, 'You are not in a department' end
    local d
    for _, x in ipairs(list) do if x.id == Pick[source] then d = x end end
    if not d then for _, x in ipairs(list) do if x.onDuty then d = x break end end end
    d = d or list[1]
    local perms = {}
    for _, p in ipairs(PERMS) do
        perms[p] = staff or WC:HasJobPermission(source, d.jobId, p, { onDuty = false }) == true
    end
    local rights = ED:GetRights(source, d.id) or {}
    local names = namesOf({ charId })
    local c = {
        source = source, charId = charId, name = names[charId] or ('#' .. charId), staff = staff,
        dept = d, depts = list, perms = perms, rights = rights, myLevel = d.roleLevel or rights.myLevel or 0,
        onDuty = d.onDuty == true,
        readOnly = Config.OffDutyReadOnly and d.onDuty ~= true and not staff,
    }
    Cache[source] = { at = GetGameTimer(), ctx = c }
    return c
end

-- 2.0.10: a job edited in /whip (its roles' permissions), or a department / rank / roster changed in /departments
AddEventHandler('whip_core:job:updated', function() dropAllCtx() dutyDrop() end)
AddEventHandler('es_departments:server:changed', function() dropAllCtx() dutyDrop() end)

AddEventHandler('playerDropped', function()
    local src = source
    dutyDrop()
    Seen[src] = nil
    local c = Cache[src] and Cache[src].ctx
    Cache[src] = nil Pick[src] = nil
    for tid, t in pairs(Teams) do
        for cid, s2 in pairs(t.src) do if s2 == src then dissolve(tid, 'dropped', cid) break end end
    end
    if c and c.charId then Invites[c.charId] = nil Units[c.charId] = nil end
    refresh('units')
end)
for _, ev in ipairs({ 'whip_core:job:clockedOn', 'whip_core:job:clockedOff', 'whip_core:job:roleChanged', 'whip_core:job:fired', 'whip_core:job:hired' }) do
    AddEventHandler(ev, function(e)
        if type(e) == 'table' and e.source then Cache[e.source] = nil end
        dutyDrop()
        if ev == 'whip_core:job:clockedOff' and type(e) == 'table' and e.charId then
            dissolveOf(e.charId, 'offduty')
            Invites[e.charId] = nil
            Units[e.charId] = nil
        end
        if ev:find('clocked') then
            refresh('units')
            -- their own MDT header (on duty / read-only) follows at once
            if type(e) == 'table' and e.source then TriggerClientEvent('es_mdt:client:refresh', e.source, 'dept') end
        end
    end)
end

--- 1.9.0: es_doj's judge-only mode (Config.Warrants.judgeOnly there): warrants wait for a judge's signature
local function judgeOnly()
    if GetResourceState('es_doj') ~= 'started' then return false end
    local ok, r = pcall(function() return exports.es_doj:WarrantsNeedJudge() end)
    return ok and r == true
end

--- 1.9.0: es_doj court orders on reports: { [reportId] = 'sealed' | 'expunged' } for this person ({} without es_doj)
local function courtMarks(cid)
    if not cid or GetResourceState('es_doj') ~= 'started' then return {} end
    local ok, m = pcall(function() return exports.es_doj:GetCourtMarks('report', nil, cid) end)
    return ok and type(m) == 'table' and m or {}
end
local function notExpunged(marksMap, col)
    local ids = {}
    for rid, mode in pairs(marksMap) do if mode == 'expunged' and tonumber(rid) then ids[#ids + 1] = math.floor(tonumber(rid)) end end
    if #ids == 0 then return '' end
    return (' AND %s NOT IN (%s)'):format(col, table.concat(ids, ','))
end

--- nil when allowed, else the reason
local function need(c, perm, write)
    if write and c.readOnly then return 'You are off duty: the MDT is read-only' end
    if perm and not c.perms[perm] then return 'Your rank cannot do that' end
    return nil
end

-- 1.8.0: multi-user safety. Each saved report / case gets a version (memory). The editor sends the version it opened;
-- a save from an older one is refused with who saved in between, so nobody overwrites another officer's changes.
-- Editing (presence): who has the same thing open in an editor right now.
local Ver, Editing = {}, {}
local function verOf(k) return Ver[k] and Ver[k].n or 0 end
local function verCheck(k, ver, c)
    local cur = Ver[k]
    ver = tonumber(ver)
    if not cur or ver == nil or cur.n <= ver or cur.by == c.charId then return nil end
    local ago = math.max(1, os.time() - cur.at)
    return ('%s saved changes %s ago, after you opened it. Copy what you typed, go back and open it again.'):format(cur.name or 'Someone',
        ago < 60 and (ago .. ' s') or (math.floor(ago / 60) .. ' min'))
end
local function bump(k, c) Ver[k] = { n = verOf(k) + 1, by = c.charId, name = c.name, at = os.time() } end

local function cb(name, opts, fn)
    if opts.lock then
        local inner, kind = fn, opts.lock
        fn = function(c, d)
            local rid = id(d.id)
            local k = rid and (kind .. ':' .. rid)
            if k then
                local no = verCheck(k, d.ver, c)
                if no then return false, no end
            end
            local a, b = inner(c, d)
            if a and k then bump(k, c) end
            if a and k and Editing[k] then Editing[k][c.charId] = nil end
            return a, b
        end
    end
    Whip.core:SecureCallback('es_mdt:' .. name, { rateLimit = opts.rate or 200, burst = opts.burst or 8, sheet = 'light',
        whileDead = opts.whileDead or nil, params = { { 'd', 'any' } } }, function(source, _, d)
        local c, why = ctxOf(source)
        if not c then return false, why end
        Seen[source] = GetGameTimer()
        if not (c.perms.mdt_view or c.staff or opts.anyRank) then return false, 'Your rank cannot use the MDT' end
        if opts.perm or opts.write then
            local no = need(c, opts.perm, opts.write)
            if no then return false, no end
        end
        return fn(c, type(d) == 'table' and d or {})
    end)
end

-- ---------------------------------------------------------------- weapons (helpers)

local W = Config.Weapons or {}
local WSTATUS = { registered = true, stolen = true, seized = true, destroyed = true }
local WROLES = { seized = true, used = true, found = true, evidence = true }

--- A serial as typed: letters/digits/dash, upper case, 4-32 long (whip_gunny makes 12 A-Z0-9)
local function serialOf(v)
    local s = (str(v, 40):upper():gsub('[^A-Z0-9%-]', ''))
    return (#s >= 4 and #s <= 32) and s or nil
end

local function likeOf(q) return '%' .. (q:gsub('[%%_\\]', '\\%0')) .. '%' end

--- [itemKey] = label for every registrable weapon item: whip_gunny guns (the ones with the Open action / a caliber row),
--- melee too when Config.Weapons.includeMelee. Built once, on first use (item defs are all registered by then).
local GunDefs
local function gunDefs()
    if GunDefs then return GunDefs end
    local out, n = {}, 0
    for key, def in pairs(WC:GetItemDefs() or {}) do
        if type(def) == 'table' and def.type == 'weapon' and def.defaultAction == 'whip_gunny:equip_weapon' then
            local gun = false
            for _, o in ipairs(type(def.contextOptions) == 'table' and def.contextOptions or {}) do
                if type(o) == 'table' and o.action == 'whip_gunny:open_weapon' then gun = true end
            end
            for _, f in ipairs(type(def.metaFields) == 'table' and def.metaFields or {}) do
                if type(f) == 'table' and f.key == 'caliber' then gun = true end
            end
            local melee = not gun and not def.stack and not def.fuelCapacity
            if gun or (W.includeMelee and melee) then out[key] = def.name or key n = n + 1 end
        end
    end
    if n > 0 then GunDefs = out end   -- nothing yet (whip_gunny not up): try again next time
    return out
end

local function weaponTypes()
    local list = {}
    for k, label in pairs(gunDefs()) do list[#list + 1] = { item = k, label = label } end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

local function weaponLog(weaponId, byCharId, what, detail, reportId)
    return { query = 'INSERT INTO `es_mdt_weapon_log` (`weaponId`,`byCharId`,`what`,`detail`,`reportId`) VALUES (?,?,?,?,?)',
        values = { weaponId, byCharId, what, tostring(detail or ''):sub(1, 500), reportId } }
end

local function closeWeaponBolos(serial, byCharId)
    local n = MySQL.update.await("UPDATE `es_mdt_bolos` SET `status` = 'closed', `closedBy` = ? WHERE `kind` = 'weapon' AND `serial` = ? AND `status` = 'active'",
        { byCharId, serial }) or 0
    if n > 0 then refresh('bolos') end
    return n
end

-- ---------------------------------------------------------------- open / context

local function openData(c)
    local depts = {}
    for _, x in ipairs(c.depts) do
        depts[#depts + 1] = { id = x.id, short = x.short, name = x.name, color1 = x.color1, color2 = x.color2, logoVer = x.logoVer,
            roleName = x.roleName, onDuty = x.onDuty == true }
    end
    local d = c.dept
    return {
        me = { charId = c.charId, name = c.name, callsign = d.callsign, badge = d.badge, roleName = d.roleName, roleLevel = c.myLevel,
            status = (Teams[TeamOf[c.charId] or 0] or {}).status or (Units[c.charId] or {}).status or 'available' },
        dept = { id = d.id, short = d.short, name = d.name, color1 = d.color1, color2 = d.color2, logoVer = d.logoVer, type = d.type },
        depts = depts, perms = c.perms, rights = c.rights, staff = c.staff, onDuty = c.onDuty, readOnly = c.readOnly,
        urgent = MDT.urgentAnnouncements and MDT.urgentAnnouncements(c) or {},   -- 2.0.4: shown once when the MDT opens
        trainee = ED:IsTrainee(d.id, c.charId) == true,
        court = GetResourceState('es_doj') == 'started',   -- 1.10.0: the Court (DOJ) page in the nav
        config = { statuses = Config.UnitStatuses, reportTypes = Config.ReportTypes, personFlags = Config.PersonFlags,
            vehicleFlags = Config.VehicleFlags, dept = ED:GetConfig(),
            chargeOverride = { maxFineMult = (Config.ChargeOverride or {}).maxFineMult or 1.0, maxMonthsMult = (Config.ChargeOverride or {}).maxMonthsMult or 1.0 },
            unpaidFineWarrantDays = Config.UnpaidFineWarrantDays or 0, highCommandLevel = Config.HighCommandLevel or 80,
            weaponTypes = weaponTypes(), licenseTypes = W.licenseTypes or { 'Firearm' }, boloOnStolen = W.boloOnStolen ~= false,
            outcomes = MDT.outcomeList and MDT.outcomeList() or {}, mapRefreshMs = Config.MapRefreshMs or 3000,
            liveMap = MDT.liveMapPage and MDT.liveMapPage() or nil,   -- 2.0.9
            panicKey = (Config.Panic or {}).key or '', panicCommand = (Config.Panic or {}).command or 'panic',
            reportTemplates = Config.ReportTemplates or {}, mugshotRange = (Config.Mugshots or {}).range or 6,
            esEvidence = GetResourceState('es_evidence') == 'started', devTools = EsSuite.DevTools == true },   -- 1.11.1: es_evidence parts hidden when it is off
    }
end

-- ---------------------------------------------------------------- units

--- Who is on duty right now, by department. Only characters clocked on AND in the game: nobody off duty shows.
--- idx[charId] = { g = group, u = unit }
--- 2.0.10: the part that asks other code (departments, who is clocked on, names) is kept for 1 s and dropped at once on
--- a clock on / off, rank, roster or department change; every call still gets its own fresh tables (callers change them)
--- and the unit's status as it is now.
local DutyRaw, DutyAt = nil, -1e9
dutyDrop = function() DutyRaw = nil end
local function dutyRaw()
    if DutyRaw and GetGameTimer() - DutyAt < 1000 then return DutyRaw end
    local depts, seen, ids = {}, {}, {}
    for _, d in ipairs(ED:GetDepartments() or {}) do
        local rd = { g = { id = d.id, jobId = d.jobId, short = d.short, name = d.name, type = d.type, color1 = d.color1, logoVer = d.logoVer }, units = {} }
        for _, u in ipairs(ED:GetOnDuty(d.id) or {}) do
            if u.source and not seen[u.charId] and WC:IsPlayerClockedOn({ charId = u.charId }, d.jobId) == true then
                seen[u.charId] = true
                rd.units[#rd.units + 1] = { charId = u.charId, source = u.source, callsign = u.callsign, roleName = u.roleName, roleLevel = u.roleLevel }
                ids[#ids + 1] = u.charId
            end
        end
        depts[#depts + 1] = rd
    end
    DutyRaw, DutyAt = { depts = depts, names = namesOf(ids) }, GetGameTimer()
    return DutyRaw
end
local function dutyNow()
    local raw = dutyRaw()
    local groups, idx = {}, {}
    for _, rd in ipairs(raw.depts) do
        local g = {}
        for k, v in pairs(rd.g) do g[k] = v end
        g.units = {}
        for _, u in ipairs(rd.units) do
            local st = Units[u.charId] or {}
            local x = { charId = u.charId, source = u.source, callsign = u.callsign, roleName = u.roleName, roleLevel = u.roleLevel,
                status = st.status or 'available', since = st.at, name = raw.names[u.charId] or ('#' .. u.charId) }
            g.units[#g.units + 1] = x
            idx[u.charId] = { g = g, u = x }
        end
        groups[#groups + 1] = g
    end
    return groups, idx
end

--- A paired unit's card: one card, both officers
local function teamCard(t, idx)
    local L, P = idx[t.lead], idx[t.partner]
    local members = {}
    for _, e in ipairs({ L, P }) do
        local cid = e.u.charId
        members[#members + 1] = { charId = cid, name = e.u.name, callsign = e.u.callsign, roleName = e.u.roleName,
            deptId = e.g.id, deptShort = e.g.short, color1 = e.g.color1,
            role = t.type == 'fto' and (cid == t.fto and 'FTO' or 'Trainee') or (cid == t.lead and 'Lead' or 'Partner') }
    end
    return { charId = t.lead, team = { id = t.id, type = t.type, members = members, startedAt = t.startedAt },
        callsign = (L.u.callsign or '—') .. ' / ' .. (P.u.callsign or '—'), name = L.u.name .. ' & ' .. P.u.name,
        roleName = t.type == 'fto' and 'FTO ride-along' or 'Patrol unit', status = t.status, since = t.at }
end

local function unitsAll()
    local groups, idx = dutyNow()
    -- a unit whose member is no longer on duty here ends (catches anything the events missed)
    for tid, t in pairs(Teams) do
        if not idx[t.lead] or not idx[t.partner] then dissolve(tid, 'gone', idx[t.lead] and t.partner or t.lead) end
    end
    local out = {}
    for _, g in ipairs(groups) do
        local list, people = {}, 0
        for _, u in ipairs(g.units) do
            local t = Teams[TeamOf[u.charId] or 0]
            if not t then list[#list + 1] = u people = people + 1
            elseif t.lead == u.charId then list[#list + 1] = teamCard(t, idx) people = people + 2 end
        end
        local now = os.time()
        for _, u in ipairs(list) do
            u.source = nil
            if (Panic[u.charId] or 0) > now then u.panic = true end
            if u.team then for _, m in ipairs(u.team.members) do if (Panic[m.charId] or 0) > now then u.panic = true end end end
        end
        table.sort(list, function(a, b) return (a.callsign or 'zz') < (b.callsign or 'zz') end)
        if #list > 0 then
            out[#out + 1] = { id = g.id, short = g.short, name = g.name, color1 = g.color1, logoVer = g.logoVer, units = list, people = people }
        end
    end
    return out, idx
end

-- ---------------------------------------------------------------- fines

-- ---------------------------------------------------------------- 1.3.6: warrant BOLOs
-- An active warrant posts a person BOLO and one vehicle BOLO per car the suspect owns (each only if no active BOLO
-- already covers it), linked by es_mdt_bolos.warrantId. They close when the warrant is served, voided or expires.
-- Runs after every warrant change and on the unpaid-fine timer (which catches expiry).
local WB = Config.WarrantBolos or {}
local function wbLog(actor, what, detail)
    print(('[es_mdt] %s: %s'):format(what, detail))
    CreateThread(function() pcall(function() WC:LogActivity(actor and actor.source or 0, 'es_mdt_' .. what, { detail = detail }) end) end)
end
--- 1.5.7: who a system-made warrant is from. Escape warrants (es_jail) come from the prison, never a player:
--- "Escaped from Bolingbroke Penitentiary with ..." -> 'Bolingbroke Penitentiary'. Works for rows made before 1.5.7 too.
local function systemIssuer(w)
    if type(w) ~= 'table' or type(w.reason) ~= 'string' or w.reason:sub(1, 12) ~= 'Escaped from' then return nil end
    if w.issuedBy and w.issuedBy ~= 0 then return nil end           -- a person signed it: theirs
    local place = w.reason:match('^Escaped from (.-) with ') or w.reason:match('^Escaped from (.-)%.')
    if not place or place == '' or place == 'prison' then place = (Config.EscapeIssuer or 'Department of Corrections') end
    return place
end
local function isImg(v) return type(v) == 'string' and #v < 400000 and v:sub(1, 11) == 'data:image/' end
--- 1.5.6: the face for a person BOLO
local function boloFace(cid)
    local m = MySQL.single.await([[SELECT m.`image` FROM `es_mdt_profiles` pr JOIN `es_mdt_mugshots` m ON m.`id` = pr.`mugshotId` WHERE pr.`charId` = ?]], { cid })
    if m and isImg(m.image) then return m.image end
    m = MySQL.single.await('SELECT `image` FROM `es_mdt_mugshots` WHERE `charId` = ? ORDER BY `id` DESC LIMIT 1', { cid })
    if m and isImg(m.image) then return m.image end
    m = MySQL.single.await('SELECT `image` FROM `character_portraits` WHERE `charId` = ?', { cid })
    if m and isImg(m.image) then return m.image end
    return nil
end
local function plateKeyOf(p) return (type(p) == 'string' and p or ''):upper():gsub('[^A-Z0-9]', '') end

local function warrantBolos(actor)
    if WB.enabled == false then return end
    local changed = false
    -- 1.5.6: close first, so a BOLO about to close (an older warrant just served) never stops a new warrant's BOLO
    -- warrant over (served / void / expired): its BOLOs close
    local over = MySQL.query.await([[SELECT b.`id`, b.`warrantId`, w.`status` FROM `es_mdt_bolos` b JOIN `es_mdt_warrants` w ON w.`id` = b.`warrantId`
        WHERE b.`status` = 'active' AND (w.`status` IN ('served','void') OR (w.`expiresAt` IS NOT NULL AND w.`expiresAt` <= NOW()))]]) or {}
    if #over > 0 then
        local ids, by = {}, {}
        for _, b in ipairs(over) do
            ids[#ids + 1] = b.id
            by[b.warrantId] = by[b.warrantId] or { st = b.status, ids = {} }
            table.insert(by[b.warrantId].ids, b.id)
        end
        MySQL.update.await(('UPDATE `es_mdt_bolos` SET `status` = \'closed\', `closedBy` = NULLIF(?,0) WHERE `id` IN (%s) AND `status` = \'active\''):format(marks(#ids)),
            { actor and actor.charId or 0, table.unpack(ids) })
        for wid, x in pairs(by) do
            wbLog(actor, 'warrant_bolos_closed', ('warrant #%d %s: BOLO #%s'):format(wid, x.st == 'active' and 'expired' or x.st, table.concat(x.ids, ', #')))
        end
        changed = true
    end
    local rows = MySQL.query.await([[SELECT `id`,`deptId`,`charId`,`reason`,`auto`, COALESCE(`issuedBy`,`requestedBy`) AS `byChar`
        FROM `es_mdt_warrants` WHERE `status` = 'active' AND `kind` = 'arrest' AND `bolosPosted` = 0 AND (`expiresAt` IS NULL OR `expiresAt` > NOW()) ORDER BY `id` LIMIT 100]]) or {}
    for _, w in ipairs(rows) do
        -- claim it first: two passes at once never post twice
        local claimed = MySQL.update.await('UPDATE `es_mdt_warrants` SET `bolosPosted` = 1 WHERE `id` = ? AND `bolosPosted` = 0', { w.id })
        local auto = w.auto == 1 or w.auto == true
        if (tonumber(claimed) or 0) > 0 and not (auto and WB.autoFineWarrants == false) then
            local name = namesOf({ w.charId })[w.charId] or ('#' .. w.charId)
            local reason = (w.reason or ''):sub(1, 300)
            local posted = {}
            if WB.person ~= false then
                local has = MySQL.single.await("SELECT `id` FROM `es_mdt_bolos` WHERE `kind` = 'person' AND `charId` = ? AND `status` = 'active' AND (`expiresAt` IS NULL OR `expiresAt` > NOW()) LIMIT 1", { w.charId })
                if not has then
                    local bid = MySQL.insert.await([[INSERT INTO `es_mdt_bolos` (`deptId`,`kind`,`charId`,`title`,`description`,`createdBy`,`expiresAt`,`warrantId`)
                        VALUES (?,'person',?,?,?,?,(SELECT `expiresAt` FROM `es_mdt_warrants` WHERE `id` = ?),?)]],
                        { w.deptId, w.charId, ('Wanted: %s (warrant #%d)'):format(name, w.id):sub(1, 120),
                          ('Active warrant #%d. %s'):format(w.id, reason), w.byChar, w.id, w.id })
                    if bid then posted[#posted + 1] = 'person #' .. bid end
                end
            end
            if WB.vehicles ~= false then
                local cars = MySQL.query.await([[SELECT v.`plate`, COALESCE(k.`displayName`, v.`model`) AS `label` FROM `vehicles` v
                    LEFT JOIN `vehicle_catalog` k ON k.`model` = v.`model` WHERE v.`ownerCharId` = ? ORDER BY v.`vehicleId` LIMIT ?]],
                    { w.charId, tonumber(WB.maxVehicles) or 10 }) or {}
                for _, v in ipairs(cars) do
                    local key = plateKeyOf(v.plate)
                    if key ~= '' then
                        local has = MySQL.single.await([[SELECT `id` FROM `es_mdt_bolos` WHERE `kind` = 'vehicle' AND `status` = 'active'
                            AND (`expiresAt` IS NULL OR `expiresAt` > NOW()) AND REPLACE(`plate`,' ','') = ? LIMIT 1]], { key })
                        if not has then
                            local bid = MySQL.insert.await([[INSERT INTO `es_mdt_bolos` (`deptId`,`kind`,`charId`,`plate`,`title`,`description`,`createdBy`,`expiresAt`,`warrantId`)
                                VALUES (?,'vehicle',?,?,?,?,?,(SELECT `expiresAt` FROM `es_mdt_warrants` WHERE `id` = ?),?)]],
                                { w.deptId, w.charId, (v.plate or ''):sub(1, 10), ('%s · owner wanted (warrant #%d)'):format(v.label or 'Vehicle', w.id):sub(1, 120),
                                  ('%s, registered to %s. Owner has active warrant #%d. %s'):format(v.label or 'Vehicle', name, w.id, reason), w.byChar, w.id, w.id })
                            if bid then posted[#posted + 1] = ('vehicle %s #%d'):format(v.plate, bid) end
                        end
                    end
                end
            end
            if #posted > 0 then
                changed = true
                wbLog(actor, 'warrant_bolos', ('warrant #%d (%s): %s'):format(w.id, name, table.concat(posted, ', ')))
            end
        end
    end
    if changed then
        if MDT and MDT.clearPlateCache then MDT.clearPlateCache() end
        refresh('bolos')
    end
end
local function warrantBolosSoon(actor)
    CreateThread(function()
        local ok, err = pcall(warrantBolos, actor)
        if not ok then print(('^3[es_mdt] warrant BOLOs: %s^7'):format(tostring(err))) end
    end)
end

--- An automatic "failure to pay" warrant ends with its fine: served when paid, void when the fine is voided
local function closeAutoWarrant(fineId, status)
    local n = MySQL.update.await("UPDATE `es_mdt_warrants` SET `status` = ? WHERE `fineId` = ? AND `auto` = 1 AND `status` IN ('active','requested')",
        { status == 'void' and 'void' or 'served', fineId })
    if (tonumber(n) or 0) > 0 then refresh('warrants') warrantBolosSoon(nil) end
end

--- Fines unpaid for Config.UnpaidFineWarrantDays get one automatic warrant each; paid/voided ones close theirs.
local function autoWarrants()
    local days = tonumber(Config.UnpaidFineWarrantDays) or 0
    local changed = false
    if days > 0 then
        local rows = MySQL.query.await([[SELECT f.`id`, f.`deptId`, f.`charId`, f.`reportId`, f.`amount`, f.`issuedBy` FROM `es_mdt_fines` f
            LEFT JOIN `es_mdt_warrants` w ON w.`fineId` = f.`id`
            WHERE f.`status` = 'unpaid' AND f.`contested` = 0 AND COALESCE(f.`dueAt`, f.`createdAt`) < NOW() - INTERVAL ? DAY AND w.`id` IS NULL LIMIT 200]], { days }) or {}
        for _, f in ipairs(rows) do
            local reason = ('Failure to pay: $%d (%s)'):format(f.amount, f.reportId and ('Report #' .. f.reportId) or 'Direct fine')
            local wid = MySQL.insert.await([[INSERT IGNORE INTO `es_mdt_warrants` (`deptId`,`charId`,`reportId`,`reason`,`status`,`requestedBy`,`fineId`,`auto`)
                VALUES (?,?,NULLIF(?,0),?,'active',?,?,1)]], { f.deptId, f.charId, f.reportId or 0, reason, f.issuedBy, f.id })
            if wid and wid > 0 then changed = true end
        end
    end
    local n = MySQL.update.await([[UPDATE `es_mdt_warrants` w JOIN `es_mdt_fines` f ON f.`id` = w.`fineId`
        SET w.`status` = IF(f.`status` = 'paid', 'served', 'void') WHERE w.`auto` = 1 AND w.`status` IN ('active','requested') AND f.`status` <> 'unpaid']])
    if changed or (tonumber(n) or 0) > 0 then refresh('warrants') end
    local okb, errb = pcall(warrantBolos, nil)   -- new auto warrants post theirs; served / void / expired ones close theirs
    if not okb then print(('^3[es_mdt] warrant BOLOs: %s^7'):format(tostring(errb))) end
end

--- 2.1.0: money for a paid fine goes to the issuing department's job account (Config.FineToDepartment)
--- 2.2.0: money that went into a department's account, for whip_jobs' Finances tab (a local server event: nothing moves)
local function deptIncome(jobId, amount, kind, note, charId)
    if jobId and amount and amount ~= 0 then TriggerEvent('es_mdt:server:deptIncome', jobId, amount, kind or 'fine', note, charId) end
end

local function fineToDept(fine, note)
    if not Config.FineToDepartment then return end
    local d = ED:GetDepartment(fine.deptId)
    local jaccts = d and WC:GetJobBankAccounts(d.jobId) or {}
    if jaccts[1] then
        local dok, dwhy = WC:BankSystemDeposit(jaccts[1].accountId, fine.amount, { reason = note or ('Fine #%d'):format(fine.id) })
        if not dok then print(('^3[es_mdt] fine #%d paid but the department deposit failed: %s^7'):format(fine.id, tostring(dwhy)))
        else deptIncome(d.jobId, fine.amount, fine.kind, note or ('Fine #%d'):format(fine.id), fine.charId) end
    end
end

local function payFine(fine)
    local acct = WC:GetDefaultBankAccount({ charId = fine.charId })
    if not acct then return false, 'They have no bank account' end
    local ok, why = WC:BankSystemWithdraw(acct.accountId, fine.amount, { reason = ('Fine #%d%s'):format(fine.id, fine.reason and (': ' .. fine.reason) or '') })
    if not ok then return false, why end
    MySQL.update.await("UPDATE `es_mdt_fines` SET `status` = 'paid', `paidAt` = NOW() WHERE `id` = ?", { fine.id })
    closeAutoWarrant(fine.id, 'served')
    refresh('fines')
    if MDT.onFinePaid then pcall(MDT.onFinePaid, fine.id, 'bank') end   -- 2.1.0: a ticket's / impound's own bookkeeping, the owner's text
    if Config.FineToDepartment then
        local d = ED:GetDepartment(fine.deptId)
        local jaccts = d and WC:GetJobBankAccounts(d.jobId) or {}
        if jaccts[1] then
            local dok, dwhy = WC:BankSystemDeposit(jaccts[1].accountId, fine.amount, { reason = ('Fine #%d'):format(fine.id) })
            if not dok then print(('^3[es_mdt] fine #%d paid but the department deposit failed: %s^7'):format(fine.id, tostring(dwhy)))
            else deptIncome(d.jobId, fine.amount, fine.kind, ('Fine #%d%s'):format(fine.id, fine.reason and (': ' .. fine.reason) or ''), fine.charId) end
        else
            print(('^3[es_mdt] fine #%d paid; %s has no job account, so it went to the state^7'):format(fine.id, d and d.short or '?'))
        end
    end
    for src, p in pairs(WC:GetPlayers({ light = true }) or {}) do
        if p.charId == fine.charId then WC:NotifyPlayer(tonumber(src), ('You paid a $%d fine'):format(fine.amount), 'warning', 8000) end
    end
    return true
end

--- extra (2.1.0): { kind = 'citation'|'parking'|'impound', ticketId, impoundId, quiet } for tickets.lua / impound.lua
local function issueFine(c, charId, amount, reason, reportId, extra)
    extra = extra or {}
    if amount < 1 then return false, 'No fine to issue' end
    local inv = type(Config.Invoices) == 'table' and Config.Invoices.enabled ~= false
    local due = inv and math.max(0, math.floor(tonumber(Config.Invoices.dueDays) or 3)) or 0
    local fid = MySQL.insert.await([[INSERT INTO `es_mdt_fines` (`deptId`,`charId`,`reportId`,`amount`,`reason`,`issuedBy`,`kind`,`ticketId`,`impoundId`,`dueAt`)
        VALUES (?,?,NULLIF(?,0),?,?,?,?,?,?,IF(? = 1, NOW() + INTERVAL ? DAY, NULL))]],
        { c.dept.id, charId, reportId or 0, amount, reason, c.charId, extra.kind or 'fine', extra.ticketId, extra.impoundId, inv and 1 or 0, due })
    if not fid then return false, reportId and 'That person was already fined on this report' or 'Could not save the fine' end
    -- 2.1.0: an invoice. Nothing is taken now: they pay in the court portal by the due day, or it is taken from their bank then.
    if inv then
        log(c, 'fine', ('#%d char %d $%d invoice, due in %d day(s)'):format(fid, charId, amount, due))
        refresh('fines')
        if MDT.onInvoice and not extra.quiet then pcall(MDT.onInvoice, fid) end
        return { id = fid, paid = false, invoice = true, dueDays = due }
    end
    local paid, why = payFine({ id = fid, deptId = c.dept.id, charId = charId, amount = amount, reason = reason })
    log(c, 'fine', ('#%d char %d $%d %s'):format(fid, charId, amount, paid and 'paid' or ('unpaid: ' .. tostring(why))))
    refresh('fines')
    return { id = fid, paid = paid, why = (not paid) and why or nil }
end

-- ---------------------------------------------------------------- reports

--- Is this character listed as an officer on the report? (list = the report's officers if already loaded)
local function onReport(rid, charId, list)
    if list then
        for _, o in ipairs(list) do if o.charId == charId then return true end end
        return false
    end
    return rid ~= nil and MySQL.scalar.await('SELECT 1 FROM `es_mdt_report_officers` WHERE `reportId` = ? AND `charId` = ? LIMIT 1', { rid, charId }) ~= nil
end
--- Your department's reports, plus any report you are listed on (a partner from another department)
local function canSeeReport(c, r, list) return c.staff or r.deptId == c.dept.id or onReport(r.id, c.charId, list) end
--- High command: rank level >= Config.HighCommandLevel at this department, or an admin
local function isHighCommand(c)
    return c.staff or (tonumber(c.myLevel) or 0) >= (tonumber(Config.HighCommandLevel) or 80)
end
--- Author, any officer listed on it (they worked it together), supervisors (mdt_reports_delete) and high command
--- of its department, or an admin. Every edit is logged either way.
local function canEditReport(c, r, list)
    if c.readOnly then return false end
    if c.staff or r.authorCharId == c.charId then return true end
    if r.deptId == c.dept.id and (c.perms.mdt_reports_delete or isHighCommand(c)) then return true end
    return onReport(r.id, c.charId, list)
end
local function canDeleteReport(c, r)
    if c.readOnly then return false end
    return c.staff or (r.deptId == c.dept.id and isHighCommand(c))
end

--- A report as it is now, in full (for the audit copy kept before an edit or a delete)
local function reportSnapshot(rid)
    local r = MySQL.single.await([[SELECT `id`,`deptId`,`type`,`title`,`body`,`location`,`authorCharId`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt`
        FROM `es_mdt_reports` WHERE `id` = ?]], { rid })
    if not r then return nil end
    r.people = MySQL.query.await('SELECT `charId`,`role` FROM `es_mdt_report_people` WHERE `reportId` = ?', { rid }) or {}
    r.officers = MySQL.query.await('SELECT `charId`,`primary` FROM `es_mdt_report_officers` WHERE `reportId` = ?', { rid }) or {}
    r.charges = MySQL.query.await('SELECT `charId`,`penalId`,`code`,`title`,`count`,`fine`,`months`,`baseFine`,`baseMonths` FROM `es_mdt_report_charges` WHERE `reportId` = ? ORDER BY `id`', { rid }) or {}
    r.weapons = MySQL.query.await('SELECT `serial`,`role` FROM `es_mdt_report_weapons` WHERE `reportId` = ? ORDER BY `serial`', { rid }) or {}
    return r
end

local function reportFull(c, rid)
    local r = MySQL.single.await([[SELECT `id`,`deptId`,`type`,`title`,`body`,`location`,`authorCharId`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt`,
        UNIX_TIMESTAMP(`updatedAt`) AS `updatedAt` FROM `es_mdt_reports` WHERE `id` = ?]], { rid })
    if not r then return false, 'No such report' end
    if not canSeeReport(c, r) then return false, 'That report belongs to another department' end
    r.people = MySQL.query.await('SELECT `charId`,`role` FROM `es_mdt_report_people` WHERE `reportId` = ?', { rid }) or {}
    r.officers = MySQL.query.await('SELECT `charId`,`primary` FROM `es_mdt_report_officers` WHERE `reportId` = ? ORDER BY `primary` DESC', { rid }) or {}
    r.charges = MySQL.query.await('SELECT `charId`,`penalId`,`code`,`title`,`category`,`count`,`fine`,`months`,`baseFine`,`baseMonths` FROM `es_mdt_report_charges` WHERE `reportId` = ? ORDER BY `id`', { rid }) or {}
    r.fines = MySQL.query.await("SELECT `id`,`charId`,`amount`,`status` FROM `es_mdt_fines` WHERE `reportId` = ?", { rid }) or {}
    r.warrants = MySQL.query.await("SELECT `id`,`charId`,`status` FROM `es_mdt_warrants` WHERE `reportId` = ?", { rid }) or {}
    r.weapons = MySQL.query.await([[SELECT rw.`serial`, rw.`role`, w.`item`, w.`label`, w.`status`, w.`ownerCharId` FROM `es_mdt_report_weapons` rw
        LEFT JOIN `es_mdt_weapons` w ON w.`serial` = rw.`serial` WHERE rw.`reportId` = ? ORDER BY rw.`serial`]], { rid }) or {}
    r.log = MySQL.query.await([[SELECT `byCharId`,`what`,`detail`,UNIX_TIMESTAMP(`createdAt`) AS `at` FROM `es_mdt_report_log`
        WHERE `reportId` = ? ORDER BY `id` DESC LIMIT 100]], { rid }) or {}
    local ids = { r.authorCharId }
    for _, x in ipairs(r.log) do ids[#ids + 1] = x.byCharId end
    for _, x in ipairs(r.people) do ids[#ids + 1] = x.charId end
    for _, x in ipairs(r.officers) do ids[#ids + 1] = x.charId end
    for _, x in ipairs(r.weapons) do ids[#ids + 1] = x.ownerCharId end
    local names = namesOf(ids)
    r.authorName = names[r.authorCharId]
    for _, x in ipairs(r.weapons) do x.owner = x.ownerCharId and names[x.ownerCharId] or nil x.registered = x.item ~= nil end
    for _, x in ipairs(r.log) do x.byName = names[x.byCharId] or ('#' .. x.byCharId) end
    for _, x in ipairs(r.people) do x.name = names[x.charId] or ('#' .. x.charId) end
    for _, x in ipairs(r.officers) do x.name = names[x.charId] or ('#' .. x.charId) x.primary = x.primary == 1 or x.primary == true end
    local ds = deptShort()[r.deptId]
    r.deptShort = ds and ds.short
    r.canEdit = canEditReport(c, r, r.officers)
    r.canDelete = canDeleteReport(c, r)
    r.edits = 0
    for _, x in ipairs(r.log) do if x.what == 'edited' then r.edits = r.edits + 1 end end
    r.lastEdit = nil
    for _, x in ipairs(r.log) do if x.what == 'edited' then r.lastEdit = { at = x.at, byName = x.byName } break end end
    return r
end

-- ---------------------------------------------------------------- people & vehicles

local function flagsOf(raw)
    if type(raw) ~= 'string' or raw == '' then return {} end
    local ok, v = pcall(json.decode, raw)
    return ok and type(v) == 'table' and v or {}
end

local function cleanFlags(list, allowed)
    local ok, out = {}, {}
    for _, f in ipairs(allowed) do ok[f] = true end
    for _, f in ipairs(type(list) == 'table' and list or {}) do if ok[f] then out[#out + 1] = f end end
    return out
end

local function personSummary(rows)
    local ids = {}
    for _, r in ipairs(rows) do ids[#ids + 1] = r.charId end
    if #ids == 0 then return rows end
    local w = {}
    for _, x in ipairs(MySQL.query.await(("SELECT `charId`, COUNT(*) AS `n` FROM `es_mdt_warrants` WHERE `status` = 'active' AND `kind` = 'arrest' AND `charId` IN (%s) GROUP BY `charId`"):format(marks(#ids)), ids) or {}) do w[x.charId] = tonumber(x.n) end
    local f = {}
    for _, x in ipairs(MySQL.query.await(("SELECT `charId`,`flags` FROM `es_mdt_profiles` WHERE `charId` IN (%s)"):format(marks(#ids)), ids) or {}) do f[x.charId] = flagsOf(x.flags) end
    local pm = MDT.permitMap and MDT.permitMap(ids) or {}
    for _, r in ipairs(rows) do r.warrants = w[r.charId] or 0 r.flags = f[r.charId] or {} r.permit = pm[r.charId] or 'none' end
    return rows
end

-- ---------------------------------------------------------------- the calls

local function todoOf(c)
    local todo = {}
    todo.invites = inviteFor(c.charId) and 1 or 0
    todo.rides = #(Rides[c.charId] or {})
    if c.perms.loa_manage then todo.loa = #(ED:GetLOAs(c.dept.id, { status = 'pending' }) or {}) end
    if c.perms.permits_manage then
        local r = MySQL.single.await("SELECT COUNT(*) AS `n` FROM `es_mdt_permit_apps` WHERE `status` = 'pending'")
        todo.permits = r and tonumber(r.n) or 0
    end
    -- 2.1.0: contests of my tickets waiting for my statement
    local okt, nt = pcall(MySQL.scalar.await, [[SELECT COUNT(*) FROM `es_mdt_ticket_contests` k JOIN `es_mdt_tickets` t ON t.`id` = k.`ticketId`
        WHERE k.`status` = 'open' AND k.`statement` IS NULL AND t.`officerCharId` = ?]], { c.charId })
    todo.statements = okt and tonumber(nt) or 0
    if c.perms.canPromote then todo.recs = #(ED:GetRecommendations(c.dept.id, 'pending') or {}) end
    if c.perms.fto_train or c.perms.fto_manage then
        local q = ED:GetTrainees(c.dept.id) or {}
        local open, overdue, mine = 0, 0, 0
        for _, t in ipairs(q) do
            if not t.ftoCharId then open = open + 1 end
            if t.ftoCharId == c.charId then mine = mine + 1 if t.overdue then overdue = overdue + 1 end end
        end
        todo.trainees, todo.unclaimed, todo.overdue, todo.mine = #q, open, overdue, mine
    end
    if c.perms.warrants_issue then
        local r = MySQL.single.await("SELECT COUNT(*) AS `n` FROM `es_mdt_warrants` WHERE `status` = 'requested'")
        todo.warrantRequests = r and tonumber(r.n) or 0
    end
    do
        local r = MySQL.single.await("SELECT COUNT(*) AS `n` FROM `es_mdt_calls` WHERE `status` = 'active'")
        todo.calls = r and tonumber(r.n) or 0
    end
    if c.perms.loa_manage then
        local act = ED:GetActivity(c.dept.id, { flaggedOnly = true })
        todo.inactive = act and #act.members or 0
    end
    if c.perms.personnel_manage or c.staff then   -- 1.7.0: certifications expiring soon or expired
        local okc, al = pcall(function() return ED:GetCertAlerts(c.dept.id) end)
        todo.certs = okc and type(al) == 'table' and #al or 0
    end
    return todo
end

-- ---------------------------------------------------------------- weapons

--- Auto-registration: a gun that is NEW to the registry, bought in a shop or given by a script/admin, goes on the
--- registry in the receiver's name. A serial already on the registry is never touched (a stolen gun stays the
--- owner's), and a gun picked up off the ground or taken from a stash is never registered.
local Pending = {}   -- [source] = { shop = {[item]=n}, given = {[item]=n}, by = resource }

local function autoRegister(source, p)
    local charId = WC:GetCharId(source)
    if not charId then return end
    local want = {}
    for item, n in pairs(p.shop) do want[item] = math.max(want[item] or 0, n) end
    for item, n in pairs(p.given) do want[item] = math.max(want[item] or 0, n) end
    local found, all = {}, {}
    for _, cont in pairs(WC:GetInventory(source) or {}) do
        if type(cont) == 'table' then
            for _, it in pairs(cont) do
                local s = type(it) == 'table' and want[it.item] and type(it.metadata) == 'table' and serialOf(it.metadata.serial)
                if s then found[it.item] = found[it.item] or {} table.insert(found[it.item], s) all[#all + 1] = s end
            end
        end
    end
    if #all == 0 then return end
    local known = {}
    for _, r in ipairs(MySQL.query.await(('SELECT `serial` FROM `es_mdt_weapons` WHERE `serial` IN (%s)'):format(marks(#all)), all) or {}) do known[r.serial] = true end
    local defs = gunDefs()
    for item, serials in pairs(found) do
        local left = want[item]
        local how = (p.shop[item] or 0) > 0 and 'shop' or 'given'
        for _, s in ipairs(serials) do
            if left <= 0 then break end
            if not known[s] then
                known[s], left = true, left - 1
                local wid = MySQL.insert.await([[INSERT IGNORE INTO `es_mdt_weapons` (`serial`,`item`,`label`,`ownerCharId`,`origin`) VALUES (?,?,?,?,?)]],
                    { s, item, defs[item] or item, charId, how })
                if wid and wid > 0 then
                    MySQL.insert.await('INSERT INTO `es_mdt_weapon_log` (`weaponId`,`byCharId`,`what`,`detail`) VALUES (?,NULL,?,?)',
                        { wid, 'registered', how == 'shop' and 'Registered automatically: bought in a shop' or ('Registered automatically: given' .. (p.by and (' by ' .. p.by) or '')) })
                end
            end
        end
    end
end

local function autoQueue(source, item, n, how, by)
    if not gunDefs()[item] then return end
    local p = Pending[source]
    if not p then
        p = { shop = {}, given = {} }
        Pending[source] = p
        SetTimeout(800, function()
            Pending[source] = nil
            local ok, err = pcall(autoRegister, source, p)
            if not ok then print(('^3[es_mdt] weapon auto-register: %s^7'):format(tostring(err))) end
        end)
    end
    p[how][item] = (p[how][item] or 0) + (tonumber(n) or 1)
    if by then p.by = by end
end

local function skipBy(by)
    for _, r in ipairs(W.autoRegisterSkip or {}) do if r == by then return true end end
    return false
end

local function weaponRow(serial)
    return MySQL.single.await([[SELECT `id`,`serial`,`item`,`label`,`ownerCharId`,`origin`,`status`,`notes`,`registeredBy`,
        UNIX_TIMESTAMP(`registeredAt`) AS `registeredAt`, UNIX_TIMESTAMP(`updatedAt`) AS `updatedAt` FROM `es_mdt_weapons` WHERE `serial` = ?]], { serial })
end

local function charExists(cid)
    return cid and MySQL.single.await('SELECT `charId` FROM `characters` WHERE `charId` = ? AND `deleted` IS NULL', { cid }) ~= nil
end

local function registerWeapons()
    AddEventHandler('whip_core:shop:purchased', function(e)
        if not W.autoRegisterShops or type(e) ~= 'table' or not tonumber(e.source) then return end
        for _, it in ipairs(type(e.items) == 'table' and e.items or {}) do
            if type(it) == 'table' and it.itemKey then autoQueue(tonumber(e.source), it.itemKey, it.amount, 'shop') end
        end
    end)
    AddEventHandler('whip_core:item:added', function(e)
        if not W.autoRegisterGiven or type(e) ~= 'table' or not tonumber(e.source) or not e.by then return end
        local by = tostring(e.by)
        if skipBy(by) then return end
        autoQueue(tonumber(e.source), e.item, e.amount, 'given', by)
    end)

    cb('weaponTypes', { rate = 1000, burst = 4 }, function() return weaponTypes() end)

    --- The Weapons page before a gun is picked: counts and the latest registry activity
    cb('weaponOverview', { rate = 500, burst = 4 }, function()
        local out = { counts = { registered = 0, stolen = 0, seized = 0, destroyed = 0 }, licenses = 0 }
        for _, r in ipairs(MySQL.query.await('SELECT `status`, COUNT(*) AS `n` FROM `es_mdt_weapons` GROUP BY `status`') or {}) do
            out.counts[r.status] = tonumber(r.n) or 0
        end
        local l = MySQL.single.await("SELECT COUNT(*) AS `n` FROM `es_mdt_weapon_licenses` WHERE `status` = 'active'")
        out.licenses = l and tonumber(l.n) or 0
        out.recent = MySQL.query.await([[SELECT g.`what`, g.`detail`, g.`byCharId`, g.`reportId`, UNIX_TIMESTAMP(g.`createdAt`) AS `at`,
            w.`serial`, w.`label`, w.`item`, w.`status` FROM `es_mdt_weapon_log` g JOIN `es_mdt_weapons` w ON w.`id` = g.`weaponId`
            ORDER BY g.`id` DESC LIMIT 10]]) or {}
        local ids = {}
        for _, x in ipairs(out.recent) do ids[#ids + 1] = x.byCharId end
        local names = namesOf(ids)
        for _, x in ipairs(out.recent) do x.byName = x.byCharId and (names[x.byCharId] or ('#' .. x.byCharId)) or 'System' end
        return out
    end)

    cb('weapons', { rate = 300, burst = 6 }, function(c, d)
        local q = str(d.q, 40)
        local st = WSTATUS[d.status] and d.status or nil
        local where, args = {}, {}
        if #q >= 2 then
            local like = likeOf(q)
            where[#where + 1] = "(w.`serial` LIKE ? OR w.`label` LIKE ? OR w.`item` LIKE ? OR CONCAT(ch.`firstName`,' ',ch.`lastName`) LIKE ?)"
            for _ = 1, 4 do args[#args + 1] = like end
        end
        if st then where[#where + 1] = 'w.`status` = ?' args[#args + 1] = st end
        args[#args + 1] = q:upper()   -- an exact serial first
        local rows = MySQL.query.await(([[SELECT w.`id`, w.`serial`, w.`item`, w.`label`, w.`ownerCharId`, w.`origin`, w.`status`,
            UNIX_TIMESTAMP(w.`registeredAt`) AS `registeredAt`, CONCAT(ch.`firstName`,' ',ch.`lastName`) AS `owner`,
            (SELECT COUNT(*) FROM `es_mdt_bolos` b WHERE b.`kind` = 'weapon' AND b.`serial` = w.`serial` AND b.`status` = 'active'
                AND (b.`expiresAt` IS NULL OR b.`expiresAt` > NOW())) AS `bolos`
            FROM `es_mdt_weapons` w LEFT JOIN `characters` ch ON ch.`charId` = w.`ownerCharId`
            %s ORDER BY (w.`serial` = ?) DESC, FIELD(w.`status`,'stolen','seized','registered','destroyed'), w.`id` DESC LIMIT 50]])
            :format(#where > 0 and ('WHERE ' .. table.concat(where, ' AND ')) or ''), args) or {}
        local owners = {}
        for _, r in ipairs(rows) do r.bolos = tonumber(r.bolos) or 0 if r.ownerCharId then owners[#owners + 1] = r.ownerCharId end end
        -- 1.8.0: the owner's firearm permit; a live gun whose owner holds none is flagged
        local pm = MDT.permitMap and MDT.permitMap(owners) or {}
        for _, r in ipairs(rows) do
            r.permit = r.ownerCharId and (pm[r.ownerCharId] or 'none') or nil
            r.noPermit = r.ownerCharId ~= nil and r.permit ~= 'active' and r.status ~= 'destroyed'
        end
        return rows
    end)

    cb('weapon', { rate = 300, burst = 6 }, function(c, d)
        local s = serialOf(d.serial)
        if not s then return false, 'Type a serial number' end
        local w = weaponRow(s)
        local out = w or { serial = s }
        out.registered = w ~= nil
        out.log = w and MySQL.query.await([[SELECT `byCharId`,`what`,`detail`,`reportId`,UNIX_TIMESTAMP(`createdAt`) AS `at` FROM `es_mdt_weapon_log`
            WHERE `weaponId` = ? ORDER BY `id` DESC LIMIT 100]], { w.id }) or {}
        out.reports = MySQL.query.await([[SELECT r.`id`, r.`deptId`, r.`type`, r.`title`, rw.`role`, UNIX_TIMESTAMP(r.`createdAt`) AS `createdAt`
            FROM `es_mdt_report_weapons` rw JOIN `es_mdt_reports` r ON r.`id` = rw.`reportId` WHERE rw.`serial` = ? ORDER BY r.`id` DESC LIMIT 50]], { s }) or {}
        local ds = deptShort()
        for _, r in ipairs(out.reports) do
            r.deptShort = ds[r.deptId] and ds[r.deptId].short
            r.visible = canSeeReport(c, r)
        end
        out.bolos = MySQL.query.await([[SELECT `id`,`title`,`description`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt` FROM `es_mdt_bolos`
            WHERE `kind` = 'weapon' AND `serial` = ? AND `status` = 'active' AND (`expiresAt` IS NULL OR `expiresAt` > NOW()) ORDER BY `id` DESC]], { s }) or {}
        out.licenses = w and w.ownerCharId and MySQL.query.await("SELECT `type`,`status`,`origin` FROM `es_mdt_weapon_licenses` WHERE `charId` = ? ORDER BY `type`", { w.ownerCharId }) or {}
        if w and w.ownerCharId then
            out.permit = 'none'
            for _, l in ipairs(out.licenses) do if l.type == MDT.permitType then out.permit = l.status end end
            out.permitLabel = MDT.permitLabel
            out.noPermit = out.permit ~= 'active' and w.status ~= 'destroyed'
        end
        local ids = {}
        if w then ids[#ids + 1] = w.ownerCharId ids[#ids + 1] = w.registeredBy end
        for _, x in ipairs(out.log) do ids[#ids + 1] = x.byCharId end
        local names = namesOf(ids)
        if w then out.owner = w.ownerCharId and names[w.ownerCharId] or nil out.registeredByName = w.registeredBy and names[w.registeredBy] or nil end
        for _, x in ipairs(out.log) do x.byName = x.byCharId and (names[x.byCharId] or ('#' .. x.byCharId)) or 'System' end
        return out
    end)

    cb('weaponRegister', { perm = 'weapons_register', write = true, rate = 1000, burst = 3 }, function(c, d)
        local s = serialOf(d.serial)
        if not s then return false, 'Type the serial (4-32 letters or digits)' end
        local defs = gunDefs()
        local item = type(d.item) == 'string' and d.item or ''
        if not defs[item] then return false, 'Pick the weapon type' end
        local owner = id(d.ownerCharId)
        if owner and not charExists(owner) then return false, 'No such person' end
        local had = weaponRow(s)
        if had then
            local nm = had.ownerCharId and (namesOf({ had.ownerCharId })[had.ownerCharId]) or 'no owner'
            return false, ('Serial %s is already registered (%s, %s)'):format(s, had.label or had.item, nm)
        end
        local notes = str(d.notes, 1000)
        local wid = MySQL.insert.await([[INSERT IGNORE INTO `es_mdt_weapons` (`serial`,`item`,`label`,`ownerCharId`,`origin`,`notes`,`registeredBy`)
            VALUES (?,?,?,?,?,NULLIF(?,''),?)]], { s, item, defs[item], owner, 'officer', notes, c.charId })
        if not wid or wid == 0 then return false, 'Could not register it (already registered?)' end
        local nm = owner and (namesOf({ owner })[owner] or ('#' .. owner)) or 'no owner'
        MySQL.insert.await('INSERT INTO `es_mdt_weapon_log` (`weaponId`,`byCharId`,`what`,`detail`) VALUES (?,?,?,?)',
            { wid, c.charId, 'registered', ('Registered by an officer: %s, owner %s'):format(defs[item], nm) })
        log(c, 'weapon', ('registered %s (%s) to %s'):format(s, defs[item], nm))
        refresh('weapons')
        return s
    end)

    cb('weaponAct', { write = true, rate = 800, burst = 4 }, function(c, d)
        local s = serialOf(d.serial)
        local w = s and weaponRow(s)
        if not w then return false, 'That serial is not on the registry' end
        local action, note = d.action, str(d.note, 500)
        local perm = action == 'note' and 'weapons_register' or 'weapons_manage'
        if not c.perms[perm] then return false, 'Your rank cannot do that' end
        local label = w.label or w.item
        local qs = {}
        if action == 'note' then
            if note == '' then return false, 'Write the note' end
            qs[#qs + 1] = weaponLog(w.id, c.charId, 'note', note)
        elseif action == 'transfer' then
            local owner = id(d.ownerCharId)
            if not owner or not charExists(owner) then return false, 'Pick the new owner' end
            if owner == w.ownerCharId then return false, 'They already own it' end
            local names = namesOf({ owner, w.ownerCharId })
            qs[#qs + 1] = { query = 'UPDATE `es_mdt_weapons` SET `ownerCharId` = ? WHERE `id` = ?', values = { owner, w.id } }
            qs[#qs + 1] = weaponLog(w.id, c.charId, 'owner', ('Owner: %s → %s%s'):format(w.ownerCharId and (names[w.ownerCharId] or ('#' .. w.ownerCharId)) or 'none',
                names[owner] or ('#' .. owner), note ~= '' and (' · ' .. note) or ''))
        else
            local to = ({ stolen = 'stolen', seized = 'seized', returned = 'registered', destroyed = 'destroyed' })[action]
            if not to then return false, 'Unknown action' end
            if w.status == to then return false, ('It is already %s'):format(to) end
            if w.status == 'destroyed' then return false, 'That weapon was destroyed' end
            qs[#qs + 1] = { query = 'UPDATE `es_mdt_weapons` SET `status` = ? WHERE `id` = ?', values = { to, w.id } }
            qs[#qs + 1] = weaponLog(w.id, c.charId, 'status', ('%s → %s%s'):format(w.status, to, note ~= '' and (' · ' .. note) or ''))
        end
        if not MySQL.transaction.await(qs) then return false, 'Could not save (database error)' end
        local bolo
        if action == 'stolen' and W.boloOnStolen ~= false then
            local hours = int(W.boloHours, 0, 24 * 30)
            local owner = w.ownerCharId and namesOf({ w.ownerCharId })[w.ownerCharId]
            bolo = MySQL.insert.await([[INSERT INTO `es_mdt_bolos` (`deptId`,`kind`,`serial`,`title`,`description`,`createdBy`,`expiresAt`)
                VALUES (?,'weapon',?,?,?,?,IF(? = 0, NULL, NOW() + INTERVAL ? HOUR))]],
                { c.dept.id, s, ('Stolen %s · %s'):format(label, s):sub(1, 120),
                  (('Reported stolen%s.%s'):format(owner and (' from ' .. owner) or '', note ~= '' and (' ' .. note) or '')):sub(1, 1000), c.charId, hours, hours })
            if bolo then MySQL.insert.await('INSERT INTO `es_mdt_weapon_log` (`weaponId`,`byCharId`,`what`,`detail`) VALUES (?,?,?,?)', { w.id, c.charId, 'bolo', ('BOLO #%d posted'):format(bolo) }) end
            refresh('bolos')
        elseif action == 'returned' or action == 'destroyed' or action == 'seized' then
            local n = closeWeaponBolos(s, c.charId)
            if n > 0 then MySQL.insert.await('INSERT INTO `es_mdt_weapon_log` (`weaponId`,`byCharId`,`what`,`detail`) VALUES (?,?,?,?)', { w.id, c.charId, 'bolo', ('%d BOLO%s closed'):format(n, n > 1 and 's' or '') }) end
        end
        log(c, 'weapon', ('%s %s %s'):format(action, s, note))
        refresh('weapons')
        return true
    end)

    cb('licenseAct', { perm = 'licenses_manage', write = true, rate = 800, burst = 4 }, function(c, d)
        local cid = id(d.charId)
        if not cid or not charExists(cid) then return false, 'No such person' end
        local typ
        for _, t in ipairs(W.licenseTypes or { 'Firearm' }) do if t == d.type then typ = t end end
        if not typ then return false, 'Pick the license type' end
        local note, action = str(d.note, 300), d.action
        local cur = MySQL.single.await('SELECT `id`,`status` FROM `es_mdt_weapon_licenses` WHERE `charId` = ? AND `type` = ?', { cid, typ })
        local to = ({ issue = 'active', reinstate = 'active', suspend = 'suspended', revoke = 'revoked' })[action]
        if not to then return false, 'Unknown action' end
        if action == 'issue' and cur and cur.status == 'active' then return false, 'They already hold an active ' .. typ .. ' license' end
        if action ~= 'issue' and not cur then return false, 'They do not hold a ' .. typ .. ' license' end
        if cur and cur.status == to then return false, ('That license is already %s'):format(to) end
        if action == 'reinstate' and cur.status ~= 'suspended' then return false, 'Only a suspended license can be reinstated (issue it again instead)' end
        if (action == 'suspend' or action == 'revoke') and note == '' then return false, 'Give a reason' end
        local lid
        if action == 'issue' then
            MySQL.query.await([[INSERT INTO `es_mdt_weapon_licenses` (`charId`,`type`,`status`,`issuedBy`,`updatedBy`,`note`,`origin`) VALUES (?,?,'active',?,?,NULLIF(?,''),'manual')
                ON DUPLICATE KEY UPDATE `status` = 'active', `issuedBy` = VALUES(`issuedBy`), `issuedAt` = NOW(), `updatedBy` = VALUES(`updatedBy`), `note` = VALUES(`note`), `origin` = 'manual']],
                { cid, typ, c.charId, c.charId, note })
            local r = MySQL.single.await('SELECT `id` FROM `es_mdt_weapon_licenses` WHERE `charId` = ? AND `type` = ?', { cid, typ })
            lid = r and r.id
        else
            MySQL.update.await('UPDATE `es_mdt_weapon_licenses` SET `status` = ?, `updatedBy` = ?, `note` = NULLIF(?,\'\') WHERE `id` = ?', { to, c.charId, note, cur.id })
            lid = cur.id
        end
        if not lid then return false, 'Could not save (database error)' end
        MySQL.insert.await('INSERT INTO `es_mdt_weapon_license_log` (`licenseId`,`byCharId`,`action`,`note`) VALUES (?,?,?,NULLIF(?,\'\'))', { lid, c.charId, action, note })
        log(c, 'license', ('%s %s #%d %s'):format(action, typ, cid, note))
        local said = ({ issue = 'issued', reinstate = 'reinstated', suspend = 'suspended', revoke = 'revoked' })[action]
        notifyChar(cid, ('Your %s license was %s by %s.'):format(typ, said, c.dept.short or 'the police'), (action == 'issue' or action == 'reinstate') and 'success' or 'warning')
        refresh('weapons')
        return true
    end)
end

local function register()
    -- 1.10.0: the Department of Justice is part of the MDT. With the DOJ department picked, the MDT opens the court
    -- side (es_doj's screen); { law = true } asks for a police department instead (the "Police MDT" button there).
    local function courtUp() return GetResourceState('es_doj') == 'started' end
    local function openOrCourt(c)
        if c.dept.type == 'doj' and courtUp() then return { doj = true, deptId = c.dept.id } end
        if not (c.perms.mdt_view or c.staff) then return false, 'Your rank cannot use the MDT' end
        return openData(c)
    end
    cb('open', { rate = 500, burst = 4, anyRank = true }, function(c, d)
        if d.law and c.dept.type == 'doj' then
            for _, x in ipairs(c.depts) do
                if x.type ~= 'doj' then
                    Pick[c.source] = x.id
                    Cache[c.source] = nil
                    c = ctxOf(c.source) or c
                    break
                end
            end
            if c.dept.type == 'doj' then return false, 'You are not in a police department' end
        end
        return openOrCourt(c)
    end)

    cb('pickDept', { anyRank = true }, function(c, d)
        local want = id(d.id)
        for _, x in ipairs(c.depts) do
            if x.id == want then
                Pick[c.source] = want
                Cache[c.source] = nil
                local nc = ctxOf(c.source)
                return openOrCourt(nc)
            end
        end
        return false, 'You are not in that department'
    end)

    cb('dashboard', { rate = 1000, burst = 4 }, function(c)
        local out = { units = unitsAll() }
        out.reports = MySQL.query.await([[SELECT `id`,`type`,`title`,`authorCharId`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt` FROM `es_mdt_reports`
            WHERE `deptId` = ? ORDER BY `id` DESC LIMIT 6]], { c.dept.id }) or {}
        out.warrants = MySQL.query.await([[SELECT `id`,`charId`,`reason`,`status`,`kind`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt` FROM `es_mdt_warrants`
            WHERE `status` IN ('active','requested') ORDER BY `id` DESC LIMIT 6]]) or {}
        out.bolos = MySQL.query.await([[SELECT `id`,`kind`,`plate`,`serial`,`charId`,`title`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt` FROM `es_mdt_bolos`
            WHERE `status` = 'active' AND (`expiresAt` IS NULL OR `expiresAt` > NOW()) ORDER BY `id` DESC LIMIT 6]]) or {}
        local ids = {}
        for _, r in ipairs(out.reports) do ids[#ids + 1] = r.authorCharId end
        for _, w in ipairs(out.warrants) do ids[#ids + 1] = w.charId end
        for _, b in ipairs(out.bolos) do if b.charId then ids[#ids + 1] = b.charId end end
        local names = namesOf(ids)
        for _, r in ipairs(out.reports) do r.authorName = names[r.authorCharId] end
        for _, w in ipairs(out.warrants) do w.name = names[w.charId] end
        for _, b in ipairs(out.bolos) do b.name = b.charId and names[b.charId] or nil end
        out.myDuty7 = ED:GetDutySeconds(c.charId, { days = 7, dept = c.dept.id }) or 0
        local mine = MySQL.single.await("SELECT COUNT(*) AS `n` FROM `es_mdt_reports` WHERE `authorCharId` = ? AND `createdAt` > NOW() - INTERVAL 7 DAY", { c.charId })
        out.myReports7 = mine and tonumber(mine.n) or 0
        out.todo = todoOf(c)
        out.myLoa = ED:GetLOAs(c.dept.id, { charId = c.charId, status = 'active' }) or {}
        if MDT.dashboardExtra then MDT.dashboardExtra(c, out) end
        return out
    end)

    cb('badges', { rate = 1000, burst = 4 }, function(c) return todoOf(c) end)

    --- A unit's position for the GPS (only someone on duty right now)
    cb('unitGps', { rate = 1000, burst = 3 }, function(c, d)
        local cid = id(d.charId)
        if not cid then return false, 'Pick a unit' end
        local _, idx = dutyNow()
        if not idx[cid] then return false, 'That unit is not on duty' end
        local src = onlineByChar()[cid]
        local ped = src and GetPlayerPed(src)
        if not ped or ped == 0 then return false, 'Could not find that unit' end
        local p = GetEntityCoords(ped)
        return { x = p.x, y = p.y }
    end)

    cb('units', { rate = 500, burst = 6 }, function(c)
        local groups, idx = unitsAll()
        local t = Teams[TeamOf[c.charId] or 0]
        local out = { groups = groups, mine = t and t.status or (Units[c.charId] or {}).status or 'available',
            onDuty = idx[c.charId] ~= nil, teamId = t and t.id or nil, rides = Rides[c.charId] or {} }
        local iv = inviteFor(c.charId)
        if iv and idx[iv.from] then
            out.invite = { from = iv.from, mode = iv.mode, type = iv.type, name = idx[iv.from].u.name, callsign = idx[iv.from].u.callsign,
                deptShort = idx[iv.from].g.short, left = INVITE_TTL - (os.time() - iv.at) }
        end
        for to, x in pairs(Invites) do
            if x.from == c.charId and inviteFor(to) and idx[to] then
                out.sent = { to = to, name = idx[to].u.name, callsign = idx[to].u.callsign, mode = x.mode, type = x.type }
            end
        end
        return out
    end)

    --- Pair up: mode 'invite' (you lead, they join you) or 'join' (you join them, they lead). They accept in their MDT.
    cb('unitInvite', { rate = 1500, burst = 3 }, function(c, d)
        local to = id(d.charId)
        local mode = d.mode == 'join' and 'join' or 'invite'
        local kind = d.type == 'fto' and 'fto' or 'patrol'
        if not to or to == c.charId then return false, 'Pick another unit' end
        local _, idx = dutyNow()
        local me, them = idx[c.charId], idx[to]
        if not me then return false, 'Clock on first' end
        if not them then return false, 'They are not on duty' end
        if TeamOf[c.charId] then return false, 'Leave your unit first' end
        if TeamOf[to] then return false, 'They are already in a unit' end
        local iv = inviteFor(to)
        if iv and iv.from ~= c.charId then return false, 'They have another request waiting, try again in a minute' end
        if inviteFor(c.charId) then return false, 'Answer the request waiting for you first' end
        for k, x in pairs(Invites) do if x.from == c.charId then Invites[k] = nil end end   -- one request out at a time
        if kind == 'fto' then
            if me.g.id ~= them.g.id then return false, 'A ride-along is within one department' end
            local mine = WC:HasJobPermission({ charId = c.charId }, me.g.jobId, 'fto_train', { onDuty = false }) == true
            local theirs = WC:HasJobPermission({ charId = to }, me.g.jobId, 'fto_train', { onDuty = false }) == true
            if not mine and not theirs then return false, 'A ride-along needs an FTO: one of you must be an FTO' end
            if mine and theirs then return false, 'You are both FTOs: make it a patrol unit instead' end
        end
        Invites[to] = { from = c.charId, mode = mode, type = kind, at = os.time() }
        local what = kind == 'fto' and 'an FTO ride-along' or 'a patrol unit'
        local text = mode == 'join' and ('%s %s asks to join your unit (%s). Open the MDT to answer.')
            or ('%s %s invites you to %s. Open the MDT to answer.')
        WC:NotifyPlayer(them.u.source, mode == 'join' and text:format(me.u.callsign or '', me.u.name, what) or text:format(me.u.callsign or '', me.u.name, what), 'inform', 10000)
        TriggerClientEvent('es_mdt:client:refresh', them.u.source, 'invite')
        refresh('units')
        return true
    end)

    cb('unitCancel', { rate = 800, burst = 3 }, function(c)
        for k, x in pairs(Invites) do if x.from == c.charId then Invites[k] = nil end end
        refresh('units')
        return true
    end)

    cb('unitAnswer', { rate = 1000, burst = 3 }, function(c, d)
        local iv = inviteFor(c.charId)
        if not iv then return false, 'That request ran out' end
        Invites[c.charId] = nil
        local online = onlineByChar()
        local _, idx = dutyNow()
        local me, them = idx[c.charId], idx[iv.from]
        if d.accept ~= true then
            notifyChar(iv.from, ('%s said no to your unit request'):format(me and me.u.name or 'They'), 'inform', online)
            refresh('units')
            return true
        end
        if not me then return false, 'Clock on first' end
        if not them then return false, 'They are not on duty any more' end
        if TeamOf[c.charId] or TeamOf[iv.from] then return false, 'One of you is already in a unit' end
        -- who leads: the one who invited, or the one asked to be joined
        local lead, partner = iv.from, c.charId
        if iv.mode == 'join' then lead, partner = c.charId, iv.from end
        local t = { type = iv.type, lead = lead, partner = partner, at = os.time(), startedAt = os.time(),
            status = (Units[lead] or {}).status or 'available',
            names = { [c.charId] = me.u.name, [iv.from] = them.u.name }, src = { [c.charId] = me.u.source, [iv.from] = them.u.source } }
        if iv.type == 'fto' then
            if me.g.id ~= them.g.id then return false, 'A ride-along is within one department' end
            local a = WC:HasJobPermission({ charId = c.charId }, me.g.jobId, 'fto_train', { onDuty = false }) == true
            local b = WC:HasJobPermission({ charId = iv.from }, me.g.jobId, 'fto_train', { onDuty = false }) == true
            if a == b then return false, 'A ride-along needs exactly one FTO' end
            t.fto, t.trainee, t.deptId = a and c.charId or iv.from, a and iv.from or c.charId, me.g.id
            -- the trainee is claimed by this FTO in the Needs-training queue (if they are in it)
            local ftoSrc = t.src[t.fto]
            pcall(function() ED:AssignTrainee(ftoSrc, t.deptId, t.trainee, nil) end)
            refresh('training')
        end
        teamSeq = teamSeq + 1
        t.id = teamSeq
        Teams[t.id] = t
        TeamOf[lead], TeamOf[partner] = t.id, t.id
        local label = (idx[lead].u.callsign or '—') .. ' / ' .. (idx[partner].u.callsign or '—')
        local kindText = t.type == 'fto' and 'FTO ride-along' or 'Patrol unit'
        notifyChar(lead, ('%s %s started: %s'):format(kindText, label, t.names[partner]), 'success', online)
        notifyChar(partner, ('%s %s started with %s'):format(kindText, label, t.names[lead]), 'success', online)
        refresh('units')
        return true
    end)

    cb('unitLeave', { rate = 1000, burst = 3 }, function(c)
        if not TeamOf[c.charId] then return false, 'You are not in a unit' end
        dissolveOf(c.charId, 'left')
        return true
    end)

    --- Ride-alongs that ended: the FTO writes them up (es_departments LogTraining), or lets them go
    local function rideOf(c, rid)
        for i, r in ipairs(Rides[c.charId] or {}) do if r.id == rid then return r, i end end
    end
    cb('rideLog', { write = true, rate = 1500, burst = 2 }, function(c, d)
        local r, i = rideOf(c, id(d.id) or 0)
        if not r then return false, 'That ride-along is already written up' end
        local okl, whyl = ED:LogTraining(c.source, r.deptId, r.traineeCharId, { kind = d.kind or 'ridealong', minutes = d.minutes or r.minutes,
            notes = str(d.notes, 4000), ratings = type(d.ratings) == 'table' and d.ratings or {},
            checklist = type(d.checklist) == 'table' and d.checklist or {}, signed = keyList(d.signed), at = r.startedAt })
        if not okl then return false, whyl end
        table.remove(Rides[c.charId], i)
        refresh('training')
        return okl
    end)
    cb('rideSkip', { rate = 800, burst = 3 }, function(c, d)
        local _, i = rideOf(c, id(d.id) or 0)
        if i then table.remove(Rides[c.charId], i) end
        return true
    end)

    cb('setStatus', {}, function(c, d)
        local ok = false
        for _, s in ipairs(Config.UnitStatuses) do if s.key == d.status then ok = true end end
        if not ok then return false, 'Unknown status' end
        if not c.onDuty then return false, 'Clock on first' end
        local t = Teams[TeamOf[c.charId] or 0]
        if t then t.status, t.at = d.status, os.time() else Units[c.charId] = { status = d.status, at = os.time() } end
        refresh('units')
        return true
    end)

    -- people
    cb('people', { rate = 300, burst = 6 }, function(c, d)
        local q = str(d.q, 60)
        if #q < 2 then return {} end
        local rows
        if q:match('^%d+$') then
            rows = MySQL.query.await([[SELECT c.`charId`, CONCAT(c.`firstName`,' ',c.`lastName`) AS `name`, DATE_FORMAT(c.`dateOfBirth`,'%Y-%m-%d') AS `dob`, c.`gender`,
                (SELECT p.`phoneNumber` FROM `phone_numbers` p WHERE p.`charId` = c.`charId` AND p.`retiredAt` IS NULL LIMIT 1) AS `phone`
                FROM `characters` c WHERE c.`deleted` IS NULL AND (c.`charId` = ? OR c.`charId` IN (SELECT `charId` FROM `phone_numbers` WHERE `phoneNumber` LIKE CONCAT(?, '%')))
                LIMIT ?]], { tonumber(q), q, Config.SearchLimit }) or {}
        else
            rows = MySQL.query.await([[SELECT c.`charId`, CONCAT(c.`firstName`,' ',c.`lastName`) AS `name`, DATE_FORMAT(c.`dateOfBirth`,'%Y-%m-%d') AS `dob`, c.`gender`,
                (SELECT p.`phoneNumber` FROM `phone_numbers` p WHERE p.`charId` = c.`charId` AND p.`retiredAt` IS NULL LIMIT 1) AS `phone`
                FROM `characters` c WHERE c.`deleted` IS NULL AND CONCAT(c.`firstName`,' ',c.`lastName`) LIKE CONCAT('%', ?, '%')
                ORDER BY c.`lastName`, c.`firstName` LIMIT ?]], { q, Config.SearchLimit }) or {}
        end
        return personSummary(rows)
    end)

    cb('person', { rate = 300, burst = 6 }, function(c, d)
        local cid = id(d.charId)
        if not cid then return false, 'Pick a person' end
        local p = MySQL.single.await([[SELECT c.`charId`, c.`firstName`, c.`lastName`, DATE_FORMAT(c.`dateOfBirth`,'%Y-%m-%d') AS `dob`, c.`gender`,
            UNIX_TIMESTAMP(c.`lastPlayed`) AS `lastPlayed`,
            (SELECT p.`phoneNumber` FROM `phone_numbers` p WHERE p.`charId` = c.`charId` AND p.`retiredAt` IS NULL LIMIT 1) AS `phone`
            FROM `characters` c WHERE c.`charId` = ? AND c.`deleted` IS NULL]], { cid })
        if not p then return false, 'No such person' end
        p.name = p.firstName .. ' ' .. p.lastName
        local img = MySQL.single.await('SELECT `image` FROM `character_portraits` WHERE `charId` = ?', { cid })
        p.portrait = img and type(img.image) == 'string' and #img.image < 400000 and img.image:sub(1, 11) == 'data:image/' and img.image or nil
        -- 1.3.0: the profile mugshot (MDT photo) wins over the character portrait
        local mug = MySQL.single.await([[SELECT m.`id`, m.`image` FROM `es_mdt_profiles` pr JOIN `es_mdt_mugshots` m ON m.`id` = pr.`mugshotId`
            WHERE pr.`charId` = ?]], { cid })
        if mug and type(mug.image) == 'string' and mug.image:sub(1, 11) == 'data:image/' then p.mugshot = mug.image p.mugshotId = mug.id end
        local mc = MySQL.single.await('SELECT COUNT(*) AS `n` FROM `es_mdt_mugshots` WHERE `charId` = ?', { cid })
        p.mugshotCount = mc and tonumber(mc.n) or 0
        -- 1.5.3: fingerprints on file (es_evidence)
        if GetResourceState('es_evidence') == 'started' then
            local ok, fp = pcall(function() return exports.es_evidence:PrintsOnFile(cid) end)
            p.prints = ok and type(fp) == 'table' and fp or nil
        end
        local prof = MySQL.single.await('SELECT `notes`,`flags`,`updatedBy`,UNIX_TIMESTAMP(`updatedAt`) AS `updatedAt` FROM `es_mdt_profiles` WHERE `charId` = ?', { cid })
        p.notes, p.flags = prof and prof.notes or '', prof and flagsOf(prof.flags) or {}
        p.vehicles = MySQL.query.await([[SELECT v.`vehicleId`, v.`plate`, v.`model`, v.`state`, COALESCE(k.`displayName`, v.`model`) AS `label`
            FROM `vehicles` v LEFT JOIN `vehicle_catalog` k ON k.`model` = v.`model` WHERE v.`ownerCharId` = ? ORDER BY v.`vehicleId` LIMIT 50]], { cid }) or {}
        p.reports = MySQL.query.await([[SELECT r.`id`, r.`type`, r.`title`, r.`deptId`, pp.`role`, UNIX_TIMESTAMP(r.`createdAt`) AS `createdAt`
            FROM `es_mdt_report_people` pp JOIN `es_mdt_reports` r ON r.`id` = pp.`reportId` WHERE pp.`charId` = ? ORDER BY r.`id` DESC LIMIT 50]], { cid }) or {}
        local ds = deptShort()
        local cm = courtMarks(cid)   -- 1.9.0: sealed / expunged by the court (es_doj)
        for _, r in ipairs(p.reports) do
            r.deptShort = ds[r.deptId] and ds[r.deptId].short
            r.visible = c.staff or r.deptId == c.dept.id
            r.court = cm[r.id] or cm[tostring(r.id)]
        end
        p.charges = MySQL.query.await(([[SELECT `code`,`title`,`category`, SUM(`count`) AS `n` FROM `es_mdt_report_charges` WHERE `charId` = ?%s
            GROUP BY `code`,`title`,`category` ORDER BY `n` DESC LIMIT 40]]):format(notExpunged(cm, '`reportId`')), { cid }) or {}
        if GetResourceState('es_doj') == 'started' then
            local okc, court = pcall(function() return exports.es_doj:GetRecordSummary(cid, { cases = true }) end)
            p.court = okc and type(court) == 'table' and court or nil
        end
        p.warrants = MySQL.query.await([[SELECT `id`,`reason`,`status`,`reportId`,`kind`,`scope`,`judgeName`,`judgeNote`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt`,UNIX_TIMESTAMP(`expiresAt`) AS `expiresAt`
            FROM `es_mdt_warrants` WHERE `charId` = ? ORDER BY FIELD(`status`,'active','requested','served','void'), `id` DESC LIMIT 30]], { cid }) or {}
        p.fines = MySQL.query.await([[SELECT `id`,`amount`,`reason`,`status`,`reportId`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt`
            FROM `es_mdt_fines` WHERE `charId` = ? ORDER BY FIELD(`status`,'unpaid','paid','void'), `id` DESC LIMIT 50]], { cid }) or {}
        p.owed = 0
        for _, f in ipairs(p.fines) do if f.status == 'unpaid' then p.owed = p.owed + f.amount end end
        p.bolos = MySQL.query.await("SELECT `id`,`title`,`description` FROM `es_mdt_bolos` WHERE `kind` = 'person' AND `charId` = ? AND `status` = 'active'", { cid }) or {}
        p.weapons = MySQL.query.await([[SELECT `serial`,`item`,`label`,`status`,`origin`,UNIX_TIMESTAMP(`registeredAt`) AS `registeredAt` FROM `es_mdt_weapons`
            WHERE `ownerCharId` = ? ORDER BY FIELD(`status`,'stolen','seized','registered','destroyed'), `id` DESC LIMIT 50]], { cid }) or {}
        p.licenses = MySQL.query.await([[SELECT `id`,`type`,`status`,`issuedBy`,`updatedBy`,`note`,`origin`,UNIX_TIMESTAMP(`issuedAt`) AS `issuedAt`,
            UNIX_TIMESTAMP(`updatedAt`) AS `updatedAt` FROM `es_mdt_weapon_licenses` WHERE `charId` = ? ORDER BY `type`]], { cid }) or {}
        if #p.licenses > 0 then
            local lids, byId = {}, {}
            for _, l in ipairs(p.licenses) do lids[#lids + 1] = l.id byId[l.id] = l l.log = {} end
            local lg = MySQL.query.await(([[SELECT `licenseId`,`byCharId`,`action`,`note`,UNIX_TIMESTAMP(`createdAt`) AS `at` FROM `es_mdt_weapon_license_log`
                WHERE `licenseId` IN (%s) ORDER BY `id` DESC LIMIT 60]]):format(marks(#lids)), lids) or {}
            local ids = {}
            for _, x in ipairs(lg) do ids[#ids + 1] = x.byCharId end
            for _, l in ipairs(p.licenses) do ids[#ids + 1] = l.issuedBy end
            local names = namesOf(ids)
            for _, x in ipairs(lg) do x.byName = x.byCharId and (names[x.byCharId] or ('#' .. x.byCharId)) or 'System' table.insert(byId[x.licenseId].log, x) end
            for _, l in ipairs(p.licenses) do l.issuedByName = l.issuedBy and names[l.issuedBy] or nil end
        end
        -- 1.8.0: firearm permit at a glance, plus their applications
        p.permit = { type = MDT.permitType, label = MDT.permitLabel, status = 'none' }
        for _, l in ipairs(p.licenses) do if l.type == MDT.permitType then p.permit.status = l.status p.permit.origin = l.origin end end
        p.permitApps = MySQL.query.await([[SELECT `id`,`status`,`reason`,`decisionNote`,`decidedByLabel`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt`,UNIX_TIMESTAMP(`decidedAt`) AS `decidedAt`
            FROM `es_mdt_permit_apps` WHERE `charId` = ? ORDER BY `id` DESC LIMIT 5]], { cid }) or {}
        local jobs = ED:GetPlayerDepartments({ charId = cid }) or {}
        p.departments = {}
        for _, j in ipairs(jobs) do p.departments[#p.departments + 1] = { short = j.short, roleName = j.roleName, callsign = j.callsign } end
        return p
    end)

    cb('profileSave', { perm = 'mdt_reports_write', write = true }, function(c, d)
        local cid = id(d.charId)
        if not cid then return false, 'Pick a person' end
        local flags = cleanFlags(d.flags, Config.PersonFlags)
        MySQL.update.await([[INSERT INTO `es_mdt_profiles` (`charId`,`notes`,`flags`,`updatedBy`) VALUES (?,?,?,?)
            ON DUPLICATE KEY UPDATE `notes` = VALUES(`notes`), `flags` = VALUES(`flags`), `updatedBy` = VALUES(`updatedBy`)]],
            { cid, str(d.notes, 4000), json.encode(flags), c.charId })
        log(c, 'profile', ('char %d'):format(cid))
        refresh('people')
        return true
    end)

    -- vehicles
    cb('vehicles', { rate = 300, burst = 6 }, function(c, d)
        local q = str(d.q, 10):upper()
        if #q < 2 then return {} end
        local rows = MySQL.query.await([[SELECT v.`vehicleId`, v.`plate`, v.`model`, v.`state`, v.`ownerCharId`, COALESCE(k.`displayName`, v.`model`) AS `label`,
            n.`flags`, (SELECT COUNT(*) FROM `es_mdt_bolos` b WHERE b.`plate` = v.`plate` AND b.`status` = 'active') AS `bolos`
            FROM `vehicles` v LEFT JOIN `vehicle_catalog` k ON k.`model` = v.`model` LEFT JOIN `es_mdt_vehicle_notes` n ON n.`vehicleId` = v.`vehicleId`
            WHERE REPLACE(v.`plate`,' ','') LIKE CONCAT('%', REPLACE(?,' ',''), '%') ORDER BY v.`plate` LIMIT ?]], { q, Config.SearchLimit }) or {}
        local ids = {}
        for _, r in ipairs(rows) do ids[#ids + 1] = r.ownerCharId end
        local names = namesOf(ids)
        for _, r in ipairs(rows) do r.owner = r.ownerCharId and names[r.ownerCharId] or nil r.flags = flagsOf(r.flags) r.bolos = tonumber(r.bolos) or 0 end
        -- a plate nobody owns still answers if a BOLO names it
        if #rows == 0 then
            local b = MySQL.query.await("SELECT `id`,`plate`,`title` FROM `es_mdt_bolos` WHERE `kind` = 'vehicle' AND `status` = 'active' AND `plate` LIKE CONCAT('%', ?, '%') LIMIT 10", { q }) or {}
            for _, x in ipairs(b) do rows[#rows + 1] = { plate = x.plate, label = 'Unregistered', bolos = 1, flags = {}, boloOnly = true } end
        end
        return rows
    end)

    cb('vehicle', { rate = 300, burst = 6 }, function(c, d)
        local vid = id(d.vehicleId)
        if not vid then return false, 'Pick a vehicle' end
        local v = MySQL.single.await([[SELECT v.`vehicleId`, v.`plate`, v.`model`, v.`state`, v.`garage`, v.`ownerCharId`, UNIX_TIMESTAMP(v.`createdAt`) AS `createdAt`,
            COALESCE(k.`displayName`, v.`model`) AS `label`, k.`class` FROM `vehicles` v LEFT JOIN `vehicle_catalog` k ON k.`model` = v.`model` WHERE v.`vehicleId` = ?]], { vid })
        if not v then return false, 'No such vehicle' end
        local n = MySQL.single.await('SELECT `notes`,`flags` FROM `es_mdt_vehicle_notes` WHERE `vehicleId` = ?', { vid })
        v.notes, v.flags = n and n.notes or '', n and flagsOf(n.flags) or {}
        v.owner = v.ownerCharId and (namesOf({ v.ownerCharId })[v.ownerCharId]) or nil
        v.bolos = MySQL.query.await("SELECT `id`,`title`,`description`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt` FROM `es_mdt_bolos` WHERE `plate` = ? AND `status` = 'active'", { v.plate }) or {}
        return v
    end)

    cb('vehicleSave', { perm = 'mdt_reports_write', write = true }, function(c, d)
        local vid = id(d.vehicleId)
        if not vid then return false, 'Pick a vehicle' end
        local flags = cleanFlags(d.flags, Config.VehicleFlags)
        MySQL.update.await([[INSERT INTO `es_mdt_vehicle_notes` (`vehicleId`,`notes`,`flags`,`updatedBy`) VALUES (?,?,?,?)
            ON DUPLICATE KEY UPDATE `notes` = VALUES(`notes`), `flags` = VALUES(`flags`), `updatedBy` = VALUES(`updatedBy`)]],
            { vid, str(d.notes, 4000), json.encode(flags), c.charId })
        return true
    end)

    -- penal code
    cb('penal', { rate = 500, burst = 4 }, function(c)
        return MySQL.query.await(("SELECT `id`,`code`,`title`,`category`,`fine`,`months`,`description`,`active` FROM `es_penal_code` %s ORDER BY FIELD(`category`,'infraction','misdemeanor','felony'), `code`")
            :format(c.staff and '' or 'WHERE `active` = 1')) or {}
    end)

    cb('penalSave', {}, function(c, d)
        if not c.staff then return false, 'Only admins can edit the penal code' end
        local code, title = str(d.code, 16):upper(), str(d.title, 120)
        local cat = ({ infraction = 1, misdemeanor = 1, felony = 1 })[d.category] and d.category or nil
        if code == '' or title == '' or not cat then return false, 'Code, title and category are needed' end
        local fine, months = int(d.fine, 0, Config.FineMax), int(d.months, 0, 9999)
        local pid = id(d.id)
        local dup = MySQL.single.await('SELECT `id` FROM `es_penal_code` WHERE `code` = ? AND `id` <> ?', { code, pid or 0 })
        if dup then return false, 'Another charge already uses code ' .. code end
        if pid then
            MySQL.update.await('UPDATE `es_penal_code` SET `code`=?,`title`=?,`category`=?,`fine`=?,`months`=?,`description`=?,`active`=? WHERE `id`=?',
                { code, title, cat, fine, months, str(d.description, 500), d.active == false and 0 or 1, pid })
        else
            pid = MySQL.insert.await('INSERT INTO `es_penal_code` (`code`,`title`,`category`,`fine`,`months`,`description`) VALUES (?,?,?,?,?,?)',
                { code, title, cat, fine, months, str(d.description, 500) })
        end
        log(c, 'penal', code)
        return pid
    end)

    -- reports
    cb('reports', { rate = 300, burst = 6 }, function(c, d)
        -- your department's reports, plus any you are listed on as an officer (a partner from another department)
        local where, args = { '(r.`deptId` = ? OR r.`id` IN (SELECT ro.`reportId` FROM `es_mdt_report_officers` ro WHERE ro.`charId` = ?))' }, { c.dept.id, c.charId }
        local t = str(d.type, 16)
        if t ~= '' then where[#where + 1] = 'r.`type` = ?' args[#args + 1] = t end
        if d.mine then
            where[#where + 1] = '(r.`authorCharId` = ? OR r.`id` IN (SELECT ro2.`reportId` FROM `es_mdt_report_officers` ro2 WHERE ro2.`charId` = ?))'
            args[#args + 1] = c.charId args[#args + 1] = c.charId
        end
        local q = str(d.q, 60)
        if q ~= '' then
            if q:match('^#?%d+$') then where[#where + 1] = 'r.`id` = ?' args[#args + 1] = tonumber((q:gsub('#', '')))
            else
                where[#where + 1] = [[(r.`title` LIKE CONCAT('%', ?, '%') OR r.`id` IN (SELECT pp.`reportId` FROM `es_mdt_report_people` pp
                    JOIN `characters` ch ON ch.`charId` = pp.`charId` WHERE CONCAT(ch.`firstName`,' ',ch.`lastName`) LIKE CONCAT('%', ?, '%')))]]
                args[#args + 1] = q args[#args + 1] = q
            end
        end
        args[#args + 1] = int(d.offset, 0, 100000)
        local rows = MySQL.query.await(([[SELECT r.`id`, r.`type`, r.`title`, r.`location`, r.`authorCharId`, UNIX_TIMESTAMP(r.`createdAt`) AS `createdAt`,
            (SELECT COUNT(*) FROM `es_mdt_report_people` pp WHERE pp.`reportId` = r.`id`) AS `people`,
            (SELECT COUNT(*) FROM `es_mdt_report_charges` rc WHERE rc.`reportId` = r.`id`) AS `charges`,
            (SELECT COALESCE(SUM(rc.`fine` * rc.`count`), 0) FROM `es_mdt_report_charges` rc WHERE rc.`reportId` = r.`id`) AS `totalFine`,
            (SELECT COALESCE(SUM(rc.`months` * rc.`count`), 0) FROM `es_mdt_report_charges` rc WHERE rc.`reportId` = r.`id`) AS `totalMonths`,
            (SELECT COUNT(*) FROM `es_mdt_report_people` pp WHERE pp.`reportId` = r.`id` AND pp.`role` = 'suspect') AS `suspects`,
            (SELECT CONCAT(ch.`firstName`,' ',ch.`lastName`) FROM `es_mdt_report_people` pp JOIN `characters` ch ON ch.`charId` = pp.`charId`
                WHERE pp.`reportId` = r.`id` AND pp.`role` = 'suspect' ORDER BY pp.`charId` LIMIT 1) AS `suspect`,
            LEFT(r.`body`, 160) AS `preview`,
            (SELECT COUNT(*) FROM `es_mdt_report_log` rl WHERE rl.`reportId` = r.`id` AND rl.`what` = 'edited') AS `edits`
            FROM `es_mdt_reports` r WHERE %s ORDER BY r.`id` DESC LIMIT 40 OFFSET ?]]):format(table.concat(where, ' AND ')), args) or {}
        local ids = {}
        for _, r in ipairs(rows) do ids[#ids + 1] = r.authorCharId end
        local names = namesOf(ids)
        for _, r in ipairs(rows) do
            r.authorName = names[r.authorCharId]
            r.totalFine, r.totalMonths, r.suspects = tonumber(r.totalFine) or 0, tonumber(r.totalMonths) or 0, tonumber(r.suspects) or 0
            r.edits = tonumber(r.edits) or 0
        end
        return rows
    end)

    cb('report', { rate = 300, burst = 6 }, function(c, d)
        local rid = id(d.id)
        if not rid then return false, 'Pick a report' end
        local x, why = reportFull(c, rid)
        if type(x) == 'table' then x.ver = verOf('report:' .. rid) end
        return x, why
    end)

    -- 1.8.0: "someone else is editing this": the editor pings every 15 s while open; answers who else has it open
    cb('editing', { rate = 2000, burst = 4 }, function(c, d)
        local kind = ({ report = 1, case = 1 })[d.kind] and d.kind or nil
        local rid = id(d.id)
        if not kind or not rid then return {} end
        local k = kind .. ':' .. rid
        local t = os.time()
        local e = Editing[k] or {}
        Editing[k] = e
        if d.done then e[c.charId] = nil else e[c.charId] = { name = c.name, at = t, since = (e[c.charId] and e[c.charId].since) or t } end
        local out = {}
        for cid, x in pairs(e) do
            if t - x.at > 40 then e[cid] = nil
            elseif cid ~= c.charId then out[#out + 1] = { name = x.name, since = x.since } end
        end
        if not next(e) then Editing[k] = nil end
        return { others = out, ver = verOf(k) }
    end)

    cb('reportSave', { perm = 'mdt_reports_write', write = true, rate = 1000, burst = 3, lock = 'report' }, function(c, d)
        local rid = id(d.id)
        if rid then
            local r = MySQL.single.await('SELECT `id`,`deptId`,`authorCharId` FROM `es_mdt_reports` WHERE `id` = ?', { rid })
            if not r then return false, 'No such report' end
            if not canEditReport(c, r) then return false, 'Only its author, the officers on it, a supervisor or high command can edit this report' end
        end
        local old = rid and reportSnapshot(rid)
        local typ = 'incident'
        for _, t in ipairs(Config.ReportTypes) do if d.type == t.key then typ = t.key end end
        local title = str(d.title, 120)
        if title == '' then return false, 'Give the report a title' end
        -- people, officers and charges, checked
        local people, seen = {}, {}
        for _, p in ipairs(type(d.people) == 'table' and d.people or {}) do
            local cid = id(type(p) == 'table' and p.charId)
            local role = type(p) == 'table' and ({ suspect = 1, victim = 1, witness = 1, other = 1 })[p.role] and p.role or 'suspect'
            if cid and not seen[cid] and #people < 30 then seen[cid] = true people[#people + 1] = { cid, role } end
        end
        local officers, oseen = { { c.charId, 1 } }, { [c.charId] = true }
        if rid then
            local r = MySQL.single.await('SELECT `authorCharId` FROM `es_mdt_reports` WHERE `id` = ?', { rid })
            officers, oseen = { { r.authorCharId, 1 } }, { [r.authorCharId] = true }
        end
        for _, o in ipairs(type(d.officers) == 'table' and d.officers or {}) do
            local cid = id(o)
            if cid and not oseen[cid] and #officers < 20 then oseen[cid] = true officers[#officers + 1] = { cid, 0 } end
        end
        -- a new report from someone in a paired unit lists their partner too
        if not rid then
            local t = Teams[TeamOf[c.charId] or 0]
            local partner = t and (t.lead == c.charId and t.partner or t.lead)
            if partner and not oseen[partner] then oseen[partner] = true officers[#officers + 1] = { partner, 0 } end
        end
        local charges = {}
        local penal = {}
        local CO = Config.ChargeOverride or {}
        local fMult, mMult = tonumber(CO.maxFineMult) or 1.0, tonumber(CO.maxMonthsMult) or 1.0
        for _, p in ipairs(MySQL.query.await('SELECT `id`,`code`,`title`,`category`,`fine`,`months` FROM `es_penal_code`') or {}) do penal[p.id] = p end
        for _, ch in ipairs(type(d.charges) == 'table' and d.charges or {}) do
            local cid, pid = id(type(ch) == 'table' and ch.charId), id(type(ch) == 'table' and ch.penalId)
            local pc = pid and penal[pid]
            if cid and pc and seen[cid] and #charges < 100 then
                local maxF, maxM = math.floor(pc.fine * fMult + 0.5), math.floor(pc.months * mMult + 0.5)
                local f = tonumber(ch.fine) and int(ch.fine, 0, maxF) or math.min(pc.fine, maxF)
                local m = tonumber(ch.months) and int(ch.months, 0, maxM) or math.min(pc.months, maxM)
                charges[#charges + 1] = { cid, pc.id, pc.code, pc.title, pc.category, int(ch.count, 1, 20), f, m, pc.fine, pc.months }
            end
        end
        local weapons, wseen = {}, {}
        for _, w in ipairs(type(d.weapons) == 'table' and d.weapons or {}) do
            local sr = type(w) == 'table' and serialOf(w.serial)
            if sr and not wseen[sr] and #weapons < 30 then wseen[sr] = true weapons[#weapons + 1] = { sr, WROLES[w.role] and w.role or 'evidence' } end
        end
        local body, loc = str(d.body, 20000), str(d.location, 120)
        local qs = {}
        -- what the charges were, to log every change to a fine or jail time
        local before, isNew = {}, rid == nil
        if rid then
            for _, o in ipairs(MySQL.query.await('SELECT `charId`,`penalId`,`code`,`title`,`count`,`fine`,`months` FROM `es_mdt_report_charges` WHERE `reportId` = ?', { rid }) or {}) do
                before[o.charId .. ':' .. tostring(o.penalId)] = o
            end
        end
        -- what changed, field by field (old -> new), for the report's History
        local pnames = {}
        do
            local ids = {}
            for _, p in ipairs(people) do ids[#ids + 1] = p[1] end
            for _, o in ipairs(officers) do ids[#ids + 1] = o[1] end
            for _, p in ipairs(old and old.people or {}) do ids[#ids + 1] = p.charId end
            for _, o in ipairs(old and old.officers or {}) do ids[#ids + 1] = o.charId end
            pnames = namesOf(ids)
        end
        local function nm(cid) return pnames[cid] or ('#' .. cid) end
        local function short(v, n) v = tostring(v or ''):gsub('%s+', ' ') if #v > n then v = v:sub(1, n - 1) .. '…' end return v == '' and '(empty)' or ('"' .. v .. '"') end
        local logs, changed = {}, {}
        local function add(what, field, detail) logs[#logs + 1] = { what, detail } changed[field] = true end
        if old then
            if old.type ~= typ then add('change', 'type', ('Type: %s → %s'):format(old.type, typ)) end
            if (old.title or '') ~= title then add('change', 'title', ('Title: %s → %s'):format(short(old.title, 200), short(title, 200))) end
            if (old.location or '') ~= loc then add('change', 'location', ('Location: %s → %s'):format(short(old.location, 200), short(loc, 200))) end
            if (old.body or '') ~= body then
                add('change', 'narrative', ('Narrative (%d → %d characters): %s → %s'):format(#(old.body or ''), #body, short(old.body, 200), short(body, 200)))
            end
            local op, np = {}, {}
            for _, p in ipairs(old.people) do op[p.charId] = p.role end
            for _, p in ipairs(people) do np[p[1]] = p[2] end
            for cid, role in pairs(np) do
                if not op[cid] then add('change', 'people', ('Person added: %s (%s)'):format(nm(cid), role))
                elseif op[cid] ~= role then add('change', 'people', ('%s: %s → %s'):format(nm(cid), op[cid], role)) end
            end
            for cid, role in pairs(op) do if not np[cid] then add('change', 'people', ('Person removed: %s (%s)'):format(nm(cid), role)) end end
            local oo, no = {}, {}
            for _, o in ipairs(old.officers) do oo[o.charId] = true end
            for _, o in ipairs(officers) do no[o[1]] = true end
            for cid in pairs(no) do if not oo[cid] then add('change', 'officers', ('Officer added: %s'):format(nm(cid))) end end
            for cid in pairs(oo) do if not no[cid] then add('change', 'officers', ('Officer removed: %s'):format(nm(cid))) end end
        end
        local newKeys = {}
        for _, ch in ipairs(charges) do
            local key = ch[1] .. ':' .. ch[2]
            newKeys[key] = true
            local who, o = nm(ch[1]), before[key]
            if o and (o.fine ~= ch[7] or o.months ~= ch[8]) then
                add('charge_edit', 'charges', ('%s · %s %s: fine $%d → $%d, jail %d → %d mo (penal code $%d, %d mo)'):format(who, ch[3], ch[4], o.fine, ch[7], o.months, ch[8], ch[9], ch[10]))
            elseif not o and (ch[7] ~= ch[9] or ch[8] ~= ch[10]) then
                add('charge_set', 'charges', ('%s · %s %s: fine $%d (penal code $%d), jail %d mo (penal code %d)'):format(who, ch[3], ch[4], ch[7], ch[9], ch[8], ch[10]))
            end
            if o and (tonumber(o.count) or 1) ~= ch[6] then add('change', 'charges', ('%s · %s %s: count %d → %d'):format(who, ch[3], ch[4], tonumber(o.count) or 1, ch[6])) end
            if not o and old then add('change', 'charges', ('Charge added: %s · %s %s ×%d'):format(who, ch[3], ch[4], ch[6])) end
        end
        for key, o in pairs(before) do
            if not newKeys[key] then add('change', 'charges', ('Charge removed: %s · %s %s ×%d'):format(nm(o.charId), o.code or '', o.title or '', tonumber(o.count) or 1)) end
        end
        local ow, wAdded = {}, {}
        for _, w in ipairs(old and old.weapons or {}) do ow[w.serial] = w.role end
        for _, w in ipairs(weapons) do
            if not ow[w[1]] then wAdded[#wAdded + 1] = w if old then add('change', 'weapons', ('Weapon added: %s (%s)'):format(w[1], w[2])) end
            elseif ow[w[1]] ~= w[2] then wAdded[#wAdded + 1] = w add('change', 'weapons', ('Weapon %s: %s → %s'):format(w[1], ow[w[1]], w[2])) end
        end
        for sr, role in pairs(ow) do if not wseen[sr] then add('change', 'weapons', ('Weapon removed: %s (%s)'):format(sr, role)) end end
        if old and not next(changed) then return rid end   -- saved with nothing changed: nothing to write or log
        if old then
            local fields = {}
            for _, f in ipairs({ 'type', 'title', 'location', 'narrative', 'people', 'officers', 'charges', 'weapons' }) do if changed[f] then fields[#fields + 1] = f end end
            local hc = old.authorCharId ~= c.charId and isHighCommand(c) and ' (high command)' or ''
            table.insert(logs, 1, { 'edited', ('Edited%s: %s'):format(hc, table.concat(fields, ', ')) })
        else
            table.insert(logs, 1, { 'filed', 'Report filed' })
        end
        if not rid then
            rid = MySQL.insert.await('INSERT INTO `es_mdt_reports` (`deptId`,`type`,`title`,`body`,`location`,`authorCharId`) VALUES (?,?,?,?,?,?)',
                { c.dept.id, typ, title, body, loc, c.charId })
            if not rid then return false, 'Could not save the report (database error)' end
        else
            qs[#qs + 1] = { query = 'UPDATE `es_mdt_reports` SET `type`=?,`title`=?,`body`=?,`location`=? WHERE `id`=?', values = { typ, title, body, loc, rid } }
        end
        qs[#qs + 1] = { query = 'DELETE FROM `es_mdt_report_people` WHERE `reportId` = ?', values = { rid } }
        qs[#qs + 1] = { query = 'DELETE FROM `es_mdt_report_officers` WHERE `reportId` = ?', values = { rid } }
        qs[#qs + 1] = { query = 'DELETE FROM `es_mdt_report_charges` WHERE `reportId` = ?', values = { rid } }
        qs[#qs + 1] = { query = 'DELETE FROM `es_mdt_report_weapons` WHERE `reportId` = ?', values = { rid } }
        for _, w in ipairs(weapons) do qs[#qs + 1] = { query = 'INSERT INTO `es_mdt_report_weapons` (`reportId`,`serial`,`role`) VALUES (?,?,?)', values = { rid, w[1], w[2] } } end
        -- the weapons' own history: listed on this report (and, for a seizure by someone allowed to, marked seized)
        local seizeNow = {}
        if #wAdded > 0 then
            local ser = {}
            for _, w in ipairs(wAdded) do ser[#ser + 1] = w[1] end
            local reg = {}
            for _, r in ipairs(MySQL.query.await(('SELECT `id`,`serial`,`status` FROM `es_mdt_weapons` WHERE `serial` IN (%s)'):format(marks(#ser)), ser) or {}) do reg[r.serial] = r end
            for _, w in ipairs(wAdded) do
                local r = reg[w[1]]
                if r then
                    qs[#qs + 1] = weaponLog(r.id, c.charId, 'report', ('Listed on report #%d (%s): %s'):format(rid, w[2], title), rid)
                    if w[2] == 'seized' and c.perms.weapons_manage and (r.status == 'registered' or r.status == 'stolen') then
                        qs[#qs + 1] = { query = "UPDATE `es_mdt_weapons` SET `status` = 'seized' WHERE `id` = ?", values = { r.id } }
                        qs[#qs + 1] = weaponLog(r.id, c.charId, 'status', ('%s → seized (report #%d)'):format(r.status, rid), rid)
                        seizeNow[#seizeNow + 1] = w[1]
                    end
                end
            end
        end
        for _, p in ipairs(people) do qs[#qs + 1] = { query = 'INSERT INTO `es_mdt_report_people` (`reportId`,`charId`,`role`) VALUES (?,?,?)', values = { rid, p[1], p[2] } } end
        for _, o in ipairs(officers) do qs[#qs + 1] = { query = 'INSERT INTO `es_mdt_report_officers` (`reportId`,`charId`,`primary`) VALUES (?,?,?)', values = { rid, o[1], o[2] } } end
        for _, ch in ipairs(charges) do
            qs[#qs + 1] = { query = 'INSERT INTO `es_mdt_report_charges` (`reportId`,`charId`,`penalId`,`code`,`title`,`category`,`count`,`fine`,`months`,`baseFine`,`baseMonths`) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
                values = { rid, ch[1], ch[2], ch[3], ch[4], ch[5], ch[6], ch[7], ch[8], ch[9], ch[10] } }
        end
        if old then
            qs[#qs + 1] = { query = 'INSERT INTO `es_mdt_report_audit` (`reportId`,`deptId`,`byCharId`,`what`,`title`,`snapshot`) VALUES (?,?,?,?,?,?)',
                values = { rid, old.deptId, c.charId, 'edit', old.title, json.encode(old) } }
        end
        for _, l in ipairs(logs) do
            qs[#qs + 1] = { query = 'INSERT INTO `es_mdt_report_log` (`reportId`,`byCharId`,`what`,`detail`) VALUES (?,?,?,?)', values = { rid, c.charId, l[1], l[2]:sub(1, 500) } }
        end
        local ok = MySQL.transaction.await(qs)
        if not ok then return false, 'Could not save the report (database error)' end
        log(c, 'report', ('#%d %s: %s'):format(rid, typ, title))
        for _, sr in ipairs(seizeNow) do closeWeaponBolos(sr, c.charId) end
        if #weapons > 0 or (old and old.weapons and #old.weapons > 0) then refresh('weapons') end
        refresh('reports')
        if typ == 'arrest' then
            pcall(function() WC:SendDirectorEvent('police.arrested', { source = c.source, reportId = rid }) end)
        end
        return rid
    end)

    --- High command (or an admin) only. The whole report is kept in es_mdt_report_audit first.
    cb('reportDelete', { write = true }, function(c, d)
        local rid = id(d.id)
        local r = rid and MySQL.single.await('SELECT `id`,`deptId`,`title`,`authorCharId` FROM `es_mdt_reports` WHERE `id` = ?', { rid })
        if not r then return false, 'No such report' end
        if not c.staff and r.deptId ~= c.dept.id then return false, 'That report belongs to another department' end
        if not canDeleteReport(c, r) then return false, 'Only high command can delete a report' end
        local snap = reportSnapshot(rid)
        if snap then
            snap.log = MySQL.query.await('SELECT `byCharId`,`what`,`detail`,UNIX_TIMESTAMP(`createdAt`) AS `at` FROM `es_mdt_report_log` WHERE `reportId` = ? ORDER BY `id`', { rid }) or {}
        end
        local ok = MySQL.transaction.await({
            { query = 'INSERT INTO `es_mdt_report_audit` (`reportId`,`deptId`,`byCharId`,`what`,`title`,`snapshot`) VALUES (?,?,?,?,?,?)',
                values = { rid, r.deptId, c.charId, 'delete', r.title, json.encode(snap or {}) } },
            { query = 'DELETE FROM `es_mdt_reports` WHERE `id` = ?', values = { rid } },
        })
        if not ok then return false, 'Could not delete the report (database error)' end
        log(c, 'report_delete', ('#%d %s (kept in es_mdt_report_audit)'):format(rid, r.title))
        refresh('reports')
        return true
    end)

    -- fines
    cb('fineReport', { perm = 'fines_issue', write = true, rate = 1000, burst = 3 }, function(c, d)
        local rid, cid = id(d.reportId), id(d.charId)
        local r = rid and MySQL.single.await('SELECT `id`,`deptId`,`title` FROM `es_mdt_reports` WHERE `id` = ?', { rid })
        if not r or not cid then return false, 'Pick a report and a person' end
        if not c.staff and r.deptId ~= c.dept.id then return false, 'That report belongs to another department' end
        local s = MySQL.single.await('SELECT SUM(`fine` * `count`) AS `t` FROM `es_mdt_report_charges` WHERE `reportId` = ? AND `charId` = ?', { rid, cid })
        local total = s and tonumber(s.t) or 0
        if total < 1 then return false, 'No fines in their charges' end
        return issueFine(c, cid, math.min(total, Config.FineMax), ('Report #%d'):format(rid), rid)
    end)

    cb('fineCustom', { perm = 'fines_issue', write = true, rate = 1000, burst = 3 }, function(c, d)
        local cid = id(d.charId)
        if not cid then return false, 'Pick a person' end
        local reason = str(d.reason, 200)
        if reason == '' then return false, 'Say what the fine is for' end
        return issueFine(c, cid, int(d.amount, 0, Config.FineMax), reason, nil)
    end)

    cb('fineAct', { perm = 'fines_issue', write = true }, function(c, d)
        local f = MySQL.single.await('SELECT `id`,`deptId`,`charId`,`amount`,`reason`,`status`,`issuedBy` FROM `es_mdt_fines` WHERE `id` = ?', { id(d.id) or 0 })
        if not f then return false, 'No such fine' end
        if f.status ~= 'unpaid' then return false, 'That fine is already ' .. f.status end
        if d.action == 'pay' then
            local ok, why = payFine(f)
            if not ok then return false, 'Still unpaid: ' .. tostring(why) end
            return true
        elseif d.action == 'void' then
            if not (c.staff or f.issuedBy == c.charId or c.perms.canManage) then return false, 'Only who issued it or a supervisor can void it' end
            MySQL.update.await("UPDATE `es_mdt_fines` SET `status` = 'void' WHERE `id` = ?", { f.id })
            closeAutoWarrant(f.id, 'void')
            refresh('fines')
            log(c, 'fine_void', ('#%d'):format(f.id))
            return true
        end
        return false, 'pay or void'
    end)

    -- warrants (shared by every department)
    cb('warrants', { rate = 300, burst = 6 }, function(c, d)
        local st = ({ active = 1, requested = 1, served = 1, void = 1 })[d.status] and d.status or nil
        local rows = MySQL.query.await(([[SELECT `id`,`deptId`,`charId`,`reportId`,`reason`,`status`,`requestedBy`,`issuedBy`,`auto`,`fineId`,`kind`,`scope`,`judgeName`,`judgeNote`,
            UNIX_TIMESTAMP(`createdAt`) AS `createdAt`, UNIX_TIMESTAMP(`expiresAt`) AS `expiresAt` FROM `es_mdt_warrants` %s ORDER BY `id` DESC LIMIT 100]])
            :format(st and 'WHERE `status` = ?' or "WHERE `status` IN ('active','requested')"), st and { st } or {}) or {}
        local ids, ds = {}, deptShort()
        for _, w in ipairs(rows) do ids[#ids + 1] = w.charId ids[#ids + 1] = w.requestedBy end
        local names = namesOf(ids)
        for _, w in ipairs(rows) do
            w.name, w.requestedByName = names[w.charId], names[w.requestedBy]
            w.deptShort = ds[w.deptId] and ds[w.deptId].short
            local sys = systemIssuer(w)
            if sys then w.requestedByName, w.system = sys, true end
            if w.status == 'active' and w.expiresAt and w.expiresAt < os.time() then w.expired = true end
            w.auto = w.auto == 1 or w.auto == true
        end
        return rows
    end)

    cb('warrantCounts', { rate = 300, burst = 6 }, function(c)
        local out = { open = 0, active = 0, requested = 0, served = 0, void = 0 }
        for _, r in ipairs(MySQL.query.await('SELECT `status`, COUNT(*) AS `n` FROM `es_mdt_warrants` GROUP BY `status`') or {}) do
            out[r.status] = tonumber(r.n) or 0
        end
        out.open = out.active + out.requested
        return out
    end)

    cb('warrantSave', { write = true, rate = 1000, burst = 3 }, function(c, d)
        if not (c.perms.warrants_issue or c.perms.warrants_request) then return false, 'Your rank cannot request warrants' end
        local cid = id(d.charId)
        if not cid then return false, 'Pick a person' end
        local reason = str(d.reason, 500)
        if reason == '' then return false, 'Give the reason' end
        local days = int(d.days, 0, 90)
        -- 1.9.0: arrest or search warrant; with es_doj in judge-only mode every warrant waits for a judge
        local kind = d.kind == 'search' and 'search' or 'arrest'
        local scope = kind == 'search' and str(d.scope, 300) or nil
        if kind == 'search' and (scope or '') == '' then return false, 'Say what is to be searched (an address, a vehicle plate, a phone)' end
        local st = (c.perms.warrants_issue and not judgeOnly()) and 'active' or 'requested'
        -- 1.5.0: a warrant can be issued from (and belong to) a case
        local caseRow = id(d.caseId) and MySQL.single.await("SELECT `id`,`status` FROM `es_mdt_cases` WHERE `id` = ?", { id(d.caseId) })
        if caseRow and caseRow.status == 'archived' then return false, 'That case is archived' end
        local wid = MySQL.insert.await([[INSERT INTO `es_mdt_warrants` (`deptId`,`charId`,`reportId`,`caseId`,`reason`,`status`,`requestedBy`,`issuedBy`,`expiresAt`,`kind`,`scope`)
            VALUES (?,?,NULLIF(?,0),?,?,?,?,NULLIF(?,0),IF(? = 0, NULL, NOW() + INTERVAL ? DAY),?,?)]],
            { c.dept.id, cid, id(d.reportId) or 0, caseRow and caseRow.id or nil, reason, st, c.charId, st == 'active' and c.charId or 0, days, days, kind, scope })
        if wid and caseRow and MDT.caseLog then MDT.caseLog(caseRow.id, c, 'warrant', ('Warrant #%d (%s)'):format(wid, st)) end
        if not wid then return false, 'Could not save the warrant' end
        log(c, 'warrant', ('#%d char %d %s'):format(wid, cid, st))
        refresh('warrants')
        if st == 'active' then warrantBolosSoon(c) end
        if st == 'requested' then TriggerEvent('es_mdt:warrantRequested', wid) end   -- es_doj tells the judges
        return { id = wid, status = st, judge = st == 'requested' and judgeOnly() or nil }
    end)

    cb('warrantAct', { write = true }, function(c, d)
        local w = MySQL.single.await('SELECT `id`,`status` FROM `es_mdt_warrants` WHERE `id` = ?', { id(d.id) or 0 })
        if not w then return false, 'No such warrant' end
        if d.action == 'approve' then
            if not c.perms.warrants_issue then return false, 'Your rank cannot issue warrants' end
            if judgeOnly() and not c.staff then return false, 'A judge signs warrants (DOJ). It waits in their queue.' end
            if w.status ~= 'requested' then return false, 'That warrant is not waiting' end
            MySQL.update.await("UPDATE `es_mdt_warrants` SET `status` = 'active', `issuedBy` = ? WHERE `id` = ?", { c.charId, w.id })
        elseif d.action == 'serve' then
            if w.status ~= 'active' then return false, 'That warrant is not active' end
            MySQL.update.await("UPDATE `es_mdt_warrants` SET `status` = 'served', `closedBy` = ? WHERE `id` = ?", { c.charId, w.id })
        elseif d.action == 'void' then
            if not c.perms.warrants_issue then return false, 'Your rank cannot void warrants' end
            if w.status == 'served' or w.status == 'void' then return false, 'That warrant is already closed' end
            MySQL.update.await("UPDATE `es_mdt_warrants` SET `status` = 'void', `closedBy` = ? WHERE `id` = ?", { c.charId, w.id })
        else return false, 'approve, serve or void' end
        log(c, 'warrant_' .. d.action, ('#%d'):format(w.id))
        refresh('warrants')
        warrantBolosSoon(c)
        return true
    end)

    -- BOLOs (shared)
    cb('bolos', { rate = 300, burst = 6 }, function(c, d)
        local rows = MySQL.query.await(([[SELECT `id`,`deptId`,`kind`,`charId`,`plate`,`serial`,`title`,`description`,`status`,`createdBy`,`lastX`,`lastY`,`warrantId`,
            UNIX_TIMESTAMP(`createdAt`) AS `createdAt`, UNIX_TIMESTAMP(`expiresAt`) AS `expiresAt` FROM `es_mdt_bolos`
            WHERE %s ORDER BY `id` DESC LIMIT 100]]):format(d.closed and "`status` = 'closed'" or "`status` = 'active' AND (`expiresAt` IS NULL OR `expiresAt` > NOW())")) or {}
        local ids, ds = {}, deptShort()
        for _, b in ipairs(rows) do ids[#ids + 1] = b.createdBy if b.charId then ids[#ids + 1] = b.charId end end
        local names = namesOf(ids)
        -- 1.5.7: BOLOs a warrant posted by itself are signed by what made the warrant, not a player
        local wids, wmap = {}, {}
        for _, b in ipairs(rows) do if b.warrantId then wids[#wids + 1] = b.warrantId end end
        if #wids > 0 then
            for _, w in ipairs(MySQL.query.await(('SELECT `id`,`reason`,`issuedBy`,`auto` FROM `es_mdt_warrants` WHERE `id` IN (%s)'):format(marks(#wids)), wids) or {}) do wmap[w.id] = w end
        end
        for _, b in ipairs(rows) do
            b.createdByName, b.name = names[b.createdBy], b.charId and names[b.charId] or nil
            b.deptShort = ds[b.deptId] and ds[b.deptId].short
            local w = b.warrantId and wmap[b.warrantId]
            if w then
                local sys = systemIssuer(w)
                if sys then b.createdByName = sys
                elseif w.auto == 1 or w.auto == true then b.createdByName = ('Automatic · unpaid-fine warrant #%d'):format(w.id)
                else b.createdByName = ('Automatic · warrant #%d'):format(w.id) end
            end
        end
        -- 1.5.6: a face on person BOLOs (MDT mugshot, else the newest mugshot, else the character portrait), first 24 people
        local faces, n = {}, 0
        for _, b in ipairs(rows) do
            if b.kind == 'person' and b.charId and faces[b.charId] == nil and n < 24 then
                n = n + 1
                faces[b.charId] = boloFace(b.charId) or false
            end
            if b.kind == 'person' and b.charId then b.photo = faces[b.charId] or nil end
            b.lastSeen = (b.lastX and b.lastY) and { x = b.lastX, y = b.lastY } or nil
        end
        return rows
    end)

    cb('boloSave', { perm = 'bolo_manage', write = true, rate = 1000, burst = 3 }, function(c, d)
        local kind = (d.kind == 'person' or d.kind == 'weapon') and d.kind or 'vehicle'
        local title = str(d.title, 120)
        if title == '' then return false, 'Give it a title' end
        local plate = kind == 'vehicle' and str(d.plate, 10):upper() or ''
        local cid = kind == 'person' and id(d.charId) or nil
        if kind == 'vehicle' and plate == '' and str(d.description, 1000) == '' then return false, 'Give a plate or a description' end
        local serial = kind == 'weapon' and serialOf(d.serial) or ''
        if kind == 'weapon' and serial == '' and str(d.description, 1000) == '' then return false, 'Give a serial or a description' end
        local hours = int(d.hours, 0, 24 * 30)
        local bid = MySQL.insert.await([[INSERT INTO `es_mdt_bolos` (`deptId`,`kind`,`charId`,`plate`,`serial`,`title`,`description`,`createdBy`,`expiresAt`)
            VALUES (?,?,NULLIF(?,0),NULLIF(?,''),NULLIF(?,''),?,?,?,IF(? = 0, NULL, NOW() + INTERVAL ? HOUR))]],
            { c.dept.id, kind, cid or 0, plate, serial, title, str(d.description, 1000), c.charId, hours, hours })
        if not bid then return false, 'Could not save the BOLO' end
        log(c, 'bolo', ('#%d %s'):format(bid, title))
        refresh('bolos')
        return bid
    end)

    cb('boloClose', { write = true }, function(c, d)
        local b = MySQL.single.await('SELECT `id`,`createdBy`,`status` FROM `es_mdt_bolos` WHERE `id` = ?', { id(d.id) or 0 })
        if not b or b.status ~= 'active' then return false, 'That BOLO is not active' end
        if not (c.perms.bolo_manage or b.createdBy == c.charId) then return false, 'Your rank cannot close BOLOs' end
        MySQL.update.await("UPDATE `es_mdt_bolos` SET `status` = 'closed', `closedBy` = ? WHERE `id` = ?", { c.charId, b.id })
        refresh('bolos')
        return true
    end)

    -- department (leaders)
    cb('dept', { rate = 400, burst = 6 }, function(c)
        local dd = ED:GetDepartment(c.dept.id) or {}
        local roster = ED:GetRoster(c.dept.id) or {}
        local act = ED:GetActivity(c.dept.id) or {}
        local byChar = {}
        for _, m in ipairs(act.members or {}) do byChar[m.charId] = m end
        for _, m in ipairs(roster) do
            m.source = nil
            local a = byChar[m.charId]
            if a then
                m.lastDuty, m.level, m.inactiveDays, m.onLeave, m.neverTracked = a.lastDuty, a.level, a.inactiveDays, a.loa ~= nil, a.neverTracked
            end
        end
        -- 1.7.0: certification badges on the roster (and its filter)
        local okc, badges = pcall(function() return ED:GetCertBadges(c.dept.id) end)
        badges = okc and type(badges) == 'table' and badges or {}
        for _, m in ipairs(roster) do m.certs = badges[m.charId] or badges[tostring(m.charId)] end
        local okd, cl = pcall(function() return ED:GetCerts(c.dept.id) end)
        local certList = {}
        for _, x in ipairs(okd and type(cl) == 'table' and cl.list or {}) do certList[#certList + 1] = { id = x.id, name = x.name, icon = x.icon, color = x.color } end
        return { roster = roster, ranks = dd.ranks or {}, rights = c.rights, myLevel = c.myLevel, me = c.charId,
            thresholds = act.thresholds, staff = c.staff, certList = certList, personnel = c.staff or c.perms.personnel_manage == true }
    end)

    cb('onlinePlayers', { rate = 1000, burst = 4 }, function(c)
        if not (c.staff or (c.rights or {}).hire) then return false, 'Your rank cannot hire' end
        local inDept = {}
        for _, m in ipairs(ED:GetRoster(c.dept.id) or {}) do inDept[m.charId] = true end
        local me = GetPlayerPed(c.source)
        local mp = me and me ~= 0 and GetEntityCoords(me) or nil
        local list, ids = {}, {}
        for key, p in pairs(WC:GetPlayers({ light = true }) or {}) do
            local src = tonumber(key)
            if src and type(p) == 'table' and p.charId and src ~= c.source then
                local dist
                local ped = GetPlayerPed(src)
                if mp and ped and ped ~= 0 then dist = math.floor(#(GetEntityCoords(ped) - mp) + 0.5) end
                list[#list + 1] = { source = src, charId = p.charId, dist = dist, member = inDept[p.charId] == true }
                ids[#ids + 1] = p.charId
            end
        end
        local names = namesOf(ids)
        for _, x in ipairs(list) do x.name = names[x.charId] or ('#' .. x.charId) end
        table.sort(list, function(a, b) return (a.dist or 1e9) < (b.dist or 1e9) end)
        return list
    end)

    cb('hire', { write = true, rate = 1000, burst = 3 }, function(c, d)
        local ok, why = ED:HireMember(c.source, c.dept.id, id(d.target) or 0, id(d.roleId) or 0)
        if ok then refresh('training') end
        return ok, why
    end)
    cb('setRank', { write = true, rate = 800, burst = 3 }, function(c, d)
        return ED:SetMemberRank(c.source, c.dept.id, id(d.charId) or 0, id(d.roleId) or 0, str(d.reason, 500))
    end)
    cb('fire', { write = true, rate = 1500, burst = 2 }, function(c, d)
        return ED:FireMember(c.source, c.dept.id, id(d.charId) or 0, str(d.reason, 500))
    end)
    cb('memberInfo', { write = true, rate = 500, burst = 4 }, function(c, d)
        return ED:SetMemberInfo(c.source, c.dept.id, id(d.charId) or 0, { callsign = d.callsign, badge = d.badge, notes = d.notes })
    end)

    cb('stats', { rate = 1000, burst = 4 }, function(c, d)
        local s, why = ED:GetStats(c.dept.id, { days = int(d.days, 1, 365), top = 5 })
        if not s then return false, why end
        if not (c.perms.loa_manage or c.staff) then s.members = nil end   -- the full list is for leaders
        -- duty seconds per day (the viewer's days: tz = minutes from getTimezoneOffset)
        local days, off = s.days or 30, -int(d.tz, -900, 900) * 60
        local now = os.time()
        local today = math.floor((now + off) / 86400)
        local daily = {}
        for i = 1, days do daily[i] = 0 end
        local rows = MySQL.query.await([[SELECT UNIX_TIMESTAMP(`startedAt`) AS `s`, UNIX_TIMESTAMP(COALESCE(`endedAt`, NOW())) AS `e` FROM `es_duty_sessions`
            WHERE `jobId` = ? AND COALESCE(`endedAt`, NOW()) > NOW() - INTERVAL ? DAY]], { c.dept.jobId, days + 1 }) or {}
        for _, r in ipairs(rows) do
            local a, b = tonumber(r.s) or 0, math.min(tonumber(r.e) or 0, now)
            while a < b do
                local di = math.floor((a + off) / 86400)
                local dayEnd = (di + 1) * 86400 - off
                local piece = math.min(b, dayEnd) - a
                local idx = days - (today - di)
                if idx >= 1 and idx <= days then daily[idx] = daily[idx] + piece end
                a = a + piece
            end
        end
        s.daily = daily
        return s
    end)

    cb('officer', { rate = 500, burst = 4 }, function(c, d)
        local cid = id(d.charId)
        if not cid then return false, 'Pick someone' end
        if cid ~= c.charId and not (c.staff or c.perms.loa_manage or c.perms.canPromote or c.perms.fto_train) then return false, 'Only leaders see officer cards' end
        local days = int(d.days, 1, 365)
        local s = ED:GetStats(c.dept.id, { days = days, top = 1 }) or {}
        local m
        for _, x in ipairs(s.members or {}) do if x.charId == cid then m = x end end
        if not m then return false, 'They are not in this department' end
        m.source = nil
        local rep = MySQL.single.await("SELECT COUNT(*) AS `n` FROM `es_mdt_reports` WHERE `authorCharId` = ? AND `deptId` = ? AND `createdAt` > NOW() - INTERVAL ? DAY", { cid, c.dept.id, days })
        local trainee
        for _, t in ipairs(ED:GetTrainees(c.dept.id, { status = 'all' }) or {}) do if t.charId == cid then trainee = t end end
        return { member = m, days = days, reports = rep and tonumber(rep.n) or 0, loas = ED:GetLOAs(c.dept.id, { charId = cid }) or {},
            sessions = ED:GetTrainingSessions(c.dept.id, cid) or {}, trainee = trainee, thresholds = s.thresholds }
    end)

    cb('activity', { perm = 'loa_manage' }, function(c) return ED:GetActivity(c.dept.id) end)

    -- leave
    cb('loaMine', {}, function(c) return ED:GetLOAs(c.dept.id, { charId = c.charId }) or {} end)
    cb('loaList', { perm = 'loa_manage' }, function(c, d)
        return ED:GetLOAs(c.dept.id, { status = ({ pending = 1, active = 1 })[d.status] and d.status or nil }) or {}
    end)
    cb('loaFile', { rate = 2000, burst = 2 }, function(c, d)
        local ok, why = ED:FileLOA(c.source, c.dept.id, str(d.startDate, 10), str(d.endDate, 10), str(d.reason, 300))
        if not ok then return false, why end
        refresh('loa')
        -- tell the leaders who can decide it; with nobody else to decide, the admins
        CreateThread(function()
            local online, told = onlineByChar(), 0
            local text = ('%s: %s asked for leave (%s to %s)'):format(c.dept.short, c.name, str(d.startDate, 10), str(d.endDate, 10))
            local others = 0
            for _, cid in ipairs(holdersOf(c.dept, 'loa_manage')) do
                if cid ~= c.charId then
                    others = others + 1
                    if online[cid] then notifyChar(cid, text, 'info', online) told = told + 1 end
                end
            end
            if others == 0 or told == 0 then
                for _, src in pairs(online) do if ED:IsStaff(src) == true and src ~= c.source then WC:NotifyPlayer(src, text .. ' · needs an admin', 'info', 10000) end end
            end
        end)
        return ok
    end)
    cb('loaAct', { rate = 500, burst = 4 }, function(c, d)
        local action = str(d.action, 10)
        if action == 'approve' or action == 'deny' then
            local l = MySQL.single.await('SELECT `charId` FROM `es_dept_loa` WHERE `id` = ?', { id(d.id) or 0 })
            if l and l.charId == c.charId then
                -- nobody decides their own leave; an admin may only when no other leader exists
                local others = 0
                for _, cid in ipairs(holdersOf(c.dept, 'loa_manage')) do if cid ~= c.charId then others = others + 1 end end
                if not c.staff or others > 0 then return false, 'Another leader has to decide your own leave' end
            end
        end
        local ok, why = ED:DecideLOA(c.source, id(d.id) or 0, action, str(d.note, 200))
        if ok then refresh('loa') end
        return ok, why
    end)

    -- FTO (1.6.0: the field training program; es_departments holds it and checks every call again)
    local function ftoOrLeader(c) return c.perms.fto_train or c.perms.fto_manage or c.perms.canPromote or c.staff end
    local function ftosOf(c)
        local ftos = {}
        for _, m in ipairs(ED:GetRoster(c.dept.id) or {}) do
            if WC:HasJobPermission({ charId = m.charId }, c.dept.jobId, 'fto_train', { onDuty = false }) == true then
                ftos[#ftos + 1] = { charId = m.charId, name = m.name, callsign = m.callsign, roleName = m.roleName }
            end
        end
        return ftos
    end
    --- Training home: every trainee (all statuses), the program, ranks, FTOs, my ride-alongs to write up
    cb('ftoHome', { rate = 500, burst = 4 }, function(c)
        local prog = ED:GetTrainingProgram(c.dept.id) or {}
        local home = { me = c.charId, program = prog.program, ranks = prog.ranks, limits = prog.limits,
            trainee = ED:IsTrainee(c.dept.id, c.charId) == true, rides = Rides[c.charId] or {},
            can = { train = c.perms.fto_train == true, manage = c.perms.fto_manage == true, promote = c.perms.canPromote == true, staff = c.staff == true },
            myLevel = c.myLevel }
        if ftoOrLeader(c) then
            home.list = ED:GetTrainees(c.dept.id, { status = 'all' }) or {}
            home.ftos = ftosOf(c)
            home.members = {}
            for _, m in ipairs(ED:GetRoster(c.dept.id) or {}) do home.members[#home.members + 1] = { charId = m.charId, name = m.name, roleName = m.roleName, callsign = m.callsign } end
        end
        return home
    end)
    cb('ftoFile', { rate = 400, burst = 4 }, function(c, d)
        local cid = id(d.charId)
        if not cid then return false, 'Pick a trainee' end
        if not ftoOrLeader(c) and cid ~= c.charId then return false, 'Only FTOs and supervisors see other trainees' end
        local f, why = ED:GetTraineeFile(c.dept.id, cid)
        if not f then return false, why end
        if cid == c.charId and not ftoOrLeader(c) then f.readOnly = true end
        return f
    end)
    cb('ftoStats', { rate = 800, burst = 3 }, function(c)
        if not (c.perms.fto_manage or c.staff or c.perms.canPromote) then return false, 'Only training supervisors see the numbers' end
        return ED:GetTrainingStats(c.dept.id)
    end)
    cb('ftoProgramSave', { perm = 'fto_manage', write = true, rate = 1500, burst = 2 }, function(c, d)
        local ok, why = ED:SaveTrainingProgram(c.source, c.dept.id, type(d.program) == 'table' and d.program or {})
        if ok then refresh('training') end
        return ok, why
    end)
    cb('ftoStart', { perm = 'fto_manage', write = true, rate = 1000, burst = 2 }, function(c, d)
        local ok, why = ED:StartTraining(c.source, c.dept.id, id(d.charId) or 0)
        if ok then refresh('training') end
        return ok, why
    end)
    cb('ftoSign', { write = true, rate = 400, burst = 6 }, function(c, d)
        if not (c.perms.fto_train or c.perms.fto_manage or c.staff) then return false, 'Only FTOs sign off training' end
        local ok, why = ED:SignTrainingItems(c.source, c.dept.id, id(d.charId) or 0, keyList(d.keys), d.on ~= false)
        if ok then refresh('training') end
        return ok, why
    end)
    cb('ftoComplete', { perm = 'fto_manage', write = true, rate = 2000, burst = 2 }, function(c, d)
        local ok, why = ED:CompleteTraining(c.source, c.dept.id, id(d.charId) or 0, { promote = d.promote == true, roleId = id(d.roleId),
            override = d.override == true, note = str(d.note, 300) })
        if ok then refresh('training') refresh('dept') end
        return ok, why
    end)
    cb('trainees', {}, function(c, d)
        if not ftoOrLeader(c) then return false, 'Only FTOs and leaders see training' end
        local list = ED:GetTrainees(c.dept.id, { status = d.all and 'all' or nil }) or {}
        -- FTOs to assign to
        local ftos = {}
        for _, m in ipairs(ED:GetRoster(c.dept.id) or {}) do
            if WC:HasJobPermission({ charId = m.charId }, c.dept.jobId, 'fto_train', { onDuty = false }) == true then
                ftos[#ftos + 1] = { charId = m.charId, name = m.name, callsign = m.callsign }
            end
        end
        local cfg = ED:GetConfig().fto or {}
        local items = cfg.checklist or {}
        local done = {}
        for _, r in ipairs(MySQL.query.await('SELECT `traineeCharId`,`checklist` FROM `es_fto_sessions` WHERE `deptId` = ?', { c.dept.id }) or {}) do
            local okj, v = pcall(json.decode, r.checklist or '')
            if okj and type(v) == 'table' then
                local set = done[r.traineeCharId] or {}
                done[r.traineeCharId] = set
                for k, on in pairs(v) do if on then set[k] = true end end
            end
        end
        for _, t in ipairs(list) do
            local set, list2 = done[t.charId] or {}, {}
            for _, k in ipairs(items) do if set[k] then list2[#list2 + 1] = k end end
            t.checkDone, t.checkTotal = list2, #items
        end
        return { trainees = list, ftos = ftos, required = cfg.rideAlongsRequired or 3, checklist = items, rides = Rides[c.charId] or {} }
    end)
    cb('ftoSessions', {}, function(c, d)
        local cid = id(d.charId)
        if not cid then return false, 'Pick a trainee' end
        if not ftoOrLeader(c) and cid ~= c.charId then return false, 'Only FTOs and leaders see training' end
        return ED:GetTrainingSessions(c.dept.id, cid) or {}
    end)
    cb('ftoAssign', { perm = 'fto_train', write = true }, function(c, d)
        local to = d.ftoCharId == false and false or (d.ftoCharId and id(d.ftoCharId) or nil)
        local ok, why = ED:AssignTrainee(c.source, c.dept.id, id(d.charId) or 0, to)
        if ok then refresh('training') end
        return ok, why
    end)
    cb('ftoLog', { perm = 'fto_train', write = true, rate = 1500, burst = 2 }, function(c, d)
        local okl, whyl = ED:LogTraining(c.source, c.dept.id, id(d.charId) or 0, { kind = d.kind, minutes = d.minutes, notes = str(d.notes, 4000),
            ratings = type(d.ratings) == 'table' and d.ratings or {}, checklist = type(d.checklist) == 'table' and d.checklist or {},
            signed = keyList(d.signed), at = tonumber(d.at) })
        if okl then refresh('training') end
        return okl, whyl
    end)
    cb('ftoSignOff', { write = true }, function(c, d)
        local ok, why = ED:SignOffTrainee(c.source, c.dept.id, id(d.charId) or 0)
        if ok then refresh('training') end
        return ok, why
    end)
    cb('recommend', { perm = 'fto_train', write = true, rate = 2000, burst = 2 }, function(c, d)
        local ok, why = ED:RecommendPromotion(c.source, c.dept.id, id(d.charId) or 0, str(d.reason, 500), id(d.toRoleId) or 0)
        if ok then refresh('training') end
        return ok, why
    end)
    cb('recs', {}, function(c, d)
        if not ftoOrLeader(c) then return false, 'Only FTOs and leaders see recommendations' end
        return ED:GetRecommendations(c.dept.id, d.all and 'all' or 'pending') or {}
    end)
    cb('recAct', { write = true }, function(c, d)
        local ok, why = ED:DecideRecommendation(c.source, id(d.id) or 0, str(d.action, 10), id(d.roleId) or nil)
        if ok then refresh('training') end
        return ok, why
    end)

    -- The tablet in hand while the MDT is open: WHIP makes the prop for everyone (HoldProps), the game plays the anim.
    -- whileDead so a close on death still takes it away. Your props go by themselves when es_mdt stops.
    Whip.core:SecureEvent('es_mdt:tablet', { rateLimit = 400, burst = 4, whileDead = true, params = { { 'on', 'bool' } } },
        function(source, _, on)
            local T = Config.Tablet
            local held = exports.whip_core:GetHeldPropsTag(source) == 'es_mdt:tablet'
            if not on then
                if held then exports.whip_core:DropHeldProps(source, 'tablet') end
                return
            end
            if not (T and T.enabled) or held then return end
            local c = ctxOf(source)
            if not c or not (c.perms.mdt_view or c.staff) then return end
            local ped = GetPlayerPed(source)
            if ped == 0 or GetVehiclePedIsIn(ped, false) ~= 0 then return end
            local o, r = T.offset or {}, T.rot or {}
            exports.whip_core:HoldProps(source, { {
                model = T.prop or 'prop_cs_tablet', bone = T.bone or 28422,
                offset = { o.x or 0.0, o.y or 0.0, o.z or 0.0 }, rot = { r.x or 0.0, r.y or 0.0, r.z or 0.0 },
            } }, 'tablet')
        end)
end

-- ---------------------------------------------------------------- exports for other resources

--- Arrests per officer: every arrest report they are on (author or assisting). opts: { days = 30, jobId? }
exports('GetArrestCounts', function(charIds, opts)
    local out = {}
    if type(charIds) ~= 'table' or #charIds == 0 then return out end
    opts = type(opts) == 'table' and opts or {}
    local days = math.max(1, math.min(36500, tonumber(opts.days) or 30))
    local deptId
    if opts.jobId then local d = ED:GetDepartment({ jobId = opts.jobId }) deptId = d and d.id end
    local args = { days }
    for _, c in ipairs(charIds) do args[#args + 1] = c end
    if deptId then args[#args + 1] = deptId end
    local rows = MySQL.query.await(([[SELECT o.`charId`, COUNT(*) AS `n` FROM `es_mdt_report_officers` o JOIN `es_mdt_reports` r ON r.`id` = o.`reportId`
        WHERE r.`type` = 'arrest' AND r.`createdAt` > NOW() - INTERVAL ? DAY AND o.`charId` IN (%s)%s GROUP BY o.`charId`]])
        :format(marks(#charIds), deptId and ' AND r.`deptId` = ?' or ''), args) or {}
    for _, r in ipairs(rows) do out[r.charId] = tonumber(r.n) or 0 end
    return out
end)

exports('GetActiveWarrants', function(charId)
    return MySQL.query.await("SELECT `id`,`reason`,`deptId` FROM `es_mdt_warrants` WHERE `charId` = ? AND `status` = 'active' AND `kind` = 'arrest' AND (`expiresAt` IS NULL OR `expiresAt` > NOW())", { tonumber(charId) or 0 }) or {}
end)

-- 1.9.0: es_doj. A judge signs (approve) or refuses (deny) a requested warrant; by = the judge's charId.
exports('DecideWarrant', function(wid, decision, by, byName, note, days)
    wid, by = tonumber(wid), tonumber(by)
    local w = wid and MySQL.single.await('SELECT `id`,`status`,`requestedBy`,`charId`,`kind` FROM `es_mdt_warrants` WHERE `id` = ?', { wid })
    if not w then return false, 'No such warrant' end
    if w.status ~= 'requested' then return false, 'That warrant is not waiting for a judge' end
    note = note and tostring(note):sub(1, 300) or nil
    byName = byName and tostring(byName):sub(1, 80) or nil
    local n
    if decision == 'approve' then
        days = math.floor(tonumber(days) or 0)
        n = MySQL.update.await([[UPDATE `es_mdt_warrants` SET `status` = 'active', `issuedBy` = ?, `judgeCharId` = ?, `judgeName` = ?, `judgeNote` = ?, `decidedAt` = NOW(),
            `expiresAt` = IF(? > 0, NOW() + INTERVAL ? DAY, `expiresAt`) WHERE `id` = ? AND `status` = 'requested']], { by, by, byName, note, days, days, wid })
    elseif decision == 'deny' then
        n = MySQL.update.await([[UPDATE `es_mdt_warrants` SET `status` = 'void', `closedBy` = ?, `judgeCharId` = ?, `judgeName` = ?, `judgeNote` = ?, `decidedAt` = NOW()
            WHERE `id` = ? AND `status` = 'requested']], { by, by, byName, note, wid })
    else return false, 'approve or deny' end
    if (tonumber(n) or 0) < 1 then return false, 'Someone decided it first' end
    refresh('warrants')
    if decision == 'approve' and w.kind == 'arrest' then warrantBolosSoon(nil) end
    local who = namesOf({ w.charId })[w.charId] or ('#' .. w.charId)
    notifyChar(w.requestedBy, ('%s warrant #%d for %s was %s by %s%s'):format(w.kind == 'search' and 'Search' or 'Arrest', wid, who,
        decision == 'approve' and 'SIGNED' or 'DENIED', byName or 'a judge', note and note ~= '' and (': ' .. note) or ''), decision == 'approve' and 'success' or 'error')
    return true
end)

-- 1.9.0: es_doj. A warrant the court ends (served at court, recalled).
exports('CloseWarrant', function(wid, status, by)
    if status ~= 'served' and status ~= 'void' then return false, 'served or void' end
    local n = MySQL.update.await("UPDATE `es_mdt_warrants` SET `status` = ?, `closedBy` = ? WHERE `id` = ? AND `status` IN ('active','requested')", { status, tonumber(by), tonumber(wid) or 0 })
    if (tonumber(n) or 0) < 1 then return false, 'That warrant is already closed' end
    refresh('warrants') warrantBolosSoon(nil)
    return true
end)

-- 1.9.0: es_doj. A fine paid at the courthouse: the court already took the money (ChargePlayer) and passes it on here.
-- Marks it paid, closes its automatic warrant, and pays the department like a fine paid from the bank.
exports('MarkFinePaid', function(fineId, by, how)
    local f = MySQL.single.await("SELECT `id`,`deptId`,`charId`,`amount`,`status` FROM `es_mdt_fines` WHERE `id` = ?", { tonumber(fineId) or 0 })
    if not f then return false, 'No such fine' end
    if f.status ~= 'unpaid' then return false, 'That fine is not unpaid' end
    local n = MySQL.update.await("UPDATE `es_mdt_fines` SET `status` = 'paid', `paidAt` = NOW() WHERE `id` = ? AND `status` = 'unpaid'", { f.id })
    if (tonumber(n) or 0) < 1 then return false, 'That fine was just paid' end
    closeAutoWarrant(f.id, 'served')
    refresh('fines')
    if MDT.onFinePaid then pcall(MDT.onFinePaid, f.id, how) end
    if Config.FineToDepartment then
        local d = ED:GetDepartment(f.deptId)
        local jaccts = d and WC:GetJobBankAccounts(d.jobId) or {}
        if jaccts[1] and WC:BankSystemDeposit(jaccts[1].accountId, f.amount, { reason = ('Fine #%d (paid at %s)'):format(f.id, tostring(how or 'court'):sub(1, 40)) }) then
            deptIncome(d.jobId, f.amount, 'fine', ('Fine #%d (paid at %s)'):format(f.id, tostring(how or 'court'):sub(1, 40)), f.charId)
        end
    end
    return true, f.amount
end)

-- 1.9.0: es_doj. A court voids a fine (acquittal, dismissal, expungement).
exports('VoidFine', function(fineId, by)
    local n = MySQL.update.await("UPDATE `es_mdt_fines` SET `status` = 'void' WHERE `id` = ? AND `status` = 'unpaid'", { tonumber(fineId) or 0 })
    if (tonumber(n) or 0) < 1 then return false, 'That fine is not unpaid' end
    closeAutoWarrant(tonumber(fineId), 'void')
    refresh('fines')
    return true
end)

exports('HasActiveBolo', function(plate)
    local r = MySQL.single.await("SELECT `id`,`title` FROM `es_mdt_bolos` WHERE `plate` = ? AND `status` = 'active' AND (`expiresAt` IS NULL OR `expiresAt` > NOW()) LIMIT 1", { tostring(plate or ''):upper() })
    return r ~= nil, r
end)

--- For the Evidence phase (casings carry the gun's serial) and other resources: the registry row, or nil
exports('GetWeaponBySerial', function(serial)
    local s = serialOf(serial)
    return s and weaponRow(s) or nil
end)

exports('GetWeaponLicenses', function(charId)
    return MySQL.query.await('SELECT `type`,`status` FROM `es_mdt_weapon_licenses` WHERE `charId` = ?', { tonumber(charId) or 0 }) or {}
end)

exports('GetUnpaidFines', function(charId)
    return MySQL.query.await("SELECT `id`,`amount`,`reason`,`deptId` FROM `es_mdt_fines` WHERE `charId` = ? AND `status` = 'unpaid'", { tonumber(charId) or 0 }) or {}
end)

-- 1.5.5: es_jail. An escape posts a warrant (its BOLOs follow by themselves); jailing them again serves it.
local ESCAPE_PREFIX = 'Escaped from'
--- 1.5.6: `bolo` = { title?, description?, coords? }: the escape gets its own person BOLO at once (linked to the warrant,
--- closes with it), even when the person already has a BOLO from another warrant.
local function escapeBolo(wid, deptId, charId, byCharId, bolo)
    if WB.enabled == false or WB.person == false then return end
    local has = MySQL.single.await("SELECT `id` FROM `es_mdt_bolos` WHERE `kind` = 'person' AND `warrantId` = ? AND `status` = 'active' LIMIT 1", { wid })
    if has then return has.id end
    bolo = type(bolo) == 'table' and bolo or {}
    local name = namesOf({ charId })[charId] or ('#' .. charId)
    local w = MySQL.single.await('SELECT `reason` FROM `es_mdt_warrants` WHERE `id` = ?', { wid })
    local title = str(bolo.title ~= nil and bolo.title or ('Escaped inmate: %s'):format(name), 120)
    local desc = str(bolo.description ~= nil and bolo.description or (w and w.reason or ''), 1000)
    local c = type(bolo.coords) == 'table' and bolo.coords or {}
    local x, y = tonumber(c.x), tonumber(c.y)
    local bid = MySQL.insert.await([[INSERT INTO `es_mdt_bolos` (`deptId`,`kind`,`charId`,`title`,`description`,`createdBy`,`expiresAt`,`warrantId`,`lastX`,`lastY`,`lastSeenAt`)
        VALUES (?,'person',?,?,?,?,(SELECT `expiresAt` FROM `es_mdt_warrants` WHERE `id` = ?),?,?,?,IF(? IS NULL, NULL, NOW()))]],
        { deptId, charId, title ~= '' and title or ('Escaped inmate: ' .. name), desc, 0, wid, wid, x, y, x })   -- 1.5.7: system-made
    if bid then
        wbLog(nil, 'escape_bolo', ('warrant #%d (%s): person #%d'):format(wid, name, bid))
        refresh('bolos')
    end
    return bid
end

exports('EscapeWarrant', function(charId, reason, days, byCharId, bolo)
    charId = id(charId)
    if not charId then return false, 'Who?' end
    local has = MySQL.single.await("SELECT `id`,`deptId` FROM `es_mdt_warrants` WHERE `charId` = ? AND `status` = 'active' AND `reason` LIKE ? LIMIT 1", { charId, ESCAPE_PREFIX .. '%' })
    if has then
        local okb, err = pcall(escapeBolo, has.id, has.deptId, charId, byCharId, bolo)
        if not okb then print(('^3[es_mdt] escape BOLO: %s^7'):format(tostring(err))) end
        return has.id
    end
    local dept
    for _, d in ipairs(ED:GetDepartments() or {}) do
        if d.type == 'police' or d.type == 'sheriff' or d.type == 'state' then dept = d break end
    end
    if not dept then return false, 'No law department' end
    reason = str(reason, 500)
    if reason:sub(1, #ESCAPE_PREFIX) ~= ESCAPE_PREFIX then reason = (ESCAPE_PREFIX .. ' prison. ' .. reason):sub(1, 500) end
    days = int(days or 7, 0, 90)
    local wid = MySQL.insert.await([[INSERT INTO `es_mdt_warrants` (`deptId`,`charId`,`reason`,`status`,`requestedBy`,`issuedBy`,`expiresAt`)
        VALUES (?,?,?,'active',0,NULL,IF(? = 0, NULL, NOW() + INTERVAL ? DAY))]], { dept.id, charId, reason, days, days })   -- 1.5.7: from the prison (0 = system), not a player
    if not wid then return false, 'Could not save the warrant' end
    print(('[es_mdt] escape warrant #%d for char %d'):format(wid, charId))
    refresh('warrants')
    local okb, err = pcall(escapeBolo, wid, dept.id, charId, byCharId, bolo)
    if not okb then print(('^3[es_mdt] escape BOLO: %s^7'):format(tostring(err))) end
    warrantBolosSoon(nil)   -- their cars
    return wid
end)
exports('ServeEscapeWarrants', function(charId, byCharId)
    charId = id(charId)
    if not charId then return 0 end
    local n = MySQL.update.await("UPDATE `es_mdt_warrants` SET `status` = 'served', `closedBy` = ? WHERE `charId` = ? AND `status` = 'active' AND `reason` LIKE ?",
        { id(byCharId), charId, ESCAPE_PREFIX .. '%' }) or 0
    if n > 0 then refresh('warrants') warrantBolosSoon(nil) end
    return n
end)

-- 1.9.0: es_doj. A warrant the court itself issues (bench warrant: missed court, unpaid court fine). Active at once.
-- data = { charId, reason, kind?='arrest', scope?, days?=7, byCharId, byName, deptId?, caseId? } -> warrant id | false, why
exports('IssueWarrant', function(data)
    data = type(data) == 'table' and data or {}
    local charId = id(data.charId)
    if not charId then return false, 'Who?' end
    local kind = data.kind == 'search' and 'search' or 'arrest'
    local deptId = id(data.deptId)
    if not deptId then
        for _, d in ipairs(ED:GetDepartments() or {}) do
            if d.type == 'police' or d.type == 'sheriff' or d.type == 'state' then deptId = d.id break end
        end
    end
    if not deptId then return false, 'No law department' end
    local reason = str(data.reason, 500)
    if reason == '' then return false, 'Give a reason' end
    local days = int(data.days or 7, 0, 90)
    local by = id(data.byCharId) or 0
    local wid = MySQL.insert.await([[INSERT INTO `es_mdt_warrants` (`deptId`,`charId`,`reason`,`status`,`requestedBy`,`issuedBy`,`expiresAt`,`caseId`,`kind`,`scope`,
        `judgeCharId`,`judgeName`,`decidedAt`) VALUES (?,?,?,'active',?,?,IF(? = 0, NULL, NOW() + INTERVAL ? DAY),?,?,?,?,?,NOW())]],
        { deptId, charId, reason, by, by > 0 and by or nil, days, days, id(data.caseId), kind, data.scope and str(data.scope, 300) or nil,
          by > 0 and by or nil, data.byName and str(data.byName, 80) or nil })
    if not wid then return false, 'Could not save the warrant' end
    refresh('warrants')
    if kind == 'arrest' then warrantBolosSoon(nil) end
    return wid
end)

-- 1.3.0: the helpers server/ops.lua (dispatch, panic, map, mugshots, announcements, templates, plates) builds on
MDT = MDT or {}
for k, v in pairs({ cb = cb, str = str, int = int, id = id, marks = marks, namesOf = namesOf, deptShort = deptShort, log = log,
    refresh = refresh, onlineByChar = onlineByChar, notifyChar = notifyChar, dutyNow = dutyNow, unitsAll = unitsAll,
    isHighCommand = isHighCommand, canSeeReport = canSeeReport, flagsOf = flagsOf, ctxOf = ctxOf,
    issueFine = issueFine, payFine = payFine, fineToDept = fineToDept, deptIncome = deptIncome, closeAutoWarrant = closeAutoWarrant, holdersOf = holdersOf, need = need,
    Teams = Teams, TeamOf = TeamOf, Units = Units, Panic = Panic, warrantBolosSoon = warrantBolosSoon, verOf = verOf }) do MDT[k] = v end

Whip.register(function()
    local ok, why = Tables.ensure()
    if not ok then Whip.startProblem('tables: %s', tostring(why)) return end
    Tables.seedPenal()
    register()
    registerWeapons()
    if MDT.registerOps then MDT.registerOps()
    else print('^1[es_mdt] server/ops.lua is not loaded: dispatch, panic, map, mugshots, radar and announcements are OFF. Run `refresh` then `ensure es_mdt`.^7') end
    if MDT.registerEvidence then MDT.registerEvidence()
    else print('^1[es_mdt] server/evidence.lua is not loaded: the Evidence tab is OFF. Run `refresh` then `ensure es_mdt`.^7') end
    if MDT.registerOfficer then MDT.registerOfficer()
    else print('^1[es_mdt] server/officer.lua is not loaded: officer profiles are OFF. Run `refresh` then `ensure es_mdt`.^7') end
    if MDT.registerPermits then MDT.registerPermits()
    else print('^1[es_mdt] server/permits.lua is not loaded: firearm permits are OFF. Run `refresh` then `ensure es_mdt`.^7') end
    if MDT.registerTestData then MDT.registerTestData() end
    if MDT.registerCases then MDT.registerCases()
    else print('^1[es_mdt] server/cases.lua is not loaded: Cases are OFF. Run `refresh` then `ensure es_mdt`.^7') end
    if MDT.registerWhipEv and MDT.registerCases then MDT.registerWhipEv() end   -- 1.11.0: optional whip_evidence locker
    -- 2.1.0: owner texts, roadside tickets / invoices / contests, impound
    if MDT.registerTexts then MDT.registerTexts() end
    if MDT.registerTickets then MDT.registerTickets()
    else print('^1[es_mdt] server/tickets.lua is not loaded: tickets and invoices are OFF. Run `refresh` then `ensure es_mdt`.^7') end
    if MDT.registerImpound then MDT.registerImpound()
    else print('^1[es_mdt] server/impound.lua is not loaded: impound is OFF. Run `refresh` then `ensure es_mdt`.^7') end
    -- automatic "failure to pay" warrants: on start, then every few minutes
    CreateThread(function()
        Wait(20000)
        while true do
            local okw, err = pcall(autoWarrants)
            if not okw then print(('^3[es_mdt] unpaid-fine warrants: %s^7'):format(tostring(err))) end
            Wait(math.max(1, tonumber(Config.UnpaidFineCheckMinutes) or 10) * 60000)
        end
    end)
end)

Whip.sayStarted()
