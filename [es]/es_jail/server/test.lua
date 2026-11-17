-- es_jail 1.0.3: staff test mode. With nobody to cuff, so staff can spawn a test suspect (an NPC) and run the
-- whole Restrain menu on it, cuff themselves to try the breakout and lockpicking, and draw the prison fence.
-- Test NPCs live in memory only: nothing about them is written to the database, and they are deleted on
-- /cufftest clear, when their owner leaves, and when the resource stops.

local WC = exports.whip_core
local T, B, C, IT, PR = Config.Test or {}, Config.Breakout, Config.Cuffs, Config.Items, Config.Prison

local Npcs = {}    -- [netId] = { ent, owner, st = { mode, kind } | nil, esc = { n, at }, flee, lockedTold, cuffing }
local Debug = {}   -- [source] = true while /jaildebug draws

function JL.isTestStaff(source)
    if not source or source == 0 then return source == 0 end
    return IsPlayerAceAllowed(source, Config.Jail.staffAce or 'es_jail.admin') or IsPlayerAceAllowed(source, 'command') or JL.isStaff(source)
end

local function npcsOf(source)
    local out = {}
    for net, n in pairs(Npcs) do if n.owner == source then out[#out + 1] = net end end
    return out
end

--- the TEST MODE tag: on while the player owns a test NPC or wears test cuffs
function JL.testChanged(source)
    if not source or not GetPlayerName(source) then return end
    local st = JL.isCuffed(source)
    TriggerClientEvent('es_jail:testTag', source, (#npcsOf(source) > 0) or (st and st.test) or false)
end

local function bagOf(n)
    local st = n.st
    if DoesEntityExist(n.ent) then Entity(n.ent).state:set('esCuffed', st and (st.mode .. ':' .. st.kind) or nil, true) end
end

local function tellOwner(n, what, extra)
    TriggerClientEvent('es_jail:npcDo', n.owner, NetworkGetNetworkIdFromEntity(n.ent), what, extra)
end

local function remove(net)
    local n = Npcs[net]
    if not n then return end
    Npcs[net] = nil
    if DoesEntityExist(n.ent) then DeleteEntity(n.ent) end
    JL.testChanged(n.owner)
end

local function clearOf(source)
    local list = npcsOf(source)
    for _, net in ipairs(list) do remove(net) end
    return #list
end

local function escOf(n)
    if n.esc.n > 0 and (B.resetMinutes or 0) > 0 and os.time() - n.esc.at > B.resetMinutes * 60 then n.esc = { n = 0, at = 0 } end
    return n.esc
end

-- ---------------------------------------------------------------- spawning
local function spawn(source, flee)
    if #npcsOf(source) >= (T.maxNpcs or 3) then return false, ('You already have %d test NPCs (/cufftest clear)'):format(T.maxNpcs or 3) end
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false, 'No ped' end
    local p, h = GetEntityCoords(ped), GetEntityHeading(ped)
    local r = math.rad(h)
    local x, y = p.x - math.sin(r) * 1.6, p.y + math.cos(r) * 1.6
    local ent = CreatePed(4, joaat(T.npcModel or 'a_m_y_downtown_01'), x, y, p.z - 0.95, (h + 180.0) % 360.0, true, true)
    local t = GetGameTimer() + 3000
    while not DoesEntityExist(ent) and GetGameTimer() < t do Wait(50) end
    if not DoesEntityExist(ent) then return false, 'The game would not make the NPC' end
    SetEntityRoutingBucket(ent, GetPlayerRoutingBucket(source))
    local net = NetworkGetNetworkIdFromEntity(ent)
    Npcs[net] = { ent = ent, owner = source, esc = { n = 0, at = 0 }, flee = flee and true or false }
    Entity(ent).state:set('esTest', source, true)
    tellOwner(Npcs[net], 'setup')
    JL.testChanged(source)
    return net
end

-- ---------------------------------------------------------------- test NPCs that are gone
CreateThread(function()
    while true do
        Wait(2000)
        for net, n in pairs(Npcs) do
            if not DoesEntityExist(n.ent) or not GetPlayerName(n.owner) then remove(net) end
        end
    end
end)

--- 1.0.3: a 'flee' NPC tries to slip free WHILE it is being cuffed (like a player would), not after.
--- Runs beside the officer's bar; a win ends the bar through its tag.
local function npcWindow(n, net, ms, tag, kind)
    if not n.flee then return end
    local e = escOf(n)
    local max = B.maxEscapes or 3
    if e.n >= max then
        if not n.lockedTold then
            n.lockedTold = true
            JL.notify(n.owner, ('[TEST] The suspect strains but can not slip these (%d escapes used: locked)'):format(e.n), 'info', 6000)
        end
        return
    end
    local kindWord = kind == 'ziptie' and 'zip ties' or 'cuffs'
    -- tries partway through the window; harder each escape (Config.Test.fleeChance)
    local at = math.random(math.floor(ms * 0.2), math.floor(ms * 0.45))
    SetTimeout(at, function()
        if Npcs[net] ~= n or n.st or not n.cuffing or n.cuffing.tag ~= tag then return end
        local text = ('[TEST] Test suspect is struggling against the %s! (escape %d of %d)'):format(kindWord, e.n + 1, max)
        local where = GetEntityCoords(n.ent)
        for _, s in ipairs(JL.officersNear(where, B.alertRange or 40.0)) do if s ~= n.owner then JL.notify(s, text, 'warning', 5000) end end
        JL.notify(n.owner, text, 'warning', 5000)
        tellOwner(n, 'struggle')
        local chance = (T.fleeChance or {})[e.n + 1] or 30
        local left = ms - at
        SetTimeout(math.max(600, math.floor(left * 0.6)), function()
            if Npcs[net] ~= n or n.st or not n.cuffing or n.cuffing.tag ~= tag then return end
            if math.random(100) <= chance then
                e.n, e.at = e.n + 1, os.time()
                n.cuffing.escaped = true
                WC:ReleaseTag(tag)          -- the officer's bar ends
                local msg = ('[TEST] Test suspect slipped free before the %s locked! (%d of %d used%s)'):format(kindWord, e.n, max, e.n >= max and ', the next cuffing holds' or '')
                for _, s in ipairs(JL.officersNear(GetEntityCoords(n.ent), B.alertRange or 40.0)) do if s ~= n.owner then JL.notify(s, msg, 'error', 7000) end end
                JL.notify(n.owner, msg, 'error', 7000)
                tellOwner(n, 'flee')
            else
                n.cuffing.failed = true
                local msg = '[TEST] The suspect tried to slip free and failed'
                for _, s in ipairs(JL.officersNear(GetEntityCoords(n.ent), B.alertRange or 40.0)) do if s ~= n.owner then JL.notify(s, msg, 'info', 4000) end end
                JL.notify(n.owner, msg, 'info', 4000)
            end
        end)
    end)
end

-- ---------------------------------------------------------------- actions on a test NPC (from the Restrain menu)
local function npcAction(source, player, net, action)
    if not JL.isTestStaff(source) then return false, 'Test mode is for staff' end
    local n = Npcs[net]
    if not n or not DoesEntityExist(n.ent) then return false, 'That is not a test NPC' end
    local me = JL.pedCoords(source)
    if not me or #(me - GetEntityCoords(n.ent)) > 4.0 and action ~= 'jail' then return false, 'Get closer' end
    if action == 'soft' or action == 'hard' or action == 'zip' then
        if n.st then return false, 'Already restrained' end
        local kind = action == 'zip' and 'ziptie' or 'cuffs'
        local item = kind == 'ziptie' and IT.ziptie or IT.cuffs
        if not WC:HasItem(source, item) then return false, kind == 'ziptie' and 'You have no zip ties' or 'You have no handcuffs' end
        if n.cuffing then return false, 'Already cuffing them' end
        TriggerClientEvent('es_jail:anim', source, 'cop', 0)
        tellOwner(n, 'crook', source)
        local ms = math.floor((C.seconds or 6) * 1000)
        local tag = ('es_jail:testcuff:%d:%d'):format(net, GetGameTimer())
        n.cuffing = { tag = tag }
        npcWindow(n, net, ms, tag, kind)
        local done = WC:Progress(source, { label = kind == 'ziptie' and 'Zip-tying...' or 'Cuffing...', duration = ms, tag = tag })
        local c = n.cuffing
        n.cuffing = nil
        if c and c.escaped then return false end            -- it ran: the flee is already under way
        if not done or Npcs[net] ~= n then tellOwner(n, 'idle') return false end
        if not WC:RemoveItem(source, item, 1, nil, 'cuffed a test NPC') then tellOwner(n, 'idle') return false, 'You have no handcuffs' end
        n.st = { mode = action == 'hard' and 'hard' or 'soft', kind = kind }
        n.lockedTold = false
        bagOf(n)
        tellOwner(n, 'cuffed', n.st.mode)
        local e = escOf(n)
        JL.notify(source, ('[TEST] Test suspect %s.%s'):format(kind == 'ziptie' and 'zip-tied' or 'cuffed',
            n.flee and (e.n >= (B.maxEscapes or 3) and ' They have used every escape: these hold.' or (' Locked on: no more breaking out (%d of %d escapes used).'):format(e.n, B.maxEscapes or 3)) or ''), 'success', 5000)
    elseif action == 'uncuff' then
        if not n.st then return false, 'They are not restrained' end
        if n.st.kind == 'cuffs' and C.needKey ~= false and not WC:HasItem(source, IT.key) then return false, 'You need a cuff key' end
        local done = WC:Progress(source, { label = n.st.kind == 'ziptie' and 'Cutting the zip ties...' or 'Unlocking the cuffs...', duration = 2500,
            anim = { dict = 'mp_arresting', clip = 'a_uncuff' } })
        if not done or Npcs[net] ~= n or not n.st then return false end
        local kind = n.st.kind
        n.st = nil
        bagOf(n)
        tellOwner(n, 'idle')
        if kind == 'cuffs' and C.returnCuffs ~= false and WC:IsSessionCurrent(source, player.session) then WC:AddItem(source, IT.cuffs, 1, nil, 'took cuffs off a test NPC') end
        JL.notify(source, '[TEST] Restraints off', 'success', 3000)
    elseif action == 'tohard' or action == 'tosoft' then
        if not n.st then return false, 'They are not restrained' end
        n.st.mode = action == 'tohard' and 'hard' or 'soft'
        bagOf(n)
        tellOwner(n, 'cuffed', n.st.mode)
    elseif action == 'search' then
        if not n.st then return false, 'Cuff them first' end
        local items = {}
        for i, it in ipairs(T.searchItems or {}) do items[i] = { item = it.item, amount = it.amount or 1 } end
        local ok, why = WC:OpenPanel(source, { id = 'es_jail:testsearch:' .. source, label = 'Test suspect (look only)', slots = 10, items = items, readOnly = true,
            onClose = function() end })   -- test stock: nothing is handed out or logged as lost
        if not ok then return false, why or 'Could not search' end
    elseif action == 'jail' then
        if not n.st then return false, 'Cuff them first' end
        n.st = nil
        bagOf(n)
        local a = PR.arrive[math.random(#PR.arrive)]
        tellOwner(n, 'jail', { x = a.x, y = a.y, z = a.z, w = a.w })
        JL.notify(source, ('[TEST] Test suspect booked into %s (test only: nothing saved). Fly there to see them, or /cufftest clear.'):format(PR.name), 'success', 7000)
    elseif action == 'reset' then
        n.esc = { n = 0, at = 0 }
        JL.notify(source, '[TEST] Test suspect escape count reset', 'info', 3000)
    end
end

-- ---------------------------------------------------------------- commands and events
local Selfing = {}    -- [source] = true while /cufftest self runs its cuffing window
local USE = 'Use: /cufftest npc [flee] | jailnpc | self [soft|hard|zip] | reset | free | clear'
local function register()
    if T.enabled == false then return end
    WC:SecureEvent('es_jail:testNpc', { rateLimit = 800, burst = 3,
        params = { { 'net', 'id' }, { 'action', 'enum', { 'soft', 'hard', 'zip', 'uncuff', 'tohard', 'tosoft', 'search', 'jail', 'reset' } } } },
        function(source, player, net, action) return npcAction(source, player, net, action) end)

    Whip.command('cufftest', { rateLimit = { burst = 4, everyMs = 1000 }, console = false }, function(source, args)
        if not JL.isTestStaff(source) then return JL.notify(source, 'Cuff test mode is for staff', 'error', 4000) end
        local sub = (args[1] or ''):lower()
        if sub == 'npc' then
            local net, why = spawn(source, (args[2] or ''):lower() == 'flee')
            if not net then return JL.notify(source, why, 'error', 5000) end
            JL.notify(source, ('[TEST] Test suspect spawned%s. Aim at them for the Restrain menu.'):format((args[2] or ''):lower() == 'flee' and ' (will try to slip free while you cuff them)' or ''), 'success', 6000)
        elseif sub == 'jailnpc' then
            local best, bd
            local me = JL.pedCoords(source)
            for net, n in pairs(Npcs) do
                if n.owner == source and DoesEntityExist(n.ent) and n.st then
                    local d = me and #(me - GetEntityCoords(n.ent)) or 0
                    if not bd or d < bd then best, bd = net, d end
                end
            end
            if not best then return JL.notify(source, '[TEST] Cuff a test NPC first', 'error', 4000) end
            local ok, why = npcAction(source, { session = nil }, best, 'jail')
            if ok == false and why then JL.notify(source, why, 'error', 4000) end
        elseif sub == 'self' then
            local m = (args[2] or 'soft'):lower()
            if m ~= 'soft' and m ~= 'hard' and m ~= 'zip' then return JL.notify(source, USE, 'error', 6000) end
            if JL.isCuffed(source) then return JL.notify(source, 'You are already cuffed (/cufftest free)', 'error', 4000) end
            if Selfing[source] then return JL.notify(source, '[TEST] Already being cuffed', 'error', 3000) end
            Selfing[source] = true
            local pend = { mode = m == 'hard' and 'hard' or 'soft', kind = m == 'zip' and 'ziptie' or 'cuffs', by = 0, test = true }
            local ms = math.floor((C.seconds or 6) * 1000)
            JL.notify(source, ('[TEST] An officer is cuffing you (%.0fs). Press %s and shake the mouse to slip free before the %s lock.'):format(
                ms / 1000, B.key or 'X', m == 'zip' and 'zip ties' or 'cuffs'), 'info', 7000)
            CreateThread(function()
                local w = JL.openCuffWindow(source, pend, ms, nil, nil)
                local stop = GetGameTimer() + ms
                while GetGameTimer() < stop and not (w and w.result == 'won') and GetPlayerName(source) do Wait(100) end
                w = JL.closeCuffWindow(source, w)
                Selfing[source] = nil
                if not GetPlayerName(source) then return end
                if w and w.result == 'won' then return end   -- they got out; the struggle already told them
                if JL.isCuffed(source) then return end
                JL.applyCuffs(source, pend)
                JL.notify(source, ('[TEST] The %s locked. Shaking will not help now: F1 for the lockpick (soft cuffs), /cufftest free to get out.'):format(
                    m == 'zip' and 'zip ties' or 'cuffs'), 'info', 8000)
            end)
        elseif sub == 'free' then
            if not JL.isCuffed(source) then return JL.notify(source, 'You are not cuffed', 'error', 3000) end
            JL.applyCuffs(source, nil)
            JL.notify(source, '[TEST] Uncuffed', 'success', 3000)
        elseif sub == 'reset' then
            JL.resetEscapes(source)
            JL.clearCool(source)
            for _, n in pairs(Npcs) do if n.owner == source then n.esc = { n = 0, at = 0 } n.lockedTold = false end end
            local st = JL.isCuffed(source)
            if st then JL.applyCuffs(source, st) end   -- re-send the pill with the fresh count
            JL.notify(source, '[TEST] Escape count and cooldown reset (you and your test NPCs)', 'success', 4000)
        elseif sub == 'clear' then
            local n = clearOf(source)
            JL.notify(source, ('[TEST] %d test NPC%s removed'):format(n, n == 1 and '' or 's'), 'info', 3000)
        else
            JL.notify(source, USE, 'info', 8000)
        end
    end)

    Whip.command('jaildebug', { rateLimit = { burst = 3, everyMs = 1000 }, console = false }, function(source)
        if not JL.isTestStaff(source) then return JL.notify(source, '/jaildebug is for staff', 'error', 4000) end
        Debug[source] = not Debug[source] or nil
        TriggerClientEvent('es_jail:debug', source, Debug[source] and true or false)
        JL.notify(source, Debug[source] and 'Jail debug on: fence (red), spawns (green), board (blue), jobs (yellow), release (white)' or 'Jail debug off', 'info', 6000)
    end)
end
JL.registerTest = register

AddEventHandler('playerDropped', function() local s = source clearOf(s) Debug[s] = nil Selfing[s] = nil end)
AddEventHandler('whip_core:player:logout', function(e) if e and e.source then clearOf(e.source) end end)
AddEventHandler('onResourceStop', function(r)
    if r ~= GetCurrentResourceName() then return end
    for net in pairs(Npcs) do local n = Npcs[net] if n and DoesEntityExist(n.ent) then DeleteEntity(n.ent) end end
end)
