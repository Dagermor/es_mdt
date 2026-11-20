-- es_mdt: the emergency-services suite for WHIP in one resource: the MDT (police, sheriff, state, rangers),
-- Departments (logos, ranks, permissions, rosters, duty, FTO, personnel) and the DOJ (courts, attorneys, clerk, /court).
-- 2.0.0 merged es_departments and es_doj into es_mdt; their exports, events, tables and data keep working.
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'es_mdt'
description 'Emergency services for WHIP: MDT, Departments and DOJ in one resource'
author 'Rob'
version '2.5.0'
whip_requires '1.0'

dependencies { 'oxmysql', 'whip_core' }   -- optional: es_jail (or any jail script), whip_evidence

-- No `provide 'es_departments'` / `provide 'es_doj'`: FiveM then reports those names as started, and whip_core would
-- think the old resources still run and refuse es_mdt their jobs. The old export names work without it (shared/env.lua).

shared_scripts {
    '@whip_core/lib/satellite.lua',
    'shared/env.lua',              -- each part's own globals (see the top of the file)
    'shared/suite.lua',            -- EsSuite: settings for the whole resource (DevTools)
    'departments/config.lua',
    'mdt/config.lua',
    'doj/config.lua',
    'mdt/shared/speed.lua',        -- 2.0.8: the speeding alert's limit (both sides)
    'shared/settings.lua',         -- 2.0.8: /whip > Settings > MDT (after every config: saved values are written over them)
    'shared/perms.lua',            -- 2.1.0: the ticket and impound permissions on every law department's ranks
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@whip_core/server/db_guard.lua',
    'server/schema.lua',           -- 2.0.5: EsSchema, the startup schema self-check every table goes through
    'server/adopt.lua',
    'server/jail.lua',
    'departments/server/logo.lua',
    'departments/server/fetch.lua',
    'departments/server/duty.lua',
    'departments/server/fto.lua',
    'departments/server/personnel.lua',
    'departments/server/main.lua',
    'mdt/server/tables.lua',
    'mdt/server/fetch.lua',
    'mdt/server/places.lua',       -- 2.0.8: named stores, banks and Vangelico for robbery alerts
    'mdt/server/ops.lua',
    'mdt/server/evidence.lua',
    'mdt/server/cases.lua',
    'mdt/server/whipev.lua',
    'mdt/server/officer.lua',
    'mdt/server/permits.lua',
    'mdt/server/texts.lua',        -- 2.1.0: texts to owners (whip_phone) + court portal notices
    'mdt/server/tickets.lua',      -- 2.1.0: roadside tickets, invoices, contests
    'mdt/server/impound.lua',      -- 2.1.0: impound, holds, the lot, tows
    'mdt/server/ems.lua',          -- 2.5.0: the EMS side of the MDT (patients, incident reports, bills, deaths, stats)
    'mdt/server/testdata.lua',
    'mdt/server/main.lua',
    'doj/server/tables.lua',
    'doj/server/fetch.lua',
    'doj/server/core.lua',
    'doj/server/cases.lua',
    'doj/server/warrants.lua',
    'doj/server/records.lua',
    'doj/server/clerk.lua',
    'doj/server/bar.lua',
    'doj/server/admin.lua',
    'doj/server/civ.lua',
    'doj/server/contests.lua',     -- 2.1.0: ticket contests (judges), tickets and impounds in /court
    'doj/server/test.lua',
    'doj/server/main.lua',
}

client_scripts {
    'departments/client/main.lua',
    'mdt/client/main.lua',
    'mdt/client/ops.lua',
    'mdt/client/radar.lua',
    'mdt/client/permits.lua',
    'mdt/client/roadside.lua',     -- 2.1.0: /ticket, /mdtimpound, signing, the paper ticket
    'doj/client/main.lua',
    'doj/client/phone.lua',        -- 2.3.0: the Court app on whip_phone (RegisterModule)
    'client/ui.lua',               -- 2.0.2: each player's display size (KVP), /mdtscale
    'client/pad.lua',              -- 2.0.13: controller support (WHIP's pad buttons, Whip.padScreen, the on-screen keyboard)
}

ui_page 'html/index.html'
nui_callback_strict_mode 'true'

files {
    'html/phone/court.js',         -- 2.3.0: the Court phone app (whip_phone module)
    'html/index.html',
    'html/shell.js',
    'html/scale.js',
    'html/pad.js',                 -- 2.0.13: controller navigation, hints and the hold ring in every page
    'html/pad.css',
    'html/mdt/app.css',
    'html/mdt/app.js',
    'html/mdt/cases.js',
    'html/mdt/ems.css',
    'html/mdt/ems.js',
    'html/mdt/evidence.js',
    'html/mdt/index.html',
    'html/mdt/jail.js',
    'html/mdt/lightbox.css',
    'html/mdt/lightbox.js',
    'html/mdt/board.js',
    'html/mdt/officer.css',
    'html/mdt/officer.js',
    'html/mdt/ops.css',
    'html/mdt/ops.js',
    'html/mdt/livemap.css',   -- 2.0.9: the Live map tab
    'html/mdt/livemap.js',
    'html/mdt/permitapp.js',
    'html/mdt/permits.css',
    'html/mdt/permits.js',
    'html/mdt/radar.css',
    'html/mdt/radar.js',
    'html/mdt/repev.js',
    'html/mdt/training.css',
    'html/mdt/training.js',
    'html/mdt/whipev.css',
    'html/mdt/whipev.js',
    'html/mdt/roadside.css',  -- 2.1.0: the roadside ticket / impound forms, signing, the paper ticket
    'html/mdt/roadside.js',
    'html/mdt/tickets.css',   -- 2.1.0: MDT tabs Tickets and Impound lot, the vehicle page's impound
    'html/mdt/tickets.js',
    'html/img/items/*.webp',  -- 2.1.0: the paper ticket item's picture
    'html/mdt/img/*',         -- 2.0.9: the map picture (img/map.webp, or your own: Config.LiveMap.image)
    'html/departments/app.css',
    'html/departments/app.js',
    'html/departments/index.html',
    'html/doj/app.js',
    'html/doj/base.css',
    'html/doj/cases.js',
    'html/doj/court.js',
    'html/doj/doj.css',
    'html/doj/index.html',
    'html/doj/office.js',
    'html/doj/portal.js',
    'html/doj/tickets.js',    -- 2.1.0: ticket contests (tablet), my tickets and impounded vehicles (portal)
    'html/doj/upload.js',
}
