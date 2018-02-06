set(spacer_files 
    init.lua
    compat.lua
    fileio.lua
    migration.lua
    myinspect.lua
    ops.lua
    stmt.lua
    transformations.lua
    util.lua
)

foreach(file IN LISTS spacer_files)
    install(FILES ${file} DESTINATION ${TARANTOOL_INSTALL_LUADIR}/spacer)
endforeach()
