
-- USAGE --

--[[
spacer.create_space('space1', {
	{ name='id', type='num' },              -- 1
	{ name='name', type='str' },            -- 2
	{ name='type', type='str' },            -- 3
	{ name='status', type='str' },          -- 4
	{ name='extra', type='*' },             -- 5
	
}, {
	{ name = 'primary', type = 'hash', parts = { 'id' } },
	{ name = 'type', type = 'tree', unique = false, parts = { 'type', 'status' } },
})

spacer.create_space('space2', {
	{ name='id', type='num' },              -- 1
	{ name='name', type='str' },            -- 2
	{ name='type', type='str' },            -- 3
	{ name='status', type='str' },          -- 4
	{ name='extra', type='*' },             -- 5
	
}, {
	{ name = 'primary', type = 'hash', unique = true, parts = { 'id' } },
}, {
	engine = 'sophia'
})

spacer.duplicate_space('space3', 'space1') -- will be identical to space1 (structure + indexes)
spacer.duplicate_space('space4', 'space1', {
	indexes = {
		{ name = 'status', type = 'tree', unique = false, parts = { 'status' } },
	}
}) -- will be identical to space1 (structure + indexes, extra indexes will be created)
spacer.duplicate_space('space5', 'space1', {
	dupindex = false
}) -- will be identical to space1 (only structure, indexes will be omitted)
spacer.duplicate_space('space6', 'space1', {
	dupindex = false,
	indexes = {
		{ name = 'status', type = 'tree', unique = false, parts = { 'status' } },
	}
}) -- will be identical to space1 (only structure, indexes will be omitted, extra indexes will be created)
--]]

local log = require('log')
local msgpack = require('msgpack')

local F = {}
local T = {}

local function _tuple2hash ( f )
	local idx = {}
	for k,v in pairs(f) do
		if type(v) == 'number' then
			idx[ v ] = k
		end
	end
	local rows = {}
	for k,v in ipairs(idx) do
		table.insert(rows,"\t"..v.." = t["..tostring(k).."];\n")
	end
	return dostring("return function(t) return {\n"..table.concat(rows, "").."} end\n")
end

local function _hash2tuple ( f )
	local idx = {}
	for k,v in pairs(f) do
		if type(v) == 'number' then
			idx[ v ] = k
		end
	end
	local rows = {}
	for k,v in ipairs(idx) do
		if k < #idx then
			table.insert(rows,"\th."..v..",\n")
		else
			table.insert(rows,"\th."..v.." or require'msgpack'.NULL\n")
		end
	end
	return dostring("return function(h) return box.tuple.new({\n"..table.concat(rows, "").."}) end\n")
end

local function init_tuple_info(space_name, format)
	F[space_name] = {}
	F[space_name]['_'] = {}
	for k, v in pairs(format) do
		F[space_name][v.name] = k
		F[space_name]['_'][v.name] = {
			fieldno = k,
			type = v.type
		}
	end
	T[space_name] = {}
	T[space_name].hash = _tuple2hash( F[space_name] )
	T[space_name].dict = T[space_name].hash
	T[space_name].tuple = _hash2tuple( F[space_name] )
end

local function init_all_spaces_info()
	local spaces = box.space._space:select{}
	for _, sp in pairs(spaces) do
		init_tuple_info(sp[3], sp[7])
	end
end

local function get_changed_opts_for_index(existing_index, ind_opts)
	if existing_index == nil or ind_opts == nil then
		return nil
	end
	
	local changed_opts = {}
	local changed_opts_count = 0
	
	if ind_opts.unique == nil then
		ind_opts.unique = true  -- default value of unique
	end
	
	local index_type = string.lower(existing_index.type)
	if index_type ~= 'bitset' and index_type ~= 'rtree' and existing_index.unique ~= ind_opts.unique then
		changed_opts.unique = ind_opts.unique
		changed_opts_count = changed_opts_count + 1
	end
	
	if index_type ~= string.lower(ind_opts.type) then
		changed_opts.type = ind_opts.type
		changed_opts_count = changed_opts_count + 1
	end
	
	if ind_opts.type == 'rtree' then
		if ind_opts.dimension == nil then
			ind_opts.dimension = 2  -- default value for dimension
		end
		
		if ind_opts.distance == nil then
			ind_opts.distance = 'euclid'  -- default value for distance
		end
		
		if existing_index.dimension ~= ind_opts.dimension then
			changed_opts.dimension = ind_opts.dimension
			changed_opts_count = changed_opts_count + 1
		end
		
		if existing_index.distance ~= ind_opts.distance then
			changed_opts.distance = ind_opts.distance
			changed_opts_count = changed_opts_count + 1
		end
	end
	
	local parts_changed = false
	if ind_opts.parts == nil then
		ind_opts.parts = { 1, 'NUM' }  -- default value when parts = nil
	else
		for i, part in pairs(existing_index.parts) do
			local j = i * 2 - 1
			local want_field_no = ind_opts.parts[j]
			local want_field_type = ind_opts.parts[j + 1]
			
			if want_field_no ~= part.fieldno or string.lower(want_field_type) ~= string.lower(part.type) then
				parts_changed = true
			end
		end
	end
	
	if parts_changed then
		changed_opts.parts = ind_opts.parts
		changed_opts_count = changed_opts_count + 1
	end

	if changed_opts_count == 0 then
		return nil
	end
	
	return changed_opts
end

