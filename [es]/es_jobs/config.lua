-- es_jobs 0.1.0: the job pack. Stations (shared by departments), their peds and spots, pay by rank,
-- the armory, the fleet garage and lockers, and businesses. Stations and businesses are made in game (/stations, /business):
-- they live in the database, not here. Everything below is a default; /whip > Settings > Jobs changes it live.
Config = Config or {}

Config.Command = 'stations'              -- opens the station editor (admins and department staff)
Config.BusinessCommand = 'business'     -- opens Businesses (owners and managers; admins see them all)
Config.AdminAce = 'es_jobs.admin'       -- may edit every station and business (server.cfg add_ace); WHIP admins always may

Config.Stations = {
    pedDistance = 45.0,                  -- metres: a station's peds appear within this, and go past it + 10
    reach = 2.0,                         -- metres: how close to use a ped or spot
    seeFrom = 8.0,                       -- metres: prompts appear from
    blips = true,                        -- show station blips at all
    blipSprite = 60,                     -- the default blip (60 = police star), per station in the editor
    blipColor = 29,
    historyKeep = 30,                    -- undo steps kept per station
    -- The ped a new spot gets, by the department type (then by name: "Fire" / "FD" and "Ranger" / "Park" get their own)
    peds = {
        police = 's_m_y_cop_01', sheriff = 's_m_y_sheriff_01', state = 's_m_y_hwaycop_01', ranger = 's_m_y_ranger_01',
        ems = 's_m_m_paramedic_01', fire = 's_m_y_fireman_01', doj = 's_m_m_highsec_01', none = 's_m_m_security_01',
    },
    -- The ped list in the editor (any other model can be typed in)
    pedList = {
        { model = 's_m_y_cop_01', label = 'Police officer' }, { model = 's_f_y_cop_01', label = 'Police officer (female)' },
        { model = 's_m_y_sheriff_01', label = 'Sheriff deputy' }, { model = 's_f_y_sheriff_01', label = 'Sheriff deputy (female)' },
        { model = 's_m_y_hwaycop_01', label = 'Highway patrol' }, { model = 's_m_y_ranger_01', label = 'Park ranger' },
        { model = 's_f_y_ranger_01', label = 'Park ranger (female)' }, { model = 's_m_m_paramedic_01', label = 'Paramedic' },
        { model = 's_m_y_fireman_01', label = 'Firefighter' }, { model = 's_m_m_doctor_01', label = 'Doctor' },
        { model = 's_f_y_scrubs_01', label = 'Nurse' }, { model = 's_m_m_highsec_01', label = 'Court security' },
        { model = 's_m_m_security_01', label = 'Security guard' }, { model = 'cs_prolsec_02', label = 'Prison guard' },
        { model = 's_m_y_swat_01', label = 'SWAT' }, { model = 's_m_m_ciasec_01', label = 'Agent' },
        { model = 'a_f_y_business_01', label = 'Clerk (female)' }, { model = 'a_m_y_business_01', label = 'Clerk' },
    },
}

-- Pay by rank, from each department's or business's own bank account (its WHIP job account), while on duty.
Config.Pay = {
    enabled = true,
    intervalMinutes = 15,                -- on-duty minutes per paycheck
    base = 150,                          -- a rank with no pay set: base + level x perLevel per paycheck
    perLevel = 3,
    maxPay = 5000,                       -- the most one paycheck can be (the Pay tab refuses more)
    bossNotice = true,                   -- tell the department's leaders (and staff) when the account can't pay
}

-- The armory, the fleet and the locker
Config.Gear = {
    armoryMax = 10,                      -- the most of one item someone may carry from the armory
    fleetOne = true,                     -- one fleet vehicle per person at a time
    fleetReturnOnClockOff = true,        -- their fleet vehicle goes away when they clock off
    fleetReturnRange = 40.0,             -- metres from a garage spot to put the vehicle back
    fleetDespawnMinutes = 0,             -- 0 = it stays while they are on duty (WHIP still removes it after 10 min with nobody near)
    uniformsOnlyOnDuty = true,           -- the uniform locker is for people on duty at one of the station's departments
    adjust = true,                       -- officers may adjust a uniform (hat, vest, gloves...) in the locker, for their shift
    restoreOnClockOff = true,            -- clocking off puts their own clothes back on
    lockerSlots = 20,                    -- a personal locker's slots (0: no personal locker)
    lockerWeight = 40.0,
}

-- Player-owned businesses (/business). An admin makes one for its owner; with playerCreate a player may start their own.
Config.Business = {
    playerCreate = false,                -- players may start a business themselves
    createPrice = 25000,                 -- what that costs them (from their bank)
    maxPerOwner = 2,                     -- businesses one character may own
    startBalance = 0,                    -- put into a new business account when an admin makes it
    ped = 'a_m_y_business_01',           -- a new business spot's ped
    ranks = {                            -- a new business's ranks (the owner takes the top one)
        { name = 'Owner', level = 100 }, { name = 'Manager', level = 80, permissions = { canHire = true, canFire = true, canPromote = true, canDemote = true } },
        { name = 'Supervisor', level = 50, permissions = { canHire = true } }, { name = 'Employee', level = 20 }, { name = 'Trainee', level = 1 },
    },
}
