local errno = require('errno')
local fio = require('fio')

local fileio = {}

local modes = fio.c.mode
local perms = bit.bor(modes.S_IRUSR, modes.S_IWUSR,
                      modes.S_IRGRP, modes.S_IWGRP,
                      modes.S_IROTH, modes.S_IWOTH)
local folder_perms = bit.bor(modes.S_IRUSR, modes.S_IWUSR, modes.S_IXUSR,
                             modes.S_IRGRP, modes.S_IWGRP, modes.S_IXGRP,
                             modes.S_IROTH,                modes.S_IXOTH)


function fileio.get_mode(file_path)
    local stat = fio.stat(file_path)
    if stat:is_dir() then
        return 'directory'
    end
    return 'file'
end


local function merge_tables(t, ...)
    for _, tt in ipairs({...}) do
        for _, v in ipairs(tt) do
            table.insert(t, v)
        end
    end
    return t
end


function fileio.listdir(path)
    local files = {}
    for _, postfix in ipairs({'/*', '/.*'}) do
        for _, file in ipairs(fio.glob(path .. postfix)) do
            if fio.basename(file) ~= "." and fio.basename(file) ~= ".." then
                local mode = fileio.get_mode(file)
                table.insert(files, {
                    mode = mode,
                    path = file
                })
                if mode == "directory" then
                    files = merge_tables(files, fileio.listdir(file))
                end
            end
        end
    end
    return files
end


function fileio.read_file(filepath)
    local fh = fio.open(filepath, {'O_RDONLY'})
    if not fh then
        error(string.format("Failed to open file %s: %s", filepath, errno.strerror()))
    end

    local data
    if _TARANTOOL >= "1.9" then
        data = fh:read()
    else
        data = fh:read(fh:stat().size)
    end

    fh:close()
    return data
end


function fileio.write_to_file(filepath, data)
    local local_perms = perms

    local fh = fio.open(filepath, {'O_WRONLY', 'O_CREAT'}, local_perms)
    if not fh then
        error(string.format("Failed to open file %s: %s", filepath, errno.strerror()))
    end

    fh:write(data)
    fh:close()
end


function fileio.mkdir(path)
    local ok = fio.mkdir(path, folder_perms)
    if not ok then
        error(string.format("Could not create folder %s: %s", path, errno.strerror()))
    end
end


function fileio.exists(path)
    return fio.stat(path) ~= nil
end


return fileio
