
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
	engine = 'vinyl'
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

spacer.duplicate_space('vy_space1', 'space1', {
	engine = 'vinyl'
}) -- will be identical to space1 (but in engine = 'vinyl')
--]]

local digest = require 'digest'
local log = require 'log'
local msgpack = require 'msgpack'

local compat = require 'spacer.compat'

local SPACER_V1_SCHEMA_PREFIX = '_spacer_v1'

local spacer = {}
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
	return dostring("return function(t) return t and {\n"..table.concat(rows, "").."} or nil end\n")
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
			table.insert(rows,"\th."..v.." or h."..v.." == nil and require'msgpack'.NULL\n")
		end
	end
	return dostring("return function(h) return h and box.tuple.new({\n"..table.concat(rows, "").."}) or nil end\n")
end

local function init_tuple_info(space_name, format)
	if format == nil then
		return
	end

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

local function _space_format_hash(format)
	local sig = ''

	if format == nil then
		sig = 'nil'
	else
		for _, part in ipairs(format) do
			if part.name == nil then
				error('part name cannot be null')
			end

			if part.type == nil then
				error('part type cannot be null')
			end

			sig = sig .. ';' .. part.name .. ':' .. part.type
		end
	end

	sig = _TARANTOOL .. '!' .. sig
	return digest.md5_hex(sig)
end

local function _check_space_format_changed(space, format)
	assert(space ~= nil, 'space name must be non-nil')
	local sig = _space_format_hash(format)

	local key = SPACER_V1_SCHEMA_PREFIX .. ':' .. space .. ':formatsig'
	local t = box.space._schema:get({key})
	if t ~= nil then
		local cur_sig = t[2]
		if sig == cur_sig then
			return false
		end
	end

	box.space._schema:replace({key, sig})
	return true
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

	if ind_opts.type == nil then
		ind_opts.type = 'tree'
	else
		ind_opts.type = string.lower(ind_opts.type)
	end

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

	if true then  -- check sequence changes
		local existsing_seq
		local seq_changed = false

		if existing_index.sequence_id ~= nil then
			-- check if some sequence actually exist
			existsing_seq = box.space._sequence:get({existing_index.sequence_id})
		end

		if type(ind_opts.sequence) == 'boolean' then
			-- user specified just 'true' or 'false' as sequence, so any sequence is ok
			if ind_opts.sequence == true and existsing_seq == nil then
				seq_changed = true
			elseif ind_opts.sequence == false and existsing_seq ~= nil then
				seq_changed = true
			end
		elseif ind_opts.sequence == nil then
			-- changed to not using sequence
			if existsing_seq ~= nil then
				seq_changed = true
			end
		elseif type(ind_opts.sequence) == 'string' then
			local fld_sequence_name = 3
			if existsing_seq == nil or existsing_seq[fld_sequence_name] ~= ind_opts.sequence then
				seq_changed = true
			end
		else
			seq_changed = true
		end

		if seq_changed then
			changed_opts.sequence = ind_opts.sequence
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
		if #existing_index.parts ~= #ind_opts.parts / 2 then
			parts_changed  = true
		else
			for i, part in ipairs(existing_index.parts) do
				local j = i * 2 - 1
				local want_field_no = ind_opts.parts[j]
				local want_field_type = ind_opts.parts[j + 1]

				local want_field_type = compat.compat_type(want_field_type)
				local have_field_type = compat.compat_type(part.type)

				if want_field_no ~= part.fieldno or want_field_type ~= have_field_type then
					parts_changed = true
				end
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
			ind_opts.type = ind.type
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

					local index_obj = sp.index[ind.name]
					local ok, data = pcall(index_obj.alter, index_obj, changed_opts)
					if not ok then
						log.error("Error altering index '%s' of space '%s': %s", ind.name, space_name, data)
					end
				end
			else
				log.info("Creating index '%s' of space '%s'.", ind.name, space_name)
				local ok, data = pcall(sp.create_index, sp, ind.name, ind_opts)
				if ok then
					existing_index = data
				else
					log.error("Error creating index '%s' of space '%s': %s", ind.name, space_name, data)
					existing_index = nil
				end
			end
			if existing_index ~= nil then
				created_indexes[existing_index.id] = true
			end
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

	if _check_space_format_changed(name, format) then
		log.info("Updating format for space '%s'", name)
		sp:format(format)
	end
	init_tuple_info(name, format)

	init_indexes(name, indexes)
	if not indexes then
		log.warn("No indexes for space '%s' provided.", name)
	end
	log.info("Finished processing space '%s'.", name)
	return sp
end

local function duplicate_space(new_space, old_space, opts)
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

	if _check_space_format_changed(new_space, format) then
		log.info("Updating format for space '%s'", new_space)
		sp:format(format)
	end
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
	log.warn('tuple_unpack(t, f_info) is deprecated. Use T.<space_name>.dict(t) instead.')
	local t = {}
	for field_name, fieldno in pairs(f_info) do
		if field_name ~= '_' then
			t[field_name] = tuple[fieldno] or msgpack.NULL
		end
	end
	return t
end

local function tuple_pack(t, f_info)
	log.warn('tuple_pack(t, f_info) is deprecated. Use T.<space_name>.tuple(t) instead.')
	local tuple = {}
	for field_name, fieldno in pairs(f_info) do
		if field_name ~= '_' then
			tuple[fieldno] = t[field_name]
		end
	end
	return box.tuple.new(tuple)
end

local function create_space_stub(new_space)
	log.info("Skipping spacer create_space() action for '%s', because database in read only mode.", new_space)
end

local function duplicate_space_stub(new_space)
	log.info("Skipping spacer duplicate_space() action for '%s', because database in read only mode.", new_space)
end


init_all_spaces_info()
rawset(_G, 'F', F)
rawset(_G, 'T', T)

spacer.F = F
spacer.T = T
spacer.tuple_pack = tuple_pack
spacer.tuple_unpack = tuple_unpack

if box.cfg.read_only then
	spacer.create_space = create_space_stub
	spacer.duplicate_space = duplicate_space_stub
else
	spacer.create_space = create_space
	spacer.duplicate_space = duplicate_space
end

return spacer
