local version_parse
local version_make

local function compare_versions(v1, v2)
    if type(v1) == 'string' then
        v1 = version_parse(v1)
    end
    if type(v2) == 'string' then
        v2 = version_parse(v2)
    end

    if v1 == nil or v1.ts == nil or v1.name == nil then
        error(string.format('version "%s" is invalid', version1))
    end

    if v2 == nil or v2.ts == nil or v2.name == nil then
        error(string.format('version "%s" is invalid', version2))
    end

    if v1.ts < v2.ts then
        return -1
    end

    if v1.ts > v2.ts then
        return 1
    end

    -- ts1 and ts2 are the smae

    if v1.name < v2.name then
        return -1
    end

    if v1.name > v2.name then
        return 1
    end

    return 0
end


local M = {}
M.__index = M

function M.new(ts, name)
    if ts == nil or name == nil then
        return nil
    end

    local self = setmetatable({}, M)
    self.ts = tonumber(ts) or NULL
    self.name = name
    return self
end

function M.parse(s)
    local ts, name = string.match(s, '(%d+)_(.+)')
    return M.new(ts, name)
end

function M.str(self, postfix)
    if postfix == nil then
        postfix = ''
    end
    return string.format("%d_%s%s", tonumber(self.ts), self.name, postfix)
end

function M.__tostring(self)
    return self:str()
end

function M.__eq(lhs, rhs)
    return compare_versions(lhs, rhs) == 0
end

function M.__lt(lhs, rhs)
    return compare_versions(lhs, rhs) < 0
end

M.__serialize = M.__tostring

return M
