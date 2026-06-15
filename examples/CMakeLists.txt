add_executable(cpp_basic_building
    cpp_basic_building.cpp
)

target_link_libraries(cpp_basic_building PRIVATE tbe_api)

add_executable(c_basic_building
    c_basic_building.c
)

target_link_libraries(c_basic_building PRIVATE tbe_capi)
