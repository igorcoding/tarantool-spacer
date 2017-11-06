local clock = require 'clock'
local fio = require 'fio'
local fun = require 'fun'
local log = require 'log'
local inspect = require 'inspect'.inspect

local fileio = require 'spacer.fileio'
local space_migration = require 'spacer.space_migration'
local util = require 'spacer.util'

local NULL = require 'msgpack'.NULL

local SCHEMA_KEY = '_spacer_ver'
local __models__ = {}

local function space(self, name, format, indexes, opts)
    assert(name ~= nil, "Space name cannot be null")
    assert(format ~= nil, "Space format cannot be null")
    assert(indexes ~= nil, "Space indexes cannot be null")
    __models__[name] = {
        type = 'raw',
        space_name = name,
        space_format = format,
        space_indexes = indexes,
        space_opts = opts,
    }
end


---
--- migrate_up function
---
local function migrate_up(self, _n)
    local n = tonumber(_n)
    if n == nil and _n ~= nil then
        error('n must be a number or nil')
    end

    local ver_t = box.space._schema:get({SCHEMA_KEY})
    local ver, name
    if ver_t ~= nil then
        ver = ver_t[2]
        name = ver_t[3]
    end

    local migrations = util.read_migrations(self.migrations_path, 'up', ver, n)

    if #migrations == 0 then
        log.info('No migrations to apply. Last migration: %s_%s', inspect(ver), inspect(name))
        return
    end

    for _, m in ipairs(migrations) do
        setfenv(m.migration, _G)
        local funcs = m.migration()
        assert(funcs ~= nil, 'Migration file should return { up = function() ... end, down = function() ... end } table')
        assert(funcs.up ~= nil, 'up function is required')
        local ok, err = pcall(funcs.up)
        if not ok then
            log.error('Error running migration %s: %s', m.filename, err)
            return false
        end

        box.space._schema:replace({SCHEMA_KEY, m.ver, m.name})
        log.info('Applied migration "%s"', m.filename)
    end

    return true
end


---
--- migrate_down function
---
local function migrate_down(self, _n)
    local n = tonumber(_n)
    if n == nil and _n ~= nil then
        error('n must be a number or nil')
    end

    if n == nil then
        n = 1
    end

    local ver_t = box.space._schema:get({SCHEMA_KEY})
    local ver, name
    if ver_t ~= nil then
        ver = ver_t[2]
        name = ver_t[3]
    end

    local migrations = util.read_migrations(self.migrations_path, 'down', ver, n + 1)

    if #migrations == 0 then
        if name == nil then
            name = 'nil'
        end
        log.info('No migrations to apply. Last migration: %s_%s', inspect(ver), name)
        return
    end

    for i, m in ipairs(migrations) do
        setfenv(m.migration, _G)
        local funcs = m.migration()
        assert(funcs ~= nil, 'Migration file should return { up = function() ... end, down = function() ... end } table')
        assert(funcs.down ~= nil, 'down function is required')
        local ok, err = pcall(funcs.down)
        if not ok then
            log.error('Error running migration %s: %s', m.filename, err)
            return false
        end

        local prev_migration = migrations[i + 1]
        if prev_migration == nil then
            box.space._schema:delete({SCHEMA_KEY})
        else
            box.space._schema:replace({SCHEMA_KEY, prev_migration.ver, prev_migration.name})
        end
        log.info('Rolled back migration "%s"', m.filename)
        n = n - 1
        if n == 0 then
            break
        end
    end

    return true
end


---
--- makemigration function
---
local function makemigration(self, name)
    assert(name ~= nil, 'Migration name is required')
    local date = clock.time()

    local count = 0
    for _, space_decl in pairs(__models__) do
        count = count + 1
    end

    if count == 0 then
        log.error('No spaces declared. Make sure to call spacer.space() function.')
        return
    end
    local migration = space_migration.spaces_migration(__models__)

    local requirements_body = table.concat(
        fun.iter(migration.requirements):map(
            function(key, r)
                return string.format("local %s = require '%s'", r.name, key)
            end):totable(),
        '\n')

    local tab = string.rep(' ', 8)
    local up_body = util.tabulate_string(table.concat(migration.up, '\n'), tab)
    local down_body = util.tabulate_string(table.concat(migration.down, '\n'), tab)

    local migration_body = string.format([[--
-- Migration "%s"
-- Date: %d - %s
--
%s

return {
    up = function()
%s
    end,

    down = function()
%s
    end,
}
]], name, date, os.date('%x %X', date), requirements_body, up_body, down_body)

    local path = fio.pathjoin(self.migrations_path, string.format('%d_%s.lua', date, name))
    fileio.write_to_file(path, migration_body)
    return migration_body
end

local M
if rawget(_G,'__spacer__') then
    M = rawget(_G,'__spacer__')
else
    M = setmetatable({
        migrations_path = NULL,
        __models__ = __models__,
    },{
        __call = function(M, migrations_path)
            assert(fileio.exists(migrations_path), string.format("Migrations path '%s' does not exist", migrations_path))
            M.migrations_path = migrations_path
            return M
        end,
        __index = {
            space = space,
            migrate_up = migrate_up,
            migrate_down = migrate_down,
            makemigration = makemigration
        }
    })
    rawset(_G, '__spacer__', M)
end

return M
