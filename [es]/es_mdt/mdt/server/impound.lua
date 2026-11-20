local _ENV = ESAPP('mdt'); -- es_mdt 2.1.0: impound, holds, the lot, and towing nobody's cars.
--
-- WHIP's own garages carry it (whip_autos, whip_autos_shop and whip_dealership have no impound; whip_core's garages and
-- SetVehicleCustody are the documented way): each lot of Config.Impound.lots is a whip_core garage (made at start when
-- missing). Impounding a vehicle:
--   stored in a garage   -> moved to the lot (SetVehicleGarage) and held (SetVehicleCustody): it cannot be taken out
--   out, not in the world -> stored straight into the lot (DespawnVehicle { garage = lot })
--   out in the world:
--     on the street (/mdtimpound, the officer by it): taken away now (DespawnVehicle { garage = lot, refuseOccupied })
--     from the MDT (it is somewhere else): MARKED (status 'pending', held at once so it can never be taken out again);
--     the next time it is stored (whip_core:vehicle:despawned), or at the next start, it goes to the lot
-- The fee: Config.Impound.fee (the officer may change it) + dailyFee per full day on the lot, never more than storageCap.
-- Release: the owner pays in the court portal once any hold is over (the car stays at the lot, or goes home:
-- Config.Impound.releaseTo), or an officer with impound_lot releases it (the fees become an invoice, or are waived with a
-- reason). Before a hold ends only impound_override may release it, with a reason, logged as an override. Released rows
-- stay: the vehicle's impound history. Impounding closes the plate's active BOLOs (Config.Impound.resolveBolos).
-- Loaded BEFORE server/main.lua; runs from MDT.registerImpound().
local WC = exports.whip_core
MDT = MDT or {}

