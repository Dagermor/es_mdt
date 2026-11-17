local _ENV = ESAPP('doj'); -- es_doj core: who is asking (their court roles), the callback wrapper, helpers shared by every server file.
-- Roles come from the DOJ department's rank permissions (es_departments, type "doj"), an active bar license
-- (private attorneys), police read-only access (Config.LawCanView), and staff (everything; /dojtest role views as one).
DOJ = DOJ or {}
local WC = exports.whip_core
local ED = exports.es_departments
DOJ.WC, DOJ.ED = WC, ED

-- ---------------------------------------------------------------- small helpers
local function trim(s) return (type(s) == 'string' and (s:gsub('^%s+', ''):gsub('%s+$', ''))) or '' end
function DOJ.str(v, max)
    local s = trim(type(v) == 'string' and v or (type(v) == 'number' and tostring(v) or ''))
    s = s:gsub('[%c]', function(ch) return (ch == '\n' or ch == '\t') and ch or '' end)
    return s:sub(1, max)
end
function DOJ.int(v, lo, hi) v = math.floor(tonumber(v) or 0) if v < lo then v = lo end if v > hi then v = hi end return v end
function DOJ.id(v) v = tonumber(v) return (v and v >= 1 and v == math.floor(v) and v < 4294967295) and v or nil end
function DOJ.marks(n) local m = {} for i = 1, n do m[i] = '?' end return table.concat(m, ',') end
function DOJ.oneOf(v, list, def) for _, x in ipairs(list) do if v == x then return v end end return def end
function DOJ.keys(list) local out = {} for _, x in ipairs(list) do out[#out + 1] = x.key end return out end
function DOJ.labelOf(list, key) for _, x in ipairs(list) do if x.key == key then return x.label end end return key end

function DOJ.namesOf(ids)
    local uniq, list = {}, {}
    for _, x in pairs(ids) do x = tonumber(x) if x and not uniq[x] then uniq[x] = true list[#list + 1] = x end end
    if #list == 0 then return {} end
    local out = {}
    for i = 1, #list, 200 do
        local part = {}
        for j = i, math.min(i + 199, #list) do part[#part + 1] = list[j] end
        for k, v in pairs(WC:GetCharacterNames(part) or {}) do out[tonumber(k) or k] = v end
    end
    return out
end
function DOJ.nameOf(cid) if not cid then return nil end return DOJ.namesOf({ cid })[cid] end

function DOJ.onlineByChar()
    local out = {}
    for src, p in pairs(WC:GetPlayers({ light = true }) or {}) do
        if type(p) == 'table' and p.charId then out[p.charId] = tonumber(src) end
    end
    return out
end

function DOJ.notifyChar(charId, text, kind, online)
    local src = (online or DOJ.onlineByChar())[charId]
    if src then WC:NotifyPlayer(src, text, kind or 'info', 9000) end
    return src
end

function DOJ.refresh(what) TriggerClientEvent('es_doj:client:refresh', -1, what) end

function DOJ.isImg(v) return type(v) == 'string' and v:match('^data:image/[a-z]+;base64,') ~= nil and #v <= ((Config.Images or {}).maxBytes or 420000) end

function DOJ.charExists(cid)
    cid = DOJ.id(cid)
    return cid and MySQL.scalar.await('SELECT 1 FROM `characters` WHERE `charId` = ? AND `deleted` IS NULL', { cid }) ~= nil
end

--- The DOJ department (the first of type doj), or nil
function DOJ.dept()
    for _, d in ipairs(ED:GetDepartments() or {}) do if d.type == 'doj' then return d end end
end

--- Money the court keeps goes to the DOJ department's job account (Config.Fees.toDepartment), else the state.
function DOJ.deposit(amount, reason)
    if (amount or 0) < 1 or (Config.Fees or {}).toDepartment == false then return false end
    local d = DOJ.dept()
    local accts = d and WC:GetJobBankAccounts(d.jobId) or {}
    if not accts[1] then return false end
    local ok, why = WC:BankSystemDeposit(accts[1].accountId, amount, { reason = tostring(reason or 'Court'):sub(1, 120) })
    if not ok then print(('^3[es_doj] deposit of $%d failed: %s^7'):format(amount, tostring(why))) end
    return ok
end

-- ---------------------------------------------------------------- the docket log and notices
function DOJ.log(caseId, c, what, detail)
    MySQL.insert.await('INSERT INTO `es_doj_log` (`caseId`,`byCharId`,`byLabel`,`what`,`detail`) VALUES (?,?,?,?,?)',
        { caseId, c and c.charId or nil, c and c.label or 'System', tostring(what):sub(1, 32), detail and tostring(detail):sub(1, 500) or nil })
    if c and c.source then CreateThread(function() WC:LogActivity(c.source, 'es_doj_' .. tostring(what):sub(1, 40), { detail = detail and tostring(detail):sub(1, 200) or nil }) end) end
end

--- A court notice to a person (kept in their portal; a toast when online). Returns the notice id.
function DOJ.notice(charId, title, body, caseId, kind, by, test)
    charId = DOJ.id(charId)
    if not charId then return nil end
    local nid = MySQL.insert.await('INSERT INTO `es_doj_notices` (`charId`,`caseId`,`kind`,`title`,`body`,`createdBy`,`test`) VALUES (?,?,?,?,?,?,?)',
        { charId, caseId, kind or 'notice', tostring(title):sub(1, 160), body and tostring(body):sub(1, 1000) or nil, by, test and 1 or 0 })
    local src = DOJ.notifyChar(charId, ('⚖ Court notice: %s  (/%s)'):format(tostring(title):sub(1, 90), Config.PortalCommand or 'court'), 'info')
    if src then TriggerClientEvent('es_doj:client:notices', src) end
    return nid
end

-- ---------------------------------------------------------------- who is asking
local PERMS = { 'doj_view', 'doj_cases', 'doj_sign', 'doj_deny', 'doj_prosecute', 'doj_defend', 'doj_clerk', 'doj_bar', 'doj_penal', 'doj_seal',
    'warrants_issue', 'permits_manage' }
DOJ.PERMS = PERMS

-- staff "view as" (/dojtest role): what each role holds
local ROLE_SETS = {
    judge = { doj_view = true, doj_cases = true, doj_sign = true, doj_deny = true, doj_seal = true, warrants_issue = true, permits_manage = true },
    prosecutor = { doj_view = true, doj_cases = true, doj_prosecute = true },
    defender = { doj_view = true, doj_defend = true },
    clerk = { doj_view = true, doj_cases = true, doj_clerk = true },
}
DOJ.ViewAs = {}   -- [source] = 'judge'|'prosecutor'|'defender'|'clerk'|'attorney'|'leo'

local Cache = {}
AddEventHandler('playerDropped', function() Cache[source] = nil DOJ.ViewAs[source] = nil end)
for _, ev in ipairs({ 'whip_core:job:clockedOn', 'whip_core:job:clockedOff', 'whip_core:job:roleChanged', 'whip_core:job:fired', 'whip_core:job:hired' }) do
    AddEventHandler(ev, function(e) if type(e) == 'table' and e.source then Cache[e.source] = nil end end)
end
function DOJ.forget(source) if source then Cache[source] = nil else Cache = {} end end

function DOJ.barOf(cid)
    return cid and MySQL.single.await('SELECT `charId`,`number`,`kind`,`firm`,`phone`,`status` FROM `es_doj_bar` WHERE `charId` = ?', { cid }) or nil
end

local function lastName(full) return (tostring(full or ''):match('(%S+)%s*$')) or full end

function DOJ.ctxOf(source)
    local hit = Cache[source]
    if hit and GetGameTimer() - hit.at < 3000 then return hit.ctx end
    local charId = WC:GetCharId(source)
    if not charId then return false, 'No character' end
    local staff = ED:IsStaff(source) == true
    local name = DOJ.nameOf(charId) or ('#' .. charId)
    local d, law
    for _, x in ipairs(ED:GetPlayerDepartments(source) or {}) do
        if x.type == 'doj' and not d then d = x end
        if (x.type == 'police' or x.type == 'sheriff' or x.type == 'state') and not law then law = x end
    end
    local perms = {}
    for _, p in ipairs(PERMS) do perms[p] = (d and WC:HasJobPermission(source, d.jobId, p, { onDuty = false }) == true) or false end
    local bar = DOJ.barOf(charId)
    local barActive = bar and bar.status == 'active' or false
    local leo = law and Config.LawCanView ~= false and WC:HasJobPermission(source, law.jobId, 'mdt_view', { onDuty = false }) == true or false
    local view = staff and DOJ.ViewAs[source] or nil
    if view then
        staff = false
        perms = {}
        for k, v in pairs(ROLE_SETS[view] or {}) do perms[k] = v end
        if view == 'attorney' then barActive = true bar = bar or { number = 'TEST', kind = 'private', status = 'active' } end
        leo = view == 'leo'
        if not ROLE_SETS[view] then d = nil end
    end
    local member = d ~= nil and perms.doj_view
    if not (staff or member or barActive or leo) then return false, 'The DOJ tablet is for the Department of Justice, licensed attorneys and the police' end
    local r = {
        staff = staff, member = member or false, attorney = barActive, leo = leo,
        judge = staff or perms.doj_sign, deny = staff or perms.doj_deny or perms.doj_sign,
        prosecutor = staff or perms.doj_prosecute, defender = staff or perms.doj_defend,
        clerk = staff or perms.doj_clerk, cases = staff or perms.doj_cases or perms.doj_clerk or perms.doj_prosecute,
        bar = staff or perms.doj_bar, penal = staff or perms.doj_penal, seal = staff or perms.doj_seal,
        warrants = staff or perms.doj_sign, permits = staff or perms.permits_manage,
    }
    r.court = r.judge or r.clerk or r.cases          -- sees every (unsealed) case in full
    local onDuty = d and d.onDuty == true or false
    local readOnly = (not staff) and ((not member and not barActive) or (Config.OffDutyReadOnly and member and not onDuty)) or false
    local title = d and d.roleName or (barActive and 'Attorney') or (leo and law.short) or (staff and 'Staff') or ''
    local label = (r.judge and not staff) and ('Judge ' .. lastName(name)) or (title ~= '' and (title .. ' ' .. lastName(name)) or name)
    if staff then label = name end
    local c = {
        source = source, charId = charId, name = name, label = label, staff = staff, viewAs = view,
        dept = d, law = law, perms = perms, r = r, bar = bar, onDuty = onDuty, readOnly = readOnly,
        level = d and d.roleLevel or 0, roleName = d and d.roleName or nil,
    }
    Cache[source] = { at = GetGameTimer(), ctx = c }
    return c
end

-- ---------------------------------------------------------------- the callback wrapper
-- opts.role = key of c.r (or a list: any), opts.write = refused read-only, opts.rate/burst
function DOJ.cb(name, opts, fn)
    Whip.core:SecureCallback('es_doj:' .. name, { rateLimit = opts.rate or 200, burst = opts.burst or 8, sheet = 'light',
        params = { { 'd', 'any' } } }, function(source, _, d)
        local c, why = DOJ.ctxOf(source)
        if not c then return false, why end
        if opts.write and c.readOnly then return false, c.r.leo and not c.r.member and 'Police have read-only access to the DOJ tablet' or 'You are off duty: the DOJ tablet is read-only' end
        if opts.role then
            local roles = type(opts.role) == 'table' and opts.role or { opts.role }
            local ok = false
            for _, k in ipairs(roles) do if c.r[k] then ok = true break end end
            if not ok then return false, opts.why or 'Your role cannot do that' end
        end
        local okp, a, b = pcall(fn, c, type(d) == 'table' and d or {})
        if not okp then
            print(('^1[es_doj] %s failed: %s^7'):format(name, tostring(a)))
            return false, 'Something went wrong (the server console says why)'
        end
        return a, b
    end)
end

-- ---------------------------------------------------------------- cases: access and sides
local KINDS = {}
for _, k in ipairs(Config.CaseKinds) do KINDS[k.key] = k end
DOJ.KINDS = KINDS

function DOJ.caseRow(id)
    id = DOJ.id(id)
    return id and MySQL.single.await([[SELECT `id`,`number`,`kind`,`title`,`summary`,`status`,`stage`,`defendantCharId`,`plaintiffCharId`,`plaintiffName`,
        `judgeCharId`,`prosecutorCharId`,`defenseCharId`,`defenseKind`,`plea`,`verdict`,`mdtCaseId`,`reportId`,`parentId`,`bailStatus`,`bailAmount`,`bailFeeId`,
        `sealed`,`sealReason`,`test`,`createdBy`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt`,UNIX_TIMESTAMP(`updatedAt`) AS `updatedAt`,
        UNIX_TIMESTAMP(`closedAt`) AS `closedAt`,UNIX_TIMESTAMP(`verdictAt`) AS `verdictAt` FROM `es_doj_cases` WHERE `id` = ?]], { id }) or nil
end

function DOJ.isClient(attorney, client)
    return attorney and client and MySQL.scalar.await("SELECT 1 FROM `es_doj_clients` WHERE `attorneyCharId` = ? AND `clientCharId` = ? AND `status` = 'active'", { attorney, client }) ~= nil
end

--- What this person is on the case: 'judge' | 'prosecution' | 'defense' | 'clerk' | nil
function DOJ.sideOf(c, k)
    if k.judgeCharId == c.charId or (c.r.judge and not c.staff) then return 'court' end
    if k.prosecutorCharId == c.charId then return 'prosecution' end
    if k.defenseCharId == c.charId then return 'defense' end
    if c.staff then return 'court' end
    if c.r.prosecutor then return 'prosecution' end
    if c.r.defender and (k.defenseKind == 'public' or not k.defenseCharId) then return 'defense' end
    if c.r.attorney and k.defendantCharId and DOJ.isClient(c.charId, k.defendantCharId) then return 'defense' end
    if c.r.clerk or c.r.cases then return 'clerk' end
    return nil
end

--- 'full' (court, parties), 'read' (police, other attorneys: public parts) or nil
function DOJ.access(c, k)
    if not k then return nil end
    if c.staff then return 'full' end
    local side = DOJ.sideOf(c, k)
    if k.sealed == 1 or k.sealed == true then
        if c.r.judge or c.r.seal or k.judgeCharId == c.charId or k.prosecutorCharId == c.charId or k.defenseCharId == c.charId then return 'full' end
        return nil
    end
    if side or c.r.court then return 'full' end
    if c.r.leo or c.r.attorney or c.r.member then return 'read' end
    return nil
end

--- Which filings this side may read
function DOJ.visibleFilingSql(c, k, side)
    if c.staff or side == 'court' or side == 'clerk' then return '1=1', {} end
    if side == 'prosecution' then return "`visibility` IN ('public','parties','prosecution')", {} end
    if side == 'defense' then return "`visibility` IN ('public','parties','defense')", {} end
    return "`visibility` = 'public'", {}
end

function DOJ.stageLabel(k) return DOJ.labelOf(Config.Stages, k) end
