local msgpack = require 'msgpack'

local compat = require 'spacer.compat'
local inspect = require 'spacer.myinspect'
local ops = require 'spacer.ops'
local stmt_obj = require 'spacer.stmt'


local function generate_field_info(space_format)
    local f = {}
    local f_extra = {}
	for k, v in ipairs(space_format) do
		f[v.name] = k

        local is_nullable = v.is_nullable
        if is_nullable == nil then
            is_nullable = false
        end

		f_extra[v.name] = {
			fieldno = k,
			type = v.type,
            is_nullable = is_nullable,
            collation = v.collation,
		}
	end
	return f, f_extra
end


local function get_changed_opts_for_index(spacer, space_name, existing_index, ind_opts)
	if existing_index == nil or ind_opts == nil then
		return nil
	end

    local space_tuple = box.space._vspace.index.name:get({space_name})
    assert(space_tuple ~= nil, string.format('Space "%s" not found', space_name))
    local index_tuple = box.space._vindex:get({space_tuple[1], existing_index.id})
    assert(index_tuple ~= nil, string.format('Index #%d not found in space "%s"', existing_index.id, space_name))

	local opts_up = {}
	local opts_down = {}

	local changed_opts_count = 0

	if ind_opts.unique == nil then
		ind_opts.unique = true  -- default value of unique
	end

	local index_type = string.lower(existing_index.type)
	if index_type ~= 'bitset' and index_type ~= 'rtree' and existing_index.unique ~= ind_opts.unique then
		opts_up.unique = ind_opts.unique
        opts_down.unique = existing_index.unique
		changed_opts_count = changed_opts_count + 1
	end

	if index_type ~= string.lower(ind_opts.type) then
		opts_up.type = ind_opts.type
		opts_down.type = index_type
		changed_opts_count = changed_opts_count + 1
	end

	if true then  -- check sequence changes
		local existing_seq
		local seq_changed = false

        local fld_sequence_name = 3
        local old_sequence_value

		if existing_index.sequence_id ~= nil then
			-- check if some sequence actually exist
			existing_seq = box.space._sequence:get({existing_index.sequence_id})
		end

		if type(ind_opts.sequence) == 'boolean' then
			-- user specified just 'true' or 'false' as sequence, so any sequence is ok
			if ind_opts.sequence == true and existing_seq == nil then
				seq_changed = true
                old_sequence_value = msgpack.NULL
			elseif ind_opts.sequence == false and existing_seq ~= nil then
				seq_changed = true
                old_sequence_value = existing_seq[fld_sequence_name]
			end
		elseif ind_opts.sequence == nil then
			-- changed to not using sequence
			if existing_seq ~= nil then
				seq_changed = true
                old_sequence_value = existing_seq[fld_sequence_name]
			end
		elseif type(ind_opts.sequence) == 'string' then
			if existing_seq == nil or existing_seq[fld_sequence_name] ~= ind_opts.sequence then
				seq_changed = true
                old_sequence_value = existing_seq[fld_sequence_name]
			end
		else
			seq_changed = true
            old_sequence_value = existing_seq[fld_sequence_name]
		end

		if seq_changed then
			opts_up.sequence = ind_opts.sequence
            opts_down.sequence = old_sequence_value
			changed_opts_count = changed_opts_count + 1
		end
	end

	if ind_opts.type == 'rtree' then
		if ind_opts.dimension == nil then
			ind_opts.dimension = 2  -- default value for dimension
		end

		if ind_opts.distance == nil then
			ind_opts.distance = 'euclid'  -- default value for distance
		end

		if existing_index.dimension ~= ind_opts.dimension then
			opts_up.dimension = ind_opts.dimension
            opts_down.dimension = existing_index.dimension
			changed_opts_count = changed_opts_count + 1
		end

		if existing_index.distance ~= ind_opts.distance then
			opts_up.distance = ind_opts.distance
            opts_down.distance = existing_index.distance
			changed_opts_count = changed_opts_count + 1
		end
	end

	local parts_changed = false
    assert(ind_opts.parts ~= nil, 'index parts must not be nil')
    local old_parts = compat.normalize_index_tuple_format(index_tuple[6])
    local new_parts = compat.normalize_index_tuple_format(ind_opts.parts)

    if #old_parts ~= #new_parts then
        parts_changed = true
    else
        for i, _ in ipairs(old_parts) do
            local old_part = old_parts[i]
            local new_part = new_parts[i]

            for k, _ in pairs(old_part) do
                -- check all keys (fieldno, type, is_nullable, collation, ...)
                if old_part[k] ~= new_part[k] then
                    parts_changed = true
                    break
                end
            end
        end
    end

	if parts_changed then
		opts_up.parts = compat.index_parts_from_normalized(new_parts)
        opts_down.parts = compat.index_parts_from_normalized(old_parts)
		changed_opts_count = changed_opts_count + 1
	end

	if changed_opts_count == 0 then
		return nil, nil
	end

	return opts_up, opts_down
