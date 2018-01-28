local inspect = require 'inspect'

local remove_all_metatables = function(item, path)
    if path[#path] ~= inspect.METATABLE then
        return item
    end
end

return function(...)
    return inspect.inspect(..., {process = remove_all_metatables})
end
