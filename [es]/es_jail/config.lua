Config = {}

-- es_departments permissions (es_departments 1.x adds them: jail_cuff from rank level 10, jail_manage from 60)
Config.Perms = {
    cuff = 'jail_cuff',       -- cuff, uncuff, search, send to jail from the MDT
    manage = 'jail_manage',   -- /jail /unjail /jailtime on anyone, release from the MDT
}

-- items (keys start with es_jail_ so WHIP knows they are ours)
Config.Items = {
    cuffs = 'es_jail_cuffs',
    key = 'es_jail_cuffkey',
    ziptie = 'es_jail_ziptie',
    lockpick = 'lockpick',     -- WHIP's own lockpick item
}
Config.Shops = { 'Armory' }   -- shop names (infinite / npc) that stock cuffs, keys and zip ties, once
Config.ShopPrices = { es_jail_cuffs = 1, es_jail_cuffkey = 1, es_jail_ziptie = 1 }

Config.Cuffs = {
    range = 2.0,             -- how close to cuff someone
    seconds = 6,             -- cuffing takes this long; it is also the window to break free (1.0.3)
    needKey = true,          -- uncuffing steel cuffs takes a cuff key
    keyAnyone = true,        -- anyone holding a cuff key can uncuff (false: officers only)
    zipAnyone = false,       -- zip ties for everyone (false: officers only)
    -- 1.1.0: the cuffs (or a zip tie) shown on the wrists. Models are hashes or names; bone 60309 = left hand.
    prop = { enabled = true, cuffs = 'p_cs_cuffs_02_s', ziptie = 'hei_prop_zip_tie_positioned', bone = 60309,
        offset = vector3(-0.055, 0.06, 0.04), rot = vector3(265.0, 155.0, 80.0) },
    returnCuffs = true,      -- uncuffing gives the cuffs back
    searchRange = 2.5,
    -- a cuffed player can not sprint, jump, fight, take out weapons, open their inventory, get in or out of cars
    blockControls = { 21, 22, 23, 24, 25, 36, 37, 44, 45, 47, 58, 75, 140, 141, 142, 143, 257, 263, 264 },
}

-- breaking out by shaking the mouse WHILE the cuffs go on (Config.Cuffs.seconds). Once they lock: lockpick only.
-- 3 escapes, each harder; the 4th time you are cuffed you can not
Config.Breakout = {
    enabled = true,
    key = 'X',                  -- press while being cuffed, then shake (also on the F1 wheel)
    maxEscapes = 3,
    resetMinutes = 30,          -- the count goes back to 0 this long after the last escape (0 = never by time)
    resetOnRelease = true,      -- and when they walk out of jail
    zipties = true,             -- zip ties can be broken too
    hardCuffs = true,           -- hard cuffs can be broken too (false: soft only)
    alertRange = 40.0,          -- officers this close hear the struggle
    dropCuffs = false,          -- broken cuffs are gone (true: left on the ground)
    -- one entry per escape: meter to fill (0-100), how much each shake counts, how fast it drains per second, and the
    -- quickest it can possibly fill in seconds (the server refuses quicker answers). Keep fastest under Config.Cuffs.seconds.
    levels = {
        { need = 100, gain = 1.0,  decay = 6,  fastest = 3.0 },
        { need = 100, gain = 0.85, decay = 10, fastest = 3.8 },
        { need = 100, gain = 0.7,  decay = 14, fastest = 4.6 },
    },
}

-- lockpicking cuffs with WHIP's lockpick and its ring game
Config.Lockpick = {
    enabled = true,
    self = true,               -- the cuffed player can pick soft cuffs (hands in front)
    selfHard = false,          -- and hard cuffs (hands behind) too
    others = true,             -- someone else can pick them
    difficultySelf = 'hard',
    difficultyOther = 'medium',
    breakChance = 35,          -- % a failed pick snaps
    alertChance = 50,          -- % a pick (pass or fail) is heard by officers in Breakout.alertRange
    zipties = false,           -- a lockpick does nothing to zip ties
}

-- jail
Config.Jail = {
    secondsPerMonth = 60,      -- 1 month of sentence = 1 minute served (online only)
    maxMonths = 300,
    minMonths = 1,
    confiscate = true,         -- pockets (and the accessory strip) go in a box and come back at the gate
    keep = { 'phone', 'id_card', 'driver_license' },  -- items they keep (empty: take everything)
    tickSeconds = 10,
    saveSeconds = 30,
    staffAce = 'es_jail.admin',
}

