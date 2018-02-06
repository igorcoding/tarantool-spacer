local fun = require 'fun'


local function index_key(space, index, t)
    return fun.map(
        function(p) return t[p.fieldno] end,
        box.space[space].index[index].parts
    ):totable()
end

return {
    index_key = index_key,
}
