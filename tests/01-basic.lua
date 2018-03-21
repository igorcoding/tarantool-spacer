#! /user/bin/env tarantool

package.path = "../?.lua;../?/init.lua;./?/init.lua;" .. package.path
package.cpath = "../?.so;../?.dylib;./?.so;./?.dylib;" .. package.cpath

local fiber = require 'fiber'
local fio = require 'fio'
local json = require 'json'
local tap = require 'tap'
local tnt = require 'tnt'

local function rmtree(path)
    for _, f in ipairs(fio.listdir(path)) do
        local f_path = fio.pathjoin(path, f)
        local f_stat = fio.stat(f_path)

        if f_stat:is_dir() then
            rmtree(f_path)
        else
            fio.unlink(f_path)
        end
    end
end

local function recreate_migrations()
    rmtree('./migrations')
    fio.mktree('./migrations')
end

local function cmp_parts(t, got, expected)
    t:is(#got, #expected, 'lengths are same')
    for i, p in ipairs(got) do
        t:is(p.fieldno, expected[i].fieldno, 'fieldno correct')
        t:is(p.type, expected[i].type, 'field type correct')
    end
end

local function spacer_up(t, spacer, ...)
    local err = spacer:migrate_up(...)
    if err ~= nil then
        t:fail(string.format('migrate_up failed: %s', json.encode(err)))
    else
        t:ok(true, 'migrate_up ok')
    end
end

local function spacer_down(t, spacer, ...)
    local err = spacer:migrate_down(...)
    if err ~= nil then
        t:fail(string.format('migrate_down failed: %s', json.encode(err)))
    else
        t:ok(true, 'migrate_down ok')
    end
end



local function spacer_create_space_object(spacer)
    local fmt = {
        { name = 'id', type = 'unsigned' }
    }
    spacer:space({
        name = 'object',
        format = fmt,
        indexes = {
            { name = 'primary', type = 'tree', unique = true, parts = { 'id' } }
        }
    })
    spacer:makemigration('object_init')
    spacer:migrate_up(1)
end

local function test__space_create(t, spacer)
    t:plan(11)

    local fmt = {
        { name = 'id', type = 'unsigned' }
    }
    spacer:space({
        name = 'object',
        format = fmt,
        indexes = {
            { name = 'primary', type = 'tree', unique = true, parts = { 'id' } }
        }
    })

    spacer:makemigration('object_init')
    spacer_up(t, spacer)

    local sp = box.space.object
    t:isnt(sp, nil, 'object space created')
    t:is_deeply(sp:format(), fmt, 'format correct')
    t:isnt(sp.index.primary, nil, 'primary index created')
    t:is(string.upper(sp.index.primary.type), 'TREE', 'type correct')
    t:is(sp.index.primary.unique, true, 'unique correct')

    cmp_parts(t, sp.index.primary.parts, {
        { fieldno = 1, type = 'unsigned' }
    })

    spacer_down(t, spacer)
    t:isnil(box.space.object, 'object deleted')
end


local function test__add_field_name_and_index(t, spacer)
    t:plan(15)

    spacer_create_space_object(spacer)
    fiber.sleep(1)  -- just to make sure migrations have different ids

    box.space.object:insert({1})

    local fmt = {
        { name = 'id', type = 'unsigned' },
        { name = 'name', type = 'string' },
    }

    spacer:space({
        name = 'object',
        format = fmt,
        indexes = {
            { name = 'primary', type = 'tree', unique = true, parts = { 'id' } },
            { name = 'name', type = 'hash', unique = true, parts = { 'name', 'id' } }
        }
    })

    spacer:makemigration('object_name')
    spacer_up(t, spacer)

    local sp = box.space.object
    t:is_deeply(sp:format(), fmt, 'format correct')
    t:isnt(sp.index.name, nil, 'name index created')
    t:is(string.upper(sp.index.name.type), 'HASH', 'type correct')
    t:is(sp.index.name.unique, true, 'unique correct')

    cmp_parts(t, sp.index.name.parts, {
        { fieldno = 2, type = 'string' },
        { fieldno = 1, type = 'unsigned' }
    })

    -- check tuples
    t:is(box.space.object:get({1})[2], '', 'name added')

    spacer_down(t, spacer)
    t:is_deeply(sp:format(), {
        { name = 'id', type = 'unsigned' },
    }, 'format correct')
    t:is(sp.index.name, nil, 'name index dropped')

    spacer_up(t, spacer)
end


local function test__alter_index_parts(t, spacer)
    t:plan(10)
    fiber.sleep(1)  -- just to make sure migrations have different ids

    local fmt = {
        { name = 'id', type = 'unsigned' },
        { name = 'name', type = 'string' },
    }

    spacer:space({
        name = 'object',
        format = fmt,
        indexes = {
            { name = 'primary', type = 'tree', unique = true, parts = { 'id' } },
            { name = 'name', type = 'hash', unique = true, parts = { 'name' } }
        }
    })

    spacer:makemigration('object_name_index_alter')
    spacer_up(t, spacer)

    local sp = box.space.object
    cmp_parts(t, sp.index.name.parts, {
        { fieldno = 2, type = 'string' },
    })

    spacer_down(t, spacer)
    cmp_parts(t, sp.index.name.parts, {
        { fieldno = 2, type = 'string' },
        { fieldno = 1, type = 'unsigned' },
    })
end


local function test__index_many_alters(t, spacer)
    t:plan(10)
    fiber.sleep(1)  -- just to make sure migrations have different ids

    local fmt = {
        { name = 'id', type = 'unsigned' },
        { name = 'name', type = 'string' },
    }

    spacer:space({
        name = 'object',
        format = fmt,
        indexes = {
            { name = 'primary', type = 'tree', unique = true, parts = { 'id' }, sequence = true },
            { name = 'name', type = 'tree', unique = false, parts = { 'name' } }
        }
    })

    spacer:makemigration('object_id_sequence')

    spacer_up(t, spacer)

    local sp = box.space.object
    t:is_deeply(sp:format(), fmt, 'format correct')
    t:isnt(sp.index.primary.sequence_id, nil, 'sequence created')
    t:is(string.upper(sp.index.name.type), 'TREE', 'name type changed')
    t:is(sp.index.name.unique, false, 'name unique changed')

    spacer_down(t, spacer)

    local sp = box.space.object
    t:is_deeply(sp:format(), fmt, 'format correct')
    t:is(sp.index.primary.sequence_id, nil, 'sequence dropped')
    t:is(string.upper(sp.index.name.type), 'HASH', 'name type changed')
    t:is(sp.index.name.unique, true, 'name unique changed')

    spacer:migrate_up()
end


local function test__add_rtree_index(t, spacer)
    t:plan(11)
    fiber.sleep(1)  -- just to make sure migrations have different ids

    local fmt = {
        { name = 'id', type = 'unsigned' },
        { name = 'name', type = 'string' },
        { name = 'arr', type = 'array' },
    }

    spacer:space({
        name = 'object',
        format = fmt,
        indexes = {
            { name = 'primary', type = 'tree', unique = true, parts = { 'id' }, sequence = true },
            { name = 'name', type = 'tree', unique = false, parts = { 'name' } },
            { name = 'rtree', type = 'rtree', dimension = 3, distance = 'euclid', unique = false, parts = { 'arr' } }
        }
    })
    spacer:makemigration('object_rtree')

    spacer_up(t, spacer)

    local sp = box.space.object
    t:is_deeply(sp:format(), fmt, 'format correct')
    t:is(string.upper(sp.index.rtree.type), 'RTREE', 'rtree created')
    t:isnil(sp.index.rtree.unique, 'unique correct')
    t:is(sp.index.rtree.dimension, 3, 'dimension correct')

    local _ind = box.space._vindex:get({sp.id, sp.index.rtree.id})
    t:is(_ind[5].distance, 'euclid', 'distance correct')

    cmp_parts(t, sp.index.rtree.parts, {
        { fieldno = 3, type = 'array' },
    })

    spacer_down(t, spacer)

    local sp = box.space.object
    t:isnil(sp.index.rtree, 'rtree deleted')

    spacer:migrate_up()
end


local function test__drop_rtree_index(t, spacer)
    t:plan(11)
    fiber.sleep(1)  -- just to make sure migrations have different ids

    local fmt = {
        { name = 'id', type = 'unsigned' },
        { name = 'name', type = 'string' },
        { name = 'arr', type = 'array' },
    }

    spacer:space({
        name = 'object',
        format = fmt,
        indexes = {
            { name = 'primary', type = 'tree', unique = true, parts = { 'id' }, sequence = true },
            { name = 'name', type = 'tree', unique = false, parts = { 'name' } },
        }
    })
    spacer:makemigration('object_rtree_del')
    spacer_up(t, spacer)

    local sp = box.space.object
    t:isnil(sp.index.rtree, 'rtree deleted')

    spacer_down(t, spacer)

    t:is_deeply(sp:format(), fmt, 'format correct')
    t:is(string.upper(sp.index.rtree.type), 'RTREE', 'rtree created')
    t:isnil(sp.index.rtree.unique, 'unique correct')
    t:is(sp.index.rtree.dimension, 3, 'dimension correct')

    local _ind = box.space._vindex:get({sp.id, sp.index.rtree.id})
    t:is(_ind[5].distance, 'euclid', 'distance correct')

    cmp_parts(t, sp.index.rtree.parts, {
        { fieldno = 3, type = 'array' },
    })

    spacer:migrate_up()
end


local function test__drop_space(t, spacer)
    t:plan(21)
    fiber.sleep(1)  -- just to make sure migrations have different ids

    spacer:space_drop('object')
    spacer:makemigration('object_drop')
    spacer_up(t, spacer)

    local sp = box.space.object
    t:isnil(sp, 'space dropped')

    spacer_down(t, spacer)
    local sp = box.space.object
    t:isnt(sp, nil, 'space recreated')
    t:is(sp.engine, 'memtx', 'engine ok')
    t:is(sp.temporary, false, 'temporary ok')
    t:is(sp.field_count, 0, 'field_count ok')
    -- t:is_deeply(sp:format(), fmt, 'format correct')

    t:isnt(sp.index.primary, nil, 'primary index recreated')
    t:isnt(sp.index.primary.sequence_id, nil, 'sequence created')
    t:is(string.upper(sp.index.primary.type), 'TREE', 'primary type ok')
    t:is(sp.index.primary.unique, true, 'primary unique ok')
    cmp_parts(t, sp.index.primary.parts, {
        { fieldno = 1, type = 'unsigned' },
    })

    t:isnt(sp.index.name, nil, 'name index recreated')
    t:is(string.upper(sp.index.name.type), 'TREE', 'name type ok')
    t:is(sp.index.name.unique, false, 'name unique ok')
    cmp_parts(t, sp.index.name.parts, {
        { fieldno = 2, type = 'string' },
    })

    spacer_up(t, spacer)
end


local function test__no_check_alter(t, spacer)
    t:plan(12)

    local fmt = {
        { name = 'id', type = 'unsigned' }
    }
    spacer:space({
        name = 'object',
        format = fmt,
        indexes = {
            { name = 'primary', type = 'tree', unique = true, parts = { 'id' } }
        }
    })

    fiber.sleep(1)  -- just to make sure migrations have different ids
    spacer:makemigration('object_init')
    spacer_up(t, spacer)

    -- recreating
    fiber.sleep(1)  -- just to make sure migrations have different ids
    spacer:makemigration('object_init2', {check_alter = false})

    spacer_up(t, spacer)

    local sp = box.space.object
    t:isnt(sp, nil, 'object space created')
    t:is_deeply(sp:format(), fmt, 'format correct')
    t:isnt(sp.index.primary, nil, 'primary index created')
    t:is(string.upper(sp.index.primary.type), 'TREE', 'type correct')
    t:is(sp.index.primary.unique, true, 'unique correct')

    cmp_parts(t, sp.index.primary.parts, {
        { fieldno = 1, type = 'unsigned' }
    })

    pcall(spacer.migrate_down, spacer, 100)  -- allow to fail as there are 2 identical migrations
    t:isnil(box.space.object, 'object deleted')
end


local function test__migrate_dummy(t, spacer)
    t:plan(3)

    local fmt = {
        { name = 'id', type = 'unsigned' }
    }
    spacer:space({
        name = 'object',
        format = fmt,
        indexes = {
            { name = 'primary', type = 'tree', unique = true, parts = { 'id' } }
        }
    })

    fiber.sleep(1)  -- just to make sure migrations have different ids
    spacer:makemigration('object_init')

    t:is(spacer:version_name(), nil, 'version is nil before migrate_dummy')
    spacer:migrate_dummy('object_init')

    t:is(spacer:version_name(), 'object_init', 'version up')
    t:is(spacer:models_space():select()[1][1], 'object', 'space registered')

    spacer:clear_schema()
end


local function test__old_format(t, spacer)
    recreate_migrations()
    spacer:clear_schema()
    t:plan(2)

    local s = box.schema.create_space('object')
    local f = {
        { name = 'id', type = 'unsigned' },
        { name = 'name', type = 'string' },
    }

    s:format(f)
    s:create_index('primary', {
        unique = true,
        parts = {
            { 1, 'unsigned' }, { 2, 'string' }
        }
    })
    spacer:space({
        name = 'object',
        format = f,
        indexes = {
            { name = 'primary', type = 'tree', unique = true, parts = { 'id', 'name' } }
        }
    })

    fiber.sleep(1)  -- just to make sure migrations have different ids
    spacer:makemigration('object_init', {check_alter = false})
    spacer:migrate_dummy('object_init')

    local res = spacer:_makemigration('test')
    res = res:gsub('\n', '')
    local up_body = res:match('up%s*=%s*function%(%)(.-)end'):gsub('%s+', '')
    local down_body = res:match('down%s*=%s*function%(%)(.-)end'):gsub('%s+', '')

    t:is(up_body, '', 'up body is empty')
    t:is(down_body, '', 'down body is empty')
end

local function main()
    tnt.cfg{}

    local spacer = require 'spacer'({
        migrations = './migrations',
        down_migration_fail_on_impossible = false,
    })

    tap.test('test__space_create', test__space_create, spacer)
    tap.test('test__add_field_name_and_index', test__add_field_name_and_index, spacer)
    tap.test('test__alter_index_parts', test__alter_index_parts, spacer)
    tap.test('test__index_many_alters', test__index_many_alters, spacer)
    tap.test('test__add_rtree_index', test__add_rtree_index, spacer)
    tap.test('test__drop_rtree_index', test__drop_rtree_index, spacer)
    tap.test('test__drop_space', test__drop_space, spacer)
    tap.test('test__no_check_alter', test__no_check_alter, spacer)
    tap.test('test__migrate_dummy', test__migrate_dummy, spacer)
    tap.test('test__old_format', test__old_format, spacer)

    rmtree('./migrations')
    tnt.finish()
    os.exit(0)
end

main()
