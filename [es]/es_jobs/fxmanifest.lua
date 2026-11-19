-- es_jobs: the job pack for WHIP. Stations shared by departments and businesses (peds, duty, armory, fleet garage,
-- lockers), pay by rank from each job's own bank account, and player-owned businesses made like /departments.
-- Works with es_mdt (departments, ranks, dispatch, fines and impound money) and es_jail (cuffs); neither is required.
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'es_jobs'
description 'Job pack for WHIP: stations, peds, duty, armory, fleet, lockers, pay by rank, businesses'
author 'Rob'
version '0.1.0'
whip_requires '1.0'

dependencies { 'oxmysql', 'whip_core' }   -- optional: es_mdt (departments), es_jail (cuffs), whip_phone

shared_scripts {
    '@whip_core/lib/satellite.lua',
    'config.lua',
    'shared/settings.lua',      -- /whip > Settings > Jobs
    'shared/util.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@whip_core/server/db_guard.lua',
    'server/tables.lua',
    'server/orgs.lua',          -- departments (es_mdt) and businesses (ours): who belongs where, at what level
    'server/business.lua',      -- /business: make and run a business
    'server/stations.lua',      -- stations and their spots: the editor, history, backup
    'server/gear.lua',          -- duty, armory, fleet garage, personal locker
    'server/pay.lua',           -- paychecks from each job's account, the ledger
    'server/main.lua',
}

client_scripts {
    'client/pad.lua',           -- controller support for every es_jobs screen
    'client/main.lua',          -- the screen (NUI) and its callbacks
    'client/stations.lua',      -- peds, prompts and blips near the player
    'client/editor.lua',        -- placing: ghost peds and cars, use my position, teleport, ped pictures
}

ui_page 'html/index.html'
nui_callback_strict_mode 'true'

files {
    'html/index.html',
    'html/app.css',
    'html/app.js',
    'html/editor.js',
    'html/business.js',
    'html/gear.js',
    'html/pad.js',
    'html/pad.css',
}
