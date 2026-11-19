local _ENV = ESAPP('mdt'); -- es_mdt 2.0.8: the MDT's settings page in /whip > Settings > MDT (Whip.configPage)
-- mdt/config.lua stays the defaults: a fresh install works as before, and what an admin saves on the page is written over
-- Config on both sides as the resource starts and the moment it is changed. apply = 'restart': saved now, used from the
-- next restart (commands, keys, chat suggestions are registered once at start). Keys stay in GTA Settings > Key Bindings >
-- FiveM for each player; the page holds their DEFAULTS only.
if not (Whip and Whip.configPage) then return end

-- The page's root: Config (the MDT part's), plus `Suite` for EsSuite (shared/suite.lua). Reads and writes go straight
-- through to Config, so 'Dispatch.cooldownSec' is Config.Dispatch.cooldownSec.
-- 2.0.10: the Departments and DOJ parts' own Config tables too ('Dept.Health.note', 'Doj.Fees.appeal'), so their simple
-- settings live on this one page (WHIP gives a resource one page). Ranks, permissions, rosters, hiring, colours, logos and
-- the health view stay in /departments: they belong to one department each, not to the server.
local DEPT = (ESPART('departments') or {}).Config
local DOJC = (ESPART('doj') or {}).Config
-- a value config.lua leaves nil has no default to capture: give it its "off" value (0 = the top rank, as nil was)
if DEPT and DEPT.Health and DEPT.Health.headLevel == nil then DEPT.Health.headLevel = 0 end
local ROOT = setmetatable({ Suite = EsSuite, Dept = DEPT, Doj = DOJC }, {
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
        } },
        -- 2.0.9
        { id = 'follow', label = 'Backup and panic follow the officer', settings = {
            { key = D .. 'follow.backup', type = 'bool', label = 'A backup call follows the officer who asked',
              help = 'Its blip, GPS routes and the spot units arrive at move with them until the call closes or they go off duty.' },
            { key = D .. 'follow.panic', type = 'bool', label = 'A panic call follows the officer too' },
            { key = D .. 'follow.seconds', type = 'int', min = 2, max = 30, unit = 's', label = 'Read their position every',
              help = 'The server reads it itself.' },
            { key = D .. 'follow.minMove', type = 'int', min = 1, max = 200, unit = 'm', label = 'Move the call once they have moved' },
            { key = D .. 'follow.gpsSeconds', type = 'int', min = 3, max = 120, unit = 's', label = "Responders' GPS moves at most every",
              help = 'Only while their waypoint still points at the call. One they set somewhere else is never touched.' },
            { key = D .. 'follow.gpsMove', type = 'int', min = 10, max = 500, unit = 'm', label = "Move responders' GPS once the officer is this far from it" },
            { key = D .. 'follow.responders', type = 'bool', label = 'The officer sees a marker for each unit responding',
              help = 'On their own map only, live, until that unit arrives or the call ends.' },
            { key = D .. 'follow.arriveDistance', type = 'int', min = 5, max = 300, unit = 'm', label = 'A responding unit has arrived within',
              shownWhen = on(D .. 'follow.responders') },
        } },
        { id = 'livemap', label = 'Live map', settings = {
            { key = 'LiveMap.enabled', type = 'bool', label = 'Live map tab in the MDT', help = 'Admins always have it.' },
            { key = 'LiveMap.units', type = 'enum', label = 'Officers see the units of', options = {
                { value = 'group', label = 'Their dispatch group (police, sheriff and state police together; EMS)' },
                { value = 'own', label = 'Their own department only' }, { value = 'all', label = 'Every department on duty' } },
              shownWhen = on('LiveMap.enabled') },
            { key = 'LiveMap.calls', type = 'bool', label = 'Show active calls', help = 'The ones their Dispatch tab lists.', shownWhen = on('LiveMap.enabled') },
            { key = 'LiveMap.bolos', type = 'bool', label = 'Show where BOLO plates were last read', shownWhen = on('LiveMap.enabled') },
            { key = 'LiveMap.showSpeed', type = 'bool', label = "Show units' speed in a vehicle", shownWhen = on('LiveMap.enabled') },
            { key = 'MapRefreshMs', type = 'int', min = 1000, max = 30000, step = 500, unit = 'ms', label = 'Refresh every',
              help = 'Only while an officer has the tab open.', shownWhen = on('LiveMap.enabled') },
            { key = 'LiveMap.image', type = 'string', maxLen = 200, label = 'Map picture',
              help = 'img/map.webp (GTA V\'s map), a file in es_mdt/html/mdt/img, or an https:// link. 4096 x 4096, the same layout.',
              shownWhen = on('LiveMap.enabled') },
        } },
        -- 2.0.10: Departments (moved from departments/config.lua; it stays the defaults)
        { id = 'dept_activity', label = 'Departments: activity', settings = {
            { key = 'Dept.Health.note', type = 'int', min = 1, max = 365, unit = 'days', label = 'Inactive: yellow note after',
              help = 'Off duty MORE than this many days. Leaders see it in the MDT; leave (LOA) pauses the clock.' },
            { key = 'Dept.Health.warn', type = 'int', min = 1, max = 365, unit = 'days', label = 'Inactive: orange warning after' },
            { key = 'Dept.Health.act', type = 'int', min = 1, max = 365, unit = 'days', label = 'Inactive: red, an admin should step in, from',
              help = 'Keep them in order: note < warning < red.' },
            { key = 'Dept.Health.headLevel', type = 'int', min = 0, max = 100, label = 'Who counts as a department head: rank level from',
              help = '0 = the top rank of each department (and the job owner). Heads past a line are flagged to admins.' },
            { key = 'Dept.Health.adminNotes', type = 'bool', label = 'Note it on a head\'s account each time they reach a new level',
              help = 'In the Player Manager.' },
            { key = 'Dept.Health.checkMinutes', type = 'int', min = 5, max = 1440, unit = 'min', label = 'Check the heads every',
              help = 'Online staff hear of anyone who just crossed a line.' },
            { key = 'Dept.Health.heartbeatMinutes', type = 'int', min = 1, max = 60, unit = 'min', label = 'Save duty time every',
              help = 'The most duty time a server crash can lose.' },
        } },
        { id = 'dept_leave', label = 'Departments: leave (LOA)', settings = {
            { key = 'Dept.LOA.maxDays', type = 'int', min = 1, max = 365, unit = 'days', label = 'Longest leave one request may cover' },
            { key = 'Dept.LOA.maxAheadDays', type = 'int', min = 0, max = 365, unit = 'days', label = 'A leave may start up to',
              help = 'Days ahead of today.' },
            { key = 'Dept.LOA.reasonMax', type = 'int', min = 20, max = 2000, unit = 'characters', label = 'Longest reason' },
        } },
        { id = 'dept_training', label = 'Departments: training and certifications', settings = {
            { key = 'Dept.FTO.rideAlongsRequired', type = 'int', min = 0, max = 50, label = 'Ride-alongs a trainee needs',
              help = 'Phases, items, ratings and DOR days are each department\'s own program (MDT > Training > Program).' },
            { key = 'Dept.FTO.checklist', type = 'list', item = { type = 'string', maxLen = 60 }, label = 'Ride-along checklist',
              help = 'Ticked on each ride-along report. Commas between items.' },
            { key = 'Dept.Certs.alertDays', type = 'int', min = 1, max = 180, unit = 'days', label = 'Warn before a certification expires',
              help = 'The officer and their supervisors hear of it.' },
            { key = 'Dept.Certs.gateFto', type = 'bool', label = 'FTOs also need a valid FTO certification', help = 'On top of the FTO permission.' },
            { key = 'Dept.Certs.ftoCert', type = 'string', maxLen = 60, label = 'The FTO certification\'s name', shownWhen = on('Dept.Certs.gateFto') },
        } },
        { id = 'dept_logos', label = 'Departments: logos', settings = {
            { key = 'Dept.LogoMaxSide', type = 'int', min = 64, max = 1024, unit = 'px', label = 'Largest logo (each side)' },
            { key = 'Dept.LogoMaxBytes', type = 'int', min = 16384, max = 2097152, step = 1024, unit = 'bytes', label = 'Largest logo file',
              help = '196608 = 192 KB. Logos are sent to every MDT, so keep them small.' },
        } },
        -- 2.0.10: the DOJ (moved from doj/config.lua; it stays the defaults)
        { id = 'doj_access', label = 'DOJ: access and warrants', settings = {
            { key = 'Doj.LawCanView', type = 'bool', label = 'Police may open the DOJ tablet (read only)',
              help = 'Records, the calendar and the warrants they asked for.' },
            { key = 'Doj.OffDutyReadOnly', type = 'bool', label = 'DOJ members off duty can only read' },
            { key = 'Doj.Warrants.judgeOnly', type = 'bool', label = 'Warrants need a judge\'s signature',
              help = 'Officers request, a judge signs or denies.' },
            { key = 'Doj.Warrants.defaultDays', type = 'int', min = 1, max = 365, unit = 'days', label = 'A signed warrant expires after',
              help = 'When the request named no date.' },
            { key = 'Doj.Warrants.notifyJudges', type = 'bool', label = 'Judges on duty hear of each new request' },
            { key = 'Doj.HearingReminderMinutes', type = 'int', min = 0, max = 240, unit = 'min', label = 'Remind people of a hearing',
              help = 'Minutes before it starts. 0 = no reminder.' },
            { key = 'Doj.NameChange.cooldownDays', type = 'int', min = 0, max = 365, unit = 'days', label = 'One name change per person every' },
            { key = 'Doj.Bar.prefix', type = 'string', maxLen = 6, pattern = '^[%w]+$', patternWhy = 'letters and digits', label = 'Bar number prefix',
              help = 'New bar numbers read e.g. SA-0001.' },
        } },
        { id = 'doj_money', label = 'DOJ: fees, bail and sentences', settings = {
            { key = 'Doj.Fees.filing', type = 'int', min = 0, max = 1000000, unit = '$', label = 'Filing a civil case (portal)', help = '0 = free.' },
            { key = 'Doj.Fees.nameChange', type = 'int', min = 0, max = 1000000, unit = '$', label = 'Name change' },
            { key = 'Doj.Fees.businessLicense', type = 'int', min = 0, max = 1000000, unit = '$', label = 'Business license' },
            { key = 'Doj.Fees.businessYears', type = 'int', min = 0, max = 50, unit = 'year(s)', label = 'A business license lasts', help = '0 = no expiry.' },
            { key = 'Doj.Fees.expungement', type = 'int', min = 0, max = 1000000, unit = '$', label = 'Expungement' },
            { key = 'Doj.Fees.appeal', type = 'int', min = 0, max = 1000000, unit = '$', label = 'Appeal' },
            { key = 'Doj.Fees.record', type = 'int', min = 0, max = 1000000, unit = '$', label = 'A copy of a court record' },
            { key = 'Doj.Fees.dueDays', type = 'int', min = 0, max = 365, unit = 'days', label = 'Court fines are due in',
              help = 'Unpaid after that: an MDT warrant. 0 = never.' },
            { key = 'Doj.Fees.toDepartment', type = 'bool', label = 'Court money goes to the DOJ\'s job account', help = 'Off: to the state.' },
            { key = 'Doj.Bail.max', type = 'int', min = 0, max = 100000000, unit = '$', label = 'Highest bail' },
            { key = 'Doj.Bail.bondPercent', type = 'int', min = 1, max = 100, unit = '%', label = 'A bail bond costs' },
            { key = 'Doj.Sentence.maxFine', type = 'int', min = 0, max = 100000000, unit = '$', label = 'Largest court fine' },
            { key = 'Doj.Sentence.maxMonths', type = 'int', min = 0, max = 10000, unit = 'months', label = 'Longest sentence' },
            { key = 'Doj.Sentence.maxService', type = 'int', min = 0, max = 1000, unit = 'tasks', label = 'Most community service' },
            { key = 'Doj.Sentence.maxProbationDays', type = 'int', min = 0, max = 3650, unit = 'days', label = 'Longest probation' },
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
            restart({ key = 'Dept.Command', type = 'string', maxLen = 32, pattern = '^[%w_]+$', patternWhy = 'a command name', label = 'Departments command' }),
            restart({ key = 'Doj.Command', type = 'string', maxLen = 32, pattern = '^[%w_]+$', patternWhy = 'a command name', label = 'DOJ tablet command' }),
            restart({ key = 'Doj.Key', type = 'string', maxLen = 20, minLen = 0, nullable = true, pattern = '^[%w_]*$', patternWhy = 'a key name, e.g. F7',
              label = 'DOJ tablet key (default)', help = 'Empty = none (players can still bind one).' }),
            restart({ key = 'Doj.PortalCommand', type = 'string', maxLen = 32, pattern = '^[%w_]+$', patternWhy = 'a command name', label = 'Court portal command' }),
            restart({ key = 'Suite.DevTools', type = 'bool', label = 'Staff test tools (/dojtest, /ftotest, MDT test data)',
              help = 'Off on a live server.' }),
        } },
    },
})
