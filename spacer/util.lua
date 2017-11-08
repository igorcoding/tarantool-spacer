local fio = require 'fio'
local fun = require 'fun'
local fileio = require 'spacer.fileio'


local function make_mixin(src, mixin)
	for k, v in pairs(src) do
        if mixin[k] == nil then
            print(k, v)
            mixin[k] = v
        end
	end
	return mixin
end

local function string_split(inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    local i = 1
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        t[i] = str
        i = i + 1
    end
    return t
end


local function tabulate_string(body, tab)
    if tab == nil then
        tab = string.rep(' ', 4)
    end

    body = string_split(body, '\n')
    body = fun.iter(body):map(
        function(s) return tab .. s end
    ):totable()

    return table.concat(body, '\n')
end


local function reverse_table(tbl)
  for i=1, math.floor(#tbl / 2) do
    tbl[i], tbl[#tbl - i + 1] = tbl[#tbl - i + 1], tbl[i]
  end
end


local function read_migrations(path, direction, from_migration, n)
    local migrations = {}
    local files = fileio.listdir(path)

    if direction == 'down' then
        reverse_table(files)
    end

    for _, f in ipairs(files) do
        if f.mode == 'file' then
            local filename = fio.basename(f.path)
            local filename_no_ext = fio.basename(f.path, '.lua')
            local ver, name = string.match(filename_no_ext, '(%d+)_(.+)')
            if ver ~= nil and name ~= nil then
                ver = tonumber(ver)

                local cond = from_migration == nil or ver > from_migration
                if direction == 'down' then
                    cond = from_migration == nil or ver <= from_migration
                end
                if cond then
                    local data = fileio.read_file(f.path)
                    local compiled_code, err = loadstring(data)
                    if compiled_code == nil then
                        error(string.format("Error compiling migration '%s': \n%s", filename, err))
                    end
                    table.insert(migrations, {
                        ver = ver,
                        name = name,
                        path = f.path,
                        filename = filename,
                        migration = compiled_code
                    })
                end
            end

            if n ~= nil and #migrations == n then
                break
            end
        end
    end
    return migrations
end


return {
    make_mixin = make_mixin,
    string_split = string_split,
    tabulate_string = tabulate_string,
    read_migrations = read_migrations,
}
