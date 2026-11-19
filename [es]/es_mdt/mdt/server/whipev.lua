local _ENV = ESAPP('mdt'); -- es_mdt 1.11.0: optional bridge to a third-party evidence resource, whip_evidence (Config.WhipEvidence).
-- whip_evidence keeps the things (bags, photos, guns, lab, lockers); the MDT keeps the cases. The only link is the
-- case ID, and ours is the case number (C-2026-0009). Everything runs here on the server; the page only sends our
-- case id and the refs it picked, and both are checked (this officer may file into this case; the refs are really
-- in this officer's pockets / evidence case right now).
-- Off (enabled = false) or not installed: nothing here calls whip_evidence and every page call answers "off".
-- Works side by side with es_evidence: its own tables, its own section on case pages and reports.

local CFG = Config.WhipEvidence or {}
local RES = type(CFG.resource) == 'string' and CFG.resource or 'whip_evidence'
local REASONS = { uploaded = true, taken = true, returned = true, closed = true, reopened = true, deleted = true }
local BAG_KINDS = { casing = true, bullet = true, blood = true, fingerprint = true, vehicle_fragment = true, gsr = true, reference = true,
    shoeprint = true, tyre_track = true, fiber = true, cleaned = true, serial = true,   -- 2.0.16: whip_evidence 4.2 bags
    autopsy = true }   -- 2.0.17: whip_evidence 4.2.3 post-mortem report

--- enabled = true / false / 'auto' (auto: on whenever the resource exists on the server)
local function wanted()
    if CFG.enabled == false then return false end
    if CFG.enabled == true then return true end
    return GetResourceState(RES) ~= 'missing'
end
local function on() return wanted() and GetResourceState(RES) == 'started' end

--- One export call, never throws: returns ok, a, b
local function X(fn, ...)
    if not on() then return false end
    local args = table.pack(...)
    local okc, a, b = pcall(function() return exports[RES][fn](exports[RES], table.unpack(args, 1, args.n)) end)
    if not okc then
        print(('^3[es_mdt] whip_evidence:%s failed: %s^7'):format(fn, tostring(a)))
        return false
    end
    return true, a, b
end

--- Their case ID rules: letters / digits / _ / -, at most 32, a leading # ignored
local function caseKey(v)
    if type(v) == 'number' then v = tostring(math.floor(v)) end
    if type(v) ~= 'string' then return nil end
    v = v:gsub('^%s+', ''):gsub('%s+$', ''):gsub('^#', '')
    if v == '' or #v > 32 or not v:match('^[%w_%-]+$') then return nil end
    return v
end
local function refOk(v) return type(v) == 'string' and #v <= 80 and #v >= 5 and v:match('^%a+:[%w_%-%.:#/]+$') ~= nil end

local function caseByNumber(number)
    number = caseKey(number)
    if not number then return nil end
    return MySQL.single.await('SELECT `id`,`number`,`title`,`status` FROM `es_mdt_cases` WHERE BINARY `number` = ?', { number }) or nil
end

-- ---------------------------------------------------------------- the case check whip_evidence asks (lab device etc.)
-- They call this from their own thread, so it answers from a cache of usable case numbers (open / closed, not
-- archived), refreshed every 30 s; a miss is looked up live when the caller's thread can wait.
local Usable = {}
local function loadUsable()
    local rows = MySQL.query.await("SELECT `number` FROM `es_mdt_cases` WHERE `status` <> 'archived'") or {}
    local t = {}
    for _, r in ipairs(rows) do t[r.number] = true end
    Usable = t
end
local function caseCheck(caseId)
    local key = caseKey(caseId)
    if not key then return false end
    if Usable[key] then return true end
    if coroutine.isyieldable() then
        local okq, st = pcall(function() return MySQL.scalar.await('SELECT `status` FROM `es_mdt_cases` WHERE BINARY `number` = ?', { key }) end)
        if okq and st and st ~= 'archived' then Usable[key] = true return true end
    end
    return false
end
local function hook()
    if not on() then return end
    pcall(loadUsable)
    local ok = X('SetCaseCheck', function(caseId) return caseCheck(caseId) end)
    if ok then print('^2[es_mdt] whip_evidence found: case check hooked (case IDs are MDT case numbers, e.g. C-2026-0001)^7') end
end

-- 2.0.8: turned on in /whip > Settings > MDT while running: hook up then (a tick later: never inside whip_core's settings call)
if Whip and Whip.onConfigChanged then
    Whip.onConfigChanged('WhipEvidence.enabled', function(value)
        if value == false then return end
        SetTimeout(1000, function() pcall(hook) end)
    end)
end

-- ---------------------------------------------------------------- stored snapshots
local function decode(s)
    if type(s) ~= 'string' or s == '' then return nil end
    local okd, v = pcall(json.decode, s)
    return okd and type(v) == 'table' and v or nil
end

--- Keep a copy of a photo (their photos expire unless they sit in a case locker); nil when too big / missing
local function cachePhoto(photoId)
    photoId = photoId ~= nil and tostring(photoId) or nil
    if not photoId or #photoId > 64 then return nil end
    local have = MySQL.scalar.await('SELECT `image` FROM `es_mdt_wev_photos` WHERE `photoId` = ?', { photoId })
    if have then return have end
    local ok, img = X('GetPhotoImage', photoId)   -- whip_evidence photo ids are strings (loadPhoto refuses numbers)
    if not ok or type(img) ~= 'string' or not img:match('^data:image/[%w%+%-%.]+;base64,') then return nil end
    local max = tonumber(CFG.photoStoreBytes) or (4 * 1024 * 1024)
    if #img <= max then
        MySQL.insert.await('INSERT IGNORE INTO `es_mdt_wev_photos` (`photoId`,`image`) VALUES (?,?)', { photoId, img })
    end
    return img
end

-- 1.11.3: whip_evidence writes its times as text in the server's clock (os.date, UTC on this VPS) with no zone.
-- Read them back here with os.time (same clock), so the page gets plain epoch seconds and shows them in the
-- officer's own time like every other MDT time.
--- "2026-11-17 17:43:05" -> epoch, else nil
local function stampOf(v)
    if type(v) ~= 'string' then return nil end
    local y, mo, d, h, mi, se = v:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)[ T](%d%d):(%d%d):?(%d*)')
    if not y then return nil end
    return os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = tonumber(se) or 0 })
