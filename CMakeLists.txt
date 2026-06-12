cmake_minimum_required(VERSION 3.24)

project(TabletBimEngine
    VERSION 0.1.0
    DESCRIPTION "Lightweight cross-platform CAD/BIM engine foundation for tablet-first workflows"
    LANGUAGES CXX
)

option(TBE_BUILD_TESTS "Build unit tests" ON)
option(TBE_BUILD_CLI "Build developer CLI" ON)
option(TBE_ENABLE_OCCT "Enable Open CASCADE integration when available" ON)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

add_subdirectory(src/core)

if(TBE_BUILD_CLI)
    add_subdirectory(apps/tbe_cli)
endif()

if(TBE_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

