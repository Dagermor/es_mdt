local _ENV = ESAPP('mdt'); -- es_mdt 1.8.0: test-data cleanup (staff only; MDT → Admin · Test data). Lists records that look like testing: the
-- word "test" in a title / reason / notes, one- or two-letter titles, FTO test trainees, and the evidence filed to a
-- flagged case. Nothing is removed on its own: staff tick what goes (flagged ones come ticked) and press Clear.
local ED = exports.es_departments
MDT = MDT or {}

local function looksTest(...)
    for _, v in ipairs({ ... }) do
        local t = type(v) == 'string' and v:lower() or ''
        if t:find('%f[%a]test') then return 'says "test"' end
    end
    local first = select(1, ...)
    if type(first) == 'string' and #first:gsub('%s', '') <= 2 then return 'one- or two-letter title' end
    return nil
end

local function scan()
    local out = {}
    local function add(kind, id, label, sub, why)
        out[#out + 1] = { kind = kind, id = id, label = label, sub = sub, why = why or 'not flagged', flagged = why ~= nil }
    end
    for _, r in ipairs(MySQL.query.await('SELECT `id`,`number`,`title`,`notes`,`status` FROM `es_mdt_cases` ORDER BY `id`') or {}) do
        local why = looksTest(r.title, r.notes)
        if why then add('case', r.id, ('%s · %s'):format(r.number, r.title), ('Case, %s'):format(r.status), why) end
    end
    for _, r in ipairs(MySQL.query.await('SELECT `id`,`type`,`title`,`body` FROM `es_mdt_reports` ORDER BY `id`') or {}) do
        local why = looksTest(r.title, r.body)
        if why then add('report', r.id, ('Report #%d · %s'):format(r.id, r.title), r.type, why) end
    end
    for _, r in ipairs(MySQL.query.await('SELECT `id`,`charId`,`reason`,`status` FROM `es_mdt_warrants` ORDER BY `id`') or {}) do
        local why = looksTest(r.reason)
        if why and why:find('test') then add('warrant', r.id, ('Warrant #%d · %s'):format(r.id, (r.reason or ''):sub(1, 60)), r.status, why) end
    end
    for _, r in ipairs(MySQL.query.await('SELECT `id`,`title`,`description`,`status` FROM `es_mdt_bolos` ORDER BY `id`') or {}) do
        local why = looksTest(r.title, r.description)
        if why and why:find('test') then add('bolo', r.id, ('BOLO #%d · %s'):format(r.id, r.title or ''), r.status, why) end
    end
    local okT, tr = pcall(function() return ED:ListTestTrainees() end)
    for _, r in ipairs(okT and tr or {}) do
        add('trainee', ('%d:%d'):format(r.deptId, r.charId), ('Test trainee %s'):format(r.name or ('#' .. r.charId)), ('FTO test (%s)'):format(r.status), 'FTO test trainee')
    end
    -- evidence filed to a flagged case
    local flaggedCases = {}
    for _, x in ipairs(out) do if x.kind == 'case' and x.flagged then flaggedCases[#flaggedCases + 1] = x.id end end
    if #flaggedCases > 0 and GetResourceState('es_evidence') == 'started' then
        local rows = MySQL.query.await(('SELECT `id`,`kind`,`label`,`status`,`caseId` FROM `es_evidence` WHERE `status` <> \'destroyed\' AND `caseId` IN (%s)')
            :format(MDT.marks(#flaggedCases)), flaggedCases) or {}
        for _, r in ipairs(rows) do add('evidence', r.id, ('Evidence #%d · %s'):format(r.id, r.label or r.kind), ('%s, case %d'):format(r.status, r.caseId), 'filed to a test case') end
    end
    return out
end

local function clearOne(kind, ref, by)
    if kind == 'case' then
        local cid = tonumber(ref)
        MySQL.update.await('UPDATE `es_mdt_reports` SET `caseId` = NULL WHERE `caseId` = ?', { cid })
        MySQL.update.await('UPDATE `es_mdt_warrants` SET `caseId` = NULL WHERE `caseId` = ?', { cid })
        if GetResourceState('es_evidence') == 'started' then MySQL.update.await('UPDATE `es_evidence` SET `caseId` = NULL WHERE `caseId` = ?', { cid }) end
        return (MySQL.update.await('DELETE FROM `es_mdt_cases` WHERE `id` = ?', { cid }) or 0) > 0
    elseif kind == 'report' then
        local rid = tonumber(ref)
        if GetResourceState('es_evidence') == 'started' then MySQL.update.await('DELETE FROM `es_evidence_reports` WHERE `reportId` = ?', { rid }) end
        return (MySQL.update.await('DELETE FROM `es_mdt_reports` WHERE `id` = ?', { rid }) or 0) > 0
    elseif kind == 'warrant' then
        return (MySQL.update.await('DELETE FROM `es_mdt_warrants` WHERE `id` = ?', { tonumber(ref) }) or 0) > 0
    elseif kind == 'bolo' then
        return (MySQL.update.await('DELETE FROM `es_mdt_bolos` WHERE `id` = ?', { tonumber(ref) }) or 0) > 0
    elseif kind == 'evidence' then
        local ok = pcall(function() return exports.es_evidence:Destroy(tonumber(ref), by, 'Test data cleared') end)
        return ok
    end
    return false
end

function MDT.registerTestData()
    local cb = MDT.cb
    cb('testData', { rate = 1000, burst = 3 }, function(c)
        if not EsSuite.DevTools then return false, 'Test tools are off (EsSuite.DevTools in shared/suite.lua)' end
        if not c.staff then return false, 'Staff only' end
        return { list = scan() }
    end)
    cb('testClear', { rate = 3000, burst = 1 }, function(c, d)
        if not EsSuite.DevTools then return false, 'Test tools are off' end
        if not c.staff then return false, 'Staff only' end
        local want = {}
        for _, x in ipairs(type(d.items) == 'table' and d.items or {}) do
            if type(x) == 'table' and type(x.kind) == 'string' then want[x.kind .. ':' .. tostring(x.id)] = true end
        end
        -- only what the scan lists right now can be cleared (no deleting arbitrary ids)
        local done, trainees = {}, false
        local order = { evidence = 1, report = 2, warrant = 3, bolo = 4, case = 5, trainee = 6 }
        local list = scan()
        table.sort(list, function(a, b) return (order[a.kind] or 9) < (order[b.kind] or 9) end)
        for _, x in ipairs(list) do
            if want[x.kind .. ':' .. tostring(x.id)] then
                if x.kind == 'trainee' then trainees = true
                elseif clearOne(x.kind, x.id, c.charId) then done[#done + 1] = x.label end
            end
        end
        if trainees then
            local ok, n = pcall(function() return ED:ClearTestTrainees() end)
            if ok then done[#done + 1] = ('%d test trainee(s)'):format(tonumber(n) or 0) end
        end
        MDT.log(c, 'testclear', table.concat(done, '; '):sub(1, 400))
        for _, w in ipairs({ 'cases', 'reports', 'warrants', 'bolos', 'training', 'evidence' }) do MDT.refresh(w) end
        return { cleared = #done, labels = done }
    end)
end
