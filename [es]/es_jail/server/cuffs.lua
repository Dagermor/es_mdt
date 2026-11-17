-- es_jail cuffs: cuffing (soft / hard / zip ties), uncuffing, searching, breaking out by shaking the mouse
-- (3 escapes, each harder, the 4th time you are stuck), and lockpicking.
-- 1.0.3: the breakout happens WHILE the cuffs go on (the cuffing window, Config.Cuffs.seconds). Once they lock,
-- only a lockpick (or a key) gets them off. The server holds the truth:
--   Cuffed[source]      what they wear now (also the Sentinel bag esCuffed and the saved flag es_jail_cuffed)
--   Esc[charId]         escapes so far { n, at } (saved flag es_jail_esc)

local WC = exports.whip_core
local C, B, LP, IT = Config.Cuffs, Config.Breakout, Config.Lockpick, Config.Items
local BAG, FLAG, ESCFLAG = 'esCuffed', 'es_jail_cuffed', 'es_jail_esc'

local Cuffed = {}     -- [source] = { mode = 'soft'|'hard', kind = 'cuffs'|'ziptie', by = charId }
local Esc = {}        -- [charId] = { n, at }
local Busy = {}       -- [target] = true while being cuffed / uncuffed / picked
local Struggle = {}   -- [source] = the open cuffing window { token, level, ends, st, tag, by, started, result }
local Cool = {}       -- unused since 1.0.3 (one try per cuffing); kept so /cufftest reset still works
JL.Cuffed = Cuffed

local function now() return os.time() end

-- ---------------------------------------------------------------- escapes
local function escOf(cid)
    if not cid then return { n = 0, at = 0 } end
    local e = Esc[cid] or { n = 0, at = 0 }
    if e.n > 0 and (B.resetMinutes or 0) > 0 and now() - e.at > B.resetMinutes * 60 then e = { n = 0, at = 0 } end
    Esc[cid] = e
    return e
end
local function saveEsc(source, cid)
    local e = escOf(cid)
    WC:SetPlayerFlag(source, ESCFLAG, e.n > 0 and ('%d:%d'):format(e.n, e.at) or nil)
end
function JL.resetEscapes(source)
    local cid = WC:GetCharId(source)
    if cid then Esc[cid] = { n = 0, at = 0 } end
    WC:SetPlayerFlag(source, ESCFLAG, nil)
end

local function info(source, st)
    if not st then return false end
    local e = escOf(WC:GetCharId(source))
    local max = B.maxEscapes or 3
    local canBreak = B.enabled ~= false and e.n < max and (st.kind ~= 'ziptie' or B.zipties ~= false) and (st.mode ~= 'hard' or B.hardCuffs ~= false)
    if not st.pending then canBreak = false end   -- locked cuffs: no shaking out of them (lockpick only)
    local canPick = LP.enabled ~= false and LP.self ~= false and (st.kind ~= 'ziptie' or LP.zipties) and (st.mode == 'soft' or LP.selfHard)
    return { mode = st.mode, kind = st.kind, escapes = e.n, max = max, canBreak = canBreak, canPick = canPick, key = B.key }
end

-- ---------------------------------------------------------------- apply / clear
local function apply(source, st)
    Cuffed[source] = st or nil
    WC:SetSentinelPlayerKey(source, BAG, st and (st.mode .. ':' .. st.kind) or nil)
    WC:SetPlayerFlag(source, FLAG, st and ('%s:%s:%d'):format(st.mode, st.kind, st.by or 0) or nil)
    if st then WC:BlockHands(source, 'cuffed', { label = 'Your hands are cuffed' })
    else WC:UnblockHands(source, 'cuffed') end
    TriggerClientEvent('es_jail:cuffs', source, info(source, st))
    if JL.testChanged then JL.testChanged(source) end
end
JL.applyCuffs = apply
function JL.isCuffed(source) return Cuffed[source] end

--- Off with the cuffs without anyone doing it (jail, staff). The cuffs go back to whoever put them on, when they are online.
function JL.uncuffQuiet(source)
    local st = Cuffed[source]
    if not st then return end
    apply(source, nil)
    if st.kind == 'cuffs' and C.returnCuffs ~= false and st.by then
        local back = JL.onlineByChar()[st.by]
        if back then WC:AddItem(back, IT.cuffs, 1, nil, 'cuffs back (prisoner booked)') end
    end
