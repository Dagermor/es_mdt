local _ENV = ESAPP('doj'); -- es_doj settings. Roles come from es_departments: a department of type "doj" and its rank permissions
-- (doj_view, doj_cases, doj_sign, doj_deny, doj_prosecute, doj_defend, doj_clerk, doj_bar, doj_penal, doj_seal,
-- warrants_issue, permits_manage). Private attorneys need an active bar license (DOJ tablet → Bar).
Config = Config or {}

Config.Command = 'doj'              -- the DOJ tablet (DOJ members, bar-licensed attorneys, police read-only, staff)
Config.Key = ''                     -- a key for it (players can set one in Settings → Key Bindings → FiveM); '' = none
Config.PhoneApp = true            -- 2.3.0: the portal as a whip_phone app ("Court"), when whip_phone runs. Same data as /court, no bail.
Config.PortalCommand = 'court'      -- the public court portal (anyone): your cases, notices, payments, petitions, lawyers
Config.OffDutyReadOnly = false      -- true: DOJ members off duty can only read
Config.LawCanView = true            -- police (mdt_view) may open the tablet read-only: records, calendar, warrants they asked for

-- Warrants (es_mdt). judgeOnly = true: EVERY new warrant waits for a judge (doj_sign) in the DOJ queue, even from
-- officers who hold "Issue warrants". Leave false until the DOJ has judges, or warrants would wait for nobody.
Config.Warrants = {
    judgeOnly = false,
    defaultDays = 7,                -- expiry a judge's signature gives when the request had none
    notifyJudges = true,            -- judges on duty (and online staff) hear of each new request
}

-- Courthouse: the name and the hearing rooms. 2.4.0: the court's desks and peds (clerk window, courtroom, judge's chambers,
-- DA and public defender offices) are station spots in the job pack (whip_jobs): /departments -> the DOJ -> Locations, or
-- /w -> Stations. `desks` and `blip` below are only used on a server without whip_jobs; with it, whip_jobs moves them once
-- into a "Courthouse" station (Los Santos City Hall, Rockford Hills) and they are edited there.
Config.Courthouse = {
    label = 'Courthouse',
    blip = { sprite = 419, color = 5, scale = 0.8 },
    desks = {
        { label = 'Court clerk', coords = vector3(-544.85, -204.26, 38.22) },
    },
    rooms = { 'Courtroom 1', 'Courtroom 2', 'Chambers', 'Virtual' },
}

-- Case kinds and their number prefixes (CR-2026-0001)
Config.CaseKinds = {
    { key = 'criminal', label = 'Criminal',  prefix = 'CR' },
    { key = 'traffic',  label = 'Traffic',   prefix = 'TR' },
    { key = 'civil',    label = 'Civil',     prefix = 'CV' },
    { key = 'appeal',   label = 'Appeal',    prefix = 'AP' },
    { key = 'petition', label = 'Petition',  prefix = 'PT' },
}
Config.Stages = {
    { key = 'filed',       label = 'Filed' },
    { key = 'arraignment', label = 'Arraignment' },
    { key = 'pretrial',    label = 'Pre-trial' },
    { key = 'trial',       label = 'Trial' },
    { key = 'sentencing',  label = 'Sentencing' },
    { key = 'closed',      label = 'Closed' },
}
Config.HearingKinds = {
    { key = 'arraignment', label = 'Arraignment' },
    { key = 'pretrial',    label = 'Pre-trial conference' },
    { key = 'motion',      label = 'Motion hearing' },
    { key = 'trial',       label = 'Trial' },
    { key = 'sentencing',  label = 'Sentencing' },
    { key = 'appeal',      label = 'Appeal hearing' },
    { key = 'petition',    label = 'Petition hearing' },
    { key = 'other',       label = 'Other' },
}
Config.FilingKinds = {
    { key = 'motion',     label = 'Motion' },
    { key = 'brief',      label = 'Brief' },
    { key = 'exhibit',    label = 'Exhibit' },
    { key = 'order',      label = 'Court order' },
    { key = 'notice',     label = 'Notice' },
    { key = 'statement',  label = 'Statement' },
    { key = 'note',       label = 'Internal note' },
}

-- Money. Fines and fees are paid at the courthouse (portal or clerk window) with cash or bank (WHIP ChargePlayer).
-- Court money goes to the DOJ department's job account (when it has one), else nowhere (the state).
Config.Fees = {
    filing = 0,              -- a civil case filed by a citizen (portal) — 0 = free
    nameChange = 750,
    businessLicense = 1500,
    businessYears = 1,       -- a business license lasts this many years (0 = no expiry)
    expungement = 500,
    appeal = 250,
    record = 0,              -- a copy of a court record
    dueDays = 14,            -- court fines are due in this many days; then unpaid ones get an es_mdt warrant (0 = never)
    toDepartment = true,
}

-- Bail. 2.3.1: OFF (Rob: this server has no bail system; any future bail needs an active DOJ). Off: no bail hearings,
-- no Manage bail, no bail bills or bonds anywhere (tablet, clerk window, /court, the phone). Old bail rows stay in the
-- database untouched; bail already posted is still returned when its case ends. enabled = true brings it all back.
-- bondPercent: a bondsman-style bond (part of the bail, NOT refunded). Full bail is refunded when the case ends.
Config.Bail = {
    enabled = false,
    max = 1000000,
    bondPercent = 10,
}
-- the bail hearing type only exists while bail is on
if Config.Bail.enabled then table.insert(Config.HearingKinds, 2, { key = 'bail', label = 'Bail / bond hearing' }) end

-- Sentencing limits a judge may give (es_jail caps months too)
Config.Sentence = {
    maxFine = 1000000,
    maxMonths = 300,
    maxService = 100,        -- community service tasks
    maxProbationDays = 365,
}

-- Community service: tasks at these spots (picking up litter). One spot at a time, marked on the map.
Config.Service = {
    seconds = 8,
    label = 'Picking up litter...',
    anim = { dict = 'amb@world_human_janitor@male@idle_a', clip = 'idle_a' },
    spots = {
        vector3(195.17, -933.77, 30.69),
        vector3(174.53, -962.42, 30.09),
        vector3(213.61, -924.94, 30.69),
        vector3(232.02, -882.25, 30.49),
        vector3(160.32, -990.63, 30.09),
        vector3(149.52, -1036.71, 29.34),
    },
}

-- Name changes: WHIP's name rules (letters, spaces, hyphens; 2-30 per name)
Config.NameChange = { cooldownDays = 30 }

-- Bar license numbers: SA-0001
Config.Bar = { prefix = 'SA' }

-- Upload limits (pictures are resized in the page first)
Config.Images = { maxBytes = 420000 }

-- Reminders: parties online hear of a hearing this many minutes before it starts
Config.HearingReminderMinutes = 15

-- Staff test tools (/dojtest). Test rows are flagged: test cases name YOU as the defendant so one person can play every
-- side; nothing real happens on them (no jail, no money taken, no rename). /dojtest clear removes every test row.
Config.Test = {
    enabled = true,
    ace = 'es_doj.admin',
}
