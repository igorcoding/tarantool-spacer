local function tuple2hash ( f )
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

local function hash2tuple ( f )
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
            table.insert(rows,"\th."..v.." == nil and require'msgpack'.NULL or h."..v.."\n")
        end
    end
    return dostring("return function(h) return h and box.tuple.new({\n"..table.concat(rows, "").."}) or nil end\n")
end

return {
    tuple2hash = tuple2hash,
    hash2tuple = hash2tuple
}
