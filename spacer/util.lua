local fio = require 'fio'
local fun = require 'fun'
local fileio = require 'spacer.fileio'
local lversion = require 'spacer.version'

local NULL = require 'msgpack'.NULL

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


local function compile_migration(data)
    return loadstring(data)
end

local function _list_migration_files(path)
    local res = {}
    local files = fileio.listdir(path)
    for _, f in ipairs(files) do
        if f.mode == 'file' then
            local filename = fio.basename(f.path)
            local filename_no_ext = fio.basename(f.path, '.lua')
            local version = lversion.parse(filename_no_ext)
            if version ~= nil then
                table.insert(res, {
                    version = version,
                    path = f.path,
                    filename = filename
                })
            end
        end
    end

    return res
end


local function read_migration(path, version, compile)
    if compile == nil then
        compile = true
    end

    assert(version ~= nil, 'version is required')

    for _, m in ipairs(_list_migration_files(path)) do
        if tostring(m.version) == version
            or m.filename == version
            or m.version.ts == tonumber(version)
            or m.version.name == version then
                local data = fileio.read_file(m.path)
                if compile then
                    local err
                    data, err = loadstring(data)
                    if data == nil then
                        error(string.format("Error compiling migration '%s': \n%s", m.filename, err))
                    end

                    data = data()
                end

                m.migration = data
                return m
        end
    end

    return nil
end


local function list_migrations(path, verbose)
    local res = {}

    for _, m in ipairs(_list_migration_files(path)) do
        if not verbose then
            table.insert(res, m.filename)
        else
            table.insert(res, m)
        end
    end

    return res
end


local function read_migrations(path, direction, from_migration, n)
    if from_migration ~= nil then
        from_migration = lversion.parse(from_migration)
    end

    local migrations = {}
    local files = _list_migration_files(path)

    if direction == 'down' then
        reverse_table(files)
    end

    for _, m in ipairs(files) do
        local cond = from_migration == nil or m.version > from_migration
        if direction == 'down' then
            cond = from_migration == nil or m.version <= from_migration
        end
        if cond then
            local data = fileio.read_file(m.path)
            local compiled_code, err = loadstring(data)
            if compiled_code == nil then
                error(string.format("Error compiling migration '%s': \n%s", m.filename, err))
            end
            m.migration = compiled_code
            table.insert(migrations, m)
        end

        if n ~= nil and #migrations == n then
            break
        end
    end
    return migrations
end


local function check_version_exists(path, ts, name)
    local version = lversion.new(ts, name)
    for _, m in ipairs(_list_migration_files(path)) do
        if m.version == version or m.version.ts == ts or m.version.name == name then
            error(string.format('Version with timestamp %d or name %s already exists', ts, name))
        end
    end
end


return {
    string_split = string_split,
    tabulate_string = tabulate_string,
    read_migration = read_migration,
    read_migrations = read_migrations,
    list_migrations = list_migrations,
    check_version_exists = check_version_exists,
}
