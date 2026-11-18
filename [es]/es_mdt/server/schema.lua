-- es_mdt 2.0.5: the startup schema self-check, for every table of the resource (MDT, Departments, DOJ, jail).
--
-- Why: whip_core's EnsureTable records all of a table's migrations as done, WITHOUT running them, on the start that
-- CREATES the table (it trusts the CREATE to carry every change). Up to 2.0.4 a few CREATEs lacked columns that only
-- a migration added, so a fresh install never got them: "Unknown column 'kind'" / "Unknown column 'origin'".
--
-- So each table's CREATE statement is its one source of truth: EsSchema.parse() turns it into the list of columns and
-- keys the code expects. EsSchema.ensure() runs whip_core's EnsureTable (the migrations still run as before), then on
-- every start compares that list with information_schema and ADDs whatever is missing. It never drops, renames or
-- changes a column, key or row that is there. The end state no longer depends on the schema_migrations markers: a
-- skipped or wrongly recorded migration is caught at the next start. Each fix is logged; a fix that fails prints a
-- loud error with the SQL to run by hand (and is a WHIP start problem), never silently.
EsSchema = {}

local stats = { tables = 0, fixed = 0, failed = 0, problems = {} }
local function log(msg) print(('^3[es_mdt] schema: %s^7'):format(msg)) end
local function loud(lines)
    print('^1================ [es_mdt] SCHEMA ERROR ================^7')
    for _, l in ipairs(lines) do print('^1[es_mdt] ' .. l .. '^7') end
    print('^1=======================================================^7')
end

