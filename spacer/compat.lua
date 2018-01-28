local ver = _TARANTOOL

local function index_parts_from_fields(space_name, fields, f_extra)
    if fields == nil then
        if ver >= "1.7" then
            return {{1, 'unsigned'}}
        else
            return {1, 'NUM'}
        end
    end

    if ver >= "1.7" then
        local parts = {}
        for _, p in ipairs(fields) do
            local part = {}
            local f_info = f_extra[p]
            if f_info ~= nil then
                table.insert(part, f_info.fieldno)
                table.insert(part, f_info.type)

                if ver >= "1.7.6" then
                    part.is_nullable = f_info.is_nullable
                    part.collation = f_info.collation
                end

                table.insert(parts, part)
            else
                error(string.format("Field %s.%s not found", space_name, p))
            end
        end
        return parts
    else
        local parts = {}
        for _, p in ipairs(fields) do
            local f_info = f_extra[p]
            if f_info ~= nil then
                table.insert(parts, f_info.fieldno)
                table.insert(parts, f_info.type)
            else
                error(string.format("Field %s.%s not found", space_name, p))
            end
        end
        return parts
    end
end

local function normalize_index_tuple_format(format)
    if format == nil then
        return nil
    end

    if #format == 0 then
        return {}
    end

    if type(format[1]) == 'table' then
        -- 1.7+ format

        local parts = {}
        for _, p in ipairs(format) do
            local part
            if #format[1] == 0 then
                -- 1.7.6+ format (with is_nullable or collation) like { {fieldno = 1, type = 'unsigned', is_nullable = true}, ... }
                local fieldno = p.fieldno
                if fieldno == nil then
                    fieldno = p.field + 1 -- because fields are indexed from 0 in raw tuples
                end
                part = {
                    fieldno  = fieldno,
                    ['type'] = p.type,
                    is_nullable = p.is_nullable,
                    collation = p.collation
                }
            else
                -- <1.7.6 format { {1, 'unsigned'}, {2, 'string'}, ... }
                -- but it can contain is_nullable and collation in a 'map' of each field
                part = {
                    fieldno  = p[1],
                    ['type'] = p[2],
                    is_nullable = p.is_nullable,
                    collation = p.collation
                }
            end

            table.insert(parts, part)
        end
        return parts
    else
        -- 1.6 format like {1, 'num', 2, 'string', ...}
        local parts = {}
        assert(#format % 2 == 0, 'format length must be even')
        for i = 1, #format, 2 do
            table.insert(parts, {
                fieldno  = format[i],
                ['type'] = format[i + 1],
                is_nullable = false,
                collation = nil
            })
        end
        return parts
    end
end


local function index_parts_from_normalized(normalized_parts)
    if ver >= "1.7" then
        local parts = {}
        for _, p in ipairs(normalized_parts) do
            local part = {p.fieldno, p.type}

            if ver >= "1.7.6" then
                part.is_nullable = p.is_nullable
                part.collation = p.collation
            end

            table.insert(parts, part)
        end
        return parts
    else
        local parts = {}
        for _, p in ipairs(normalized_parts) do
            table.insert(parts, p.fieldno)
            table.insert(parts, p.type)
        end
        return parts
    end
end


local function get_default_for_type(type, field_name, indexes_decl)
    type = string.lower(type)
    if indexes_decl == nil then
        indexes_decl = {}
    end

    if type == 'unsigned' or type == 'uint' or type == 'num' then
        return 0
    end

    if type == 'integer' or type == 'int' then
        return 0
    end

    if type == 'number' then
        return 0
    end

    if type == 'string' or type == 'str' then
        return ""
    end

    if type == 'boolean' then
        return false
    end

    if type == 'array' then
        if field_name == nil then
            return {}
        end

        for _, ind in ipairs(indexes_decl) do
            if string.lower(ind.type) == 'rtree'
                and #ind.parts > 0
                and ind.parts[1] == field_name then
                    local dim = ind.dimension
                    if dim == nil then
                        dim = 2
                    end

                    local t = {}
                    for _ = 1,dim do
                        table.insert(t, 0)
                    end
                    return t
            end
        end

        return {}
    end

    if type == 'map' then
        return setmetatable({}, {__serialize = 'map'})
    end

    if type == 'scalar' then
        return 0
    end

    error(string.format('unknown type "%s"', type))
end

return {
    index_parts_from_fields = index_parts_from_fields,
    normalize_index_tuple_format = normalize_index_tuple_format,
    index_parts_from_normalized = index_parts_from_normalized,
    get_default_for_type = get_default_for_type,
}