-- Bolingbroke Penitentiary (stock GTA map, no MLO). 1.0.1: coords from the stock map, cross-checked against
-- qb-prison's defaults (spawns, electrical spots, canteen, release) and a widely used Bolingbroke outer-fence PolyZone.
Config.Prison = {
    name = 'Bolingbroke Penitentiary',
    -- the outer fence (x, y), generous: the yard, every block, the towers and the inner gates are inside. The east edge
    -- is pulled in to x 1841 so the visitor car park and the release point at the front gate (1848, 2586) are outside.
    zone = {
        { 1841.0, 2700.0 }, { 1841.0, 2506.7 }, { 1769.3, 2401.5 }, { 1660.0, 2384.2 }, { 1529.4, 2464.1 },
        { 1524.1, 2586.9 }, { 1558.1, 2680.6 }, { 1640.9, 2764.6 }, { 1773.3, 2771.6 },
    },
    zoneMinZ = 38.0, zoneMaxZ = 75.0,  -- under the yard / up in a helicopter counts as outside
    escapeGrace = 5,           -- seconds outside the fence (in a row) before it counts as an escape
    -- 1.0.5: the stock prison's own NPC inmates and guards attack people. Near the prison (anyone: inmates, officers,
    -- visitors): 'friendly' = they leave you alone, 'remove' = none spawn there, 'off' = GTA's normal behaviour.
    ambient = 'friendly',
    ambientRadius = 320.0,          -- metres from the prison centre
    arrive = {                 -- where new inmates appear (a random one): the yard (qb-prison spawns)
        vector4(1661.05, 2524.68, 45.56, 260.5),
        vector4(1650.81, 2540.58, 45.56, 230.4),
        vector4(1654.96, 2545.54, 45.56, 230.4),
        vector4(1697.11, 2525.56, 45.56, 187.2),
        vector4(1673.08, 2519.82, 45.56, 229.5),
        vector4(1666.03, 2511.37, 45.56, 233.9),
        vector4(1691.23, 2509.64, 45.56, 52.4),
    },
    -- 1.1.0: where an inmate who died wakes up (a random one; empty = the yard spots above). Inside the fence.
    infirmary = {},
    release = vector4(1848.13, 2586.05, 45.67, 269.5),   -- outside the front gate, facing away from the prison
    board = vector3(1668.40, 2526.10, 45.56),            -- the job board, in the yard among the spawns
    center = vector3(1693.33, 2569.51, 45.55),
    blip = { sprite = 188, color = 1, label = 'Bolingbroke' },
}

-- prison jobs: each finished task takes `cut` seconds off (never below `floor` seconds left). Stock Bolingbroke has
-- almost no interiors, so every spot is outdoors on the yard ground.
Config.Jobs = {
    floor = 30,
    cleaning = {
        label = 'Cleaning', icon = 'broom', verb = 'Sweep up', seconds = 8, cut = 20,
        -- 1.0.4: a broom in hand, sweeping (anim and model checked against the game's lists)
        anim = { dict = 'anim@amb@drug_field_workers@rake@male_a@base', clip = 'base', flag = 1 },
        prop = { model = 'prop_tool_broom', bone = 28422, offset = { -0.01, 0.04, -0.03 }, rot = { 0.0, 0.0, 0.0 } },
        spots = {
            vector3(1673.08, 2519.82, 45.56), vector3(1666.03, 2511.37, 45.56), vector3(1691.23, 2509.64, 45.56),
            vector3(1650.81, 2540.58, 45.56), vector3(1697.11, 2525.56, 45.56), vector3(1654.96, 2545.54, 45.56),
            vector3(1770.59, 2536.06, 45.56), vector3(1696.09, 2469.40, 45.56),   -- 1.0.6: all on the open yard / walkways
        },
    },
    electrical = {               -- qb-prison's electrician panels
        label = 'Electrical', icon = 'bolt', verb = 'Fix the panel', seconds = 10, cut = 30,
        -- 1.0.4: welding the panel with a torch
        anim = { dict = 'amb@world_human_welding@male@base', clip = 'base', flag = 1 },
        prop = { model = 'prop_weld_torch', bone = 28422, offset = { 0.0, 0.0, 0.0 }, rot = { 0.0, 0.0, 0.0 } },
        spots = {
            vector3(1761.46, 2540.41, 45.56), vector3(1718.54, 2527.80, 45.56), vector3(1700.20, 2474.81, 45.56),
            vector3(1664.83, 2501.58, 45.56), vector3(1621.62, 2509.30, 45.56), vector3(1627.94, 2538.39, 45.56),
            vector3(1625.10, 2575.99, 45.56),
        },
    },
    kitchen = {                  -- 1.0.6: grills set up out in the yard (the stock canteen can not be entered)
        label = 'Kitchen', icon = 'utensils', verb = 'Cook a tray', seconds = 9, cut = 25,
        -- 1.0.4: flipping food on the grill with a spatula
        anim = { dict = 'amb@prop_human_bbq@male@idle_a', clip = 'idle_b', flag = 1 },
        prop = { model = 'prop_fish_slice_01', bone = 28422, offset = { 0.0, 0.0, 0.0 }, rot = { 0.0, 0.0, 0.0 } },
        -- where the cook stands, on the yard floor between qb-prison's yard spawns; `faces` = the heading they cook at
        spots = { vector3(1652.90, 2543.10, 45.56), vector3(1694.20, 2517.60, 45.56), vector3(1678.60, 2510.50, 45.56) },
        faces = { 230.0, 187.0, 233.0 },
        -- a grill at each station (only on inmates' games), its back to the wall. 1.0.8: the cook's point is worked out from
        -- the grill itself (0.9 m out from its open front, found by checking which side the wall is on); `turn` adds
        -- degrees to every grill (try live with F8 `jailgrill 90`), `frontSign` is the fallback front (-1 = model -Y).
        station = { model = 'prop_bbq_5', dist = 0.8, turn = 0.0, frontSign = -1 },
    },
}

-- 1.0.1: staff test mode (/cufftest) and /jaildebug. Staff = es_jail.admin ACE, the "command" ACE (group.admin), or
-- es_departments staff.
Config.Test = {
    enabled = false,   -- staff test tools (/cufftest, /jaildebug); turn on to test alone
    npcModel = 'a_m_y_downtown_01',
    maxNpcs = 3,
    fleeChance = { 70, 50, 30 },   -- % it works on escape 1, 2, 3 (the 4th cuffing it can not)
    searchItems = { { item = 'lockpick', amount = 1 }, { item = 'es_jail_ziptie', amount = 2 } },  -- what a test NPC "carries" (look only)
}

-- when someone breaks out
Config.Escape = {
    dispatch = true,           -- an es_mdt call to every on-duty officer
    warrant = true,            -- an es_mdt warrant plus a person BOLO (photo, where they went over the fence)
    warrantDays = 7,
    addMonths = 0,             -- added to what is left when they are caught and jailed again
}
