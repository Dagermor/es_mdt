local _ENV = ESAPP('doj'); -- es_doj bar: licenses to practise law (private attorneys use the DOJ tablet with one), and attorney client lists.
local cb, str, id = DOJ.cb, DOJ.str, DOJ.id
local KINDS = { 'private', 'public', 'prosecutor' }

local function barNumber()
    local pre = (Config.Bar or {}).prefix or 'SA'
    local n = (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM `es_doj_bar`')) or 0) + 1
    for _ = 1, 50 do
        local no = ('%s-%04d'):format(pre, n)
        if not MySQL.scalar.await('SELECT 1 FROM `es_doj_bar` WHERE `number` = ?', { no }) then return no end
        n = n + 1
    end
    return ('%s-%d'):format(pre, os.time() % 1000000)
end

--- Every licensed attorney (active first), with who is in the city now
function DOJ.lawyers(activeOnly)
    local rows = MySQL.query.await(([[SELECT `charId`,`number`,`kind`,`firm`,`phone`,`status`,`note`,UNIX_TIMESTAMP(`issuedAt`) AS `issuedAt` FROM `es_doj_bar` %s
        ORDER BY FIELD(`status`,'active','suspended','revoked'), `kind`, `number`]]):format(activeOnly and "WHERE `status` = 'active'" or ''), {}) or {}
    local ids = {}
    for _, r in ipairs(rows) do ids[#ids + 1] = r.charId end
    local names = DOJ.namesOf(ids)
    local online = DOJ.onlineByChar()
    local ranks = {}
    local d = DOJ.dept()
    if d then for _, m in ipairs(DOJ.ED:GetRoster(d.id) or {}) do ranks[m.charId] = m.roleName end end
    for _, r in ipairs(rows) do
        r.name = names[r.charId] or ('#' .. r.charId)
        r.online = online[r.charId] ~= nil
        r.rank = ranks[r.charId]   -- 1.1.0: their DOJ rank (District Attorney, Public Defender...) when they work there
        r.clients = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM `es_doj_clients` WHERE `attorneyCharId` = ? AND `status` = 'active'", { r.charId })) or 0
    end
    return rows
end

-- ---------------------------------------------------------------- 1.1.0: the DOJ's own attorneys
--- What a DOJ rank makes someone: 'prosecutor' (DA's office), 'public' (public defender) or nil
function DOJ.attorneyKindOf(jobId, roleId)
    local d = DOJ.dept()
    if not d or d.jobId ~= jobId or not roleId then return nil end
    for _, r in ipairs(DOJ.WC:GetJobRoles(jobId) or {}) do
        if r.roleId == roleId then
            local p = r.permissions or {}
            if p.doj_prosecute then return 'prosecutor' end
            if p.doj_defend then return 'public' end
            return nil
        end
    end
end

--- Hired into (or moved to) a DA / public defender rank: a bar license of that kind comes with the job (a
--- suspended or revoked one stays as the bar office left it). Leaving the DOJ turns a government license private.
function DOJ.syncAttorney(cid, kind, by, left)
    if not cid then return end
    local old = DOJ.barOf(cid)
    if left then
        if old and old.status == 'active' and (old.kind == 'prosecutor' or old.kind == 'public') then
            MySQL.update.await("UPDATE `es_doj_bar` SET `kind` = 'private', `note` = 'Left the Department of Justice' WHERE `charId` = ?", { cid })
            DOJ.forget(nil) DOJ.refresh('bar')
        end
        return
    end
    if not kind then return end
    if not old then
        local no = (function()
            local pre = (Config.Bar or {}).prefix or 'SA'
            local n = (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM `es_doj_bar`')) or 0) + 1
            for _ = 1, 50 do
                local x = ('%s-%04d'):format(pre, n)
                if not MySQL.scalar.await('SELECT 1 FROM `es_doj_bar` WHERE `number` = ?', { x }) then return x end
                n = n + 1
            end
            return ('%s-%d'):format(pre, os.time() % 1000000)
        end)()
        MySQL.insert.await("INSERT IGNORE INTO `es_doj_bar` (`charId`,`number`,`kind`,`firm`,`note`,`issuedBy`) VALUES (?,?,?,?,?,?)",
            { cid, no, kind, kind == 'prosecutor' and "District Attorney's Office" or 'Public Defender\'s Office', 'With the job (DOJ)', by })
        DOJ.log(nil, by and { charId = by, label = DOJ.nameOf(by) } or nil, 'bar_issued', ('%s licensed with the job (%s, %s)'):format(DOJ.nameOf(cid) or ('#' .. cid), no, kind))
    elseif old.status == 'active' and old.kind ~= kind then
        MySQL.update.await("UPDATE `es_doj_bar` SET `kind` = ?, `firm` = ? WHERE `charId` = ?",
            { kind, kind == 'prosecutor' and "District Attorney's Office" or 'Public Defender\'s Office', cid })
    else
        return
    end
    DOJ.forget(nil)
    DOJ.refresh('bar')
end

for _, ev in ipairs({ 'whip_core:job:hired', 'whip_core:job:roleChanged', 'whip_core:job:fired' }) do
    AddEventHandler(ev, function(e)
        if type(e) ~= 'table' or not e.charId or not e.jobId then return end
        local d = DOJ.dept()
        if not d or d.jobId ~= e.jobId then return end
        CreateThread(function()
            if ev == 'whip_core:job:fired' then DOJ.syncAttorney(e.charId, nil, nil, true)
            else DOJ.syncAttorney(e.charId, DOJ.attorneyKindOf(e.jobId, e.roleId), e.by) end
        end)
    end)
end

--- On start: everyone already in a DA / public defender rank gets their license
function DOJ.syncAttorneys()
    local d = DOJ.dept()
    if not d then return 0 end
    local n = 0
    for _, m in ipairs(DOJ.ED:GetRoster(d.id) or {}) do
        local kind = DOJ.attorneyKindOf(d.jobId, m.roleId)
        if kind then DOJ.syncAttorney(m.charId, kind, nil) n = n + 1 end
    end
    return n
end

function DOJ.addClient(attorney, client, note)
    MySQL.insert.await([[INSERT INTO `es_doj_clients` (`attorneyCharId`,`clientCharId`,`note`) VALUES (?,?,?)
        ON DUPLICATE KEY UPDATE `status` = 'active', `endedAt` = NULL, `note` = COALESCE(VALUES(`note`), `note`)]], { attorney, client, note })
end

function DOJ.registerBar()
    cb('bar', {}, function() return DOJ.lawyers(false) end)

    cb('barIssue', { role = 'bar', write = true, why = 'Only the bar office licenses attorneys' }, function(c, d)
        local who = id(d.charId)
        if not who or not DOJ.charExists(who) then return false, 'Pick the person' end
        local kind = DOJ.oneOf(d.kind, KINDS, 'private')
        local firm, phone, note = str(d.firm, 80), str(d.phone, 20), str(d.note, 300)
        local old = DOJ.barOf(who)
        if old then
            if old.status == 'active' then return false, ('Already licensed (%s)'):format(old.number) end
            MySQL.update.await("UPDATE `es_doj_bar` SET `status` = 'active', `kind` = ?, `firm` = ?, `phone` = ?, `note` = ?, `issuedBy` = ? WHERE `charId` = ?",
                { kind, firm ~= '' and firm or old.firm, phone ~= '' and phone or old.phone, note ~= '' and note or nil, c.charId, who })
        else
            MySQL.insert.await('INSERT INTO `es_doj_bar` (`charId`,`number`,`kind`,`firm`,`phone`,`note`,`issuedBy`) VALUES (?,?,?,?,?,?,?)',
                { who, barNumber(), kind, firm ~= '' and firm or nil, phone ~= '' and phone or nil, note ~= '' and note or nil, c.charId })
        end
        local b = DOJ.barOf(who)
        DOJ.forget(nil)
        DOJ.log(nil, c, 'bar_issued', ('%s licensed (%s, %s)'):format(DOJ.nameOf(who) or ('#' .. who), b.number, kind))
        DOJ.notice(who, ('Bar license %s'):format(b.number), ('You may practise law (%s). Open the DOJ tablet with /%s.'):format(kind, Config.Command or 'doj'), nil, 'license', c.charId)
        DOJ.refresh('bar')
        return b
    end)

    cb('barAct', { role = 'bar', write = true, why = 'Only the bar office changes licenses' }, function(c, d)
        local who = id(d.charId)
        local b = who and DOJ.barOf(who)
        if not b then return false, 'No such license' end
        local act, note = d.act, str(d.note, 300)
        if act == 'suspend' or act == 'revoke' then
            if note == '' then return false, 'Say why' end
            MySQL.update.await('UPDATE `es_doj_bar` SET `status` = ?, `note` = ? WHERE `charId` = ?', { act == 'suspend' and 'suspended' or 'revoked', note, who })
        elseif act == 'reinstate' then
            MySQL.update.await("UPDATE `es_doj_bar` SET `status` = 'active', `note` = ? WHERE `charId` = ?", { note ~= '' and note or nil, who })
        elseif act == 'edit' then
            MySQL.update.await('UPDATE `es_doj_bar` SET `kind` = ?, `firm` = ?, `phone` = ? WHERE `charId` = ?',
                { DOJ.oneOf(d.kind, KINDS, b.kind), str(d.firm, 80), str(d.phone, 20), who })
        else return false, 'suspend, revoke, reinstate or edit' end
        DOJ.forget(nil)
        DOJ.log(nil, c, 'bar_' .. act, ('%s (%s)%s'):format(DOJ.nameOf(who) or ('#' .. who), b.number, note ~= '' and (': ' .. note) or ''))
        if act ~= 'edit' then DOJ.notice(who, ('Bar license %s: %s'):format(b.number, act), note, nil, 'license', c.charId) end
        DOJ.refresh('bar')
        return true
    end)

    -- an attorney's clients (public defenders and private attorneys)
    cb('clients', { role = { 'attorney', 'defender', 'prosecutor' } }, function(c, d)
        local att = (c.r.bar or c.staff) and id(d.attorneyCharId) or c.charId
        local rows = MySQL.query.await([[SELECT `id`,`clientCharId` AS `charId`,`status`,`note`,UNIX_TIMESTAMP(`createdAt`) AS `createdAt`,UNIX_TIMESTAMP(`endedAt`) AS `endedAt`
            FROM `es_doj_clients` WHERE `attorneyCharId` = ? ORDER BY (`status` = 'active') DESC, `id` DESC LIMIT 100]], { att }) or {}
        local ids = {}
        for _, r in ipairs(rows) do ids[#ids + 1] = r.charId end
        local names = DOJ.namesOf(ids)
        local online = DOJ.onlineByChar()
        for _, r in ipairs(rows) do
            r.name = names[r.charId] or ('#' .. r.charId)
            r.online = online[r.charId] ~= nil
            r.cases = MySQL.query.await("SELECT `id`,`number`,`title`,`stage`,`status` FROM `es_doj_cases` WHERE `defendantCharId` = ? AND `status` = 'open' AND `sealed` = 0 ORDER BY `id` DESC LIMIT 5", { r.charId }) or {}
            for _, k in ipairs(r.cases) do k.stageLabel = DOJ.stageLabel(k.stage) end
        end
        return rows
    end)

    cb('clientAdd', { role = { 'attorney', 'defender' }, write = true, rate = 1500, burst = 4 }, function(c, d)
        local who = id(d.charId)
        if not who or not DOJ.charExists(who) then return false, 'Pick the client' end
        if who == c.charId and not (c.staff or c.viewAs) then return false, 'You cannot be your own client' end
        DOJ.addClient(c.charId, who, str(d.note, 300) ~= '' and str(d.note, 300) or nil)
        DOJ.log(nil, c, 'client_added', DOJ.nameOf(who) or ('#' .. who))
        -- 1.1.0: their open criminal cases without a defense lawyer get this one
        local kind = (c.bar and c.bar.kind == 'public' or (c.r.defender and not c.r.attorney)) and 'public' or 'private'
        for _, k in ipairs(MySQL.query.await([[SELECT `id`,`number` FROM `es_doj_cases` WHERE `defendantCharId` = ? AND `status` = 'open' AND `defenseCharId` IS NULL AND `kind` <> 'civil']], { who }) or {}) do
            MySQL.update.await('UPDATE `es_doj_cases` SET `defenseCharId` = ?, `defenseKind` = ? WHERE `id` = ? AND `defenseCharId` IS NULL', { c.charId, kind, k.id })
            DOJ.log(k.id, c, 'assign', ('Defense: %s'):format(c.label or c.name))
            DOJ.refresh('case:' .. k.id)
        end
        DOJ.notice(who, ('%s now represents you'):format(c.label), 'Your lawyer can see your court cases and act for you.', nil, 'lawyer', c.charId)
        return true
    end)

    cb('clientEnd', { role = { 'attorney', 'defender' }, write = true }, function(c, d)
        local who = id(d.charId)
        local n = who and MySQL.update.await("UPDATE `es_doj_clients` SET `status` = 'ended', `endedAt` = NOW() WHERE `attorneyCharId` = ? AND `clientCharId` = ? AND `status` = 'active'", { c.charId, who }) or 0
        if (tonumber(n) or 0) < 1 then return false, 'Not your client' end
        MySQL.update.await("UPDATE `es_doj_cases` SET `defenseCharId` = NULL, `defenseKind` = 'none' WHERE `defenseCharId` = ? AND `defendantCharId` = ? AND `status` = 'open'", { c.charId, who })
        DOJ.notice(who, ('%s no longer represents you'):format(c.label), 'Hire another lawyer or ask the court for a public defender.', nil, 'lawyer', c.charId)
        return true
    end)
end
