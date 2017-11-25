package = 'spacer'
version = 'scm-2'
source  = {
    url    = 'git://github.com/igorcoding/tarantool-spacer.git',
    branch = 'v2',
}
description = {
    summary  = "Tarantool Spacer. Automatic model migrations.",
    homepage = 'https://github.com/igorcoding/tarantool-spacer',
    license  = 'MIT',
}
dependencies = {
    'lua >= 5.1',
    'inspect >= 3.1.0-1',
}
build = {
    type = 'builtin',
    modules = {
        ['spacer.init'] = 'spacer/init.lua',
        ['spacer.migration'] = 'spacer/migration.lua',
        ['spacer.ops'] = 'spacer/ops.lua',
        ['spacer.fileio'] = 'spacer/fileio.lua',
        ['spacer.util'] = 'spacer/util.lua',
        ['spacer.transformations'] = 'spacer/transformations.lua',
    }
}

-- vim: syntax=lua
