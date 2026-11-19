-- es_jobs: /whip > Settings > Jobs (Whip.configPage). config.lua stays the defaults; what an admin saves here is written
-- over Config on both sides at start and the moment it changes. Stations and businesses themselves are made in game.
if not (Whip and Whip.configPage) then return end

local function restart(e) e.apply, e.why = 'restart', 'Registered when the resource starts' return e end
local function on(path) return { path = path, equals = true } end

Whip.configPage({
    label = 'Jobs',
    groups = {
        { id = 'stations', label = 'Stations', settings = {
            { key = 'Stations.pedDistance', type = 'number', min = 15, max = 150, step = 5, unit = 'm', label = 'Station peds appear within',
              help = 'Peds are made on each player\'s own game only while someone is this close: nothing runs far away.' },
            { key = 'Stations.reach', type = 'number', min = 1, max = 5, step = 0.25, unit = 'm', label = 'Use a ped or spot from' },
            { key = 'Stations.seeFrom', type = 'number', min = 3, max = 25, step = 1, unit = 'm', label = 'Prompts show from' },
            { key = 'Stations.blips', type = 'bool', label = 'Station blips on the map', help = 'Each station picks who sees it: everyone, its own members, or nobody.' },
            { key = 'Stations.historyKeep', type = 'int', min = 5, max = 200, label = 'Undo steps kept per station' },
            { key = 'Stations.peds.police', type = 'string', maxLen = 48, pattern = '^[%w_]+$', patternWhy = 'a ped model name', label = 'Default ped: police' },
            { key = 'Stations.peds.sheriff', type = 'string', maxLen = 48, pattern = '^[%w_]+$', patternWhy = 'a ped model name', label = 'Default ped: sheriff' },
            { key = 'Stations.peds.state', type = 'string', maxLen = 48, pattern = '^[%w_]+$', patternWhy = 'a ped model name', label = 'Default ped: state police' },
            { key = 'Stations.peds.ranger', type = 'string', maxLen = 48, pattern = '^[%w_]+$', patternWhy = 'a ped model name', label = 'Default ped: rangers' },
            { key = 'Stations.peds.ems', type = 'string', maxLen = 48, pattern = '^[%w_]+$', patternWhy = 'a ped model name', label = 'Default ped: EMS' },
            { key = 'Stations.peds.fire', type = 'string', maxLen = 48, pattern = '^[%w_]+$', patternWhy = 'a ped model name', label = 'Default ped: fire' },
            { key = 'Stations.peds.doj', type = 'string', maxLen = 48, pattern = '^[%w_]+$', patternWhy = 'a ped model name', label = 'Default ped: DOJ' },
        } },
        { id = 'pay', label = 'Pay', settings = {
            { key = 'Pay.enabled', type = 'bool', label = 'Pay people on duty', help = 'From their department\'s or business\'s own bank account, by rank (set on each one\'s Pay tab).' },
            { key = 'Pay.intervalMinutes', type = 'int', min = 5, max = 120, unit = 'min', label = 'A paycheck every', shownWhen = on('Pay.enabled') },
            { key = 'Pay.base', type = 'int', min = 0, max = 10000, label = 'Rank with no pay set: base', shownWhen = on('Pay.enabled') },
            { key = 'Pay.perLevel', type = 'int', min = 0, max = 500, label = '... plus this per rank level', shownWhen = on('Pay.enabled'),
              help = 'Level 1 to 100. With base 150 and 3 a level, an Officer (30) gets $240 and a Chief (100) $450.' },
            { key = 'Pay.maxPay', type = 'int', min = 1, max = 1000000, label = 'Largest paycheck allowed', shownWhen = on('Pay.enabled') },
            { key = 'Pay.bossNotice', type = 'bool', label = 'Tell the leaders when the account can\'t pay', shownWhen = on('Pay.enabled') },
        } },
        { id = 'gear', label = 'Armory, fleet and lockers', settings = {
            { key = 'Gear.armoryMax', type = 'int', min = 1, max = 100, label = 'Most of one armory item a person may carry' },
            { key = 'Gear.fleetOne', type = 'bool', label = 'One fleet vehicle per person at a time' },
            { key = 'Gear.fleetReturnOnClockOff', type = 'bool', label = 'Fleet vehicle goes away at clock off' },
            { key = 'Gear.fleetReturnRange', type = 'number', min = 10, max = 150, step = 5, unit = 'm', label = 'Put a vehicle back within this of a garage' },
            { key = 'Gear.fleetDespawnMinutes', type = 'int', min = 0, max = 1440, unit = 'min', label = 'Fleet vehicles go after (0 = while on duty)' },
            { key = 'Gear.lockerSlots', type = 'int', min = 0, max = 100, label = 'Personal locker slots (0 = none)' },
            { key = 'Gear.lockerWeight', type = 'number', min = 5, max = 500, step = 5, unit = 'kg', label = 'Personal locker weight' },
        } },
        { id = 'business', label = 'Businesses', settings = {
            { key = 'Business.playerCreate', type = 'bool', label = 'Players may start a business themselves', help = 'Off: an admin makes it for its owner in /business.' },
            { key = 'Business.createPrice', type = 'int', min = 0, max = 10000000, label = 'Price to start one', shownWhen = on('Business.playerCreate') },
            { key = 'Business.maxPerOwner', type = 'int', min = 1, max = 20, label = 'Businesses one person may own' },
            { key = 'Business.startBalance', type = 'int', min = 0, max = 10000000, label = 'Money in a new business account (admin-made)' },
            { key = 'Business.ped', type = 'string', maxLen = 48, pattern = '^[%w_]+$', patternWhy = 'a ped model name', label = 'Default ped at a business spot' },
        } },
        { id = 'start', label = 'Commands (restart)', settings = {
            restart({ key = 'Command', type = 'string', maxLen = 32, pattern = '^[%w_]+$', patternWhy = 'a command name', label = 'Station editor command' }),
            restart({ key = 'BusinessCommand', type = 'string', maxLen = 32, pattern = '^[%w_]+$', patternWhy = 'a command name', label = 'Businesses command' }),
        } },
    },
})
