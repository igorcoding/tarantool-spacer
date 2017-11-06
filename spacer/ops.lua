local fun = require 'fun'


local function index_key(space, index, t)
    return fun.map(
        function(p) return t[p.fieldno] end,
        box.space[space].index[index].parts
    ):totable()
end


local function get_default_for_type(type)
    type = string.lower(type)
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
    index_key = index_key,
    get_default_for_type = get_default_for_type,
}