--- Split a CREATE body on its top-level commas (not those inside ( ) or quotes), dropping `--` comments.
local function splitItems(body)
    local items, cur, depth, q, i = {}, {}, 0, nil, 1
    while i <= #body do
        local ch = body:sub(i, i)
        if q then
            cur[#cur + 1] = ch
            if ch == '\\' then cur[#cur + 1] = body:sub(i + 1, i + 1); i = i + 1
            elseif ch == q then q = nil end
        elseif ch == "'" or ch == '"' or ch == '`' then q = ch; cur[#cur + 1] = ch
        elseif ch == '-' and body:sub(i + 1, i + 1) == '-' then
            local nl = body:find('\n', i, true) or #body
            i = nl
        elseif ch == '(' then depth = depth + 1; cur[#cur + 1] = ch
        elseif ch == ')' then depth = depth - 1; cur[#cur + 1] = ch
        elseif ch == ',' and depth == 0 then items[#items + 1] = table.concat(cur); cur = {}
        else cur[#cur + 1] = ch end
        i = i + 1
    end
    items[#items + 1] = table.concat(cur)
    local out = {}
    for _, it in ipairs(items) do
        it = it:gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', '')
        if it ~= '' then out[#out + 1] = it end
    end
    return out
end

--- The columns and keys a CREATE TABLE statement defines, in order:
---   { name, columns = { { name, def }... }, keys = { { name, def, primary }... } }   (FOREIGN KEY constraints are left out)
function EsSchema.parse(createSql)
    local name, rest = createSql:match('CREATE TABLE IF NOT EXISTS `([%w_]+)`%s*(%b())')
    assert(name and rest, 'not a CREATE TABLE IF NOT EXISTS `name` (...) statement')
    local spec = { name = name, columns = {}, keys = {} }
    for _, it in ipairs(splitItems(rest:sub(2, -2))) do
        local up = it:upper()
        if it:sub(1, 1) == '`' then
            spec.columns[#spec.columns + 1] = { name = it:match('^`([^`]+)`'), def = it }
        elseif up:find('^PRIMARY KEY') then
            spec.keys[#spec.keys + 1] = { name = 'PRIMARY', def = it, primary = true }
        elseif up:find('^CONSTRAINT') or up:find('^FOREIGN KEY') or up:find('^CHECK') then
            -- foreign keys / checks: never added afterwards (old rows may not satisfy them)
        else
            local kname = it:match('^[%u ]*KEY `([^`]+)`') or it:match('^[%u ]*INDEX `([^`]+)`')
            if kname then spec.keys[#spec.keys + 1] = { name = kname, def = it } end
        end
    end
    return spec
end

local function liveShape(tbl)
    local cols, keys = {}, {}
    for _, r in ipairs(MySQL.query.await('SELECT COLUMN_NAME AS c FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', { tbl }) or {}) do
        cols[tostring(r.c):lower()] = true
    end
    for _, r in ipairs(MySQL.query.await('SELECT DISTINCT INDEX_NAME AS i FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', { tbl }) or {}) do
        keys[tostring(r.i):lower()] = true
    end
    return cols, keys, next(cols) ~= nil
end

local function problem(tbl, what, sql, err)
    stats.failed = stats.failed + 1
    stats.problems[#stats.problems + 1] = ('%s.%s'):format(tbl, what)
    loud({
        ('could not add %s to `%s`: %s'):format(what, tbl, tostring(err)),
        'MDT features that use it will error until it exists. Fix the cause, then restart es_mdt, or run by hand:',
        '  ' .. sql .. ';',
    })
    if Whip and type(Whip.startProblem) == 'function' then
        pcall(Whip.startProblem, 'schema: could not add %s to %s (%s)', what, tbl, tostring(err))
    end
end

--- Compare one table with its CREATE and ADD what is missing. Answers complete (everything there afterwards), fixed.
function EsSchema.check(createSql)
    local spec = type(createSql) == 'table' and createSql or EsSchema.parse(createSql)
    local tbl = spec.name
    local cols, keys, exists = liveShape(tbl)
    if not exists then
        problem(tbl, 'the table itself', 'see the CREATE TABLE `' .. tbl .. '` in es_mdt', 'the table does not exist')
        return false, 0
    end
    local fixed, complete = 0, true
    local function add(kind, item, sql)
        local ok, err = pcall(MySQL.query.await, sql)
        local c2, k2 = liveShape(tbl)   -- oxmysql may report an error without throwing: look, don't trust
        local there = (kind == 'column' and c2 or k2)[item.name:lower()]
        if ok and there then
            fixed = fixed + 1
            stats.fixed = stats.fixed + 1
            log(('added missing %s `%s`.`%s`'):format(kind, tbl, item.name))
        else
            complete = false
            problem(tbl, ('%s `%s`'):format(kind, item.name), sql, ok and 'it is still missing after the ALTER' or err)
        end
        cols, keys = c2, k2
    end
    for _, c in ipairs(spec.columns) do        -- columns first: a key may be on a column added here
        if not cols[c.name:lower()] then
            if c.def:upper():find('AUTO_INCREMENT', 1, true) then
                complete = false
                problem(tbl, ('column `%s`'):format(c.name), 'ALTER TABLE `' .. tbl .. '` ADD COLUMN ' .. c.def, 'an AUTO_INCREMENT column cannot be added safely')
            else
                add('column', c, ('ALTER TABLE `%s` ADD COLUMN %s'):format(tbl, c.def))
            end
        end
    end
    for _, k in ipairs(spec.keys) do
        if not keys[k.name:lower()] then
            if k.primary then
                complete = false
                problem(tbl, 'PRIMARY KEY', 'ALTER TABLE `' .. tbl .. '` ADD ' .. k.def, 'the primary key is missing (not added automatically)')
            else
                add('key', k, ('ALTER TABLE `%s` ADD %s'):format(tbl, k.def))
            end
        end
    end
    return complete, fixed
end

--- Use in place of Whip.core:EnsureTable(name, createSql, migrations). Same answers: true, or false and why.
function EsSchema.ensure(name, createSql, migrations)
    local ok, why = Whip.core:EnsureTable(name, createSql, migrations or {})
    stats.tables = stats.tables + 1
    local okCheck, complete = pcall(EsSchema.check, createSql)
    if not okCheck then
        loud({ ('schema check of `%s` errored: %s'):format(name, tostring(complete)) })
        return ok, why
    end
    if not ok and complete then
        -- a migration failed (whip_core retries it next start), but every column and key the code needs is there
        log(('`%s`: %s - the table has every column and key, carrying on'):format(name, tostring(why)))
        return true
    end
    return ok, why
end

function EsSchema.stats() return stats end

-- one line at start: how it went
if type(CreateThread) == 'function' and type(Wait) == 'function' then
    CreateThread(function()
        Wait(20000)
        if stats.tables == 0 then return end
        if stats.failed > 0 then
            loud({ ('schema check: %d problem(s): %s'):format(stats.failed, table.concat(stats.problems, ', ')),
                'scroll up for the SQL to run by hand' })
        else
            print(('[es_mdt] schema check: %d tables OK%s'):format(stats.tables,
                stats.fixed > 0 and (', %d missing column(s)/key(s) added'):format(stats.fixed) or ''))
        end
    end)
end
