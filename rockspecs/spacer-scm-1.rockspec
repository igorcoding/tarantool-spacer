-- SPACER V1 IS DEPRECATED. PLEASE UPGRADE TO V2+.

package = 'spacer'
version = 'scm-1'
source  = {
    url    = 'git://github.com/igorcoding/tarantool-spacer.git',
    branch = 'v1',
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
