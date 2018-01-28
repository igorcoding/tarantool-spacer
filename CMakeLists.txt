cmake_minimum_required(VERSION 2.8 FATAL_ERROR)
set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake" ${CMAKE_MODULE_PATH})

project(zookeeper C)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Debug)
endif()

# Find Tarantool
set(TARANTOOL_FIND_REQUIRED ON)
find_package(Tarantool)

include_directories(${TARANTOOL_INCLUDE_DIRS})

# Set CFLAGS
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fPIC -O2")
set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -fPIC -O2 -Wall -Wextra")

if (APPLE)
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -undefined suppress -flat_namespace")
endif(APPLE)

# Build module
add_subdirectory(spacer)

# Tests
set(TARANTOOL tarantool)
set(LUA_PATH
    "${CMAKE_SOURCE_DIR}/?.lua\\;${CMAKE_SOURCE_DIR}/?/init.lua\\;\\;")

set(LUA_CPATH "${CMAKE_SOURCE_DIR}/?.so\\;\\;")
enable_testing()

add_test(NAME basic
         COMMAND ${TARANTOOL} ${CMAKE_SOURCE_DIR}/tests/01-basic.lua
         WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}/tests)

set(TESTS basic)
foreach(test IN LISTS TESTS)
    set_property(TEST ${test} PROPERTY ENVIRONMENT "LUA_PATH=${LUA_PATH}")
    set_property(TEST ${test} APPEND PROPERTY ENVIRONMENT
                 "LUA_CPATH=${LUA_CPATH}")
endforeach()
