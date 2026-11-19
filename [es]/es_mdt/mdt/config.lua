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
    emergency    = '911',   -- /911 <what happened>  (street and position are added by themselves)
    nonEmergency = '311',   -- /311 <what happened>
    medical      = '',      -- 2.0.6: a medical-only line, e.g. 'ems' for /ems <what happened> (goes to EMS); '' = off
    cooldownSec  = 30,      -- one call per player this often (911, 311 and the medical line together)
    chatSuggestions = true, -- 2.0.6: /911, /311, /panic, /backup show in the chat's suggestions
    -- 2.0.6: who gets which call. A GROUP is a list of department types (Departments > type); a call goes to the groups
    -- its kind names: their on-duty units get the card, sound and blip, and see it in the MDT's Dispatch tab.
    -- A group with no department on this server is skipped (no EMS / Fire department yet: 911 goes to law only). If no
    -- group is left the call goes to `fallback` (false = to every unit on duty). DOJ is in no group: it gets no calls.
    routing = {
        groups = {
            law = { 'police', 'sheriff', 'state' },
            ems = { 'ems' },
        },
        kinds = {
            ['911']  = { 'law', 'ems' },   -- emergencies: both
            ['311']  = { 'law' },
            medical  = { 'ems' },          -- the medical line, and AddCall({ kind = 'medical' })
            panic    = { 'law', 'ems' },   -- officer down
            backup   = { 'law' },          -- a backup request goes where its call went; this is for one on no call
            shots    = { 'law' },
            theft    = { 'law' },
            officer  = { 'law' },          -- calls an officer logs in the MDT
            alert    = { 'law' },          -- AddCall / NotifyDispatch without a kind (es_jail's break-outs too)
            -- 2.0.7 (a preset's own `groups` wins over these)
            robbery  = { 'law' },
            drugs    = { 'law' },
            explosion = { 'law', 'ems' },
            fight    = { 'law' },
            suspicious = { 'law' },
            down     = { 'ems' },          -- a civilian down: EMS (law when there is no EMS department: `fallback`)
            speeding = { 'law' },
        },
        fallback = 'law',
        shared   = false,   -- true: every group SEES every call in its Dispatch tab (cards, sounds and blips still follow `kinds`)
    },
    -- 2.0.6: a call nobody attached to goes up one priority after this long (P3 -> P2 -> P1), again after as long, never
    -- past `top`, never a panic. The MDT updates quietly; realert = true gives the units it went to one soft tone and its card again.
    escalate = { enabled = true, minutes = 5, top = 1, realert = true },
    -- 2.0.6: "Request backup" (the call in the MDT, or /backup): a backup call at the officer's position, linked to their call.
    -- P1 when the call is a panic or P1, else `priority`. key = default key ('' = unbound; players can rebind it).
    backup = { enabled = true, command = 'backup', key = '', priority = 2, urgentPriority = 1, cooldown = 45,
        -- 2.0.15: asked ON a call, the backup goes onto that call (no new call): "Backup requested" (who, when), the backup
        -- priority, its units alerted again, and a marker that follows the asking officer (`marker`: GTA blip sprite / colour).
        -- false: a separate backup call, as before. Backup asked on no call is always its own call.
        merge = true, marker = { sprite = 1, color = 1, scale = 1.0, flash = true } },
    -- 2.0.9: a backup (and panic) call FOLLOWS the officer who asked: the server reads their position every `seconds`
    -- and moves the call, its blip and its spot (Respond / GPS / arrival) when they have moved `minMove` metres, until the
    -- call closes (or auto-closes) or they go off duty / leave. Units on it get their GPS moved too, at most every
    -- `gpsSeconds` and only once the officer is `gpsMove` metres from where the route points (a waypoint they set
    -- somewhere else is never touched). The officer who asked sees a marker for each unit coming (`responders`), live,
    -- until that unit is `arriveDistance` metres away (or On scene) or the call ends.
    follow = {
        backup = true, panic = true,
        seconds = 4, minMove = 10,
        gpsSeconds = 10, gpsMove = 35,
        responders = true, arriveDistance = 40,
        blip = { sprite = 56, color = 3, scale = 0.85 },   -- the responders' markers (56 = GTA's "cop patrol")
    },
    -- 2.0.6: automatic alerts from the game. On-duty law never sets them off. chance = how often a witness calls it in
    -- (0.0 - 1.0); cooldown = seconds per player; a second report near an active one adds a note to it (area) instead
    -- of a new call. Other scripts: exports.es_mdt:ShotsFired(coords) / VehicleTheft(coords, plate, model) always file.
    -- 2.0.7: fights, explosions, people down and (off by default) speeding too. Every one: a witness call with a search
    -- circle (the exact spot never reaches a game), suspect details the server reads itself, merged into an open call
    -- of the same kind nearby, and at most `perMinute` NEW calls of one kind a minute server-wide (street spam).
    alerts = {
        shots = { enabled = true, chance = 0.7, cooldown = 45, priority = 2, ignoreSuppressed = true },
        theft = { enabled = true, chance = 0.5, cooldown = 90, priority = 3 },   -- locked / hot-wired / jacked cars, not your own
        fight = { enabled = true, chance = 0.6, cooldown = 60, priority = 3, witnesses = 1, witnessRange = 30.0 },   -- melee hits with someone watching
        explosion = { enabled = true, chance = 1.0, cooldown = 60, priority = 1 },   -- grenades, car bombs, rockets ... (not steam, flames, flares, smoke)
        -- ignoreTypes = { 11, 12, 13, ... },   -- GTA explosion types that never count (default: the harmless ones)
        down  = { enabled = true, chance = 1.0, cooldown = 180, priority = 2, delay = 20 },   -- a civilian down this many seconds -> EMS
        -- 2.0.8: speeding is set up in /whip > Settings > MDT too. units 'mph' | 'kmh'; limit: faster than this is speeding;
        -- highwayLimit: the same on a highway (a street named ...Fwy / Hwy / Route ...; 0 = limit everywhere); seconds over it
        -- before a witness calls it in. The alert says e.g. "112 mph in a 80 zone".
        speeding = { enabled = false, units = 'mph', limit = 80, highwayLimit = 110, seconds = 4, cooldown = 120, chance = 0.5, priority = 3,
                     highwayWords = { 'Fwy', 'Freeway', 'Hwy', 'Highway', 'Route', 'Interstate' } },   -- off by default
        area  = { radius = 150, seconds = 120 },   -- one call per this many metres, this often (repeat reports merge into it)
        perMinute = 6,           -- at most this many NEW automatic calls of one kind a minute, server-wide
        searchCircle = true,     -- witness calls show a search area, not the exact spot
        exemptLaw = true,
        quietZones = {   -- no shots alerts here (the Ammu-Nation ranges); { x, y, r = metres }
            { x = 13.5, y = -1097.4, r = 20.0 },
            { x = 821.5, y = -2163.6, r = 20.0 },
        },
        -- ignoreWeapons = { 'WEAPON_STUNGUN', ... },   -- weapons that never count (default: stun gun, extinguisher, cans, flares, balls)
    },
    -- 2.0.7: ready-made alerts for other scripts: exports.es_mdt:StoreRobbery(coords, data), BankRobbery(coords, 'fleeca' |
    -- 'paleto' | 'pacific', data), JewelryRobbery, HouseRobbery, DrugSale, Explosion, Fight, SuspiciousActivity, Carjacking, or
    -- Alert('<preset name>', data) for any of these (and any you add). Each preset:
    --   kind      the call kind (routing and the MDT filter)          priority  1-3       critical  true: above P1 (see `critical`)
    --   title     the card's title                                    icon      an emoji on the card and the board
    --   blip      { sprite, color, scale, seconds }                   groups    who gets it ({ 'law' }, { 'law', 'ems' }); nil = the kind's route
    --   witness   true: a search circle (radius metres), not the exact spot      message   the default text
    --   enabled   false: the export answers "turned off"
    --   place     2.0.8: 'store' | 'bank' | 'jewelry': the call is titled with the place's name (see `places` below)
    presets = {
        store        = { kind = 'robbery', priority = 2, title = 'Store robbery', icon = '🏪', place = 'store', message = 'Store robbery: the alarm was triggered',
                         blip = { sprite = 52, color = 1, scale = 1.0 } },
        bank_fleeca  = { kind = 'robbery', priority = 1, title = 'Fleeca bank robbery', icon = '🏦', place = 'bank', message = 'Bank robbery: the alarm was triggered',
                         blip = { sprite = 108, color = 1, scale = 1.1 } },
        bank_paleto  = { kind = 'robbery', priority = 1, critical = true, title = 'Paleto Bay bank robbery', icon = '🏦', place = 'bank',
                         message = 'Bank robbery: the Blaine County Savings alarm was triggered', blip = { sprite = 108, color = 1, scale = 1.2 } },
        bank_pacific = { kind = 'robbery', priority = 1, critical = true, title = 'Pacific Standard robbery', icon = '🏦', place = 'bank',
                         message = 'Bank robbery: the Pacific Standard vault alarm was triggered', blip = { sprite = 108, color = 1, scale = 1.25 } },
        jewelry      = { kind = 'robbery', priority = 1, title = 'Vangelico jewelry robbery', icon = '💎', place = 'jewelry', message = 'Jewelry robbery: the Vangelico alarm was triggered',
                         blip = { sprite = 617, color = 1, scale = 1.1 } },
        house        = { kind = 'robbery', priority = 2, title = 'House burglary', icon = '🏠', message = 'A neighbour reports a break-in',
                         witness = true, radius = 80, blip = { sprite = 40, color = 1 } },
        drugsale     = { kind = 'drugs', priority = 3, title = 'Suspected drug sale', icon = '💊', message = 'A witness saw what looked like a drug deal',
                         witness = true, radius = 120, blip = { sprite = 51, color = 2 } },
        explosion    = { kind = 'explosion', priority = 1, title = 'Explosion', icon = '💥', message = 'A loud explosion was reported',
                         groups = { 'law', 'ems' }, witness = true, radius = 90, blip = { sprite = 436, color = 1, scale = 1.1 } },
        fight        = { kind = 'fight', priority = 3, title = 'Fight in progress', icon = '👊', message = 'People fighting in the street',
                         witness = true, radius = 90, blip = { sprite = 280, color = 17 } },
        suspicious   = { kind = 'suspicious', priority = 3, title = 'Suspicious activity', icon = '👁', message = 'A witness reports suspicious activity',
                         witness = true, radius = 130, blip = { sprite = 280, color = 5 } },
        carjack      = { kind = 'theft', priority = 2, title = 'Carjacking', icon = '🚗', message = 'A driver was pulled from their car',
                         witness = true, radius = 100, blip = { sprite = 225, color = 47 } },
        -- the automatic alerts use the preset with their own name for title / icon / blip (their priority etc. is in `alerts`)
        shots        = { kind = 'shots', title = 'Shots fired', icon = '🔫', witness = true, blip = { sprite = 110, color = 1 } },
        theft        = { kind = 'theft', title = 'Vehicle theft', icon = '🚙', witness = true, blip = { sprite = 225, color = 47 } },
        down         = { kind = 'down', title = 'Person down', icon = '🚑', witness = true, radius = 60, blip = { sprite = 153, color = 1 } },
        speeding     = { kind = 'speeding', title = 'Reckless driver', icon = '💨', witness = true, radius = 150, blip = { sprite = 225, color = 5 } },
    },
    -- 2.0.8: named places. A robbery preset (place = ...) is titled with the place's name, e.g. "24/7 Supermarket, Innocence Blvd":
    --   1. the caller's own name: data.storeName (or data.label)
    --   2. a store id or number: data.store / data.storeId / data.id, a built-in place id ('247_innocence', 'ltd_grove',
    --      'fleeca_legion', 'vangelico' ... see mdt/server/places.lua) or a key of `ids` below
    --   3. the nearest place of that kind within `radius` metres (banks and Vangelico reach a bit further)
    --   4. else "Store, <street>" ("Bank, ...", "Jewelry store, ...")
    -- ids: your robbery script's store numbers / ids -> a place id or a name, e.g. { [1] = '247_innocence', [2] = 'Corner shop, Grove St' }
    -- extra: your own places, or a built-in one renamed by its id: { id = 'myshop', kind = 'store', name = 'Digital Den, Mirror Park',
    --        coords = vector3(1137.0, -470.0, 66.7), radius = 30 }   (kind: 'store' | 'bank' | 'jewelry'; also in /whip > Settings > MDT)
    places = { radius = 40, ids = {}, extra = {} },
    -- 2.0.7: the CRITICAL tier, above P1: a pulsing card, a flashing blip and its own alarm that repeats every `repeatSeconds`
    -- (at most `maxRepeats` times) until the unit acknowledges it (Respond / Hide on the card, the call board) or a unit
    -- responds (stopOnUnit). Panic is critical (panic = false turns that off); presets set `critical = true`. Escalation
    -- never makes a call critical.
    critical = { enabled = true, panic = true, repeatSeconds = 4, maxRepeats = 8, stopOnUnit = true },
    -- 2.0.7: alert sounds in three tiers (routine, priority = P1, critical). 'nui' plays them in the page, at each player's own
    -- volume (the Aa popover: volume and mute, saved on their PC); 'game' uses GTA's sounds (mute works, volume does not).
    sounds = { engine = 'nui', defaultVolume = 70 },
    -- 2.0.7: a repeat report (same kind, and same preset / title, within `radius` metres while the call is fresh) goes onto
    -- the open call: "x3 reports", a note, a smaller search circle. Panic, backup and officer calls never merge, and a plain
    -- 'alert' (no preset, e.g. es_jail's) only merges when the script passes merge = true.
    merge = { enabled = true, radius = 150, seconds = 180 },   -- kinds = { ['911'] = false } turns one kind off
    -- 2.0.7: the search circle of witness calls: radius in metres; each repeat report shrinks it (x shrink, never under
    -- minRadius). The true spot is always inside it and never leaves the server.
    witness = { enabled = true, radius = 120, minRadius = 40, shrink = 0.75 },
    -- 2.0.7: the quick call board: the active calls in a compact overlay (respond / waypoint / attach), MDT closed.
    -- key = the default only (each player can rebind it under GTA Settings > Key Bindings > FiveM). Pick a key your other
    -- scripts do not use; O is free on a stock WHIP server with es_mdt.
    board = { enabled = true, command = 'callboard', key = 'O', limit = 25 },
    -- 2.0.7: call retention. CLOSED calls older than this many days are deleted with their notes and unit rows, at start
    -- and once a day, in small batches. Never an open call, never a call linked to a report, warrant or case (link one in
    -- the call's page, or exports.es_mdt:LinkCall). 0 = keep every call forever.
    keepClosedDays = 90,
    -- 2.0.4: auto-close. An active call is closed by itself, silently (no popup, sound or toast; the blip and GPS go and the
    -- call stays in the call history), once it is this old:
    autoCloseMinutes  = 15,     -- minutes after the call came in (0 = never)
    autoCloseAttached = false,  -- false: a call with a unit attached right now is left open (it is being worked); true: closed too
    callTTLMin   = 120,         -- hard cap: a call with units attached is still closed after this many minutes (0 = never).
                                -- A PANIC call with a unit attached is never auto-closed, whatever these say.
    sweepSeconds = 60,          -- how often the server looks for calls to auto-close
    -- Outcome: 'Auto-closed – no response' when no unit ever attached, 'Auto-closed (timeout)' when one did (even if it left).
    blip         = { sprite = 280, color = 1, seconds = 120, areas = true },   -- new-call blip for on-duty officers (2.0.14 areas: a witness call's search circle stays on the GTA map until the call closes)
    -- 2.0.4: what an officer picks when closing a call. color = the badge (hex); note = 'required' makes the note mandatory.
    outcomes     = {
        { label = 'Resolved',         color = '#22c55e', icon = '✔' },
        { label = 'Handled on scene', color = '#14b8a6', icon = '⚑' },
        { label = 'Unfounded',        color = '#6b7fd7', icon = '∅' },
        { label = 'No contact',       color = '#f59e0b', icon = '☏' },
        { label = 'Suspect gone',     color = '#f97316', icon = '➜' },
        { label = 'Other',            color = '#a855f7', icon = '✎', note = 'required' },
    },
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
-- 2.0.4: department announcements (Dashboard). Priority: Normal, Important or Urgent (red, a toast for everyone on duty).
Config.Announcements = {
    urgentFreshHours = 12,  -- an urgent one posted this recently is shown to an on-duty member when they open the MDT (once; 0 = off)
}

Config.UI = {
    defaultScale = 1.0,     -- 1.0 = 100%
    minScale     = 0.7,     -- the smallest a player may pick (0.5 at the least)
    maxScale     = 1.5,     -- the largest (2.0 at the most)
}

-- 2.0.13: controller (gamepad) support, matching WHIP's own menus. The buttons are WHIP's (RegisterPadAction): LB + Y, LB +
-- D-pad. Players move them in the pause menu's Controller screen, and turn es_mdt's controller help on or off, set the stick
-- speed and the button pictures under Settings > Server Settings > Controller. Every value here changes live (/whip > Settings > MDT).
Config.Controller = {
    enabled    = true,      -- off: no es_mdt buttons on the controller, and its screens are mouse only (as before 2.0.13)
    buttons    = true,      -- the MDT, panic, respond / dismiss, backup and the call board on WHIP's LB combos
    navigation = true,      -- the D-pad / left stick moves a highlight in every es_mdt screen; A picks, B goes back, LB / RB tabs
    keyboard   = true,      -- A on a text box opens WHIP's on-screen keyboard (pad players only)
    hints      = true,      -- button hints at the bottom of each screen (controller pictures on a pad, keys on a keyboard)
    panicHoldMs   = 1500,   -- LB + D-Up must be held this long to send a panic (no accidental panics)
    dismissHoldMs = 600,    -- LB + D-Left: a tap responds to the call card, held this long it hides the card
    remoteHoldMs  = 600,    -- LB + D-Down: a tap opens the call board, held this long in a radar car it opens the radar remote
}

-- Panic button: any on-duty officer. Key (players can rebind it in GTA Settings > Key Bindings > FiveM).
Config.Panic = {
    command  = 'panic',     -- /panic (also the MDT's red button)
    -- 2.0.6: a key by default. It works while the officer is down or dead (no health / death check; key mappings still fire
    -- under the death screen). END was picked because nothing else on the server uses it (F9 is whip_core's editor key).
    key      = 'END',       -- '' = unbound until the player picks one
    keyCommand = 'mdt_panic_key',   -- the key mapping's id (a new one, so the default reaches players who had the old unbound one)
    title    = 'OFFICER DOWN',      -- the P1 call's title: 'OFFICER DOWN · 1-A-12 Jane Doe'
    seconds  = 90,          -- blip flashes and the unit card stays red this long
    cooldown = 15,
    blip     = { sprite = 161, color = 1 },
}

-- Live map (MDT > Live map): positions refresh this often, only while an officer has the tab open
Config.MapRefreshMs = 2500

-- 2.0.9: the Live map tab. Calls follow the Dispatch tab's routing (an officer sees the calls their MDT lists).
--   units: whose positions an officer sees: 'group' = their dispatch group (police, sheriff and state police see each
--          other; EMS sees EMS), 'own' = their own department only, 'all' = every unit on duty. Admins see everyone.
--   image: the map picture. The default (img/map.webp) is GTA V's own map, which belongs to Rockstar Games (see
--          html/mdt/img/NOTICE.md). Any 4096 x 4096 picture of the same layout works: a file in this resource or
--          an https:// link.
Config.LiveMap = {
    enabled = true,
    units = 'group',
    calls = true,
    bolos = true,
    showSpeed = true,
    image = 'img/map.webp',
}

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
-- 2.0.11: every value here is also in /whip > Settings > MDT > Radar (live). Each player sets their own volume, mute,
-- size, position, units, auto-on, lock sound and speed alert in the pause menu: Settings > Server Settings > Radar.
Config.Radar = {
    enabled     = true,             -- 2.0.11: false = no radar in any vehicle
    units       = 'mph',            -- 'mph' or 'kmh' (the default; each player may pick their own)
    lawTypeList = { 'police', 'sheriff', 'state' },   -- 2.0.11: department types that get it (see departments/config.lua Types)
    lawTypes    = { police = true, sheriff = true, state = true },   -- (before 2.0.11; used only when lawTypeList is nil)
    classList   = { 18 },           -- 2.0.11: vehicle classes it runs in (18 = emergency)
    classes     = { [18] = true },  -- (before 2.0.11; used only when classList is nil)
    models      = {},               -- or these models too: { 'police', 'police2', 'sheriff' }
    scanMs      = 250,              -- 2.0.11: how often it measures while moving (ms)
    parkedScanMs = 500,             -- 2.0.11: ... and while parked
    hitSound    = true,             -- 2.0.11: the alarm on a plate hit (BOLO / stolen / warrant)
    autoLockAllowed = true,         -- 2.0.11: players may turn on auto-lock over their speed alert
    keepHitsDays = 30,              -- 2.0.11: plate hits are kept this many days (0 = forever)
    range       = 110.0,            -- metres each antenna sees
    angle       = 18.0,             -- half-width of each antenna's beam, degrees
    plateRange  = 30.0,             -- metres the plate cameras read
    fastLimit   = 70,               -- default speed alert (fast limit), in the units above; each player may set their own
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
    hits = { bolo = 'high', stolen = 'high', warrant = 'high', unregistered = 'low' },   -- 'high' alert, 'low' amber only, 'off' (or false) off
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

-- ---------------------------------------------------------------- 2.1.0: tickets, invoices, contests, impound
-- Every setting below is also on /whip > Settings > MDT (Tickets, Invoices, Impound, Owner texts): what an admin saves
-- there is written over these defaults.

-- Invoices: every police fine (roadside tickets AND fines from reports) is sent as an invoice instead of being taken
-- from the bank at once. It is due after `dueDays`; they pay it in the court portal (/court: bank or cash), or on the
-- due day it is taken from their default bank account (autoCollect). Still unpaid then, Config.UnpaidFineWarrantDays
-- after the due day an automatic "failure to pay" warrant follows (as before). enabled = false: the old way (taken at once).
Config.Invoices = {
    enabled       = true,
    dueDays       = 3,
    autoCollect   = true,     -- take it from their bank on the due day (when the account holds enough)
    reminderHours = 24,       -- a text this many hours before it is due (0 = none)
    checkMinutes  = 5,        -- how often due invoices are looked at
}

-- Roadside tickets: /ticket (or the controller button the player sets) opens a ticket form without the MDT. The officer
-- picks the person (or, for a parking ticket, the vehicle) from who and what is actually close, the charges from the
-- penal code, and the recipient is asked to sign. Signing = accepting (pay it); refusing (or no answer, or logging off)
-- files it UNSIGNED, and an unsigned ticket may be contested in the court portal (when `contests` is on).
Config.Tickets = {
    enabled          = true,
    command          = 'ticket',
    range            = 12.0,          -- people and vehicles this close show in the lists
    categories       = { 'infraction', 'misdemeanor' },   -- penal code categories a ticket can hold
    maxCharges       = 6,
    signSeconds      = 45,            -- the recipient has this long to sign
    paper            = true,          -- both sides get a paper copy (an item: use it to read it)
    contests         = true,          -- unsigned tickets can be contested before the DOJ. Off (no DOJ): every ticket must be paid
    statementDays    = 2,             -- the officer is asked for a statement within this many days (a reminder, not a limit)
    contestLapseDays = 5,             -- no ruling after this many days: the ticket is dismissed in the citizen's favour
    contestWarnDays  = 1,             -- the DOJ is warned this many days before a contest lapses
}

-- Impound and holds. From the MDT (a vehicle's page) or on the street with /mdtimpound, the same form. A stored car goes to
-- the lot at once; a car out in the world is marked and taken the next time it is stored (it cannot be taken out again).
-- The owner pays the fee + daily storage (up to the cap) in the court portal once any hold is over, or an officer with
-- "Impound lot" releases it. A hold keeps it for N days or until an officer releases it; releasing it before then needs
-- the "release early (override)" permission and a reason, and is logged as an override.
Config.Impound = {
    enabled       = true,
    command       = 'mdtimpound',
    range         = 8.0,              -- the street form picks the vehicle this close to the officer
    lots          = {                 -- whip_core garages: made at start if they do not exist (or make one in /whip and use its key)
        { key = 'es_mdt_impound', label = 'LS Impound Lot', coords = vector3(409.3, -1623.1, 29.3), heading = 230.0 },
    },
    fee           = 500,              -- the impound fee (the officer may lower it, up to maxFee)
    maxFee        = 5000,
    dailyFee      = 100,              -- storage per full day on the lot
    storageCap    = 1500,             -- storage never goes above this
    releaseTo     = 'lot',            -- 'lot': the owner picks it up at the lot; 'home': it goes back to the garage it came from
    maxHoldDays   = 30,
    reasons       = { 'Parking violation', 'Evidence / investigation', 'No insurance / unregistered', 'Abandoned', 'Driver arrested',
        'Stolen vehicle recovered', 'Reckless driving', 'Other' },
    photoHosts    = {},               -- photo links only from these hosts ({} = any https picture link)
    resolveBolos  = true,             -- impounding closes the vehicle's active BOLOs
    unowned       = {                 -- nobody's cars (street cars): towed away, a small payout for the officer
        enabled     = true,
        payout      = 150,
        cooldownSec = 120,            -- per officer
        perShift    = 10,             -- per officer, per clock-on
        ownerRange  = 60.0,           -- refused while the player who last drove it is this close
    },
}

-- Texts to owners and recipients on their phone (whip_phone), from one government number. Kept on the phone while they
-- are offline (they see them when they look), and a copy goes to their court portal notices (/court) either way.
Config.Texts = {
    enabled = true,
    sender  = 'San Andreas Gov',      -- the contact name it shows with
    loreKey = 'es_mdt_gov',           -- its number's key in whip_phone (made once)
}