local function init_indexes(space_name, indexes, keep_obsolete)
	local sp = box.space[space_name]
	
	local created_indexes = {}
	
	-- initializing new indexes
	local name = space_name
	if indexes ~= nil then
		for _, ind in ipairs(indexes) do
			assert(ind.name ~= nil, "Index name cannot be null")
			local ind_opts = {}
			ind_opts.id = ind.id
			ind_opts.type = string.lower(ind.type)
			ind_opts.unique = ind.unique
			ind_opts.if_not_exists = ind.if_not_exists
			
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
				for _, p in pairs(ind.parts) do
					if F[name][p] ~= nil and F[name]['_'][p] ~= nil then
						table.insert(ind_opts.parts, F[name][p])
						table.insert(ind_opts.parts, F[name]['_'][p].type)
					else
						box.error{reason=string.format("Field %s.%s not found", name, p)}
					end
				end
			end
			local existing_index = sp.index[ind.name]
			if existing_index ~= nil then
				local changed_opts = get_changed_opts_for_index(existing_index, ind_opts)
				
				if changed_opts then
					log.info("Altering index '%s' of space '%s'.", ind.name, space_name)
					sp.index[ind.name]:alter(changed_opts)
				end
			else
				log.info("Creating index '%s' of space '%s'.", ind.name, space_name)
				existing_index = sp:create_index(ind.name, ind_opts)
			end
			created_indexes[existing_index.id] = true
		end
	end
	if not created_indexes[0] then
		box.error{reason=string.format("No index #0 defined for space '%s'", space_name)}
	end
	
	-- check obsolete indexes in space
	if not keep_obsolete then
		local sp_indexes = box.space._index:select({sp.id})
		for _,ind in ipairs(sp_indexes) do
			ind = {id = ind[F._index.iid], name = ind[F._index.name]}
			
			if ind.id ~= 0 and (not created_indexes[0] or not created_indexes[ind.id]) then
				log.info("Dropping index %d/'%s' of space '%s'.", ind.id, ind.name, space_name)
				sp.index[ind.id]:drop()
			end
		end
		if not created_indexes[0] then
			log.info("Dropping index #0 of space '%s'.", space_name)
			sp.index[0]:drop()
		end
	end
end

local function create_space(name, format, indexes, opts)
	assert(name ~= nil, "Space name cannot be null")

	local sp = box.space[name]
	if sp == nil or (opts and opts.if_not_exists) then
		sp = box.schema.space.create(name, opts)
	else
		log.info("Space '%s' is already created. Updating meta information.", name)
	end
	sp:format(format)
	init_tuple_info(name, format)

	init_indexes(name, indexes)
	if not indexes then
		log.warn("No indexes for space '%s' provided.", name)
	end
	log.info("Finished processing space '%s'.", name)
	return sp
end

function duplicate_space(new_space, old_space, opts)
	assert(new_space ~= nil, "Space name (new_space) cannot be null")
	assert(old_space ~= nil, "Space name (old_space) cannot be null")
	assert(box.space[old_space] ~= nil, "Space " .. old_space .. " does not exist")
	if opts == nil then
		opts = {}
	end
	
	local dupindex = opts['dupindex'] == nil or opts['dupindex'] == true
	local extra_indexes = opts['indexes']
	
	opts['dupindex'] = nil
	opts['indexes'] = nil
	
	local sp = box.space[new_space]
	if sp == nil or opts.if_not_exists then
		sp = box.schema.space.create(new_space, opts)
	else
		log.info("Space '%s' is already created. Updating meta information.", new_space)
	end
	local format = box.space._space.index.name:get({old_space})[F._space.format]
	
	sp:format(format)
	init_tuple_info(new_space, format)
	
	local new_indexes = {}
	if dupindex then  -- then copy indexes from old_space
		log.info("Duplicating indexes for '%s'", new_space)
		local old_space_id = box.space[old_space].id
		local old_indexes = box.space._index:select({old_space_id})
		
		for k1, ind in ipairs(old_indexes) do
			local new_index = {}
			new_index['name'] = ind[F._index.name]
			new_index['type'] = ind[F._index.type]
			new_index['unique'] = ind[F._index.opts]['unique']
			new_index['parts'] = {}
			for _, old_part in ipairs(ind[F._index.parts]) do
				local fieldno = old_part[1] + 1
				table.insert(new_index['parts'], format[fieldno]['name'])
			end
			
			table.insert(new_indexes, new_index)
		end
	end
	
	if extra_indexes then
		for _,ind in ipairs(extra_indexes) do
			table.insert(new_indexes, ind)
		end
	end
	init_indexes(new_space, new_indexes)
	log.info("Finished processing space '%s'.", new_space)
	return sp
end

local function tuple_unpack(tuple, f_info)
	local t = {}
	for field_name, fieldno in pairs(f_info) do
		if field_name ~= '_' then
			t[field_name] = tuple[fieldno] or msgpack.NULL
		end
	end
	return t
end

local function tuple_pack(t, f_info)
	local tuple = {}
	for field_name, fieldno in pairs(f_info) do
		if field_name ~= '_' then
			tuple[fieldno] = t[field_name]
		end
	end
	return box.tuple.new(tuple)
end


init_all_spaces_info()
rawset(_G, 'F', F)
rawset(_G, 'T', T)

return {
	F = F,
	T = T,
	create_space = create_space,
	duplicate_space = duplicate_space,
	tuple_unpack = tuple_unpack,
	tuple_pack = tuple_pack,
}