local function IC() return type(Config.Impound) == 'table' and Config.Impound or {} end
local function UO() return type(IC().unowned) == 'table' and IC().unowned or {} end
local function money(n) return ('$%s'):format(tostring(math.floor(tonumber(n) or 0)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')) end
local function portalCmd() return ((ESPART('doj') or {}).Config or {}).PortalCommand or 'court' end

local function nameOf(cid)
    if not cid then return nil end
    local n = MDT.namesOf({ cid })
    return n[cid] or ('#' .. cid)
end
local function posOf(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

-- ---------------------------------------------------------------- lots
local function lots()
    local out = {}
    for _, l in ipairs(type(IC().lots) == 'table' and IC().lots or {}) do
        if type(l) == 'table' and type(l.key) == 'string' and l.key ~= '' then out[#out + 1] = l end
    end
    return out
end
local function lotOf(key)
    for _, l in ipairs(lots()) do if l.key == key then return l end end
    return lots()[1]
end
local function lotLabel(key) local l = lotOf(key) return l and (l.label or l.key) or key end

local function ensureLots()
    for _, l in ipairs(lots()) do
        if not WC:GetGarage(l.key) then
            -- a vector3 from /whip > Settings (type 'vector3' in the game), or a plain { x, y, z } table from an older config
            local c, tc = l.coords, type(l.coords)
            local x, y, z
            if tc == 'vector3' or tc == 'vector4' then x, y, z = c.x, c.y, c.z
            elseif tc == 'table' then x, y, z = c.x or c[1], c.y or c[2], c.z or c[3] end
            local g, err = WC:CreateGarage({ key = l.key, name = l.label or 'Impound Lot', x = tonumber(x), y = tonumber(y), z = tonumber(z),
                heading = tonumber(l.heading) or 0.0, blipSprite = 68, blipColor = 47 })
            if g then print(('^2[es_mdt] impound lot "%s" made (a whip_core garage: add parking bays in /whip > Garages)^7'):format(l.key))
            else print(('^3[es_mdt] impound lot "%s" could not be made: %s^7'):format(l.key, tostring(err))) end
        end
    end
end

-- ---------------------------------------------------------------- money
--- what is owed now: { fee, days, storage, total }
local function owed(r)
    local days = 0
    if r.storedTs and r.status == 'held' then days = math.max(0, math.floor((os.time() - r.storedTs) / 86400)) end
    local storage = math.min(days * (r.dailyFee or 0), r.storageCap or 0)
    return { fee = r.fee or 0, days = days, storage = storage, total = (r.fee or 0) + storage }
end

--- is a hold keeping it: true, until (nil = until an officer releases)
local function holdOn(r)
    if r.holdOpen == 1 or r.holdOpen == true then return true, nil end
    if r.holdTs and r.holdTs > os.time() then return true, r.holdTs end
    return false
end

local COLS = [[i.*, UNIX_TIMESTAMP(i.`createdAt`) AS `at`, UNIX_TIMESTAMP(i.`storedAt`) AS `storedTs`, UNIX_TIMESTAMP(i.`holdUntil`) AS `holdTs`,
    UNIX_TIMESTAMP(i.`releasedAt`) AS `releasedTs`, d.`short` AS `dept`]]

local function decorate(r, names)
    r.owe = owed(r)
    local on, untilTs = holdOn(r)
    r.held = on
    r.holdUntilTs = untilTs
    r.owner = r.ownerCharId and ((names and names[r.ownerCharId]) or nameOf(r.ownerCharId)) or nil
    r.lotLabel = lotLabel(r.lot)
    r.createdAt, r.storedAt, r.holdUntil, r.releasedAt = nil, nil, nil, nil
    return r
end

local function impRow(iid)
    local r = MySQL.single.await('SELECT ' .. COLS .. ' FROM `es_mdt_impounds` i LEFT JOIN `es_departments` d ON d.`id` = i.`deptId` WHERE i.`id` = ?', { iid })
    return r and decorate(r) or nil
end
MDT.impRow = impRow

local function activeOf(vid)
    local r = MySQL.single.await('SELECT ' .. COLS .. " FROM `es_mdt_impounds` i LEFT JOIN `es_departments` d ON d.`id` = i.`deptId` WHERE i.`vehicleId` = ? AND i.`status` IN ('pending','held') ORDER BY i.`id` DESC LIMIT 1", { vid })
    return r and decorate(r) or nil
end

-- ---------------------------------------------------------------- moving the car
--- take it to the lot now if it can be: 'held' | 'pending', why
local function haul(vid, lot, street)
    local v = WC:GetVehicle(vid)
    if not v then return false, 'No such vehicle' end
    if v.state == 'garaged' then
        if v.garage ~= lot then
            local ok, why = WC:SetVehicleGarage(vid, lot)
            if not ok then return false, why end
        end
        return 'held'
    end
    if not v.spawned or street then
        local ok, why = WC:DespawnVehicle(vid, { garage = lot, refuseOccupied = true })
        if ok then return 'held' end
        if street then return false, why end
    end
    return 'pending'
end

local function closeBolos(plate, c)
    if IC().resolveBolos == false or not plate or plate == '' then return 0 end
    local n = MySQL.update.await("UPDATE `es_mdt_bolos` SET `status` = 'closed', `closedBy` = ? WHERE `plate` = ? AND `status` = 'active'", { c and c.charId, plate }) or 0
    if (tonumber(n) or 0) > 0 then
        if MDT.clearPlateCache then MDT.clearPlateCache() end
        MDT.refresh('bolos')
    end
    return tonumber(n) or 0
end

local function textOwner(r, body, title)
    if r.ownerCharId then MDT.text(r.ownerCharId, body, { kind = 'impound', title = title }) end
end

local function holdText(r)
    if r.holdOpen == 1 or r.holdOpen == true then return 'It is on a police hold until an officer releases it.' end
    if r.holdTs and r.holdTs > os.time() then return ('It is on a police hold until %s.'):format(os.date('%d %b %H:%M', r.holdTs)) end
    return ('Pay %s%s at /%s (Impound) to get it back.'):format(money(r.fee), (r.dailyFee or 0) > 0 and (' + %s a day storage (at most %s)'):format(money(r.dailyFee), money(r.storageCap)) or '', portalCmd())
end

--- the car reached the lot (now, or later for a pending one)
local function arrived(r)
    MySQL.update.await("UPDATE `es_mdt_impounds` SET `status` = 'held', `storedAt` = NOW() WHERE `id` = ? AND `status` IN ('pending','held')", { r.id })
    local x = impRow(r.id)
    textOwner(x, ('Your %s (%s) was impounded by %s: %s. It is at %s. %s'):format(x.vehicleLabel or 'vehicle', x.plate or '?', x.dept or 'the police', x.reason,
        x.lotLabel, holdText(x)), 'Vehicle impounded: ' .. (x.plate or ''))
    MDT.refresh('impound')
    -- hook for other scripts (garages, logs): server event, never sent to players
    TriggerEvent('es_mdt:impound:stored', { impoundId = x.id, vehicleId = x.vehicleId, plate = x.plate, lot = x.lot, ownerCharId = x.ownerCharId })
end

-- a marked car was stored by its driver: off to the lot
AddEventHandler('whip_core:vehicle:despawned', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' or not e.vehicleId then return end
    local vid = tonumber(e.vehicleId)
    CreateThread(function()
        local r = MySQL.single.await("SELECT `id`,`lot` FROM `es_mdt_impounds` WHERE `vehicleId` = ? AND `status` = 'pending' LIMIT 1", { vid })
        if not r then return end
        Wait(500)
        local st = haul(vid, r.lot, false)
        if st == 'held' then arrived(impRow(r.id)) end
    end)
end)

local function sweepPending()
    local rows = MySQL.query.await("SELECT `id`,`vehicleId`,`lot`,`status` FROM `es_mdt_impounds` WHERE `status` IN ('pending','held')") or {}
    for _, r in ipairs(rows) do
        local v = WC:GetVehicle(r.vehicleId)
        if v then
            local ok, why = WC:SetVehicleCustody(r.vehicleId, true)   -- the hold is there (again): a restart, a lost reservation
            if not ok and why ~= 'Vehicle is held by another resource' then print(('^3[es_mdt] impound #%d: hold not set: %s^7'):format(r.id, tostring(why))) end
            if r.status == 'pending' then
                local st = haul(r.vehicleId, r.lot, false)
                if st == 'held' then arrived(impRow(r.id)) end
            elseif v.state == 'garaged' and v.garage ~= r.lot then
                WC:SetVehicleGarage(r.vehicleId, r.lot)
            end
        end
    end
end

-- ---------------------------------------------------------------- the form's facts
local function priorCount(vid)
    return tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM `es_mdt_impounds` WHERE `vehicleId` = ? AND `status` IN ('held','released')", { vid })) or 0
end

local function vehicleFacts(v)
    local vid = v.vehicleId
    local notes = MySQL.single.await('SELECT `flags` FROM `es_mdt_vehicle_notes` WHERE `vehicleId` = ?', { vid })
    local flags = notes and MDT.flagsOf(notes.flags) or {}
    local stolen = false
    for _, f in ipairs(flags) do if tostring(f):lower() == 'stolen' then stolen = true end end
    local bolos = v.plate and MySQL.query.await("SELECT `id`,`title` FROM `es_mdt_bolos` WHERE `plate` = ? AND `status` = 'active' AND (`expiresAt` IS NULL OR `expiresAt` > NOW())", { v.plate }) or {}
    local ownerId = v.owner and (v.owner.charId or 0) > 0 and v.owner.charId or nil
    return {
        vehicleId = vid, plate = v.plate, label = v.displayName or v.model, model = v.model, state = v.state, garage = v.garage, spawned = v.spawned == true,
        ownerCharId = ownerId, owner = ownerId and nameOf(ownerId) or nil, ownerOnline = v.owner and v.owner.online == true or false,
        stolen = stolen, flags = flags, bolos = bolos, prior = priorCount(vid), active = activeOf(vid),
    }
end

local function formSettings(c)
    local L = {}
    for _, l in ipairs(lots()) do L[#L + 1] = { key = l.key, label = l.label or l.key } end
    return { lots = L, reasons = IC().reasons or {}, fee = tonumber(IC().fee) or 0, maxFee = tonumber(IC().maxFee) or 5000,
        dailyFee = tonumber(IC().dailyFee) or 0, storageCap = tonumber(IC().storageCap) or 0, maxHoldDays = tonumber(IC().maxHoldDays) or 30,
        canHold = c.perms.impound_hold == true, canOverride = c.perms.impound_override == true, canLot = c.perms.impound_lot == true,
        releaseTo = IC().releaseTo or 'lot', photoHosts = IC().photoHosts or {},
        unowned = UO().enabled ~= false and { payout = tonumber(UO().payout) or 0 } or false }
end

local function photoOk(url)
    url = tostring(url or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if url == '' then return true, nil end
    if #url > 500 or not url:match('^https://[%w%-%.]+%.[%a]+/') then return false end
    local hosts = IC().photoHosts
    if type(hosts) == 'table' and #hosts > 0 then
        local h = url:match('^https://([^/]+)/'):lower()
        local ok = false
        for _, x in ipairs(hosts) do x = tostring(x):lower() if h == x or h:sub(-#x - 1) == '.' .. x then ok = true end end
        if not ok then return false end
    end
    return true, url
end

-- ---------------------------------------------------------------- towing nobody's cars
local LastDriver = {}   -- [vehicleId] = charId of the player who last drove it
AddEventHandler('whip_core:vehicle:entered', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' or not e.vehicleId or e.seat ~= -1 then return end
    local cid = e.source and WC:GetCharId(e.source)
    if cid then LastDriver[tonumber(e.vehicleId)] = { charId = cid, source = e.source } end
end)
AddEventHandler('whip_core:vehicle:released', function(e) if type(e) == 'table' and e.vehicleId then LastDriver[tonumber(e.vehicleId)] = nil end end)

local ShiftStart = {}   -- [charId] = os.time() they clocked on
AddEventHandler('whip_core:job:clockedOn', function(e) if type(e) == 'table' and e.charId then ShiftStart[e.charId] = os.time() end end)

local function towed(c, ent, v)
    local U = UO()
    if U.enabled == false then return false, 'Towing unowned cars is turned off' end
    if v.temp then return false, 'That is a rental or a job vehicle: it is not abandoned' end
    if not v.session or (v.owner and (v.owner.charId or 0) > 0) then return false, 'A player owns that vehicle: impound it instead' end
    for _ in pairs(type(v.occupants) == 'table' and v.occupants or {}) do return false, 'Someone is in it' end
    if GetPedInVehicleSeat(ent, -1) ~= 0 then return false, 'Someone is driving it' end
    local ld = LastDriver[v.vehicleId]
    if ld then
        local src = MDT.onlineByChar()[ld.charId]
        local p = src and posOf(src)
        if p and #(p - GetEntityCoords(ent)) <= (tonumber(U.ownerRange) or 60.0) and ld.charId ~= c.charId then
            return false, 'Whoever drove it last is close by: it is not abandoned'
        end
    end
    local cd = math.max(0, tonumber(U.cooldownSec) or 120)
    local last = tonumber(MySQL.scalar.await('SELECT TIMESTAMPDIFF(SECOND, MAX(`createdAt`), NOW()) FROM `es_mdt_tows` WHERE `officerCharId` = ?', { c.charId }))
    if last and last < cd then return false, ('Next tow in %d s'):format(cd - last) end
    local since = ShiftStart[c.charId] or (os.time() - 8 * 3600)
    local n = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM `es_mdt_tows` WHERE `officerCharId` = ? AND `createdAt` >= FROM_UNIXTIME(?)', { c.charId, since })) or 0
    local cap = math.max(0, math.floor(tonumber(U.perShift) or 10))
    if n >= cap then return false, ('That is %d tows this shift (the most paid)'):format(cap) end
    local at = GetEntityCoords(ent)
    local okd, why = WC:DeleteVehicle(v.vehicleId)
    if not okd then return false, why or 'The tow failed' end
    if DoesEntityExist(ent) then DeleteEntity(ent) end
    local pay = math.max(0, math.floor(tonumber(U.payout) or 0))
    MySQL.insert.await('INSERT INTO `es_mdt_tows` (`officerCharId`,`deptId`,`plate`,`model`,`x`,`y`,`payout`) VALUES (?,?,?,?,?,?,?)',
        { c.charId, c.dept.id, v.plate, v.displayName or v.model, at.x, at.y, pay })
    if pay > 0 and WC:GetCharId(c.source) == c.charId then
        local why = 'Tow: abandoned vehicle ' .. tostring(v.plate or '')
        if U.payFrom == 'state' then
            WC:PayPlayer(c.source, pay, { method = 'bank', reason = why })
        else
            -- 2.2.0: from the officer's own department account (as their pay is); a short account pays nothing and says so
            local jaccts = c.dept and c.dept.jobId and WC:GetJobBankAccounts(c.dept.jobId) or {}
            local mine = WC:GetDefaultBankAccount({ charId = c.charId })
            local okp = jaccts[1] and mine and (tonumber(jaccts[1].balance) or 0) >= pay
                and WC:BankSystemTransfer(jaccts[1].accountId, mine.accountId, pay, { reason = why })
            if okp then MDT.deptIncome(c.dept.jobId, -pay, 'tow', why, c.charId)
            else
                WC:NotifyPlayer(c.source, ('%s could not pay the $%d tow: its account is short'):format(c.dept.short or 'Your department', pay), 'warning', 8000)
                pay = 0
            end
        end
    end
    MDT.log(c, 'tow', ('%s %s $%d'):format(tostring(v.plate), tostring(v.model), pay))
    return { towed = true, payout = pay, left = cap - n - 1 }
end

-- ---------------------------------------------------------------- impound / release
local function doImpound(c, v, d, street)
    local lot = lotOf(d.lot)
    if not lot then return false, 'No impound lot is set up (/whip > Settings > MDT > Impound)' end
    if activeOf(v.vehicleId) then return false, 'That vehicle is already impounded' end
    local reason = MDT.str(d.reason, 80)
    if reason == '' then return false, 'Pick a reason' end
    local pok, photo = photoOk(d.photo)
    if not pok then return false, 'The photo must be an https link to a picture' .. ((#(IC().photoHosts or {}) > 0) and ' on an allowed site' or '') end
    local fee = MDT.int(d.fee == nil and IC().fee or d.fee, 0, tonumber(IC().maxFee) or 5000)
    local holdDays, holdOpen = 0, false
    if d.hold == 'open' or d.hold == 'days' then
        if not c.perms.impound_hold then return false, 'Your rank cannot put a hold on a vehicle' end
        if d.hold == 'open' then holdOpen = true else holdDays = MDT.int(d.holdDays, 1, tonumber(IC().maxHoldDays) or 30) end
    end
    local veh = WC:GetVehicle(v.vehicleId)
    local ok, why = WC:SetVehicleCustody(v.vehicleId, true, v.ownerCharId)
    if not ok then return false, why or 'The vehicle could not be held' end
    local st, hwhy = haul(v.vehicleId, lot.key, street)
    if not st then WC:SetVehicleCustody(v.vehicleId, false) return false, hwhy or 'It could not be taken to the lot' end
    local iid = MySQL.insert.await([[INSERT INTO `es_mdt_impounds` (`vehicleId`,`plate`,`vehicleLabel`,`ownerCharId`,`deptId`,`officerCharId`,`officerName`,`reason`,`notes`,`photo`,`lot`,
        `homeGarage`,`fee`,`dailyFee`,`storageCap`,`holdUntil`,`holdOpen`,`status`,`via`) VALUES (?,?,?,?,?,?,?,?,NULLIF(?, ''),?,?,?,?,?,?,IF(? > 0, NOW() + INTERVAL ? DAY, NULL),?,?,?)]],
        { v.vehicleId, v.plate, v.label, v.ownerCharId, c.dept.id, c.charId, c.name, reason, MDT.str(d.notes, 500), photo, lot.key,
          veh and veh.garage ~= lot.key and veh.garage or nil,
          fee, math.floor(tonumber(IC().dailyFee) or 0), math.floor(tonumber(IC().storageCap) or 0), holdDays, holdDays, holdOpen and 1 or 0, 'pending', street and 'street' or 'mdt' })
    if not iid then WC:SetVehicleCustody(v.vehicleId, false) return false, 'Could not save the impound' end
    local bolos = closeBolos(v.plate, c)
    MDT.log(c, 'impound', ('#%d %s %s%s%s'):format(iid, tostring(v.plate), reason, holdOpen and ' hold:open' or holdDays > 0 and (' hold:' .. holdDays .. 'd') or '', st == 'pending' and ' (marked)' or ''))
    local r = impRow(iid)
    if st == 'held' then arrived(r)
    else
        textOwner(r, ('Your %s (%s) is marked for impound by %s: %s. The next time it is stored it goes to %s; it cannot be taken out again until it is released.')
            :format(r.vehicleLabel or 'vehicle', r.plate or '?', r.dept or 'the police', r.reason, r.lotLabel), 'Vehicle marked for impound: ' .. (r.plate or ''))
    end
    MDT.refresh('impound')
    TriggerEvent('es_mdt:impound:created', { impoundId = iid, vehicleId = v.vehicleId, plate = v.plate, status = st, lot = lot.key, ownerCharId = v.owner and v.owner.charId or nil,
        reason = reason, officerCharId = c.charId, deptId = c.dept.id, street = street == true })
    return { id = iid, status = st, bolosClosed = bolos }
end

--- release (the owner paying, lot staff, an override). how = { by = name, charId, note, override, waive, invoiceTo = c, paid = amount }
local function release(r, how)
    local ok, why = WC:SetVehicleCustody(r.vehicleId, false)
    if not ok and why ~= 'Owned vehicle not found' then return false, why end
    if r.status == 'held' and (IC().releaseTo == 'home') and r.homeGarage and r.homeGarage ~= r.lot then
        local okg = WC:SetVehicleGarage(r.vehicleId, r.homeGarage)
        if not okg then print(('^3[es_mdt] impound #%d: released, but it could not go back to %s; it waits at the lot^7'):format(r.id, r.homeGarage)) end
    end
    local st = r.status == 'pending' and 'cancelled' or 'released'
    local n = MySQL.update.await([[UPDATE `es_mdt_impounds` SET `status` = ?, `releasedAt` = NOW(), `releasedBy` = ?, `releaseNote` = NULLIF(?, ''), `override` = ?, `paid` = ?, `paidBy` = ?
        WHERE `id` = ? AND `status` IN ('pending','held')]], { st, how.by, tostring(how.note or ''):sub(1, 300), how.override and 1 or 0, how.paid, how.paidBy, r.id })
    if (tonumber(n) or 0) < 1 then return false, 'It was released just now' end   -- two releases / payments at once: only one counts
    MDT.refresh('impound')
    TriggerEvent('es_mdt:impound:released', { impoundId = r.id, vehicleId = r.vehicleId, plate = r.plate, status = st, by = how.by, override = how.override == true, paid = how.paid or 0 })
    return st
end

--- the owner pays in the court portal: p = { source, charId }. method 'bank' | 'cash'
function MDT.impoundPay(p, iid, method)
    local r = impRow(tonumber(iid) or 0)
    if not r or r.ownerCharId ~= p.charId then return false, 'Not your vehicle' end
    if r.status ~= 'held' then return false, r.status == 'pending' and 'It has not reached the lot yet' or 'It is not impounded' end
    local on, untilTs = holdOn(r)
    if on then return false, untilTs and ('It is on a police hold until %s'):format(os.date('%d %b %H:%M', untilTs)) or 'It is on a police hold until an officer releases it' end
    local amount = r.owe.total
    local receipt
    if amount > 0 then
        local w
        receipt, w = WC:ChargePlayer(p.source, amount, { method = method == 'cash' and 'cash' or 'bank', reason = ('Impound fees: %s'):format(r.plate or ('#' .. r.id)) })
        if not receipt then return false, w or 'The payment failed' end
    end
    local st, why = release(r, { by = 'Owner (paid)', paidBy = p.charId, paid = amount })
    if not st then if receipt then WC:RefundPlayer(receipt) end return false, why end
    if amount > 0 then
        -- the paid record lands in one transaction with the charge (whip_core CommitWithAction)
        local okc = WC:CommitWithAction({ { query = [[INSERT INTO `es_mdt_fines` (`deptId`,`charId`,`amount`,`reason`,`status`,`issuedBy`,`paidAt`,`kind`,`impoundId`)
            VALUES (?,?,?,?, 'paid', ?, NOW(), 'impound', ?)]], values = { r.deptId, p.charId, amount, ('Impound fees: %s'):format(r.plate or ('#' .. r.id)), r.officerCharId, r.id } } }, { source = p.source })
        local fid = okc and MySQL.scalar.await("SELECT `id` FROM `es_mdt_fines` WHERE `impoundId` = ? AND `status` = 'paid' ORDER BY `id` DESC LIMIT 1", { r.id }) or nil
        if fid then MDT.fineToDept({ id = fid, deptId = r.deptId, amount = amount, kind = 'impound', charId = p.charId }, ('Impound fees #%d %s'):format(r.id, r.plate or ''))
        else print(('^3[es_mdt] impound #%d: paid %d, but the payment record could not be written^7'):format(r.id, amount)) end
    end
    textOwner(r, ('Paid %s: your %s (%s) is released. Pick it up at %s.'):format(money(amount), r.vehicleLabel or 'vehicle', r.plate or '?',
        IC().releaseTo == 'home' and r.homeGarage and 'your garage' or r.lotLabel), 'Vehicle released: ' .. (r.plate or ''))
    return { amount = amount, lot = r.lotLabel }
end

--- an invoice for impound fees was paid (lot staff released it with an invoice): just the record
function MDT.onImpoundFeePaid(iid, f)
    MySQL.update.await('UPDATE `es_mdt_impounds` SET `paid` = COALESCE(`paid`, 0) + ? WHERE `id` = ?', { f.amount, iid })
    MDT.refresh('impound')
end

--- the owner's impounded vehicles (court portal)
function MDT.impoundsOf(charId)
    local rows = MySQL.query.await('SELECT ' .. COLS .. " FROM `es_mdt_impounds` i LEFT JOIN `es_departments` d ON d.`id` = i.`deptId` WHERE i.`ownerCharId` = ? AND (i.`status` IN ('pending','held') OR i.`releasedAt` > NOW() - INTERVAL 14 DAY) ORDER BY i.`id` DESC LIMIT 20", { charId }) or {}
    for _, r in ipairs(rows) do decorate(r) r.notes = nil r.officerCharId = nil end
    return rows
end

function MDT.registerImpound()
    local cb, str, int, id = MDT.cb, MDT.str, MDT.int, MDT.id
    if IC().enabled == false then
        -- still answer the pages (the lot view says it is off) and keep existing holds
        CreateThread(function() Wait(10000) sweepPending() end)
    else
        CreateThread(function() Wait(8000) ensureLots() Wait(4000) sweepPending() end)
    end

    -- the form: from the MDT (vehicleId) or the street (netId of the car the officer stands by)
    cb('impForm', { perm = 'impound_vehicle', rate = 500, burst = 6 }, function(c, d)
        if IC().enabled == false then return false, 'Impounding is turned off' end
        local v, street
        if d.netId then
            local near = MDT.vehiclesNear(c, { d.netId }, (tonumber(IC().range) or 8.0) + 2.0)[1]
            if not near then return false, 'No vehicle close to you' end
            street = true
            v = near.vehicleId and WC:GetVehicle(near.vehicleId, { occupants = true })
            if not v or v.session then
                -- nobody's car: the tow
                return { street = true, unowned = true, plate = near.plate, label = near.label, occupied = near.occupied, temp = near.temp, netId = tonumber(d.netId),
                    settings = formSettings(c) }
            end
        else
            local vid = id(d.vehicleId)
            v = vid and WC:GetVehicle(vid)
            if not v then return false, 'No such vehicle' end
            if v.session then return false, 'That is nobody\'s car' end
        end
        local f = vehicleFacts(v)
        f.street = street == true
        f.netId = street and tonumber(d.netId) or nil
        f.settings = formSettings(c)
        f.occupied = v.occupants and next(v.occupants) ~= nil or false
        return f
    end)

    cb('impSave', { perm = 'impound_vehicle', write = true, rate = 3000, burst = 2 }, function(c, d)
        if IC().enabled == false then return false, 'Impounding is turned off' end
        local v
        local street = false
        if d.netId then
            local near = MDT.vehiclesNear(c, { d.netId }, (tonumber(IC().range) or 8.0) + 3.0)[1]
            if not near then return false, 'That vehicle is not close to you any more' end
            local ent = NetworkGetEntityFromNetworkId(tonumber(d.netId))
            local full = near.vehicleId and WC:GetVehicle(near.vehicleId, { occupants = true })
            if not full then
                local vid2 = WC:AdoptVehicle({ netId = tonumber(d.netId), player = c.source })
                full = vid2 and WC:GetVehicle(vid2, { occupants = true })
            end
            if not full then return false, 'That vehicle could not be read' end
            if full.session then return towed(c, ent, full) end
            v = vehicleFacts(full)
            street = true
        else
            local full = id(d.vehicleId) and WC:GetVehicle(id(d.vehicleId))
            if not full or full.session then return false, 'No such vehicle' end
            v = vehicleFacts(full)
        end
        if not v.ownerCharId then return false, 'That vehicle has no owner' end
        return doImpound(c, v, d, street)
    end)

    -- the lot: everything held or marked, with what is owed now; recent releases
    cb('impList', { rate = 300, burst = 6 }, function(c, d)
        local st = d.status == 'released' and "i.`status` IN ('released','cancelled')" or "i.`status` IN ('pending','held')"
        local q = str(d.q, 20)
        local args = {}
        local extra = ''
        if q ~= '' then extra = ' AND (i.`plate` LIKE ? OR i.`vehicleLabel` LIKE ?)' local l = '%' .. q:gsub('[%%_\\]', '\\%0') .. '%' args = { l, l } end
        local rows = MySQL.query.await('SELECT ' .. COLS .. ' FROM `es_mdt_impounds` i LEFT JOIN `es_departments` d ON d.`id` = i.`deptId` WHERE ' .. st .. extra ..
            ' ORDER BY i.`id` DESC LIMIT 200', args) or {}
        local ids = {}
        for _, r in ipairs(rows) do ids[#ids + 1] = r.ownerCharId end
        local names = MDT.namesOf(ids)
        local sum = 0
        for _, r in ipairs(rows) do decorate(r, names) if r.status == 'held' then sum = sum + r.owe.total end end
        return { rows = rows, outstanding = sum, settings = formSettings(c), enabled = IC().enabled ~= false }
    end)

    cb('impGet', { rate = 300, burst = 6 }, function(c, d)
        local r = impRow(id(d.id) or 0)
        if not r then return false, 'No such impound' end
        r.prior = priorCount(r.vehicleId) - (r.status == 'held' and 1 or 0)
        r.settings = formSettings(c)
        return r
    end)

    -- a vehicle's page: its impound history + what is active
    cb('impVehicle', { rate = 300, burst = 6 }, function(c, d)
        local vid = id(d.vehicleId)
        if not vid then return false, 'Pick a vehicle' end
        local rows = MySQL.query.await('SELECT ' .. COLS .. ' FROM `es_mdt_impounds` i LEFT JOIN `es_departments` d ON d.`id` = i.`deptId` WHERE i.`vehicleId` = ? ORDER BY i.`id` DESC LIMIT 30', { vid }) or {}
        for _, r in ipairs(rows) do decorate(r) end
        local v = WC:GetVehicle(vid)
        return { rows = rows, state = v and v.state, garage = v and v.garage, spawned = v and v.spawned or false, settings = formSettings(c), canImpound = c.perms.impound_vehicle == true }
    end)

    -- change the hold: longer (impound_hold); shorter or lifted before it ends = an override
    cb('impHold', { perm = 'impound_hold', write = true, rate = 1500, burst = 3 }, function(c, d)
        local r = impRow(id(d.id) or 0)
        if not r or (r.status ~= 'held' and r.status ~= 'pending') then return false, 'That vehicle is not impounded' end
        local on, untilTs = holdOn(r)
        local newOpen, newDays = d.hold == 'open', (d.hold == 'days') and int(d.holdDays, 1, tonumber(IC().maxHoldDays) or 30) or 0
        local newUntil = newDays > 0 and (os.time() + newDays * 86400) or nil
        local shorter = on and ((not newOpen) and (untilTs == nil or (newUntil or 0) < untilTs))
        local note = str(d.note, 300)
        if shorter then
            if not c.perms.impound_override then return false, 'Ending a hold early needs the "release early (override)" permission' end
            if #note < 5 then return false, 'Say why the hold ends early' end
        end
        MySQL.update.await('UPDATE `es_mdt_impounds` SET `holdOpen` = ?, `holdUntil` = IF(? > 0, NOW() + INTERVAL ? DAY, NULL), `override` = IF(?, 1, `override`), `releaseNote` = IF(?, ?, `releaseNote`) WHERE `id` = ?',
            { newOpen and 1 or 0, newDays, newDays, shorter, shorter, shorter and ('Hold changed early by ' .. c.name .. ': ' .. note) or nil, r.id })
        MDT.log(c, shorter and 'impound_override' or 'impound_hold', ('#%d %s %s'):format(r.id, tostring(r.plate), newOpen and 'open' or (newDays .. 'd')) .. (shorter and (': ' .. note) or ''))
        local x = impRow(r.id)
        textOwner(x, ('The police hold on your %s (%s) changed. %s'):format(x.vehicleLabel or 'vehicle', x.plate or '?', holdText(x)), 'Impound hold changed: ' .. (x.plate or ''))
        MDT.refresh('impound')
        return true
    end)

    -- release by the lot: charge (an invoice to the owner), or waive (a reason). Before the hold ends: an override.
    cb('impRelease', { perm = 'impound_lot', write = true, rate = 2000, burst = 2 }, function(c, d)
        local r = impRow(id(d.id) or 0)
        if not r or (r.status ~= 'held' and r.status ~= 'pending') then return false, 'That vehicle is not impounded' end
        local on = holdOn(r)
        local note = str(d.note, 300)
        if on then
            if not c.perms.impound_override then return false, 'It is on a hold: releasing it early needs the "release early (override)" permission' end
            if #note < 5 then return false, 'Say why it is released before the hold ends' end
        end
        local waive = d.fees == 'waive' or r.status == 'pending'
        if waive and r.status ~= 'pending' and r.owe.total > 0 and #note < 3 then return false, 'Say why the fees are waived' end
        local st, why = release(r, { by = c.name, note = note, override = on })
        if not st then return false, why end
        local fid
        if not waive and r.owe.total > 0 and r.ownerCharId then
            local res = MDT.issueFine(c, r.ownerCharId, r.owe.total, ('Impound fees: %s'):format(r.plate or ('#' .. r.id)), nil, { kind = 'impound', impoundId = r.id, quiet = true })
            fid = type(res) == 'table' and res.id or nil
            if fid then MySQL.update.await('UPDATE `es_mdt_impounds` SET `fineId` = ? WHERE `id` = ?', { fid, r.id }) end
        end
        MDT.log(c, on and 'impound_override' or 'impound_release', ('#%d %s%s%s'):format(r.id, tostring(r.plate), waive and ' waived' or (' invoice $' .. r.owe.total), note ~= '' and (': ' .. note) or ''))
        if st == 'cancelled' then
            textOwner(r, ('The impound of your %s (%s) was called off. You can use it as normal.'):format(r.vehicleLabel or 'vehicle', r.plate or '?'), 'Impound called off: ' .. (r.plate or ''))
        else
            textOwner(r, ('Your %s (%s) is released%s. %s'):format(r.vehicleLabel or 'vehicle', r.plate or '?',
                IC().releaseTo == 'home' and r.homeGarage and ' to your garage' or (' at ' .. r.lotLabel),
                fid and ('The fees, %s, are an invoice: pay at /%s.'):format(money(r.owe.total), portalCmd()) or 'No fees are owed.'), 'Vehicle released: ' .. (r.plate or ''))
        end
        return { status = st, invoice = fid, amount = (not waive) and r.owe.total or 0 }
    end)
end

-- ---------------------------------------------------------------- for other scripts (docs/HOOKS.md)
exports('IsImpounded', function(vehicleId)
    local r = activeOf(tonumber(vehicleId) or 0)
    if not r then return false end
    return true, { id = r.id, status = r.status, lot = r.lot, held = r.held, holdUntil = r.holdUntilTs, owed = r.owe.total, reason = r.reason }
end)
exports('GetImpounds', function(charId) return MDT.impoundsOf(tonumber(charId) or 0) end)
--- 2.2.1: es_jobs' impound clerk: the owner pays at the counter (as the court portal's Impound tab does). method 'bank' | 'cash'
exports('PayImpound', function(source, impoundId, method)
    local cid = WC:GetCharId(source)
    if not cid then return false, 'Load a character first' end
    return MDT.impoundPay({ source = source, charId = cid }, tonumber(impoundId) or 0, method)
end)
