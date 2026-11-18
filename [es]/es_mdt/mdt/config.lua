local _ENV = ESAPP('mdt'); -- es_mdt settings. Departments, ranks and permissions come from es_departments (/departments).
Config = Config or {}

Config.Command = 'mdt'          -- /mdt
Config.Key     = 'F6'           -- default key (players can change it in GTA Settings > Key Bindings > FiveM)
Config.OffDutyReadOnly = true   -- off duty: the MDT opens, but nothing can be written
Config.FineToDepartment = true  -- fines go into the issuing department's job account (unpaid stays owing)
Config.FineMax = 1000000
Config.SearchLimit = 25

-- Officers may change the fine and jail time of each charge on a report: from 0 up to the penal code's
-- amount times these (1.0 = never above the penal code; 1.5 = up to 50% more). Every change is logged on the report.
Config.ChargeOverride = { maxFineMult = 1.0, maxMonthsMult = 1.0 }

-- Reports: officers with edit rights (the author, supervisors, high command) can still edit a filed report, and
-- every edit is logged on it (who, when, what changed: old -> new) with the previous version kept in full.
-- Deleting a report is high command only: rank level at or above this (Captain / Undersheriff / Major = 80,
-- Chief / Sheriff / Colonel = 100), or an admin. The deleted report is kept in es_mdt_report_audit.
Config.HighCommandLevel = 80

-- A fine still unpaid after this many days gets an automatic warrant ("Failure to pay"). 0 = never.
-- The warrant closes by itself when the fine is paid or voided.
Config.UnpaidFineWarrantDays = 3

-- 1.3.6: an active warrant posts BOLOs by itself (closed again when the warrant is served, voided or expires).
-- A BOLO that already covers the person or plate is not posted twice. The plate reader treats these like any vehicle BOLO.
Config.WarrantBolos = {
    enabled          = true,
    person           = true,   -- a person BOLO for the suspect
    vehicles         = true,   -- a vehicle BOLO for each car they own
    maxVehicles      = 10,
    autoFineWarrants = true,   -- also for the automatic unpaid-fine warrants
}
Config.UnpaidFineCheckMinutes = 10

-- The character holds a tablet while the MDT is open (not in a vehicle: there it just opens).
-- flag 49 = loop, upper body only, still able to move. bone 28422 = right hand (PH_R_Hand).
Config.Tablet = {
    enabled = true,
    prop    = 'prop_cs_tablet',
    dict    = 'amb@code_human_in_bus_passenger_idles@female@tablet@base',
    anim    = 'base',
    flag    = 49,
    bone    = 28422,
    offset  = { x = -0.05, y = 0.0, z = 0.0 },
    rot     = { x = 0.0, y = 0.0, z = 0.0 },
}

-- Weapons (whip_gunny guns: every gun already carries a 12-character serial in its item metadata).
-- 1.8.0: firearm permits. The permit is the weapon license of this type (Weapons & licenses on a person). Law enforcement
-- members get one on hire; civilians apply at a desk below (or /permit) and someone with permits_manage (or the DOJ) decides.
Config.Permits = {
    enabled = true,
    type = 'Firearm',                 -- one of Config.Weapons.licenseTypes
    label = 'Firearm permit',
    fee = 500,                        -- taken from the applicant's bank when approved (0 = free)
    feeToDepartment = true,           -- into the approving officer's department account
    autoOnHire = true,                -- police / sheriff / state members get one when hired (and current members at start)
    autoDeptTypes = { 'police', 'sheriff', 'state' },
    revokeAutoOnFire = true,          -- the department-issued permit ends when they leave every law department
    autoOverridesSuspension = false,  -- a suspended permit stays suspended when they are hired
    recentArrestDays = 30,            -- background check: arrests this recent are flagged
    reapplyDays = 1,                  -- wait after a denial
    reasonMin = 10,
    requirePhoto = true,              -- applicants add a photo of themselves; on approval it becomes their MDT photo
    decideLevel = 60,                 -- approve / deny needs permits_manage AND this rank level (60 = Sergeant); lower ranks only view
    command = true,                   -- /permit works anywhere (apply / status); false = front desks only
    desks = {
        { label = 'MRPD front desk', coords = vector3(441.07, -981.95, 30.69) },
    },
}

