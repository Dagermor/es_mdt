fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'es_jail'
description 'Handcuffs (soft, hard, zip ties), breaking out, lockpicking, searching, and Bolingbroke jail with prison jobs (linked to es_mdt)'
author 'Rob'
version '1.1.1'
whip_requires '1.0'

dependencies { 'oxmysql', 'whip_core', 'es_mdt' }   -- 1.1.1: es_mdt 2.0.0 or newer (it has es_departments in it)

shared_scripts {
    '@whip_core/lib/satellite.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@whip_core/server/db_guard.lua',
    'server/tables.lua',
    'server/main.lua',
    'server/cuffs.lua',
    'server/jail.lua',
    'server/test.lua',
}

client_scripts {
    'client/main.lua',
    'client/cuffs.lua',
    'client/jail.lua',
    'client/test.lua',
    'client/ambient.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/app.css',
    'html/app.js',
    'html/img/items/*.webp',
}
