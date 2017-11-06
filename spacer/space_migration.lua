local inspect = require 'inspect'.inspect
local ops = require 'spacer.ops'


local function generate_field_info(space_format)
    local f = {}
    local f_extra = {}
	for k, v in pairs(space_format) do
		f[v.name] = k
		f_extra[v.name] = {
			fieldno = k,
			type = v.type
		}
	end
	return f, f_extra
end


local function indexes_migration(stmt, space_name, indexes, f, f_extra)
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
            ind_opts.parts = {}
            for _, p in ipairs(ind.parts) do
                if f[p] ~= nil and f_extra[p] ~= nil then
                    table.insert(ind_opts.parts, f[p])
                    table.insert(ind_opts.parts, f_extra[p].type)
                else
                    error(string.format("Field %s.%s not found", space_name, p))
                end
            end
        end

        local sp = box.space[space_name]
        local existing_index
        if sp ~= nil then
            existing_index = sp.index[ind.name]
        end
        if existing_index == nil then
            stmt.up('box.space.%s:create_index(%s, %s)', space_name, inspect(ind.name), inspect(ind_opts))
            stmt.down('box.space.%s.index.%s:drop()', space_name, ind.name)
        else
            error('altering index is not supported')
        end
    end
end


local function find_format_changes(existing_format, new_format)
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
            error('Field renames are not supported yet')
        end

        if old_field.type ~= new_field.type and old_field.name == new_field.name then
            error('Field type changes are not supported yet')
        end
    end

    if #new_format == #existing_format then
        return {}
    elseif #new_format < #existing_format then
        error('Fornat field removal is not supported yet')
    end

    for fieldno = #existing_format + 1, #new_format do
        table.insert(changes, {
            type = 'new',
            fieldno = fieldno,
            field_name = new_format[fieldno].name,
            field_type = new_format[fieldno].type,
        })
    end

    return changes
end


local function run_format_changes(stmt, space_name, format_changes)
    local index0 = box.space[space_name].index[0]
    assert(index0 ~= nil, string.format('Index #0 not found in space %s', space_name))

    local updates = {}
    for _, ch in ipairs(format_changes) do
        if ch.type == 'new' then
            table.insert(updates, {'=', ch.fieldno, ops.get_default_for_type(ch.field_type)})
        end
    end

    stmt.requires('moonwalker')
    stmt.requires('spacer.ops', 'ops')
    stmt.up([[moonwalker {
    space = box.space.%s,
    actor = function(t)
        local key = ops.index_key(%s, 0, t)
        box.space.%s:update(key, %s)
    end,
}]], space_name, inspect(space_name), space_name, inspect(updates))
    stmt.down('assert(false, "Need to write explicitly a down migration")')
end

local function spaces_migration(spaces_decl)

    local requirements = {}
    local statements_up = {}
    local statements_down = {}

    local stmt = {
        requires = function(req, name)
            requirements[req] = {
                name = name or req
            }
        end,
        up = function(f, ...)
            table.insert(statements_up, string.format(f, ...))
        end,
        down = function(f, ...)
            table.insert(statements_down, string.format(f, ...))
        end,
    }

    local stmt_up_only = {
        requires = stmt.requires,
        up = stmt.up,
        down = function(f, ...) end
    }

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
            stmt.up('box.schema.create_space(%s, %s)', inspect(space_name), space_opts_str)
            stmt.up('box.space.%s:format(%s)', space_name, inspect(space_format))

            local f, f_extra = generate_field_info(space_format)
            indexes_migration(stmt_up_only, space_name, space_indexes, f, f_extra)

            stmt.down('box.space.%s:drop()', space_name)
        else
            -- if space already exists
            local sp_tuple = box.space._vspace.index.name:get({space_name})
            assert(sp_tuple ~= nil, string.format("Couldn't find space %s in _vspace", space_name))
            local existing_format = sp_tuple[7]
            local format_changes = find_format_changes(existing_format, space_format)
            if #format_changes > 0 then
                run_format_changes(stmt, space_name, format_changes)
                stmt.up('box.space.%s:format(%s)', space_name, inspect(space_format))
            end

            -- TODO: detect indexes changes
        end
    end

    return {
        requirements = requirements,
        up = statements_up,
        down = statements_down
    }
end

return {
    spaces_migration = spaces_migration
}