end
--- One custody step "11/17 17:43 Uploaded to case C-2026-0003 · Ofc. Doe" -> { at, what, who } (at nil when unreadable)
local function stepOf(s)
    local mo, d, h, mi, rest = s:match('^(%d%d)/(%d%d) (%d%d):(%d%d) (.*)$')
    local at
    if mo then
        local now = os.time()
        local y = tonumber(os.date('%Y', now))
        at = os.time({ year = y, month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = 0 })
        if at > now + 86400 then   -- no year in the text: a December step read in January
            at = os.time({ year = y - 1, month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = 0 })
        end
    else
        rest = s
    end
    local what, who = rest:match('^(.-) · (.+)$')
    return { at = at, what = what or rest, who = who }
end
local function stepsOf(custody)
    local out = {}
    if type(custody) == 'string' and custody ~= '' then
        for step in (custody .. ' → '):gmatch('(.-) → ') do if step ~= '' then out[#out + 1] = stepOf(step) end end
    end
    return out
end
--- The newest step of an entry (by time), or nil
local function lastStep(e)
    local best
    for _, st in ipairs(stepsOf(type(e) == 'table' and e.custody)) do
        if st.at and (not best or st.at >= best.at) then best = st end
    end
    return best
end

-- 2.0.17: whip_evidence 4.2.3's post-mortem report (entry.report of a kind 'autopsy' bag), kept to what the page draws.
-- `at` is their server-clock text and `age` the seconds dead at the exam: both turned into epoch times here (same clock).
local WOUND = { gunshot = true, stab = true, blunt = true, vehicle = true, fall = true, burn = true, explosion = true, other = true }
local PART = { head = true, torso = true, arms = true, legs = true }
local RANGE = { close = true, short = true, far = true }
-- 2.0.18: the exact spot of a hit (whip_evidence 4.2.4+, from the bone that was hit; _l / _r = the body's own side)
local SPOT = { head = true, neck = true, chest = true, belly = true, pelvis = true, shoulder_l = true, shoulder_r = true,
    upperarm_l = true, forearm_l = true, hand_l = true, upperarm_r = true, forearm_r = true, hand_r = true,
    thigh_l = true, shin_l = true, foot_l = true, thigh_r = true, shin_r = true, foot_r = true }
local function str(v, n) return type(v) == 'string' and v:sub(1, n or 80) or nil end
local function num(v) v = tonumber(v) return v and v == v and v or nil end
local function woundList(t)
    local out = {}
    for _, x in ipairs(type(t) == 'table' and t or {}) do
        if type(x) == 'table' and WOUND[x.w] then out[#out + 1] = { w = x.w, n = math.max(1, math.floor(num(x.n) or 1)) } end
        if #out >= 8 then break end
    end
    return out
end
local function reportView(r)
    if type(r) ~= 'table' then return nil end
    local d = type(r.details) == 'table' and r.details or {}
    local marks, byPart, ranges = {}, {}, {}
    for _, m in ipairs(type(d.marks) == 'table' and d.marks or {}) do
        if type(m) == 'table' and PART[m.p] and WOUND[m.w] then marks[#marks + 1] = { p = m.p, s = SPOT[m.s] and m.s or nil, w = m.w, i = m.i == true or nil, f = m.f == true or nil } end
        if #marks >= 24 then break end
    end
    for _, x in ipairs(type(d.byPart) == 'table' and d.byPart or {}) do
        if type(x) == 'table' and PART[x.p] then byPart[#byPart + 1] = { p = x.p, w = woundList(x.w) } end
    end
    for _, x in ipairs(type(d.ranges) == 'table' and d.ranges or {}) do if RANGE[x] then ranges[#ranges + 1] = x end end
    local at = stampOf(r.at)
    local age = num(r.age)
    local fatal = type(d.fatal) == 'table' and WOUND[d.fatal.w] and PART[d.fatal.p] and { w = d.fatal.w, p = d.fatal.p } or nil
    return {
        id = str(r.id, 32), no = num(r.no), kind = r.kind == 'player' and 'player' or 'ped',
        title = str(r.title, 40), text = str(r.text, 4000),
        examinedAt = at, examinedBy = str(r.examinedBy, 80), street = str(r.street, 120),
        age = age, diedAt = (at and age) and (at - math.floor(age)) or nil,
        wounds = woundList(r.wounds), bullets = math.floor(num(r.bullets) or 0),
        photo = r.photo == true or (r.photo ~= nil and r.photo ~= false) or nil, blood = r.blood == true or nil, gsr = r.gsr == true or nil,
        hits = math.floor(num(d.hits) or #marks), byPart = byPart, ranges = ranges, through = math.floor(num(d.through) or 0),
        defense = d.defense == true or nil, armed = d.armed == true or nil, moved = num(d.moved), fatal = fatal,
        sex = (d.sex == 'male' or d.sex == 'female') and d.sex or nil, marks = marks,
    }
end
--- photo body rows { n = 'L1', t = 'Body', i = 'Gunshot ×2', d = 4 }
local function bodyRows(t)
    local out = {}
    for _, b in ipairs(type(t) == 'table' and t or {}) do
        if type(b) == 'table' and str(b.n, 8) then out[#out + 1] = { n = str(b.n, 8), t = str(b.t, 30), i = str(b.i, 120), d = num(b.d) } end
        if #out >= 12 then break end
    end
    return #out > 0 and out or nil
end

--- Light view of an entry for the page (no pictures, results kept, custody split into steps)
local function view(e, ref)
    e = type(e) == 'table' and e or {}
    local custody = stepsOf(e.custody)
    local kind = type(e.kind) == 'string' and e.kind or (ref and ref:match('^(%a+):')) or 'item'
    return {
        ref = ref or e.ref, kind = kind, item = e.item, type = e.type, label = e.type or e.item or ref,
        bag = BAG_KINDS[kind] or (ref or ''):sub(1, 4) == 'bag:',
        analysed = e.analysed == true, case = e.case,
        time = stampOf(e.time) or e.time, street = e.street, collectedBy = e.collected_by, marker = e.marker, photographed = e.photographed, testedOn = e.tested_on,
        results = type(e.results) == 'table' and e.results or nil,
        photoId = e.photo_id, scene = e.scene, takenBy = e.taken_by, entries = type(e.entries) == 'table' and e.entries or nil,
        cars = type(e.cars) == 'table' and e.cars or nil,
        serial = e.serial, caliber = e.caliber, ballistics = e.ballistics,
        custody = custody,
        body = str(e.body, 32), report = kind == 'autopsy' and reportView(e.report) or nil, bodies = bodyRows(e.bodies),   -- 2.0.17
    }
end
MDT.wevView = view   -- 2.0.17: for the tests

--- Everything the case page needs: saved entries, who has what out of the locker, whether their side closed it
local function forCase(k)
    if not wanted() then return nil end
    local out = { enabled = true, running = on(), items = {}, taken = {}, closed = false }
    local rows = MySQL.query.await([[SELECT `ref`,`kind`,`data`,`uploadedBy`,UNIX_TIMESTAMP(`uploadedAt`) AS `uploadedAt`, `gone`
        FROM `es_mdt_wev_entries` WHERE `caseId` = ? ORDER BY `uploadedAt`, `ref`]], { k.id }) or {}
    local ids = {}
    for _, r in ipairs(rows) do ids[#ids + 1] = r.uploadedBy end
    local nm = MDT.namesOf(ids)
    for _, r in ipairs(rows) do
        local v = view(decode(r.data), r.ref)
        v.uploadedAt, v.uploadedBy, v.gone = r.uploadedAt, r.uploadedBy and nm[r.uploadedBy] or nil, r.gone == 1 or r.gone == true
        out.items[#out.items + 1] = v
    end
    if out.running then
        local ok, c = X('GetCase', k.number)
        if ok and type(c) == 'table' then
            out.closed = c.closed and true or false
            out.closedBy = c.closedBy
            for ref, t in pairs(type(c.taken) == 'table' and c.taken or {}) do
                if type(t) == 'table' then out.taken[tostring(ref)] = { by = t.by, at = t.at, what = t.what } end
            end
        end
    end
    return out
end
MDT.wevForCase = forCase

local MdtUploads = {}   -- 1.11.2: '<case>|<ref>' -> GetGameTimer() of an upload made from the MDT

--- Their locker changed: refresh our snapshots from GetCase, mark items no longer there
local function resync(k)
    local ok, c = X('GetCase', k.number)
    if not ok then return end
    if type(c) ~= 'table' then
        MySQL.update.await('UPDATE `es_mdt_wev_entries` SET `gone` = 1 WHERE `caseId` = ?', { k.id })
        return
    end
    local seen, added = {}, {}
    local had = {}
    for _, r in ipairs(MySQL.query.await('SELECT `ref` FROM `es_mdt_wev_entries` WHERE `caseId` = ? AND `gone` = 0', { k.id }) or {}) do had[r.ref] = true end
    for _, e in ipairs(type(c.items) == 'table' and c.items or {}) do
        if type(e) == 'table' and refOk(e.ref) then
            seen[e.ref] = true
            -- 1.11.2: for the case timeline (not the ones the MDT itself just uploaded)
            local mine = MdtUploads[k.number .. '|' .. e.ref]
            if not had[e.ref] and not (mine and GetGameTimer() - mine < 30000) then
                local st = lastStep(e)
                added[#added + 1] = tostring(e.type or e.item or e.ref) .. (st and st.who and (' — ' .. st.who) or '')
            end
            local okj, data = pcall(json.encode, e)
            if okj then
                MySQL.insert.await([[INSERT INTO `es_mdt_wev_entries` (`caseId`,`ref`,`kind`,`data`) VALUES (?,?,?,?)
                    ON DUPLICATE KEY UPDATE `data` = VALUES(`data`), `kind` = VALUES(`kind`), `gone` = 0]],
                    { k.id, e.ref, tostring(e.kind or ''):sub(1, 20), data })
            end
        end
    end
    -- items taken out of the locker are still the case's (taken[ref]); only drop what is in neither list
    local taken = type(c.taken) == 'table' and c.taken or {}
    for _, r in ipairs(MySQL.query.await('SELECT `ref` FROM `es_mdt_wev_entries` WHERE `caseId` = ? AND `gone` = 0', { k.id }) or {}) do
        if not seen[r.ref] and not taken[r.ref] then
            MySQL.update.await('UPDATE `es_mdt_wev_entries` SET `gone` = 1 WHERE `caseId` = ? AND `ref` = ?', { k.id, r.ref })
        end
    end
    return added, c
end

-- ---------------------------------------------------------------- MDT closes / reopens a case: tell whip_evidence
--- returns nil when fine (or nothing to tell), else a message for the officer
MDT.wevCaseStatus = function(source, k, newStatus)
    if not on() then return nil end
    if newStatus == 'archived' then Usable[k.number] = nil else Usable[k.number] = true end
    local known = MySQL.scalar.await('SELECT 1 FROM `es_mdt_wev_entries` WHERE `caseId` = ? LIMIT 1', { k.id }) ~= nil
    if not known then
        local okg, c = X('GetCase', k.number)
        known = okg and type(c) == 'table'
    end
    if not known then return nil end
    local fn = newStatus == 'open' and 'ReopenCase' or 'CloseCase'
    if newStatus ~= 'open' and k.status ~= 'open' then return nil end   -- closed <-> archived: already closed there
    local ok, res, why = X(fn, k.number, source)
    if not ok then return 'The evidence locker (whip_evidence) did not answer: its locker was not ' .. (fn == 'CloseCase' and 'closed' or 'reopened') end
    if res ~= true then
        return ('Evidence locker (whip_evidence): %s'):format(tostring(why or 'it refused'))
    end
    return nil
end

function MDT.registerWhipEv()
    local cb, str, id, log = MDT.cb, MDT.str, MDT.id, MDT.log
    local OFF = 'The whip_evidence integration is off or whip_evidence is not running'

    local function caseFor(c, caseId, needFile)
        local k = MDT.getCase(caseId)
        if not k then return nil, 'No such case' end
        if needFile then
            local ok, why = MDT.caseCanFile(c, k)
            if not ok then return nil, why end
            if k.status ~= 'open' then return nil, 'This case is ' .. k.status .. ': reopen it first' end
        end
        return k
    end

    cb('wevStatus', { rate = 300, burst = 6 }, function()
        return { enabled = wanted(), running = on() }
    end)

    -- "Add evidence": what this officer carries (pockets + evidence case), marked for this case
    cb('wevList', { rate = 500, burst = 6 }, function(c, d)
        if not on() then return false, OFF end
        local k, why = caseFor(c, d.caseId, true)
        if not k then return false, why end
        local ok, list = X('GetUploadable', c.source)
        if not ok then return false, 'whip_evidence did not answer' end
        local out = {}
        for _, e in ipairs(type(list) == 'table' and list or {}) do
            if type(e) == 'table' and refOk(e.ref) and #out < 200 then
                local v = view(e, e.ref)
                local cs = caseKey(e.case)
                v.otherCase = (cs and cs ~= k.number) and cs or nil
                v.onCase = cs == k.number
                v.canAdd = v.analysed and not v.otherCase
                out[#out + 1] = v
            end
        end
        table.sort(out, function(a, b)
            if a.canAdd ~= b.canAdd then return a.canAdd end
            return tostring(a.ref) < tostring(b.ref)
        end)
        return { caseNumber = k.number, items = out }
    end)

    -- upload the picked refs into the case's locker; save every ok entry, tell every why
    cb('wevUpload', { write = true, rate = 1500, burst = 2 }, function(c, d)
        if not on() then return false, OFF end
        local k, why = caseFor(c, d.caseId, true)
        if not k then return false, why end
        local want, seen = {}, {}
        local max = math.max(1, math.min(60, tonumber(CFG.maxUpload) or 30))
        for _, r in ipairs(type(d.refs) == 'table' and d.refs or {}) do
            if refOk(r) and not seen[r] and #want < max then seen[r] = true want[#want + 1] = r end
        end
        if #want == 0 then return false, 'Pick at least one item' end
        -- only refs this officer really has right now
        local okL, list = X('GetUploadable', c.source)
        if not okL then return false, 'whip_evidence did not answer' end
        local mine = {}
        for _, e in ipairs(type(list) == 'table' and list or {}) do if type(e) == 'table' and e.ref then mine[e.ref] = true end end
        local refs, results = {}, {}
        for _, r in ipairs(want) do
            if mine[r] then refs[#refs + 1] = r else results[#results + 1] = { ref = r, ok = false, why = 'You no longer have this item' } end
        end
        if #refs > 0 then
            -- 1.11.2: these log themselves below; the caseChanged that Upload fires must not log them again
            local now = GetGameTimer()
            for _, r in ipairs(refs) do MdtUploads[k.number .. '|' .. r] = now end
            local ok, res, err = X('Upload', c.source, refs, k.number)
            if not ok then return false, 'whip_evidence did not answer' end
            if not res then return false, tostring(err or 'whip_evidence refused the upload') end
            local photos = {}
            for _, r in ipairs(type(res) == 'table' and res or {}) do
                if type(r) == 'table' and refOk(r.ref) then
                    if r.ok and type(r.entry) == 'table' then
                        local okj, data = pcall(json.encode, r.entry)
                        if okj then
                            MySQL.insert.await([[INSERT INTO `es_mdt_wev_entries` (`caseId`,`ref`,`kind`,`data`,`uploadedBy`) VALUES (?,?,?,?,?)
                                ON DUPLICATE KEY UPDATE `data` = VALUES(`data`), `kind` = VALUES(`kind`), `gone` = 0]],
                                { k.id, r.ref, tostring(r.entry.kind or ''):sub(1, 20), data, c.charId })
                        end
                        if r.entry.photo_id ~= nil then photos[#photos + 1] = r.entry.photo_id end
                        results[#results + 1] = { ref = r.ref, ok = true, label = r.entry.type or r.entry.item }
                    else
                        results[#results + 1] = { ref = r.ref, ok = false, why = r.why and tostring(r.why) or 'Not uploaded' }
                    end
                end
            end
            local n = 0
            for _, r in ipairs(results) do if r.ok then n = n + 1 end end
            if n > 0 then
                local names = {}
                for _, r in ipairs(results) do if r.ok then names[#names + 1] = tostring(r.label or r.ref) end end
                MDT.caseLog(k.id, c, 'wev_filed', table.concat(names, ', '):sub(1, 200))   -- 1.11.3: own timeline title
                log(c, 'wev_upload', ('%s: %d items'):format(k.number, n))
                MDT.refresh('cases')
            end
            if CFG.cachePhotosOnUpload ~= false and #photos > 0 then
                CreateThread(function() for _, p in ipairs(photos) do cachePhoto(p) Wait(250) end end)
            end
        end
        return { results = results }
    end)

    -- a photo's picture, on demand: our copy first, else theirs (and keep it)
    cb('wevPhoto', { rate = 300, burst = 6 }, function(c, d)
        local k = MDT.getCase(d.caseId)
        if not k then return false, 'No such case' end
        local ref = refOk(d.ref) and d.ref or nil
        local row = ref and MySQL.single.await('SELECT `data` FROM `es_mdt_wev_entries` WHERE `caseId` = ? AND `ref` = ?', { k.id, ref })
        if not row then return false, 'Not in this case' end
        local e = decode(row.data) or {}
        if e.photo_id == nil then return false, 'Not a photo' end
        local pid = tostring(e.photo_id)
        local have = MySQL.scalar.await('SELECT `image` FROM `es_mdt_wev_photos` WHERE `photoId` = ?', { pid })
        if have then return { ref = ref, image = have } end
        if not on() then return false, OFF end
        local img = cachePhoto(pid)
        if not img then return false, 'The picture is gone (whip_evidence keeps photos outside a case locker only for a while)' end
        return { ref = ref, image = img }
    end)

    -- open the case's locker for this officer (only works standing at an evidence locker)
    cb('wevLocker', { rate = 1500, burst = 3 }, function(c, d)
        if not on() then return false, OFF end
        local k = MDT.getCase(d.caseId)
        if not k then return false, 'No such case' end
        if c.readOnly then return false, 'You are off duty: the MDT is read-only' end
        local ok, res, why = X('OpenCaseLocker', c.source, k.number)
        if not ok then return false, 'whip_evidence did not answer' end
        -- 2.0.16: whip_evidence 4.1+ says why (not at a locker, rank level); no reason = its 1 s "Opening locker" bar was cancelled
        if res == false then return false, why and tostring(why) or 'Opening the locker was cancelled. Stand still at the evidence locker and try again' end
        return true
    end)

    -- reports: attach / detach case entries as chips
    local function reportFor(c, rid, write)
        local r = rid and MySQL.single.await('SELECT `id`,`deptId`,`authorCharId`,`caseId` FROM `es_mdt_reports` WHERE `id` = ?', { rid })
        if not r then return nil, 'No such report' end
        if not MDT.canSeeReport(c, r) then return nil, 'That report is not yours to ' .. (write and 'change' or 'see') end
        return r
    end
    cb('wevReport', { rate = 300, burst = 6 }, function(c, d)
        if not wanted() then return { enabled = false } end
        local r, why = reportFor(c, id(d.reportId))
        if not r then return false, why end
        local rows = MySQL.query.await([[SELECT a.`ref`, e.`data`, e.`gone`, k.`id` AS `caseId`, k.`number` FROM `es_mdt_wev_report` a
            JOIN `es_mdt_wev_entries` e ON e.`caseId` = a.`caseId` AND e.`ref` = a.`ref` JOIN `es_mdt_cases` k ON k.`id` = a.`caseId`
            WHERE a.`reportId` = ? ORDER BY a.`addedAt`]], { r.id }) or {}
        local out = { enabled = true, running = on(), items = {}, caseId = r.caseId }
        for _, x in ipairs(rows) do
            local v = view(decode(x.data), x.ref)
            v.caseId, v.caseNumber, v.gone = x.caseId, x.number, x.gone == 1 or x.gone == true
            out.items[#out.items + 1] = v
        end
        if r.caseId then
            out.available = {}
            local have = {}
            for _, v in ipairs(out.items) do have[v.ref] = true end
            for _, x in ipairs(MySQL.query.await('SELECT `ref`,`data`,`gone` FROM `es_mdt_wev_entries` WHERE `caseId` = ? ORDER BY `uploadedAt`', { r.caseId }) or {}) do
                if not have[x.ref] then
                    local v = view(decode(x.data), x.ref)
                    v.caseId, v.gone = r.caseId, x.gone == 1 or x.gone == true
                    out.available[#out.available + 1] = v
                end
            end
        end
        return out
    end)
    cb('wevReportLink', { perm = 'mdt_reports_write', write = true, rate = 400, burst = 6 }, function(c, d)
        if not wanted() then return false, OFF end
        local r, why = reportFor(c, id(d.reportId), true)
        if not r then return false, why end
        local ref = refOk(d.ref) and d.ref or nil
        if not ref then return false, 'Pick an item' end
        if d.remove then
            MySQL.update.await('DELETE FROM `es_mdt_wev_report` WHERE `reportId` = ? AND `ref` = ?', { r.id, ref })
        else
            if not r.caseId then return false, 'File the report to a case first: whip_evidence items live in a case locker' end
            local inCase = MySQL.scalar.await('SELECT 1 FROM `es_mdt_wev_entries` WHERE `caseId` = ? AND `ref` = ?', { r.caseId, ref })
            if not inCase then return false, 'That item is not in this report\'s case' end
            MySQL.insert.await('INSERT IGNORE INTO `es_mdt_wev_report` (`reportId`,`caseId`,`ref`,`addedBy`) VALUES (?,?,?,?)', { r.id, r.caseId, ref, c.charId })
        end
        log(c, 'wev_report', ('report #%d %s %s'):format(r.id, d.remove and '-' or '+', ref))
        MDT.refresh('reports')
        return true
    end)

    -- ------------------------------------------------------------ live: their side changed a case's locker
    local pending = {}
    AddEventHandler('whip_evidence:caseChanged', function(caseId, why)
        local inv = GetInvokingResource()
        if inv and inv ~= RES then return end
        if not on() then return end
        local key = caseKey(caseId)
        if not key or pending[key] then return end
        why = REASONS[why] and why or 'changed'
        pending[key] = true
        SetTimeout(500, function()   -- several items at once fire several events: one refresh
            pending[key] = nil
            local k = caseByNumber(key)
            if not k then return end
            local okr, added, cs = pcall(resync, k)
            if not okr then print(('^3[es_mdt] whip_evidence resync %s: %s^7'):format(key, tostring(added))) added, cs = nil, nil end
            -- 1.11.2/1.11.3: the case timeline, one title per event (cases.js WEVLOG), detail "item — who".
            -- Uploads made in the MDT log themselves (wevUpload); these are the ones made elsewhere (the lab's
            -- "upload to case"), so only items we did not have yet are logged.
            local okl, errl = pcall(function()
                if why == 'uploaded' and type(added) == 'table' and #added > 0 then
                    MDT.caseLog(k.id, nil, 'wev_lab', table.concat(added, ', '):sub(1, 200))
                elseif why == 'taken' then
                    local best
                    for ref, t in pairs(type(cs) == 'table' and type(cs.taken) == 'table' and cs.taken or {}) do
                        if type(t) == 'table' and (not best or (tonumber(t.at) or 0) >= (tonumber(best.at) or 0)) then best = t best.ref = ref end
                    end
                    MDT.caseLog(k.id, nil, 'wev_taken', best and (tostring(best.what or best.ref) .. (best.by and (' — ' .. tostring(best.by)) or '')):sub(1, 200) or nil)
                elseif why == 'returned' then
                    local best, bestE
                    for _, e in ipairs(type(cs) == 'table' and type(cs.items) == 'table' and cs.items or {}) do
                        local st = lastStep(e)
                        if st and tostring(st.what):find('^Returned') and (not best or st.at >= best.at) then best, bestE = st, e end
                    end
                    MDT.caseLog(k.id, nil, 'wev_returned', bestE and (tostring(bestE.type or bestE.item or bestE.ref) .. (best.who and (' — ' .. best.who) or '')):sub(1, 200) or nil)
                elseif why == 'deleted' then
                    MDT.caseLog(k.id, nil, 'wev_deleted', 'The case locker was deleted in whip_evidence')
                end
            end)
            if not okl then print(('^3[es_mdt] whip_evidence timeline %s: %s^7'):format(key, tostring(errl))) end
            MDT.refresh('cases')
        end)
    end)

    -- the case check: hook now (if it is up) and again after every whip_evidence (re)start
    if wanted() then
        CreateThread(function()
            local tries = 0
            while GetResourceState(RES) ~= 'started' and tries < 240 do Wait(500) tries = tries + 1 end
            hook()
            while true do   -- keep the case-number cache fresh (new cases, archived ones)
                Wait(30000)
                if on() then pcall(loadUsable) end
                local now = GetGameTimer()
                for key, t in pairs(MdtUploads) do if now - t > 30000 then MdtUploads[key] = nil end end
            end
        end)
    end
    AddEventHandler('onResourceStart', function(res)
        if res == RES and wanted() then SetTimeout(1000, hook) end
    end)
end
