cmake_minimum_required(VERSION 3.22.1)

project(viewer_flutter_native LANGUAGES C CXX)

set(TBE_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(TBE_BUILD_CLI OFF CACHE BOOL "" FORCE)
set(TBE_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(TBE_ENABLE_OCCT OFF CACHE BOOL "" FORCE)

add_subdirectory(
    "${CMAKE_CURRENT_LIST_DIR}/../../../../"
    "${CMAKE_CURRENT_BINARY_DIR}/tbe_engine"
)
