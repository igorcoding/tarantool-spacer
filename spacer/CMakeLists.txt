set(spacer_files
    init.lua
    compat.lua
    fileio.lua
    migration.lua
    inspect.lua
    ops.lua
    stmt.lua
    transformations.lua
    util.lua
    version.lua
)

foreach(file IN LISTS spacer_files)
    install(FILES ${file} DESTINATION ${TARANTOOL_INSTALL_LUADIR}/spacer)
endforeach()
