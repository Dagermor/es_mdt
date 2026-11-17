local _ENV = ESAPP('mdt'); -- es_mdt 1.4.0: the Evidence tab. The evidence itself lives in es_evidence (scenes, bags, lab, lockers, camera);
-- the MDT reads and links it through es_evidence's exports. Without es_evidence running the tab says so.

local function on() return GetResourceState('es_evidence') == 'started' end
local function EV() return exports.es_evidence end
local NOT = 'The evidence system (es_evidence) is not running'

function MDT.registerEvidence()
    local cb, str, id = MDT.cb, MDT.str, MDT.id

    local function reportFor(c, rid)
        local r = rid and MySQL.single.await('SELECT `id`,`deptId`,`authorCharId` FROM `es_mdt_reports` WHERE `id` = ?', { rid })
        if not r then return false, 'No such report' end
        if not MDT.canSeeReport(c, r) then return false, 'That report is not yours to change' end
        return r
    end

    cb('evStatus', { rate = 500, burst = 4 }, function(c)
        if not on() then return { installed = false } end
        local p = c.perms
        return { installed = true, collect = p.evidence_collect or c.staff, lab = p.evidence_lab or c.staff, manage = p.evidence_manage or c.staff }
    end)

    cb('evList', { rate = 250, burst = 6 }, function(c, d)
        if not on() then return false, NOT end
        return EV():Search({ q = str(d.q, 60), kind = str(d.kind, 12), status = str(d.status, 12), caseId = d.caseId == 'none' and 'none' or id(d.caseId), limit = 60, offset = math.max(0, math.floor(tonumber(d.offset) or 0)) })
    end)

    cb('evGet', { rate = 200, burst = 8 }, function(c, d)
        if not on() then return false, NOT end
        local r = EV():Get(id(d.id))
        if not r then return false, 'No such evidence' end
        return r
    end)

    cb('evForReport', { rate = 250, burst = 6 }, function(c, d)
        if not on() then return {} end
        return EV():ForReport(id(d.reportId))
    end)

    cb('evLink', { perm = 'mdt_reports_write', write = true, rate = 500, burst = 4 }, function(c, d)
        if not on() then return false, NOT end
        local r, why = reportFor(c, id(d.reportId))
        if not r then return false, why end
        local ok, err = EV():Link(r.id, id(d.evidenceId), c.charId)
        if not ok then return false, err end
        MDT.log(c, 'evidence_link', ('report #%d: EV %d'):format(r.id, id(d.evidenceId) or 0))
        return true
    end)

    cb('evUnlink', { perm = 'mdt_reports_write', write = true, rate = 500, burst = 4 }, function(c, d)
        if not on() then return false, NOT end
        local r, why = reportFor(c, id(d.reportId))
        if not r then return false, why end
        return EV():Unlink(r.id, id(d.evidenceId), c.charId)
    end)

    -- 1.5.1: the report editor's quick sources: bags I carry, what I collected today, the report's case, my camera roll
    cb('evSources', { rate = 400, burst = 4 }, function(c, d)
        if not on() then return false, NOT end
        local out = { carrying = {}, recent = {}, case = {}, roll = {}, collect = (c.perms.evidence_collect or c.staff) and true or false }
        local okC, car = pcall(function() return EV():Carrying(c.source) end)
        if okC and type(car) == 'table' then out.carrying = car end
        if d.only == 'carrying' then return out end
        out.recent = EV():CollectedBy(c.charId, 24) or {}
        out.roll = EV():Roll(c.charId) or {}
        local cid = id(d.caseId)
        if not cid and id(d.reportId) then
            local r = MySQL.single.await('SELECT `id`,`deptId`,`authorCharId`,`caseId` FROM `es_mdt_reports` WHERE `id` = ?', { id(d.reportId) })
            if r and MDT.canSeeReport(c, r) then cid = r.caseId end
        end
        if cid then
            local okK, k = pcall(function() return EV():ForCase(cid) end)
            if okK and type(k) == 'table' then out.case = k.items or {} out.caseId = cid end
        end
        return out
    end)

    -- 1.5.1: save the evidence picked in the report editor (or Process arrest): links every item to the report
    -- (custody: "Attached to report #N"), logs picked camera-roll photos as evidence first, and files the report's
    -- evidence that has no case yet to the report's case.
    cb('evAttachMany', { perm = 'mdt_reports_write', write = true, rate = 800, burst = 3 }, function(c, d)
        if not on() then return false, NOT end
        local r, why = reportFor(c, id(d.reportId))
        if not r then return false, why end
        local ids, seen, made, fails = {}, {}, {}, {}
        local function add(x) x = id(x) if x and not seen[x] and #ids < 60 then seen[x] = true ids[#ids + 1] = x end end
        for _, x in ipairs(type(d.ids) == 'table' and d.ids or {}) do add(x) end
        local photos = type(d.photos) == 'table' and d.photos or {}
        if #photos > 0 and not (c.perms.evidence_collect or c.staff) then fails[#fails + 1] = 'Your rank cannot log camera photos as evidence'
        else
            for i, pid in ipairs(photos) do
                if i > 20 then break end
                local res, err = EV():PhotoEvidence({ source = c.source, charId = c.charId, name = c.name }, id(pid), nil, nil)
                if res then add(res.id) if not res.existing then made[#made + 1] = res.code end else fails[#fails + 1] = err end
            end
        end
        local linked = 0
        for _, evId in ipairs(ids) do
            local ok, new = EV():Link(r.id, evId, c.charId)
            if ok then if new then linked = linked + 1 end else fails[#fails + 1] = new end
        end
        local filed, caseNo = 0, nil
        local caseId = MySQL.scalar.await('SELECT `caseId` FROM `es_mdt_reports` WHERE `id` = ?', { r.id })
        if caseId then
            local rows = MySQL.query.await([[SELECT e.`id` FROM `es_evidence` e JOIN `es_evidence_reports` l ON l.`evidenceId` = e.`id`
                WHERE l.`reportId` = ? AND e.`caseId` IS NULL AND e.`status` NOT IN ('scene','gone','destroyed')]], { r.id }) or {}
            for _, x in ipairs(rows) do
                local ok, no = EV():SetCase(x.id, caseId, c.charId)
                if ok then filed = filed + 1 caseNo = no or caseNo end
            end
            if filed > 0 and MDT.caseLog then pcall(MDT.caseLog, caseId, c, 'evidence', ('%d item(s) from report #%d'):format(filed, r.id)) end
        end
        if linked > 0 or #made > 0 then MDT.log(c, 'evidence_link', ('report #%d: %d linked, %d photo(s) logged, %d filed'):format(r.id, linked, #made, filed)) end
        return { linked = linked, made = made, filed = filed, caseNo = caseNo, fails = fails }
    end)

    cb('evNote', { perm = 'evidence_collect', write = true, rate = 800, burst = 3 }, function(c, d)
        if not on() then return false, NOT end
        local ok, err = EV():SetNote(id(d.id), str(d.note, 500), c.charId)
        if not ok then return false, err or 'Not saved' end
        return true
    end)

    cb('evDestroy', { perm = 'evidence_manage', write = true, rate = 1500, burst = 2 }, function(c, d)
        if not on() then return false, NOT end
        local reason = str(d.reason, 200)
        if reason == '' then return false, 'Say why (released to owner, case closed, ...)' end
        local ok, err = EV():Destroy(id(d.id), c.charId, reason)
        if not ok then return false, err end
        MDT.log(c, 'evidence_destroy', ('EV %d: %s'):format(id(d.id) or 0, reason))
        return true
    end)

    -- 1.5.4: release a bagged weapon: the weapon itself goes to the officer (who carries the bag) to hand back
    cb('evRelease', { perm = 'evidence_manage', write = true, rate = 1500, burst = 2 }, function(c, d)
        if not on() then return false, NOT end
        local reason = str(d.reason, 200)
        if reason == '' then return false, 'Say why (released to owner, case closed, ...)' end
        local ok, res, err = pcall(function() return EV():ReleaseWeapon(id(d.id), c.source, c.charId, reason) end)
        if not ok then return false, 'Evidence is not up to date: restart es_evidence' end
        if not res then return false, err end
        MDT.log(c, 'evidence_release', ('EV %d: %s'):format(id(d.id) or 0, reason))
        return true
    end)

    cb('evRoll', { rate = 300, burst = 6 }, function(c)
        if not on() then return {} end
        return EV():Roll(c.charId)
    end)

    cb('evRollPhoto', { rate = 120, burst = 12 }, function(c, d)
        if not on() then return false, NOT end
        local img = EV():RollImage(c.charId, id(d.id))
        if not img then return false, 'That photo is not in your camera roll' end
        return { id = id(d.id), image = img }
    end)

    -- your own camera-roll photo, or a picture from a link, logged as evidence (optionally on a report)
    cb('evPhoto', { perm = 'evidence_collect', write = true, rate = 2500, burst = 2 }, function(c, d)
        if not on() then return false, NOT end
        local rid = id(d.reportId)
        if rid then local r, why = reportFor(c, rid) if not r then return false, why end end
        local res, err
        if id(d.photoId) then
            res, err = EV():PhotoEvidence({ source = c.source, charId = c.charId, name = c.name }, id(d.photoId), nil, str(d.note, 500))
        else
            local url = str(d.url, 500)
            local ok, why = Fetch.check(url)
            if not ok then return false, why end
            local img, ferr = Fetch.get(url)
            if not img then return false, ferr end
            if #img > math.floor(1024 * 1024 * 4 / 3) + 64 then return false, ('That picture is %d KB; evidence photos can be 1 MB at most'):format(math.ceil(#img * 3 / 4 / 1024)) end
            res, err = EV():PhotoEvidence({ source = c.source, charId = c.charId, name = c.name }, nil, img, str(d.note, 500), str(d.label, 100))
        end
        if not res then return false, err end
        -- 1.5.2: logged (or found already logged), then linked; a link that fails is said, not swallowed
        if rid then
            local ok, lerr = EV():Link(rid, res.id, c.charId)
            if not ok then
                return false, ('%s is %s, but it could not be attached to report #%d: %s'):format(res.code, res.existing and 'already evidence' or 'logged as evidence', rid, tostring(lerr or 'unknown error'))
            end
            res.reportId = rid
        end
        MDT.log(c, 'evidence_photo', ('%s%s%s'):format(res.code, res.existing and ' (already logged)' or '', rid and (' → report #' .. rid) or ''))
        return res
    end)

    -- 1.5.3: take a person's fingerprints (booking): they go on file, and the lab's unidentified prints of theirs
    -- match at once. Same rule as a mugshot: they must be close to you (or it is yourself, for testing).
    cb('evPrintsTake', { perm = 'mdt_reports_write', write = true, rate = 2500, burst = 2 }, function(c, d)
        if not on() then return false, NOT end
        local cid = id(d.charId)
        if not cid then return false, 'Pick a person' end
        if MDT.suspectNear then
            local src, why = MDT.suspectNear(c, cid, 'take their prints')
            if not src then return false, why end
        end
        local res, err = EV():BookPrints(cid, c.charId)
        if not res then return false, err end
        MDT.log(c, 'prints_taken', ('#%d %s%s'):format(cid, res.fp or '', (#(res.matched or {}) > 0) and (' · matched ' .. table.concat(res.matched, ',')) or ''))
        MDT.refresh('people')
        return res
    end)

    cb('evPrintsOf', { rate = 300, burst = 6 }, function(c, d)
        if not on() then return { onFile = false } end
        return EV():PrintsOnFile(id(d.charId))
    end)

    cb('evLockers', { rate = 500, burst = 4 }, function(c)
        if not on() then return false, NOT end
        if not (c.perms.evidence_collect or c.perms.evidence_manage or c.staff) then return false, 'Your rank cannot see the lockers' end
        return EV():Lockers()
    end)
end

-- 1.5.2: es_evidence says evidence moved (locker, stash, lab, hand-over, report, case): every open MDT re-reads
-- the Evidence tab, the case page and report cards (the MDT's usual refresh push, batched there).
AddEventHandler('es_evidence:changed', function()
    if GetInvokingResource() ~= 'es_evidence' then return end
    if MDT.refresh then MDT.refresh('evidence') end
end)
