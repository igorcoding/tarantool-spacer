local clock = require 'clock'
local fio = require 'fio'
local fun = require 'fun'
local log = require 'log'
local inspect = require 'inspect'.inspect

local fileio = require 'spacer.fileio'
local space_migration = require 'spacer.migration'
local util = require 'spacer.util'
local transformations = require 'spacer.transformations'

local NULL = require 'msgpack'.NULL

local SCHEMA_KEY = '_spacer_ver'
local __models__ = {}
local F = {}
local F_FULL = {}
local T = {}


local function init_fields_and_transform(space_name, format)
    local f, f_extra = space_migration.generate_field_info(format)
    F[space_name] = f
    F_FULL[space_name] = f_extra
    T[space_name] = {}
    T[space_name].dict = transformations.tuple2hash(f)
	T[space_name].tuple = transformations.hash2tuple(f)
    T[space_name].hash = T[space_name].dict  -- alias
end


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
    init_fields_and_transform(name, format)
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
        if name == nil then
            name = 'nil'
        end
        log.info('No migrations to apply. Last migration: %s_%s', inspect(ver), name)
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
local function makemigration(self, name, autogenerate, nofile)
    assert(name ~= nil, 'Migration name is required')
    if autogenerate == nil then
        autogenerate = false
    end
    local date = clock.time()

    local count = 0
    for _, space_decl in pairs(__models__) do
        count = count + 1
    end

    if count == 0 then
        log.error('No spaces declared. Make sure to call spacer.space() function.')
        return
    end

    local requirements_body = ''
    local up_body = ''
    local down_body = ''
    if autogenerate then
        local migration = space_migration.spaces_migration(self, __models__)
        requirements_body = table.concat(
            fun.iter(migration.requirements):map(
                function(key, r)
                    return string.format("local %s = require '%s'", r.name, key)
                end):totable(),
            '\n')

        local tab = string.rep(' ', 8)
        up_body = util.tabulate_string(table.concat(migration.up, '\n'), tab)
        down_body = util.tabulate_string(table.concat(migration.down, '\n'), tab)
    end

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

    if not nofile then
        local path = fio.pathjoin(self.migrations_path, string.format('%d_%s.lua', date, name))
        fileio.write_to_file(path, migration_body)
    end
    return migration_body
end

local function _clear_schema(self)
    box.space._schema:delete({SCHEMA_KEY})
end

local M
if rawget(_G,'__spacer__') then
    M = rawget(_G,'__spacer__')
else
    M = setmetatable({
        migrations_path = NULL,
        __models__ = __models__,
        F = F,
        F_FULL = F_FULL,
        T = T,
    },{
        __call = function(M, user_opts)
            local valid_options = {
                migrations = {
                    required = true
                },
                global_ft = {
                    required = false,
                    default = true,
                },
            }

            local opts = {}
            local invalid_options = {}
            -- check user provided options
            for key, value in pairs(user_opts) do
                local opt_info = valid_options[key]
                if opt_info == nil then
                    table.insert(invalid_options, key)
                else
                    if opt_info.required and value == nil then
                        error(string.format('Option "%s" is required', key))
                    elseif value == nil then
                        opts[key] = opt_info.default
                    else
                        opts[key] = value
                    end
                end
            end

            if #invalid_options > 0 then
                error(string.format('Unknown options provided: [%s]', table.concat(invalid_options, ', ')))
            end

            -- check that user provided all required options
            for valid_key, opt_info in pairs(valid_options) do
                local value = user_opts[valid_key]
                if opt_info.required and value == nil then
                    error(string.format('Option "%s" is required', valid_key))
                elseif user_opts[valid_key] == nil then
                    opts[valid_key] = opt_info.default
                else
                    opts[valid_key] = value
                end
            end

            assert(fileio.exists(opts.migrations), string.format("Migrations path '%s' does not exist", opts.migrations))
            M.migrations_path = opts.migrations

            -- initialize current spaces fields and transformations
            local spaces = box.space._vspace:select{}
            for _, sp in ipairs(spaces) do
                init_fields_and_transform(sp[3], sp[7])
            end

            if opts.global_ft then
                rawset(_G, 'F', F)
                rawset(_G, 'F_FULL', F_FULL)
                rawset(_G, 'T', T)
            end

            return M
        end,
        __index = {
            space = space,
            migrate_up = migrate_up,
            migrate_down = migrate_down,
            makemigration = makemigration,
            _clear_schema = _clear_schema,
        }
    })
    rawset(_G, '__spacer__', M)
end

return M
