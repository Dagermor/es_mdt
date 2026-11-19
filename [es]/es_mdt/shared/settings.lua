local _ENV = ESAPP('mdt'); -- es_mdt 2.0.8: the MDT's settings page in /whip > Settings > MDT (Whip.configPage)
-- mdt/config.lua stays the defaults: a fresh install works as before, and what an admin saves on the page is written over
-- Config on both sides as the resource starts and the moment it is changed. apply = 'restart': saved now, used from the
-- next restart (commands, keys, chat suggestions are registered once at start). Keys stay in GTA Settings > Key Bindings >
-- FiveM for each player; the page holds their DEFAULTS only.
if not (Whip and Whip.configPage) then return end

-- The page's root: Config (the MDT part's), plus `Suite` for EsSuite (shared/suite.lua). Reads and writes go straight
-- through to Config, so 'Dispatch.cooldownSec' is Config.Dispatch.cooldownSec.
local ROOT = setmetatable({ Suite = EsSuite }, {
    __index = function(_, k) return Config[k] end,
    __newindex = function(_, k, v) Config[k] = v end,
})

local function restart(e, why)
    e.apply, e.why = 'restart', why or 'Registered when the resource starts'
    return e
end
local function on(path) return { path = path, equals = true } end

local A = 'Dispatch.alerts.'
--- an automatic alert's card: on / off, then its numbers (shown only while it is on)
local function alertRows(k, label, extra)
    local rows = {
        { key = A .. k .. '.enabled', type = 'bool', label = label },
        { key = A .. k .. '.chance', type = 'number', min = 0, max = 1, step = 0.05, label = label .. ': chance a witness calls it in',
          help = '0 = never, 1 = always.', shownWhen = on(A .. k .. '.enabled') },
        { key = A .. k .. '.cooldown', type = 'int', min = 5, max = 3600, unit = 's', label = label .. ': per player, at most once every',
          shownWhen = on(A .. k .. '.enabled') },
        { key = A .. k .. '.priority', type = 'int', min = 1, max = 3, label = label .. ': priority (1 = highest)', shownWhen = on(A .. k .. '.enabled') },
    }
    for _, e in ipairs(extra or {}) do e.shownWhen = e.shownWhen or on(A .. k .. '.enabled') rows[#rows + 1] = e end
    return rows
end
local function join(...)
    local out = {}
    for _, l in ipairs({ ... }) do for _, e in ipairs(l) do out[#out + 1] = e end end
    return out
end

local D = 'Dispatch.'
Whip.configPage({
    label = 'MDT',
    config = ROOT,
    groups = {
        { id = 'calls', label = 'Calls', settings = {
            { key = D .. 'cooldownSec', type = 'int', min = 0, max = 600, unit = 's', label = '911 / 311: one call per player every',
              help = '911, 311 and the medical line together.' },
            { key = D .. 'routing.shared', type = 'bool', label = 'Every department sees every call',
              help = 'In the Dispatch tab. Cards, sounds and blips still go only where the call is routed.' },
            { key = D .. 'autoCloseMinutes', type = 'int', min = 0, max = 1440, unit = 'min', label = 'Auto-close calls after',
              help = 'Silent: no popup or sound, the call stays in the history. 0 = never.' },
            { key = D .. 'autoCloseAttached', type = 'bool', label = 'Auto-close calls with a unit on them too' },
            { key = D .. 'callTTLMin', type = 'int', min = 0, max = 2880, unit = 'min', label = 'Close any call after (hard cap)',
              help = 'Even with units on it. A panic with a unit on it is never auto-closed. 0 = never.' },
            { key = D .. 'sweepSeconds', type = 'int', min = 15, max = 600, unit = 's', label = 'Check for calls to close every' },
            { key = D .. 'keepClosedDays', type = 'int', min = 0, max = 3650, unit = 'days', label = 'Delete closed calls after',
              help = 'Daily. Never an open call or one linked to a report, warrant or case. 0 = keep every call.' },
            { key = D .. 'escalate.enabled', type = 'bool', label = 'Unanswered calls go up a priority' },
            { key = D .. 'escalate.minutes', type = 'int', min = 1, max = 120, unit = 'min', label = 'Go up after', shownWhen = on(D .. 'escalate.enabled') },
            { key = D .. 'escalate.top', type = 'int', min = 1, max = 3, label = 'Never above priority', shownWhen = on(D .. 'escalate.enabled') },
            { key = D .. 'escalate.realert', type = 'bool', label = 'Re-alert the units when it goes up', shownWhen = on(D .. 'escalate.enabled') },
            { key = D .. 'backup.enabled', type = 'bool', label = 'Request backup (MDT button, /backup)' },
            { key = D .. 'backup.priority', type = 'int', min = 1, max = 3, label = 'Backup call priority', shownWhen = on(D .. 'backup.enabled') },
            { key = D .. 'backup.urgentPriority', type = 'int', min = 1, max = 3, label = 'Backup priority on a panic / P1 call', shownWhen = on(D .. 'backup.enabled') },
            { key = D .. 'backup.cooldown', type = 'int', min = 0, max = 600, unit = 's', label = 'One backup request per officer every', shownWhen = on(D .. 'backup.enabled') },
            { key = 'Panic.cooldown', type = 'int', min = 0, max = 300, unit = 's', label = 'Panic button: once every' },
        } },
        { id = 'alerts', label = 'Alerts on screen', settings = {
            { key = D .. 'popup.enabled', type = 'bool', label = 'Call card on screen for new calls', help = 'For officers on duty with the MDT closed.' },
            { key = D .. 'popup.seconds', type = 'int', min = 3, max = 120, unit = 's', label = 'Card hides after', shownWhen = on(D .. 'popup.enabled') },
            { key = D .. 'popup.panicSeconds', type = 'int', min = 3, max = 300, unit = 's', label = 'Panic card hides after', shownWhen = on(D .. 'popup.enabled') },
            { key = D .. 'popup.sound', type = 'bool', label = 'Sound with the card', shownWhen = on(D .. 'popup.enabled') },
            { key = D .. 'sounds.engine', type = 'enum', label = 'Alert sounds', options = {
                { value = 'nui', label = 'MDT tones (each player sets the volume)' }, { value = 'game', label = 'GTA sounds (mute only)' } } },
            { key = D .. 'sounds.defaultVolume', type = 'int', min = 0, max = 100, unit = '%', label = 'Default alert volume',
              help = 'For players who never set their own (pause menu > Settings > MDT, or the Aa button).' },
            { key = D .. 'critical.enabled', type = 'bool', label = 'Critical calls (above P1: pulsing card, repeating alarm)' },
            { key = D .. 'critical.panic', type = 'bool', label = 'Panic is critical', shownWhen = on(D .. 'critical.enabled') },
            { key = D .. 'critical.repeatSeconds', type = 'int', min = 2, max = 60, unit = 's', label = 'Alarm repeats every', shownWhen = on(D .. 'critical.enabled') },
            { key = D .. 'critical.maxRepeats', type = 'int', min = 0, max = 50, label = 'Alarm repeats at most', shownWhen = on(D .. 'critical.enabled') },
            { key = D .. 'critical.stopOnUnit', type = 'bool', label = 'Alarm stops when any unit responds', shownWhen = on(D .. 'critical.enabled') },
            { key = D .. 'board.enabled', type = 'bool', label = 'Call board (key O by default, /callboard)' },
            { key = D .. 'board.limit', type = 'int', min = 5, max = 100, label = 'Calls on the board', shownWhen = on(D .. 'board.enabled') },
            { key = 'Announcements.urgentFreshHours', type = 'int', min = 0, max = 168, unit = 'h', label = 'Show urgent announcements on opening for',
              help = 'An urgent one posted this recently shows once when an on-duty member opens the MDT. 0 = off.' },
        } },
        { id = 'reports', label = 'Repeat reports and search areas', settings = {
            { key = D .. 'merge.enabled', type = 'bool', label = 'Repeat reports join the open call', help = '"x3 reports" and a note instead of a new call.' },
            { key = D .. 'merge.radius', type = 'int', min = 10, max = 1000, unit = 'm', label = 'Within', shownWhen = on(D .. 'merge.enabled') },
            { key = D .. 'merge.seconds', type = 'int', min = 10, max = 1800, unit = 's', label = 'While the call is younger than', shownWhen = on(D .. 'merge.enabled') },
            { key = D .. 'witness.enabled', type = 'bool', label = 'Witness calls show a search area', help = 'The exact spot never leaves the server.' },
            { key = D .. 'witness.radius', type = 'int', min = 20, max = 1000, unit = 'm', label = 'Search area radius', shownWhen = on(D .. 'witness.enabled') },
            { key = D .. 'witness.minRadius', type = 'int', min = 10, max = 500, unit = 'm', label = 'Smallest search area', shownWhen = on(D .. 'witness.enabled') },
            { key = D .. 'witness.shrink', type = 'number', min = 0.3, max = 1, step = 0.05, label = 'Each report shrinks it to', help = '0.75 = three quarters.',
              shownWhen = on(D .. 'witness.enabled') },
            { key = D .. 'places.radius', type = 'int', min = 5, max = 200, unit = 'm', label = 'Robbery alerts: name the store within',
              help = 'StoreRobbery / BankRobbery / JewelryRobbery are titled with the nearest store, bank or Vangelico this close.' },
            { key = D .. 'places.extra', type = 'records', widget = 'mapPoints', label = 'Robbery alerts: your own places',
              help = 'Shops your map adds, or a stock one renamed (use its id, e.g. 247_innocence; see mdt/server/places.lua).',
              marker = { sprite = 52, colour = 2, name = 'MDT place' },
              fields = {
                  { key = 'id', type = 'string', maxLen = 40, pattern = '^[%w_%-]+$', patternWhy = 'letters, digits, _ and -', label = 'ID' },
                  { key = 'kind', type = 'enum', label = 'Kind', options = { { value = 'store', label = 'Store' }, { value = 'bank', label = 'Bank' },
                      { value = 'jewelry', label = 'Jewelry store' } } },
                  { key = 'name', type = 'string', maxLen = 80, label = 'Name on the call', help = 'e.g. 24/7 Supermarket, Innocence Blvd' },
                  { key = 'coords', type = 'vec3', here = true, label = 'Where' },
                  { key = 'radius', type = 'int', min = 5, max = 200, unit = 'm', label = 'Reach' },
              } },
        } },
        { id = 'auto', label = 'Automatic alerts', settings = join(
            { { key = A .. 'exemptLaw', type = 'bool', label = 'Officers on duty never set them off' },
              { key = A .. 'searchCircle', type = 'bool', label = 'Show a search area, not the exact spot' },
              { key = A .. 'perMinute', type = 'int', min = 0, max = 60, label = 'New calls of one kind per minute, server-wide', help = '0 = no cap.' } },
            alertRows('shots', 'Shots fired'),
            alertRows('theft', 'Vehicle theft'),
            alertRows('fight', 'Fights'),
            alertRows('explosion', 'Explosions'),
            alertRows('down', 'Person down (to EMS)', {
                { key = A .. 'down.delay', type = 'int', min = 5, max = 300, unit = 's', label = 'Person down: after lying there for' } }),
            alertRows('speeding', 'Speeding', {
                { key = A .. 'speeding.units', type = 'enum', label = 'Speeding: units', options = {
                    { value = 'mph', label = 'mph' }, { value = 'kmh', label = 'km/h' } } },
                { key = A .. 'speeding.limit', type = 'int', min = 10, max = 400, label = 'Speeding: limit',
                  help = 'Faster than this is speeding (in the units above). The alert reads e.g. "112 mph in a 80 zone".' },
                { key = A .. 'speeding.highwayLimit', type = 'int', min = 0, max = 400, label = 'Speeding: limit on highways',
                  help = 'Streets named ...Fwy, Freeway, Hwy, Highway, Route or Interstate. 0 = the same limit everywhere.' },
                { key = A .. 'speeding.seconds', type = 'int', min = 1, max = 60, unit = 's', label = 'Speeding: over the limit for at least' },
            })
        ) },
        { id = 'records', label = 'Records, fines and jail', settings = {
            { key = 'OffDutyReadOnly', type = 'bool', label = 'Off duty: the MDT is read-only' },
            { key = 'FineMax', type = 'int', min = 0, max = 100000000, unit = '$', label = 'Largest fine' },
            { key = 'UnpaidFineWarrantDays', type = 'int', min = 0, max = 365, unit = 'days', label = 'Unpaid fine becomes a warrant after',
              help = '"Failure to pay". 0 = never.' },
            { key = 'WarrantBolos.enabled', type = 'bool', label = 'Active warrants post BOLOs' },
            { key = 'WarrantBolos.person', type = 'bool', label = 'A person BOLO', shownWhen = on('WarrantBolos.enabled') },
            { key = 'WarrantBolos.vehicles', type = 'bool', label = 'A BOLO for each car they own', shownWhen = on('WarrantBolos.enabled') },
            { key = 'WarrantBolos.maxVehicles', type = 'int', min = 0, max = 50, label = 'At most this many cars', shownWhen = on('WarrantBolos.enabled') },
            { key = 'WarrantBolos.autoFineWarrants', type = 'bool', label = 'Also for unpaid-fine warrants', shownWhen = on('WarrantBolos.enabled') },
            { key = 'Jail.provider', type = 'enum', label = 'Jail script', options = {
                { value = 'auto', label = 'Automatic (a registered one, else es_jail, else custom)' }, { value = 'es_jail', label = 'es_jail' },
                { value = 'custom', label = 'Custom (Config.Jail.custom)' }, { value = 'none', label = 'None (the MDT counts the time)' } } },
            { key = 'Jail.recordMinutesPerMonth', type = 'number', min = 0.05, max = 60, step = 0.05, unit = 'min', label = 'With no jail script: real minutes per month' },
            { key = 'WhipEvidence.enabled', type = 'enum', label = 'whip_evidence bridge', options = {
                { value = 'auto', label = 'Automatic (on when whip_evidence is installed)' }, { value = true, label = 'On' }, { value = false, label = 'Off' } } },
            { key = 'MapRefreshMs', type = 'int', min = 1000, max = 30000, step = 500, unit = 'ms', label = 'Live map refresh' },
        } },
        { id = 'display', label = 'Display size', settings = {
            { key = 'UI.defaultScale', type = 'number', min = 0.5, max = 2, step = 0.05, label = 'Default size (1 = 100%)',
              help = 'For players who never picked their own (pause menu > Settings > MDT, the Aa button, /mdtscale).' },
            { key = 'UI.minScale', type = 'number', min = 0.5, max = 1, step = 0.05, label = 'Smallest a player may pick' },
            { key = 'UI.maxScale', type = 'number', min = 1, max = 2, step = 0.05, label = 'Largest a player may pick' },
        } },
        { id = 'start', label = 'Commands and keys (restart)', settings = {
            restart({ key = 'Command', type = 'string', maxLen = 32, pattern = '^[%w_]+$', patternWhy = 'a command name', label = 'MDT command' }),
            restart({ key = 'Key', type = 'string', maxLen = 20, pattern = '^[%w_]+$', patternWhy = 'a key name, e.g. F6',
              label = 'MDT key (default)', help = 'Players rebind it in GTA Settings > Key Bindings > FiveM.' }),
            restart({ key = D .. 'emergency', type = 'string', maxLen = 20, pattern = '^[%w_]+$', patternWhy = 'a command name', label = '911 command' }),
            restart({ key = D .. 'nonEmergency', type = 'string', maxLen = 20, pattern = '^[%w_]+$', patternWhy = 'a command name', label = '311 command' }),
            restart({ key = D .. 'medical', type = 'string', maxLen = 20, minLen = 0, nullable = true, pattern = '^[%w_]*$', patternWhy = 'a command name',
              label = 'Medical line command', help = 'e.g. ems. Empty = off.' }),
            restart({ key = D .. 'chatSuggestions', type = 'bool', label = 'Show the commands in chat suggestions' }),
            restart({ key = 'Panic.command', type = 'string', maxLen = 20, pattern = '^[%w_]+$', patternWhy = 'a command name', label = 'Panic command' }),
            restart({ key = 'Panic.key', type = 'string', maxLen = 20, pattern = '^[%w_]+$', patternWhy = 'a key name, e.g. END',
              label = 'Panic key (default)' }),
            restart({ key = D .. 'backup.command', type = 'string', maxLen = 20, pattern = '^[%w_]+$', patternWhy = 'a command name', label = 'Backup command' }),
            restart({ key = D .. 'board.command', type = 'string', maxLen = 20, pattern = '^[%w_]+$', patternWhy = 'a command name', label = 'Call board command' }),
            restart({ key = D .. 'board.key', type = 'string', maxLen = 20, pattern = '^[%w_]+$', patternWhy = 'a key name, e.g. O',
              label = 'Call board key (default)', help = 'A key change reaches only players who never rebound it (FiveM keeps their own).' }),
            restart({ key = 'Suite.DevTools', type = 'bool', label = 'Staff test tools (/dojtest, /ftotest, MDT test data)',
              help = 'Off on a live server.' }),
        } },
    },
})