end

local function inCar(source) local ped = GetPlayerPed(source) return ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) ~= 0 end
local function near(a, b, range)
    local pa, pb = JL.pedCoords(a), JL.pedCoords(b)
    return pa and pb and #(pa - pb) <= range
end

local function alertOfficers(source, text, except)
    local at = JL.pedCoords(source)
    if not at then return end
    for _, s in ipairs(JL.officersNear(at, B.alertRange or 40.0)) do
        if s ~= source and s ~= except then JL.notify(s, text, 'warning', 6000) end
    end
    -- 1.0.1: a self test shows the tester what officers nearby would be told
    local st = Cuffed[source]
    if st and st.test then JL.notify(source, '[TEST] Officers nearby see: ' .. text, 'warning', 6000) end
end
JL.alertOfficers = alertOfficers
function JL.clearCool(source) Cool[source] = nil Struggle[source] = nil end

-- ---------------------------------------------------------------- the cuffing window
local function levelFor(n)
    local L = B.levels or {}
    return L[n + 1] or L[#L]
end

--- Open the window on the person being cuffed. `pend` is what they will wear if they do not get out.
--- Returns the window, or nil when they can not break these (escapes used up, config).
local function openWindow(t, pend, ms, tag, by)
    local cid = WC:GetCharId(t)
    local inf = info(t, { mode = pend.mode, kind = pend.kind, pending = true })
    if not inf.canBreak then
        if B.enabled ~= false and inf.escapes >= inf.max then
            JL.notify(t, 'Your wrists are raw. You can not slip these.', 'error', 4000)
        end
        return nil
    end
    local lv = levelFor(inf.escapes)
    if not lv then return nil end
    local w = { token = ('%x%x'):format(math.random(0, 0x7fffffff), GetGameTimer()), level = lv, st = pend, tag = tag, by = by,
        ends = GetGameTimer() + ms, cid = cid }
    Struggle[t] = w
    TriggerClientEvent('es_jail:cuffWindow', t, w.token, { ms = ms, need = lv.need or 100, gain = lv.gain or 1, decay = lv.decay or 10,
        fastest = lv.fastest or 3, attempt = inf.escapes + 1, max = inf.max, key = B.key or 'X', kind = pend.kind })
    return w
end

--- Close it: give an answer already on its way a moment to land, then tell their game the window is shut.
local function closeWindow(t, w)
    if not w then return nil end
    if w.started and not w.result then
        local stop = GetGameTimer() + 900
        while not w.result and GetGameTimer() < stop do Wait(50) end
    end
    if Struggle[t] == w then Struggle[t] = nil end
    if GetPlayerName(t) then TriggerClientEvent('es_jail:cuffWindow', t, false) end
    return w
end
JL.openCuffWindow, JL.closeCuffWindow = openWindow, closeWindow

-- ---------------------------------------------------------------- events
local function register()
    WC:RegisterSentinelKey({ key = BAG, family = 'player' })

    -- cuff someone: mode soft (walks) / hard (can not move); kind cuffs / ziptie
    WC:SecureEvent('es_jail:cuff', { rateLimit = 1500, burst = 2,
        params = { { 'target', 'player', { range = (C.range or 2.0) + 1.5 } }, { 'mode', 'enum', { 'soft', 'hard' }, 'soft' }, { 'kind', 'enum', { 'cuffs', 'ziptie' }, 'cuffs' } } },
        function(source, player, target, mode, kind)
            local t = target.source
            local off = JL.officer(source)
            if not off and not (kind == 'ziptie' and C.zipAnyone) then
                local _, why = JL.officer(source)
                return false, why or 'Only officers can do that'
            end
            if Cuffed[source] then return false, 'Your own hands are cuffed' end
            if Cuffed[t] then return false, 'They are already restrained' end
            if Busy[t] then return false, 'Someone is already doing that' end
            if inCar(t) then return false, 'Get them out of the vehicle first' end
            local item = kind == 'ziptie' and IT.ziptie or IT.cuffs
            if not WC:HasItem(source, item) then return false, kind == 'ziptie' and 'You have no zip ties' or 'You have no handcuffs' end
            Busy[t] = true
            TriggerClientEvent('es_jail:anim', source, 'cop', t)
            TriggerClientEvent('es_jail:anim', t, 'crook', source)
            local ms = math.floor((C.seconds or 6) * 1000)
            local tag = ('es_jail:cuff:%d:%d'):format(t, GetGameTimer())
            local w = openWindow(t, { mode = mode, kind = kind, by = player.charId }, ms, tag, source)
            local done = WC:Progress(source, { label = kind == 'ziptie' and 'Zip-tying...' or 'Cuffing...', duration = ms, tag = tag })
            w = closeWindow(t, w)
            Busy[t] = nil
            if w and w.result == 'won' then
                JL.notify(source, ('%s slipped free before the %s locked!'):format(target.fullName or 'They', kind == 'ziptie' and 'zip ties' or 'cuffs'), 'error', 5000)
                return false
            end
            if not done then TriggerClientEvent('es_jail:anim', t, 'stop') return false end
            if Cuffed[t] or not near(source, t, (C.range or 2.0) + 2.0) then TriggerClientEvent('es_jail:anim', t, 'stop') return false, 'They got away' end
            local took = WC:RemoveItem(source, item, 1, nil, 'cuffed someone')
            if not took then TriggerClientEvent('es_jail:anim', t, 'stop') return false, 'You have no handcuffs' end
            apply(t, { mode = mode, kind = kind, by = player.charId })
            JL.notify(source, ('%s %s. Left Arrow to escort, Right Arrow to let go.'):format(kind == 'ziptie' and 'Zip-tied' or 'Cuffed', target.fullName or 'them'), 'success', 5000)
            JL.notify(t, mode == 'hard' and 'You have been cuffed. You can not move.' or 'You have been cuffed.', 'warning', 5000)
            JL.log(target.charId, 'cuffed', ('%s %s by %s'):format(mode, kind, player.fullName or ''), player.charId)
            JL.activity(source, 'cuff', ('%s %s #%d'):format(mode, kind, target.charId or 0))
        end)

    -- off with them: steel cuffs need a key (officers too unless Config.Cuffs.needKey is off); zip ties are cut
    WC:SecureEvent('es_jail:uncuff', { rateLimit = 1500, burst = 2, params = { { 'target', 'player', { range = (C.range or 2.0) + 1.5 } } } },
        function(source, player, target)
            local t = target.source
            local st = Cuffed[t]
            if not st then return false, 'They are not restrained' end
            if Cuffed[source] then return false, 'Your own hands are cuffed' end
            if Busy[t] then return false, 'Someone is already doing that' end
            local off = JL.officer(source)
            if st.kind == 'ziptie' then
                if not off and not C.zipAnyone then return false, 'You need something to cut them with' end
            else
                local hasKey = WC:HasItem(source, IT.key)
                if off then
                    if C.needKey ~= false and not hasKey then return false, 'You need a cuff key' end
                elseif not (hasKey and C.keyAnyone ~= false) then
                    return false, 'You need a cuff key'
                end
            end
            Busy[t] = true
            local done = WC:Progress(source, { label = st.kind == 'ziptie' and 'Cutting the zip ties...' or 'Unlocking the cuffs...', duration = 2500,
                anim = { dict = 'mp_arresting', clip = 'a_uncuff' } })
            Busy[t] = nil
            if not done then return false end
            if Cuffed[t] ~= st or not near(source, t, (C.range or 2.0) + 2.0) then return false, 'They are too far away' end
            apply(t, nil)
            if st.kind == 'cuffs' and C.returnCuffs ~= false and WC:IsSessionCurrent(source, player.session) then WC:AddItem(source, IT.cuffs, 1, nil, 'took cuffs off someone') end
            JL.notify(source, 'Restraints off', 'success', 3000)
            JL.notify(t, 'Your restraints were taken off', 'success', 4000)
            JL.log(target.charId, 'uncuffed', 'by ' .. (player.fullName or ''), player.charId)
        end)

    -- soft <-> hard
    WC:SecureEvent('es_jail:mode', { rateLimit = 1000, burst = 2,
        params = { { 'target', 'player', { range = (C.range or 2.0) + 1.5 } }, { 'mode', 'enum', { 'soft', 'hard' } } } },
        function(source, player, target, mode)
            local off, why = JL.officer(source)
            if not off then return false, why end
            local st = Cuffed[target.source]
            if not st then return false, 'They are not restrained' end
            if st.mode == mode then return end
            apply(target.source, { mode = mode, kind = st.kind, by = st.by })
            JL.notify(source, mode == 'hard' and 'Cuffs tightened: they can not move' or 'Cuffs loosened: they can walk', 'info', 3000)
        end)

    -- search: officers, on someone cuffed or downed
    WC:SecureEvent('es_jail:search', { rateLimit = 2000, burst = 1, params = { { 'target', 'player', { range = (C.searchRange or 2.5) + 1.0 } } } },
        function(source, player, target)
            local off, why = JL.officer(source)
            if not off then return false, why end
            if not Cuffed[target.source] and not WC:IsPlayerDead(target.source) then return false, 'Cuff them first' end
            local ok, err = WC:OpenPlayerInventory(source, target.source, { range = C.searchRange or 2.5 })
            if not ok then return false, err or 'Could not search them' end
            JL.notify(target.source, 'You are being searched', 'warning', 4000)
            JL.log(target.charId, 'searched', 'by ' .. (player.fullName or ''), player.charId)
        end)

    -- breaking out, only while the cuffs are going on: start (the window is open, the clock is the window's) ...
    WC:SecureEvent('es_jail:struggleStart', { rateLimit = 800, burst = 2 }, function(source, player)
        local w = Struggle[source]
        if not w then
            if Cuffed[source] then return false, 'They are locked on. Only a lockpick will help now.' end
            return false
        end
        if w.started or GetGameTimer() >= w.ends then return false end
        w.started = GetGameTimer()
        TriggerClientEvent('es_jail:struggle', source, w.token)
        alertOfficers(source, ('%s is struggling against the %s!'):format(player.fullName or 'Someone', w.st.kind == 'ziptie' and 'zip ties' or 'cuffs'))
    end)

    -- ... and the end: the server checks the time it took fits the level and the window
    WC:SecureEvent('es_jail:struggleEnd', { rateLimit = 300, burst = 2, params = { { 'token', 'key', 24 }, { 'won', 'bool', false } } },
        function(source, player, token, won)
            local w = Struggle[source]
            if not w or w.token ~= token or not w.started or w.result then return false end
            local now_ = GetGameTimer()
            local took = now_ - w.started
            local minMs = math.floor((w.level.fastest or 3) * 1000 * 0.9)
            if won and (took < minMs or now_ > w.ends + 1500) then
                if took < minMs then
                    WC:RecordEventRejection('es_jail:struggleEnd', source, ('broke out in %d ms (level needs %d)'):format(took, minMs))
                end
                won = false
            end
            local kindWord = w.st.kind == 'ziptie' and 'zip ties' or 'cuffs'
            if not won then
                w.result = 'lost'
                JL.notify(source, ('You could not slip the %s.'):format(kindWord), 'error', 4000)
                alertOfficers(source, ('%s tried to slip the %s and failed.'):format(player.fullName or 'Someone', kindWord))
                return
            end
            w.result = 'won'
            local e = escOf(player.charId)
            e.n, e.at = e.n + 1, now()
            Esc[player.charId] = e
            saveEsc(source, player.charId)
            if w.tag then WC:ReleaseTag(w.tag) end            -- the officer's bar ends: 'cancelled'
            TriggerClientEvent('es_jail:anim', source, 'stop')
            if w.by then TriggerClientEvent('es_jail:anim', w.by, 'stop') end
            local left = (B.maxEscapes or 3) - e.n
            JL.notify(source, left > 0 and ('You slipped free! (%d more and your wrists will give out)'):format(left) or 'You slipped free! That was the last time you will manage it.', 'success', 6000)
            alertOfficers(source, ('%s slipped out of the %s!'):format(player.fullName or 'Someone', kindWord))
            if not w.st.test then
                JL.log(player.charId, 'escaped_cuffs', ('escape %d of %d (while being cuffed)'):format(e.n, B.maxEscapes or 3))
                JL.activity(source, 'breakout', ('escape %d'):format(e.n))
            end
        end)

    -- lockpicking: yourself (soft cuffs, hands in front) or someone else
    WC:SecureEvent('es_jail:pick', { rateLimit = 2500, burst = 1, params = { { 'target', 'player', { range = 2.5, notSelf = false } } } },
        function(source, player, target)
            if LP.enabled == false then return false, 'Cuffs can not be picked here' end
            local t = target.source
            local st = Cuffed[t]
            if not st then return false, 'They are not cuffed' end
            if st.kind == 'ziptie' and not LP.zipties then return false, 'You can not pick zip ties' end
            local self = t == source
            if self then
                if LP.self == false then return false, 'You can not reach the lock' end
                if st.mode ~= 'soft' and not LP.selfHard then return false, 'Your hands are behind your back' end
            else
                if LP.others == false then return false, 'Cuffs can not be picked here' end
                if Cuffed[source] then return false, 'Your own hands are cuffed' end
            end
            if not WC:HasItem(source, IT.lockpick) then return false, 'You need a lockpick' end
            if Busy[t] then return false, 'Someone is already doing that' end
            Busy[t] = true
            if math.random(100) <= (LP.alertChance or 0) then alertOfficers(t, ('Someone is picking %s\'s cuffs!'):format(target.fullName or 'a prisoner'), source) end
            local passed, why = WC:SkillCheck(source, self and (LP.difficultySelf or 'hard') or (LP.difficultyOther or 'medium'))
            Busy[t] = nil
            if not passed then
                if why == 'failed' or why == 'timeout' then
                    if math.random(100) <= (LP.breakChance or 0) then
                        WC:RemoveItem(source, IT.lockpick, 1, nil, 'snapped picking cuffs')
                        return false, 'The lockpick snapped'
                    end
                    return false, 'The lock did not give'
                end
                return false
            end
            if Cuffed[t] ~= st then return false end
            apply(t, nil)
            if st.kind == 'cuffs' and not st.test then
                local at = JL.pedCoords(t)
                if at then WC:CreateGroundItem({ item = IT.cuffs, amount = 1, coords = at - vector3(0, 0, 0.95), reason = 'picked open' }) end
            end
            JL.notify(source, 'Click. The cuffs are open.', 'success', 4000)
            if not self then JL.notify(t, 'Your cuffs were picked open', 'success', 4000) end
            if not st.test then JL.log(target.charId, 'picked', self and 'picked their own cuffs' or ('picked by %s'):format(player.fullName or ''), player.charId) end
        end)

    -- what the player may do: asked by their game (prompts, the F1 wheel)
    WC:SecureCallback('es_jail:me', { rateLimit = 500, burst = 4, whileDead = true }, function(source)
        local off = JL.officer(source, Config.Perms.cuff)
        local man = JL.officer(source, Config.Perms.manage)
        return { officer = off and true or false, manage = (man and true) or JL.isStaff(source) }
    end)
end
JL.registerCuffs = register

-- ---------------------------------------------------------------- relog / restart
function JL.cuffsLoaded(source)
    local cid = WC:GetCharId(source)
    local esc = WC:GetPlayerFlag(source, ESCFLAG)
    if cid and type(esc) == 'string' then
        local n, at = esc:match('^(%d+):(%d+)$')
        if n then Esc[cid] = { n = tonumber(n), at = tonumber(at) } end
    end
    local f = WC:GetPlayerFlag(source, FLAG)
    if type(f) == 'string' then
        local mode, kind, by = f:match('^(%a+):(%a+):(%d+)$')
        if (mode == 'soft' or mode == 'hard') and (kind == 'cuffs' or kind == 'ziptie') then
            apply(source, { mode = mode, kind = kind, by = tonumber(by) ~= 0 and tonumber(by) or nil })
            JL.notify(source, 'You are still cuffed', 'warning', 5000)
            return
        end
    end
    TriggerClientEvent('es_jail:cuffs', source, false)
end

local function forget(source)
    Cuffed[source], Busy[source], Struggle[source], Cool[source] = nil, nil, nil, nil
end
AddEventHandler('whip_core:player:logout', function(e) if e and e.source then forget(e.source) end end)
AddEventHandler('playerDropped', function() forget(source) end)