end


local function build_opts_for_index(spacer, space_name, index_id)
    local sp = box.space[space_name]
    if sp == nil then
        return nil
    end

    local ind = sp.index[index_id]
    if ind == nil then
        return nil
    end

    local raw_index_options = box.space._index:get({sp.id, ind.id})
    if raw_index_options == nil then
        return nil
    end
    raw_index_options = raw_index_options[5]

    local index_opts = {}

    index_opts.type = ind.type
    index_opts.unique = ind.unique
    index_opts.distance = raw_index_options.distance
    index_opts.dimension = raw_index_options.dimension
    if ind.sequence_id ~= nil then
        index_opts.sequence = true
    end

    index_opts.parts = {}
    for _, p in ipairs(ind.parts) do
        local part = {p.fieldno, p.type}
        part.is_nullable = p.is_nullable
        part.collation = p.collation

        table.insert(index_opts.parts, part)
    end

    return index_opts
end


local function indexes_migration(spacer, stmt, space_name, indexes, f, f_extra)
    local created_indexes = {}

    for _, ind in ipairs(indexes) do
        assert(ind.name ~= nil, string.format("Index name cannot be null (space '%s')", space_name))

        local ind_opts = {}
        ind_opts.id = ind.id
        ind_opts.type = string.lower(ind.type)
        ind_opts.unique = ind.unique
        ind_opts.if_not_exists = ind.if_not_exists
        ind_opts.sequence = ind.sequence

        if ind_opts.type == 'rtree' then
            if ind.dimension ~= nil then
                ind_opts.dimension = ind.dimension
            end

            if ind.distance ~= nil then
                ind_opts.distance = ind.distance
            end
        end

        if ind.parts ~= nil then
            ind_opts.parts = compat.index_parts_from_fields(space_name, ind.parts, f_extra)
        end

        local sp = box.space[space_name]
        local existing_index
        if sp ~= nil then
            existing_index = sp.index[ind.name]
        end
        if existing_index == nil then
            stmt:up('box.space.%s:create_index(%s, %s)', space_name, inspect(ind.name), inspect(ind_opts))
            stmt:down('box.space.%s.index.%s:drop()', space_name, ind.name)
        else
            local opts_up, opts_down = get_changed_opts_for_index(spacer, space_name, existing_index, ind_opts)
            if opts_up then
                stmt:up('box.space.%s.index.%s:alter(%s)', space_name, ind.name, inspect(opts_up))
            end

            if opts_down then
                stmt:down('box.space.%s.index.%s:alter(%s)', space_name, ind.name, inspect(opts_down))
            end
        end

        created_indexes[ind.name] = true
    end

    -- check obsolete indexes in space
	if not spacer.keep_obsolete_indexes then
        local sp = box.space[space_name]
        if sp ~= nil then
            local sp_indexes = box.space._index:select({sp.id})
            local primary_index_name
            for _,ind in ipairs(sp_indexes) do
                -- finding primary index
                ind = {id = ind[spacer.F._index.iid], name = ind[spacer.F._index.name]}
                if ind.id == 0 then
                    primary_index_name = ind.name
                end
            end

            if not created_indexes[primary_index_name] then
                -- primary index recreation must be first
                local ind_opts = build_opts_for_index(spacer, space_name, 0)
                stmt:down('box.space.%s:create_index(%s, %s)', space_name, inspect(primary_index_name), inspect(ind_opts))
            end

            for _,ind in ipairs(sp_indexes) do
                ind = {id = ind[spacer.F._index.iid], name = ind[spacer.F._index.name]}

                if ind.id ~= 0 and not created_indexes[ind.name] then
                    local ind_opts = build_opts_for_index(spacer, space_name, ind.id)
                    stmt:up('box.space.%s.index.%s:drop()', space_name, ind.name)
                    stmt:down('box.space.%s:create_index(%s, %s)', space_name, inspect(ind.name), inspect(ind_opts))
                end
            end

            if not created_indexes[primary_index_name] then
                -- primary index drop must be last
                stmt:up('box.space.%s.index.%s:drop()', space_name, primary_index_name)
            end
        end
	end
end


