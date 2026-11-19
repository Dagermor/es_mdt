local _ENV = ESAPP('mdt'); -- es_mdt 2.1.0: texts to owners and recipients (impounds, fees, releases, tickets, contest rulings).
-- whip_phone has no "send a text" export, so this does what whip_phone's own lore characters do (its server/lore.lua):
--   * one government number of our own in phone_numbers (no charId, loreKey = Config.Texts.loreKey), made once; then
--     exports.whip_phone:ReloadCache() so the phone knows it
--   * the text is a row in phone_messages from that number to the person's own number(s): it waits there while they are
--     offline, and is on their phone when they next look (that is the queue)
--   * online: exports.whip_phone:Push(src, 'messages', 'incoming', { id, number, text, time }), the same push whip_phone
--     sends for a lore text, so it pops up at once
-- A copy always goes to their court portal notices (/court > Notices, es_doj_notices), so a text is never lost: no
-- whip_phone, no phone number, or texts turned off, the notice is still there. Nothing here changes whip_phone.
-- Loaded BEFORE server/main.lua; MDT.text() is used by tickets.lua and impound.lua.
MDT = MDT or {}

local function TC() return type(Config.Texts) == 'table' and Config.Texts or {} end
local function phoneUp() return GetResourceState('whip_phone') == 'started' end

local sender           -- our number (string), once known
local senderTried = 0  -- os.time() of the last failed try (not every text tries again)

local function q(fn, sql, args)
    local ok, r = pcall(fn, sql, args)
    if not ok then return nil, r end
    return r
end

--- our government number: found by its loreKey, or made (a 10-digit number nobody holds)
local function senderNumber()
    if sender then return sender end
    if os.time() - senderTried < 60 then return nil end
    local key = tostring(TC().loreKey or 'es_mdt_gov'):sub(1, 64)
    local row = q(MySQL.single.await, 'SELECT `phoneNumber` FROM `phone_numbers` WHERE `loreKey` = ? LIMIT 1', { key })
    if row and row.phoneNumber then sender = row.phoneNumber return sender end
    for _ = 1, 8 do
        local n = ('555%07d'):format(math.random(0, 9999999))
        local taken = q(MySQL.scalar.await, 'SELECT 1 FROM `phone_numbers` WHERE `phoneNumber` = ?', { n })
        if taken == nil then
            local ok = q(MySQL.insert.await, 'INSERT INTO `phone_numbers` (`phoneNumber`,`charId`,`loreKey`) VALUES (?, NULL, ?)', { n, key })
            if ok ~= nil then
                sender = n
                pcall(function() exports.whip_phone:ReloadCache() end)
                print(('^2[es_mdt] owner texts: the government number is %s (whip_phone)^7'):format(n))
                return sender
            end
        end
    end
    senderTried = os.time()
    return nil
end

--- the person's live phone numbers (a SIM of theirs not locked or retired)
local function numbersOf(charId)
    local rows = q(MySQL.query.await, 'SELECT `phoneNumber` FROM `phone_numbers` WHERE `charId` = ? AND `locked` = 0 AND `retiredAt` IS NULL LIMIT 3', { charId }) or {}
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = r.phoneNumber end
    return out
end

--- the contact name on their phone (once per number)
local function ensureContact(own, from)
    local name = tostring(TC().sender or 'San Andreas Gov'):sub(1, 50)
    local has = q(MySQL.scalar.await, 'SELECT 1 FROM `phone_contacts` WHERE `phoneNumber` = ? AND `contactNumber` = ? LIMIT 1', { own, from })
    if has == nil then q(MySQL.insert.await, 'INSERT INTO `phone_contacts` (`phoneNumber`,`contactName`,`contactNumber`) VALUES (?,?,?)', { own, name, from }) end
end

--- the portal copy (es_doj_notices). kind: 'impound' | 'ticket' | 'contest' | 'invoice'
local function notice(charId, title, body, kind)
    q(MySQL.insert.await, 'INSERT INTO `es_doj_notices` (`charId`,`kind`,`title`,`body`) VALUES (?,?,?,?)',
        { charId, kind or 'notice', tostring(title):sub(1, 160), body and tostring(body):sub(1, 1000) or nil })
end

--- Text a character (online or not). Returns 'texted' | 'notice' (no phone: the portal copy only) | nil.
--- opts: { kind, title (the portal notice's title; default the first line), online = MDT.onlineByChar() map }
function MDT.text(charId, body, opts)
    opts = opts or {}
    charId = tonumber(charId)
    if not charId or charId >= 900000000 then return nil end   -- FTO test trainees are not characters
    body = tostring(body or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if body == '' then return nil end
    if #body > 480 then body = body:sub(1, 477) .. '...' end
    notice(charId, opts.title or body:match('^[^\n]+'), body, opts.kind)
    local online = opts.online or (MDT.onlineByChar and MDT.onlineByChar()) or {}
    local src = online[charId]
    if src then TriggerClientEvent('es_doj:client:notices', src) end
    if TC().enabled == false or not phoneUp() then
        if src then exports.whip_core:NotifyPlayer(src, body:match('^[^\n]+'), 'info', 9000) end
        return 'notice'
    end
    local from = senderNumber()
    local nums = from and numbersOf(charId) or {}
    if #nums == 0 then
        if src then exports.whip_core:NotifyPlayer(src, body:match('^[^\n]+'), 'info', 9000) end
        return 'notice'
    end
    local sent = false
    for _, to in ipairs(nums) do
        ensureContact(to, from)
        local mid = q(MySQL.insert.await, 'INSERT INTO `phone_messages` (`senderNumber`,`receiverNumber`,`content`) VALUES (?,?,?)', { from, to, body })
        if mid then
            sent = true
            if src then pcall(function() exports.whip_phone:Push(src, 'messages', 'incoming', { id = mid, number = from, text = body, time = os.time() }) end) end
        end
    end
    if not sent then
        if src then exports.whip_core:NotifyPlayer(src, body:match('^[^\n]+'), 'info', 9000) end
        return 'notice'
    end
    return 'texted'
end

--- for the status line in /whip and the tests
function MDT.textStatus()
    if TC().enabled == false then return 'off' end
    if not phoneUp() then return 'no phone script (portal notices only)' end
    return senderNumber() and 'whip_phone' or 'whip_phone (number not made yet)'
end

function MDT.registerTexts()
    if TC().enabled ~= false and phoneUp() then
        CreateThread(function() Wait(3000) senderNumber() end)
    end
end