Config.Weapons = {
    -- Put a gun in the registry by itself, owned by the character who got it, the moment it is new to the registry:
    autoRegisterShops = true,     -- bought in a shop (whip_core:shop:purchased)
    autoRegisterGiven = true,     -- given by a script or an admin (whip_core:item:added with "by <resource>")
    autoRegisterSkip = {},        -- resources whose gives never register (a black-market script): { 'my_blackmarket' }
    includeMelee = false,         -- knives, bats... (they carry serials too) in the registry as well
    boloOnStolen = true,          -- marking a weapon stolen posts a weapon BOLO (closed again when it is returned)
    boloHours = 0,                -- how long that BOLO lasts (0 = until closed)
    licenseTypes = { 'Firearm', 'Concealed carry', 'Hunting' },
}

Config.UnitStatuses = {
    { key = 'available', label = '10-8 Available', color = '#3ecf8e' },
    { key = 'busy',      label = '10-6 Busy',      color = '#f5a623' },
    { key = 'enroute',   label = 'En route',       color = '#4aa8ff' },
    { key = 'scene',     label = 'On scene',       color = '#b07cff' },
    { key = 'break',     label = '10-7 Break',     color = '#8a93a6' },
}

Config.ReportTypes = {
    { key = 'incident', label = 'Incident' },
    { key = 'arrest',   label = 'Arrest' },
    { key = 'citation', label = 'Citation' },
    { key = 'traffic',  label = 'Traffic' },
}

Config.PersonFlags  = { 'Armed', 'Dangerous', 'Gang affiliated', 'Mental health', 'Parole', 'Probation', 'Flight risk' }
Config.VehicleFlags = { 'Stolen', 'Wanted', 'Impounded', 'No insurance', 'Unregistered' }

