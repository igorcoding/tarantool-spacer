package = 'spacer'
version = 'scm-2'
source  = {
    url    = 'git://github.com/igorcoding/tarantool-spacer.git',
    branch = 'v2',
}
description = {
    summary  = "Spacer for Tarantool. For managing spaces easily.",
    homepage = 'https://github.com/igorcoding/tarantool-spacer',
    license  = 'MIT',
}
dependencies = {
    'lua >= 5.1'
}
build = {
    type = 'builtin',
    modules = {
        ['spacer'] = 'spacer.lua',
    }
}

-- vim: syntax=lua