local function find_format_changes(spacer, existing_format, new_format)
    -- ignores type changes, field removals and field renames
    local changes = {}

    local min_length = math.min(#existing_format, #new_format)
    for fieldno = 1, min_length do
        local old_field = existing_format[fieldno]
        local new_field = new_format[fieldno]

        old_field.type = string.lower(old_field.type)
        new_field.type = string.lower(new_field.type)

        if old_field.type == new_field.type and old_field.name ~= new_field.name then
            -- field rename
            error([[Seems like you are trying to rename field.
            It is illegal in automatic migrations.
            Either write a migration with new format scheme
            or add new fields at the bottom of format list]])
        end

        if old_field.type ~= new_field.type and old_field.name == new_field.name then
            error('Field type changes are not supported yet')
        end

        if old_field.is_nullable ~= new_field.is_nullable
                or old_field.collation ~= new_field.collation then
            table.insert(changes, {
                type = 'alter',
                fieldno = fieldno,
                field_name = new_field.name,
                field_type = new_field.type,
                is_nullable = new_field.is_nullable,
                collation = new_field.collation,
            })
        end
    end

    if #new_format < #existing_format then
        error('Format field removal is not supported yet')
    end

    for fieldno = #existing_format + 1, #new_format do
        local new_field = new_format[fieldno]

        table.insert(changes, {
            type = 'new',
            fieldno = fieldno,
            field_name = new_field.name,
            field_type = new_field.type,
            is_nullable = new_field.is_nullable,
            collation = new_field.collation,
        })
    end

    return changes
end


local function run_format_changes(spacer, stmt, space_name, format_changes)
    local index0 = box.space[space_name].index[0]
    assert(index0 ~= nil, string.format('Index #0 not found in space %s', space_name))

    local updates = {}
    local has_new_changes = false
    for _, ch in ipairs(format_changes) do
        if ch.type == 'new' then
            table.insert(updates, {'=', ch.fieldno, ops.get_default_for_type(ch.field_type)})
            has_new_changes = true
        end
    end

    if #updates > 0 then
        stmt:requires('moonwalker')
        stmt:requires('spacer.ops', 'ops')
        stmt:up([[moonwalker {
    space = box.space.%s,
    actor = function(t)
        local key = ops.index_key(%s, 0, t)
        box.space.%s:update(key, %s)
    end,
}]], space_name, inspect(space_name), space_name, inspect(updates))
    end

    if has_new_changes then
        stmt:down('assert(false, "Need to write explicitly a down migration for field removal")')
    end
end

local function spaces_migration(spacer, spaces_decl)
    local stmt = stmt_obj.new()

    for _, space_decl in pairs(spaces_decl) do
        local space_name = space_decl.space_name
        local space_format = space_decl.space_format
        local space_indexes = space_decl.space_indexes
        local space_opts = space_decl.space_opts

        assert(space_name ~= nil, "Space name cannot be null")
        assert(space_format ~= nil, "Space format cannot be null")
        assert(space_indexes ~= nil, "Space indexes cannot be null")

        local space_exists = box.space[space_name] ~= nil

        if not space_exists then
            local space_opts_str = 'nil'
            if space_opts ~= nil then
                space_opts_str = inspect(space_opts)
            end
            stmt:only_up()
            stmt:up_tx_begin()
            stmt:up('box.schema.create_space(%s, %s)', inspect(space_name), space_opts_str)
            stmt:up('box.space.%s:format(%s)', space_name, inspect(space_format))

            local f, f_extra = generate_field_info(space_format)
            indexes_migration(spacer, stmt, space_name, space_indexes, f, f_extra)

            stmt:only_up(false)
            stmt:down('box.space.%s:drop()', space_name)
        else
            -- if space already exists
            local sp_tuple = box.space._vspace.index.name:get({space_name})
            assert(sp_tuple ~= nil, string.format("Couldn't find space %s in _vspace", space_name))
            local existing_format = sp_tuple[7]
            local format_changes = find_format_changes(spacer, existing_format, space_format)

            stmt:up_tx_begin()
            stmt:down_tx_begin()
            if #format_changes > 0 then
                stmt:up('box.space.%s:format({})', space_name)  -- clear format
                stmt:down('box.space.%s:format({})', space_name)  -- clear format
                run_format_changes(spacer, stmt, space_name, format_changes)
                stmt:up_last('box.space.%s:format(%s)', space_name, inspect(space_format))
                stmt:down_last('box.space.%s:format(%s)', space_name, inspect(existing_format))
            end

            local f, f_extra = generate_field_info(space_format)
            indexes_migration(spacer, stmt, space_name, space_indexes, f, f_extra)
        end
    end

    stmt:up_tx_commit()
    stmt:down_tx_commit()

    return {
        requirements = stmt.requirements,
        up = stmt:build_up(),
        down = stmt:build_down()
    }
end

return {
    generate_field_info = generate_field_info,
    spaces_migration = spaces_migration
}