-- Starter penal code (seeded once; edit it in the MDT's Penal code tab as an admin)
Config.PenalSeed = {
    -- infractions
    { 'I-101', 'Speeding (1-15 over)',              'infraction',  150,  0 },
    { 'I-102', 'Speeding (16-30 over)',             'infraction',  300,  0 },
    { 'I-103', 'Speeding (31+ over)',               'infraction',  600,  0 },
    { 'I-104', 'Running a red light / stop sign',   'infraction',  200,  0 },
    { 'I-105', 'Illegal parking',                   'infraction',  100,  0 },
    { 'I-106', 'Failure to yield',                  'infraction',  200,  0 },
    { 'I-107', 'Driving without headlights',        'infraction',  100,  0 },
    { 'I-108', 'Unroadworthy vehicle',              'infraction',  250,  0 },
    { 'I-109', 'Jaywalking',                        'infraction',   75,  0 },
    { 'I-110', 'Littering',                         'infraction',  100,  0 },
    -- misdemeanors
    { 'M-201', 'Reckless driving',                  'misdemeanor', 750, 10 },
    { 'M-202', 'Driving without a license',         'misdemeanor', 500,  5 },
    { 'M-203', 'Evading (on foot)',                 'misdemeanor', 500, 10 },
    { 'M-204', 'Trespassing',                       'misdemeanor', 400,  5 },
    { 'M-205', 'Disorderly conduct',                'misdemeanor', 350,  5 },
    { 'M-206', 'Public intoxication',               'misdemeanor', 300,  5 },
    { 'M-207', 'Petty theft',                       'misdemeanor', 500, 10 },
    { 'M-208', 'Vandalism',                         'misdemeanor', 600, 10 },
    { 'M-209', 'Simple assault',                    'misdemeanor', 800, 15 },
    { 'M-210', 'Obstruction of justice',            'misdemeanor', 800, 15 },
    { 'M-211', 'Resisting arrest',                  'misdemeanor', 900, 15 },
    { 'M-212', 'Possession of a controlled substance', 'misdemeanor', 750, 10 },
    { 'M-213', 'Brandishing a weapon',              'misdemeanor', 1000, 15 },
    { 'M-214', 'False report to police',            'misdemeanor', 600, 10 },
    { 'M-215', 'Harassment',                        'misdemeanor', 600, 10 },
    -- felonies
    { 'F-301', 'Evading in a vehicle',              'felony',     2500, 25 },
    { 'F-302', 'Driving under the influence',       'felony',     2000, 20 },
    { 'F-303', 'Grand theft auto',                  'felony',     3000, 30 },
    { 'F-304', 'Burglary',                          'felony',     3000, 30 },
    { 'F-305', 'Robbery',                           'felony',     4000, 40 },
    { 'F-306', 'Armed robbery',                     'felony',     6000, 60 },
    { 'F-307', 'Aggravated assault',                'felony',     5000, 45 },
    { 'F-308', 'Assault on a public servant',       'felony',     6000, 50 },
    { 'F-309', 'Possession with intent to sell',    'felony',     4000, 40 },
    { 'F-310', 'Weapons trafficking',               'felony',     8000, 60 },
    { 'F-311', 'Unlicensed firearm',                'felony',     3000, 25 },
    { 'F-312', 'Kidnapping',                        'felony',    10000, 80 },
    { 'F-313', 'Attempted murder',                  'felony',    15000, 100 },
    { 'F-314', 'Murder',                            'felony',    25000, 150 },
    { 'F-315', 'Bank robbery',                      'felony',    12000, 90 },
}

-- ---------------------------------------------------------------- 1.3.0: dispatch, panic, map, mugshots, arrest, radar

-- 911 / 311: any player can call. The caller's position comes from the server; the street name from their game.
Config.Dispatch = {
    emergency    = '911',   -- /911 <what happened>
    nonEmergency = '311',   -- /311 <what happened>
    cooldownSec  = 30,      -- one call per player this often
    callTTLMin   = 120,     -- an active call nobody closed is closed by itself after this many minutes (0 = never)
    blip         = { sprite = 280, color = 1, seconds = 120 },   -- new-call blip for on-duty officers
    outcomes     = { 'Resolved', 'Report filed', 'Arrest made', 'Citation issued', 'Unfounded', 'Gone on arrival', 'Referred' },
    -- 1.3.2: on-screen call card for officers on duty (not while the MDT is open, it shows calls itself).
    -- Keys are defaults only: each player can rebind them in GTA Settings > Key Bindings > FiveM.
    popup = {
        enabled    = true,
        seconds    = 15,          -- a card hides by itself after this long (it can be brought back)
        panicSeconds = 30,        -- panic cards stay up longer
        sound      = true,
        keep       = 6,           -- how many recent calls /calls can bring back
        attendKey  = 'E',         -- respond to the call on screen: attach your unit and set GPS (only while a card shows)
        dismissKey = 'DELETE',    -- hide the card (the next queued call shows)
        recallKey  = '',          -- bring the latest call back ('' = unbound, /calls always works)
        detachKey  = '',          -- leave the call you are on ('' = unbound, /detach always works)
        recallCommand = 'calls',
        detachCommand = 'detach',
    },
    -- 1.3.5: the unit's status follows its call (Config.UnitStatuses keys 'enroute', 'scene', 'available')
    autoStatus = {
        enroute      = true,   -- attaching (E on the card, the Dispatch tab, /calls) sets the unit, and partner, En route
        arrive       = true,   -- within arriveRadius of the call: On scene, a call note, GPS cleared
        arriveRadius = 40,     -- metres
        clearOnLeave = true,   -- detaching or the call closing puts En route / On scene units back to Available
    },
    -- 2.0.1: the es_mdt:server:externalCall net event (client scripts filing a call; server scripts use exports.es_mdt:AddCall)
    external = {
        enabled     = true,
        onDuty      = true,     -- a player on duty in any department may send it
        jobs        = {},       -- and/or players in these WHIP jobs, on duty or not, e.g. { 'tow', 'security' }
        kinds       = { '911', '311', 'alert', 'officer' },   -- a 'panic' is always refused (the panic button does that)
        cooldownSec = 10,       -- one call per player this often
        perMinute   = 5,        -- and at most this many a minute
    },
}

-- Display size of the MDT, Departments and DOJ pages (2.0.2). Each player picks their own with the Aa button in a
-- page's header or /mdtscale <percent>; it is saved on their PC. This is the size for players who never picked one.
Config.UI = {
    defaultScale = 1.0,     -- 1.0 = 100%
    minScale     = 0.7,     -- the smallest a player may pick (0.5 at the least)
    maxScale     = 1.5,     -- the largest (2.0 at the most)
}

-- Panic button: any on-duty officer. Key (players can rebind it in GTA Settings > Key Bindings > FiveM).
Config.Panic = {
    command  = 'panic',     -- /panic (also the MDT's red button)
    key      = '',          -- default key; '' = unbound until the player picks one
    seconds  = 90,          -- blip flashes and the unit card stays red this long
    cooldown = 15,
    blip     = { sprite = 161, color = 1 },
}

-- Live map (Active units > Map): positions refresh this often while an officer looks at it
Config.MapRefreshMs = 3000

-- Mugshots: a picture from the officer's own game, through a camera aimed at the suspect's face (WHIP RequestScreenshot).
-- Or a link to a public picture (http/https, jpg/png/webp, 2 MB at most).
Config.Mugshots = { range = 6.0, width = 1280, quality = 0.82, storeBytes = 700 * 1024 }   -- a link may be up to 2 MB; what is kept up to storeBytes

-- Arrest flow: "Send to jail" calls this export when that resource is running: exports[resource][fn](charId, months, reportId)
-- 2.0.0: the jail bridge. Send to jail, the Jail tab, releases and escape warrants work with any jail script.
--   provider = 'auto'     a jail script that registered itself (exports.es_mdt:RegisterJailProvider), else es_jail
--                         when it runs, else `custom` when its resource runs, else none
--            = 'es_jail' | 'custom' | 'none' | '<resource>' (a registered one by name)
-- With none, Send to jail still records the sentence in the MDT (Jail tab) and fires the server event
-- 'es_mdt:jail:sent'. See README.md, "Jail integration for developers".
Config.Jail = {
    provider = 'auto',
    recordMinutesPerMonth = 1,   -- with no jail script: the MDT counts the time itself, this many real minutes per month
    -- A jail script reached through its own exports, no code needed. Example (fill in for your script):
    custom = nil,
    -- custom = {
    --     resource = 'my_jail', label = 'My Jail',
    --     target = 'source',          -- what its exports take: 'source' (server id, player must be online) or 'charId'
    --     timeUnit = 'minutes',       -- what its time is in: 'months' | 'minutes' | 'seconds'
    --     minutesPerMonth = 1,        -- one MDT month = this many minutes
    --     jail     = { export = 'JailPlayer',   args = { 'target', 'time', 'reason' } },
    --     release  = { export = 'UnjailPlayer', args = { 'target' } },        -- optional
    --     isJailed = { export = 'IsJailed',     args = { 'target' } },        -- optional
    --     -- arg names: target, charId, source, time, months, minutes, seconds, reason, reportId, officerCharId, officerSource
    -- },
}

-- Report templates every department has (leaders add their own in the MDT)
Config.ReportTemplates = {
    { key = 'traffic', name = 'Traffic stop', type = 'traffic', title = 'Traffic stop: ',
      body = 'REASON FOR STOP:\n\nVEHICLE (plate, model, colour):\n\nDRIVER / OCCUPANTS:\n\nOBSERVATIONS:\n\nACTION TAKEN (warning / citation / arrest):\n' },
    { key = 'dui', name = 'DUI', type = 'arrest', title = 'DUI arrest: ',
      body = 'REASON FOR STOP:\n\nSIGNS OF IMPAIRMENT (odour, speech, eyes, balance):\n\nFIELD SOBRIETY TESTS:\n\nBREATH / BLOOD RESULT:\n\nMIRANDA READ: yes / no\n\nVEHICLE DISPOSITION (towed / released):\n' },
    { key = 'pursuit', name = 'Pursuit', type = 'incident', title = 'Vehicle pursuit: ',
      body = 'START (time, location, reason):\n\nROUTE AND SPEEDS:\n\nUNITS INVOLVED:\n\nTACTICS USED (PIT, spike strips, box-in):\n\nEND (location, how it ended):\n\nDAMAGE / INJURIES:\n' },
    { key = 'arrest', name = 'Arrest', type = 'arrest', title = 'Arrest: ',
      body = 'PROBABLE CAUSE:\n\nCIRCUMSTANCES OF ARREST:\n\nSEARCH / ITEMS SEIZED:\n\nMIRANDA READ: yes / no\n\nSTATEMENTS MADE:\n' },
    { key = 'uof', name = 'Use of force', type = 'incident', title = 'Use of force: ',
      body = 'SUBJECT:\n\nLEVEL OF RESISTANCE:\n\nFORCE USED (type, duration):\n\nINJURIES (subject / officers) AND MEDICAL CARE:\n\nWITNESSES / BODYCAM:\n\nSUPERVISOR NOTIFIED:\n' },
}

-- Police radar + plate reader (ALPR), in police vehicles, on duty only.
Config.Radar = {
    units       = 'mph',            -- 'mph' or 'kmh'
    lawTypes    = { police = true, sheriff = true, state = true },   -- department types that get it
    classes     = { [18] = true },  -- vehicle classes (18 = emergency)
    models      = {},               -- or these models too: { 'police', 'police2', 'sheriff' }
    range       = 110.0,            -- metres each antenna sees
    angle       = 18.0,             -- half-width of each antenna's beam, degrees
    plateRange  = 30.0,             -- metres the plate cameras read
    fastLimit   = 70,               -- default fast-limit (in the units above)
    keys = {                        -- defaults; each player can rebind in GTA Settings > Key Bindings > FiveM
        toggle     = 'F5',          -- show / hide the radar
        remote     = 'F7',          -- the remote (settings, locks, last plate hits)
        frontSpeed = 'NUMPAD8',     -- lock / unlock front speeds
        rearSpeed  = 'NUMPAD5',     -- lock / unlock rear speeds
        frontPlate = 'NUMPAD9',     -- lock / unlock the front plate
        rearPlate  = 'NUMPAD6',     -- lock / unlock the rear plate
        reset      = 'NUMPAD0',     -- clear every lock
    },
    -- plate checks: what counts as a hit (unregistered = plates with no owner on file: every NPC car)
    hits = { bolo = 'high', stolen = 'high', warrant = 'high', unregistered = 'low' },   -- 'high' alert, 'low' amber only, false off
    recheckSec  = 60,               -- a plate already checked is not asked again for this long
}

-- 1.5.0: Cases (Records → Cases). Numbers look like C-2026-0001 (prefix, year, running number per year).
-- Opening a case needs "cases_create" (rank 30+ by default), closing / archiving / reopening needs "cases_close" (60+).
Config.Cases = { prefix = 'C' }

-- 1.11.0: optional bridge to the third-party evidence resource "whip_evidence" (it keeps bags / photos / guns, the MDT
-- keeps the case; the MDT case number, e.g. C-2026-0001, is the case ID on their side).
--   enabled = 'auto'  on when whip_evidence exists on the server (default), true = always try, false = completely off.
--   With it off or not installed nothing calls whip_evidence. Works next to es_evidence (its own section).
--   On their side: Config.ApiResources = { 'es_mdt' }, and `ensure whip_evidence` before es_mdt in server.cfg.
Config.WhipEvidence = {
    enabled = 'auto',
    resource = 'whip_evidence',
    photoStoreBytes = 4 * 1024 * 1024,   -- keep our own copy of uploaded photos up to this size (theirs expire outside a case locker)
    cachePhotosOnUpload = true,          -- fetch + keep photo copies right after an upload (else on first view)
    maxUpload = 30,                      -- items per "Add evidence" upload
}
