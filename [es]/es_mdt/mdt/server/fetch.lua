local _ENV = ESAPP('mdt'); -- Fetching a picture from a link (a mugshot from a link), for when the player's browser may not
-- read it itself. Public http(s) addresses only; what comes back must be a picture (checked by its bytes).
Fetch = {}

local MAX_BYTES = 2 * 1024 * 1024
local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

local function b64encode(data)
    local out, n = {}, #data
    for i = 1, n, 3 do
        local a, b, c = data:byte(i, i + 2)
        local v = (a << 16) | ((b or 0) << 8) | (c or 0)
        local c1, c2, c3, c4 = (v >> 18) & 63, (v >> 12) & 63, (v >> 6) & 63, v & 63
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or '=') .. (c and B64:sub(c4 + 1, c4 + 1) or '=')
    end
    return table.concat(out)
end

local function kindOf(bytes)
    if bytes:sub(1, 8) == '\137PNG\r\n\26\n' then return 'png' end
    if bytes:sub(1, 3) == '\255\216\255' then return 'jpeg' end
    if bytes:sub(1, 4) == 'RIFF' and bytes:sub(9, 12) == 'WEBP' then return 'webp' end
    if bytes:sub(1, 4) == 'GIF8' then return 'gif' end
    return nil
end

--- Is this a link the server may open? true, or false and why (said to the player).
function Fetch.check(url)
    if type(url) ~= 'string' then return false, 'That is not a link' end
    url = url:gsub('^%s+', ''):gsub('%s+$', '')
    local scheme, host = url:match('^(https?)://([^/:?#]+)')
    if not scheme then return false, 'A link starts with https://' end
    host = host:lower()
    if host == 'localhost' or host:match('^[%d%.]+$') or host:find(':', 1, true) or host:match('%.local$')
        or host:match('%.internal$') or not host:find('.', 1, true) then
        return false, 'That link points at a private address'
    end
    return true
end

--- The picture at `url` as a data URL, or false and why. Waits.
function Fetch.get(url)
    local p, settled = promise.new(), false
    local function settle(v) if not settled then settled = true p:resolve(v) end end
    PerformHttpRequest(url, function(status, body, headers)
        settle({ status = status, body = body, headers = headers })
    end, 'GET', '', { ['User-Agent'] = 'Mozilla/5.0 (es_mdt mugshot fetch)', ['Accept'] = 'image/*' })
    SetTimeout(15000, function() settle({ status = 0 }) end)
    local r = Citizen.Await(p)
    if not r or r.status == 0 then return false, 'That link did not answer' end
    if r.status ~= 200 or type(r.body) ~= 'string' then return false, ('That link answered %s, not a picture'):format(tostring(r.status)) end
    if #r.body > MAX_BYTES then return false, 'That picture is over 2 MB' end
    local kind = kindOf(r.body)
    if not kind then return false, 'That link is a web page, not a picture (right-click the image and copy the image address)' end
    -- A body cut short (binary that did not survive the trip) would draw half a picture: compare with what it said
    local said
    for k, v in pairs(r.headers or {}) do if tostring(k):lower() == 'content-length' then said = tonumber(v) end end
    if said and said ~= #r.body then return false, 'The picture arrived damaged; save it and use Choose picture instead' end
    return ('data:image/%s;base64,%s'):format(kind, b64encode(r.body))
end
