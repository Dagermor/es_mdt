local _ENV = ESAPP('departments'); -- es_departments defaults. Departments themselves live in the database (/departments in game).
Config = Config or {}

Config.Command   = 'departments'            -- opens the Departments screen
Config.AdminAce  = 'es_departments.admin'   -- may create and delete departments (server.cfg add_ace)
Config.StaffPerm = 'es_mdt.departments.manage'   -- 2.0.0: was es_departments.manage (whip_core wants the resource's prefix)  -- WHIP permission: may edit any department (not create/delete)

Config.LogoMaxBytes = 192 * 1024            -- a logo, decoded
Config.LogoMaxSide  = 256                   -- pixels, each side

-- Department types, in the order the screen lists them
Config.Types = {
    { key = 'police',  label = 'Police' },
    { key = 'sheriff', label = 'Sheriff' },
    { key = 'state',   label = 'State Police / Rangers' },
    { key = 'ems',     label = 'EMS / Fire' },
    { key = 'doj',     label = 'Department of Justice' },
}

-- Each type's own permissions (WHIP job permissions, toggled per rank). Names: letters, digits, _ ; 40 at most.
local LAW = {
    { key = 'mdt_view',           label = 'MDT: open and search' },
    { key = 'mdt_reports_write',  label = 'MDT: write reports' },
    { key = 'mdt_reports_delete', label = 'MDT: delete reports' },
    { key = 'warrants_request',   label = 'Request warrants' },
    { key = 'warrants_issue',     label = 'Issue warrants' },
    { key = 'fines_issue',        label = 'Issue fines' },
    { key = 'evidence_collect',   label = 'Collect evidence' },
    { key = 'evidence_lab',       label = 'Evidence lab' },
    { key = 'evidence_manage',    label = 'Evidence: destroy / release, every locker' },
    { key = 'cases_create',       label = 'Cases: open cases, assign officers and suspects' },
    { key = 'cases_close',        label = 'Cases: close, archive and reopen cases' },
    { key = 'evidence_upload',    label = 'Upload evidence to cases (whip_evidence)' },        -- 1.9.0: checked by whip_evidence itself
    { key = 'evidence_case_close', label = 'Close evidence lockers (whip_evidence)' },        -- 1.9.0: checked by whip_evidence itself
    { key = 'bolo_manage',        label = 'Manage BOLOs' },
    { key = 'announce',           label = 'Department announcements' },
    { key = 'fto_train',          label = 'FTO: write DORs, sign off training items, recommend' },
    { key = 'fto_manage',         label = 'FTO supervisor: edit the training program, assign FTOs, final sign-off' },
    { key = 'loa_manage',         label = 'Leave (LOA) and activity: approve, see who is inactive' },
    { key = 'personnel_manage',   label = 'Personnel files: commendations, discipline, notes, certifications' },
    { key = 'weapons_register',   label = 'Weapons: register a weapon, add notes' },
    { key = 'weapons_manage',     label = 'Weapons: mark stolen / seized / returned / destroyed, change owner' },
    { key = 'licenses_manage',    label = 'Weapon licenses: issue, suspend, revoke' },
    { key = 'permits_manage',     label = 'Firearm permits: review civilian applications (approve / deny)' },
    { key = 'jail_cuff',          label = 'Cuffs: cuff, uncuff, search' },
    { key = 'jail_manage',        label = 'Jail: /jail, /unjail, release inmates' },
}
Config.Permissions = {
    police  = LAW,
    sheriff = LAW,
    state   = LAW,
    ems = {
        { key = 'mdt_view',        label = 'MDT: open and search' },
        { key = 'medical_records', label = 'Medical records' },
        { key = 'loa_manage',      label = 'Leave (LOA) and activity: approve, see who is inactive' },
        { key = 'personnel_manage', label = 'Personnel files: commendations, discipline, notes, certifications' },
    },
    doj = {
        { key = 'doj_view',       label = 'DOJ: open the tablet (cases, calendar, records)' },
        { key = 'doj_cases',      label = 'DOJ: file and manage court cases, schedule hearings' },
        { key = 'doj_sign',       label = 'Judge: sign warrants, rule, verdicts, sentences, bail' },
        { key = 'doj_deny',       label = 'Judge: deny warrants' },
        { key = 'doj_prosecute',  label = 'Prosecutor (DA office): charge, prosecute, offer plea deals' },
        { key = 'doj_defend',     label = 'Public defender: defend, answer plea offers' },
        { key = 'doj_clerk',      label = 'Clerk: petitions, fees, business licenses, transcripts' },
        { key = 'doj_bar',        label = 'Bar office: license and discipline attorneys' },
        { key = 'doj_penal',      label = 'Edit the penal code' },
        { key = 'doj_seal',       label = 'Seal and expunge records' },
        { key = 'warrants_issue', label = 'Issue warrants' },
        { key = 'permits_manage', label = 'Firearm permits: review civilian applications (approve / deny)' },
        { key = 'loa_manage',     label = 'Leave (LOA) and activity: approve, see who is inactive' },
        { key = 'personnel_manage', label = 'Personnel files: commendations, discipline, notes, certifications' },
    },
}

-- WHIP's own job permissions, shown beside the department's on each rank
Config.BuiltinPermissions = {
    { key = 'canHire',    label = 'Hire' },
    { key = 'canFire',    label = 'Fire' },
    { key = 'canPromote', label = 'Promote' },
    { key = 'canDemote',  label = 'Demote' },
    { key = 'canManage',  label = 'Manage ranks and department' },
}

Config.Insignia = { 'none', 'stars4', 'stars3', 'stars2', 'stars1', 'eagle', 'oak', 'bars2', 'bar1',
    'chevrons3', 'chevrons2', 'chevrons1' }

-- What a rank gets by default from its level (new departments and the first seed). Level 100 holds all.
Config.DefaultRankPermissions = {
    law = {
        { min = 80, perms = 'all' },
        { min = 60, perms = { 'mdt_view', 'mdt_reports_write', 'warrants_request', 'fines_issue',
            'evidence_collect', 'evidence_upload', 'evidence_lab', 'evidence_manage', 'cases_create', 'cases_close', 'evidence_case_close', 'bolo_manage', 'announce', 'fto_train', 'fto_manage', 'personnel_manage',
            'weapons_register', 'weapons_manage', 'licenses_manage', 'permits_manage', 'jail_cuff', 'jail_manage' } },
        { min = 40, perms = { 'mdt_view', 'mdt_reports_write', 'warrants_request', 'fines_issue',
            'evidence_collect', 'evidence_upload', 'evidence_lab', 'cases_create', 'bolo_manage', 'weapons_register', 'jail_cuff', 'fto_train' } },
        { min = 30, perms = { 'mdt_view', 'mdt_reports_write', 'warrants_request', 'fines_issue',
            'evidence_collect', 'evidence_upload', 'cases_create', 'bolo_manage', 'weapons_register', 'jail_cuff', 'fto_train' } },
        { min = 10, perms = { 'mdt_view', 'evidence_collect', 'evidence_upload', 'jail_cuff' } },
        { min = 1,  perms = { 'mdt_view' } },
    },
    ems = { { min = 30, perms = 'all' }, { min = 1, perms = { 'mdt_view' } } },
    -- 1.7.0: a judge's powers from 80; below that each DOJ rank's own role comes from its rank list (DefaultRanks.doj)
    doj = { { min = 100, perms = 'all' },
        { min = 80, perms = { 'doj_view', 'doj_cases', 'doj_sign', 'doj_deny', 'doj_seal', 'warrants_issue', 'permits_manage', 'loa_manage', 'personnel_manage' } },
        { min = 1, perms = { 'doj_view' } } },
}

-- Ranks a new department starts with, by type
Config.DefaultRanks = {
    police = {
        { name = 'Chief',    level = 100, abbr = 'CHF' },
        { name = 'Captain',  level = 80,  abbr = 'CPT', permissions = { canHire = true, canFire = true, canPromote = true, canDemote = true, bankAccess = 'withdraw' } },
        { name = 'Sergeant', level = 60,  abbr = 'SGT', permissions = { canPromote = true, canDemote = true, bankAccess = 'view' } },
        { name = 'Officer',  level = 30,  abbr = 'OFC' },
        { name = 'Cadet',    level = 1,   abbr = 'CDT' },
    },
    sheriff = {
        { name = 'Sheriff',      level = 100, abbr = 'SHF' },
        { name = 'Undersheriff', level = 80,  abbr = 'USH', permissions = { canHire = true, canFire = true, canPromote = true, canDemote = true, bankAccess = 'withdraw' } },
        { name = 'Sergeant',     level = 60,  abbr = 'SGT', permissions = { canPromote = true, canDemote = true, bankAccess = 'view' } },
        { name = 'Deputy',       level = 30,  abbr = 'DEP' },
        { name = 'Cadet',        level = 1,   abbr = 'CDT' },
    },
    state = {
        { name = 'Colonel',  level = 100, abbr = 'COL' },
        { name = 'Major',    level = 80,  abbr = 'MAJ', permissions = { canHire = true, canFire = true, canPromote = true, canDemote = true, bankAccess = 'withdraw' } },
        { name = 'Sergeant', level = 60,  abbr = 'SGT', permissions = { canPromote = true, canDemote = true, bankAccess = 'view' } },
        { name = 'Trooper',  level = 30,  abbr = 'TPR' },
        { name = 'Cadet',    level = 1,   abbr = 'CDT' },
    },
    ems = {
        { name = 'Chief',     level = 100, abbr = 'CHF' },
        { name = 'Captain',   level = 80,  abbr = 'CPT', permissions = { canHire = true, canFire = true, canPromote = true, canDemote = true, bankAccess = 'withdraw' } },
        { name = 'Paramedic', level = 30,  abbr = 'PM' },
        { name = 'EMT',       level = 10,  abbr = 'EMT' },
        { name = 'Trainee',   level = 1,   abbr = 'TRN' },
    },
    doj = {   -- 1.7.0: the court, the DA's office, public defenders and the clerk's office
        { name = 'Chief Justice',     level = 100, abbr = 'CJ' },
        { name = 'Judge',             level = 80,  abbr = 'JDG', permissions = { canHire = true, canFire = true, canPromote = true, canDemote = true } },
        { name = 'District Attorney', level = 70,  abbr = 'DA',  permissions = { doj_cases = true, doj_prosecute = true, canHire = true, canPromote = true, canDemote = true } },
        { name = 'Prosecutor',        level = 50,  abbr = 'ADA', permissions = { doj_cases = true, doj_prosecute = true } },
        { name = 'Chief Public Defender', level = 70, abbr = 'CPD', permissions = { doj_defend = true, canHire = true, canPromote = true, canDemote = true } },   -- 1.8.0
        { name = 'Public Defender',   level = 50,  abbr = 'PD',  permissions = { doj_defend = true } },
        { name = 'Clerk',             level = 20,  abbr = 'CLK', permissions = { doj_cases = true, doj_clerk = true, doj_bar = true, permits_manage = true } },
    },
}

-- First start only (an empty departments table that was never seeded). Logo files are base64 in departments/seed/.
Config.Seed = {
    { key = 'police', short = 'LSPD', name = 'Los Santos Police Department', type = 'police',
      color1 = '#1b2a5c', color2 = '#f2c230', logo = 'departments/seed/lspd.webp.b64', sort = 1,
      ranks = { Chief = 'CHF', Captain = 'CPT', Sergeant = 'SGT', Officer = 'OFC', Cadet = 'CDT' } },
    { key = 'bcso', short = 'BCSO', name = "Blaine County Sheriff's Office", type = 'sheriff',
      color1 = '#5a3e1b', color2 = '#d9a441', logo = 'departments/seed/bcso.webp.b64', sort = 2, owner = nil },
    -- since = 2: added after the first seed; made on the next start when no department has that job yet
    { since = 2, key = 'sasp', short = 'SASP', name = 'San Andreas State Police', type = 'state',
      color1 = '#0d203d', color2 = '#b3b4bd', logo = 'departments/seed/sasp.webp.b64', sort = 3, owner = nil },
    { since = 2, key = 'sapr', short = 'SAPR', name = 'San Andreas State Parks', type = 'state',
      color1 = '#12529a', color2 = '#f7da9c', logo = 'departments/seed/sapr.png.b64', sort = 4, owner = nil,
      rankList = {
          { name = 'Chief Ranger', level = 100, abbr = 'CRG' },
          { name = 'Captain',      level = 80,  abbr = 'CPT', permissions = { canHire = true, canFire = true, canPromote = true, canDemote = true, bankAccess = 'withdraw' } },
          { name = 'Sergeant',     level = 60,  abbr = 'SGT', permissions = { canPromote = true, canDemote = true, bankAccess = 'view' } },
          { name = 'Ranger',       level = 30,  abbr = 'RGR' },
          { name = 'Cadet',        level = 1,   abbr = 'CDT' },
      } },
    -- 1.7.0: the Department of Justice (es_doj). Ranks: Config.DefaultRanks.doj
    { since = 3, key = 'doj', short = 'DOJ', name = 'San Andreas Department of Justice', type = 'doj',
      color1 = '#16213e', color2 = '#d6b25e', logo = 'departments/seed/doj.png.b64', sort = 5, owner = nil },
}

-- Duty time and department health (the admin Health view in /departments)
Config.Health = {
    -- These apply to EVERY member (leaders see them in the MDT); a department head's flags also go to admins.
    note = 5,              -- off duty MORE than this many days: yellow note
    warn = 10,             -- more than this: orange warning
    act = 14,              -- this many or more: red, an admin should step in
    headLevel = nil,       -- who counts as a head: nil = the department's top rank (and the job owner), or a level like 80
    adminNotes = true,     -- add a note to the head's account (Player Manager) each time they reach a new level
    checkMinutes = 30,     -- how often heads are checked (online staff hear of anyone who just crossed a line)
    heartbeatMinutes = 5,  -- how much duty time a crash can lose at most
}

-- New permissions handed to existing ranks once, by level (ranks keep anything they already hold)
-- 1.8.0: ranks added once to departments of a type that already exist (their default ranks were made earlier).
-- Skipped when the department already has a rank by that name. Permissions = the type's defaults by level + these.
Config.RankAdds = {
    { id = 'doj_cpd_1', type = 'doj', name = 'Chief Public Defender', level = 70, abbr = 'CPD',
      permissions = { doj_defend = true, canHire = true, canPromote = true, canDemote = true } },
}

-- 1.9.0: new permissions copied once onto every existing rank that already holds another one (target = source).
-- whip_evidence's own names: whoever may collect evidence may upload it to a case; whoever closes cases closes lockers.
Config.PermissionMirrors = {
    { id = 'whipev_1', perms = { evidence_upload = 'evidence_collect', evidence_case_close = 'cases_close' } },
}

Config.PermissionGrants = {
    { id = 'loa_fto_1', perms = { loa_manage = 80, fto_train = 60 } },   -- permission = lowest level that gets it
    { id = 'weapons_1', perms = { weapons_register = 30, weapons_manage = 60, licenses_manage = 60 } },
    { id = 'evidence_1', perms = { evidence_collect = 10, evidence_lab = 40, evidence_manage = 60 } },
    { id = 'cases_1', perms = { cases_create = 30, cases_close = 60 } },
    { id = 'jail_1', perms = { jail_cuff = 10, jail_manage = 60 } },
    { id = 'fto_2', perms = { fto_train = 30, fto_manage = 60 } },     -- 1.4.0: FTOs from Officer up, supervisors from Sergeant
    { id = 'personnel_1', perms = { personnel_manage = 60 } },         -- 1.5.0: personnel files from Sergeant up
    { id = 'permits_1', perms = { permits_manage = 60 } },             -- 1.6.0: firearm permit reviews from Sergeant up
}

-- Leave of absence (filed in the MDT). While approved and running, the inactivity clock is paused; it restarts
-- from the day the leave ends (or is ended early).
Config.LOA = {
    maxDays = 60,          -- longest leave one request may cover
    maxAheadDays = 60,     -- how far ahead a leave may start
    reasonMax = 300,
}

-- FTO / training. 1.4.0: phases, items, rating categories, DOR due days, recruit ranks and the graduation rank are
-- the department's own training program, edited in the MDT (Training → Program) by fto_manage. These are the rest.
Config.FTO = {
    rideAlongsRequired = 3,    -- (1.3 queue cards) ride-alongs shown as a count
    kinds = { 'ridealong', 'training', 'evaluation' },
    ratings = { 'Driving', 'Radio', 'Officer safety', 'Report writing', 'Law knowledge', 'Conduct' },   -- 1-5 each
    checklist = { 'Traffic stop', 'Felony stop', 'Pursuit', 'Arrest and booking', 'Report filed', 'Radio codes', 'Use of force' },
}

-- 1.5.0: certifications (each department edits its own list in the MDT: Department → Certifications)
Config.Certs = {
    alertDays = 14,        -- supervisors (personnel_manage) and the officer hear this many days before one expires
    gateFto = false,       -- true: being an FTO (claiming / being assigned trainees) also needs a valid FTO cert, on top of fto_train
    ftoCert = 'FTO',       -- the cert's name for gateFto
}
