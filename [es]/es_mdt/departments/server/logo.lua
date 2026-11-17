local _ENV = ESAPP('departments'); -- A department logo is a data URL (webp or png), checked here before it is stored:
-- its kind from its own bytes (not the label it claims), its decoded size and its pixel size.
Logo = {}

local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local DEC = {}
for i = 1, #B64 do DEC[B64:byte(i)] = i - 1 end

-- The first `n` bytes of a base64 string (n a multiple of 3 is simplest; more is fine)
local function head(b64, n)
    local out, need = {}, math.ceil(n / 3) * 4
    local s = b64:sub(1, need)
    for i = 1, #s - 3, 4 do
        local a, b, c, d = DEC[s:byte(i)], DEC[s:byte(i + 1)], DEC[s:byte(i + 2)], DEC[s:byte(i + 3)]
        if not a or not b then break end
        local v = (a << 18) | (b << 12) | ((c or 0) << 6) | (d or 0)
        out[#out + 1] = string.char((v >> 16) & 255)
        if c then out[#out + 1] = string.char((v >> 8) & 255) end
        if d then out[#out + 1] = string.char(v & 255) end
    end
    return table.concat(out)
end

local function u16le(s, i) return s:byte(i) | (s:byte(i + 1) << 8) end
local function u24le(s, i) return s:byte(i) | (s:byte(i + 1) << 8) | (s:byte(i + 2) << 16) end
local function u32be(s, i) return (s:byte(i) << 24) | (s:byte(i + 1) << 16) | (s:byte(i + 2) << 8) | s:byte(i + 3) end

--- Width and height from a PNG or WEBP header, and its kind; nil when it is neither.
local function measure(bytes)
    if #bytes >= 24 and bytes:sub(1, 8) == '\137PNG\r\n\26\n' and bytes:sub(13, 16) == 'IHDR' then
        return 'png', u32be(bytes, 17), u32be(bytes, 21)
    end
    if #bytes >= 30 and bytes:sub(1, 4) == 'RIFF' and bytes:sub(9, 12) == 'WEBP' then
        local chunk = bytes:sub(13, 16)
        if chunk == 'VP8X' then
            return 'webp', u24le(bytes, 25) + 1, u24le(bytes, 28) + 1
        elseif chunk == 'VP8L' and bytes:byte(21) == 0x2f then
            local b0, b1, b2, b3 = bytes:byte(22), bytes:byte(23), bytes:byte(24), bytes:byte(25)
            local w = 1 + (((b1 & 0x3f) << 8) | b0)
            local h = 1 + (((b3 & 0x0f) << 10) | (b2 << 2) | ((b1 & 0xc0) >> 6))
            return 'webp', w, h
        elseif chunk == 'VP8 ' then
            return 'webp', u16le(bytes, 27) & 0x3fff, u16le(bytes, 29) & 0x3fff
        end
    end
    return nil
end

--- Check a data URL. Answers the data URL (as stored) or false, why.
function Logo.check(dataUrl)
    if type(dataUrl) ~= 'string' then return false, 'No picture' end
    local mime, b64 = dataUrl:match('^data:image/(%a+);base64,(.+)$')
    if mime ~= 'webp' and mime ~= 'png' then return false, 'A logo is a webp or png picture' end
    if b64:find('[^%w%+/=]') then return false, 'That picture is damaged' end
    local pad = b64:match('(=*)$')
    local bytes = (#b64 * 3) // 4 - #pad
    if bytes > Config.LogoMaxBytes then
        return false, ('That logo is %d KB; %d KB at most'):format(math.ceil(bytes / 1024), Config.LogoMaxBytes // 1024)
    end
    local kind, w, h = measure(head(b64, 30))
    if not kind or kind ~= mime then return false, 'That picture is not a webp or png' end
    if w < 1 or h < 1 or w > Config.LogoMaxSide or h > Config.LogoMaxSide then
        return false, ('A logo is %dx%d pixels at most (that one is %dx%d)'):format(Config.LogoMaxSide, Config.LogoMaxSide, w, h)
    end
    return dataUrl
end
