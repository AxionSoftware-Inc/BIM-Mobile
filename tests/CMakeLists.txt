add_executable(tbe_core_tests
    core_tests.cpp
)

target_link_libraries(tbe_core_tests PRIVATE tbe_core)

add_test(NAME tbe_core_tests COMMAND tbe_core_tests)

add_executable(tbe_api_tests
    api_tests.cpp
)

target_link_libraries(tbe_api_tests PRIVATE tbe_capi)
target_include_directories(tbe_api_tests PRIVATE ${CMAKE_SOURCE_DIR}/src/core/include)

add_test(NAME tbe_api_tests COMMAND tbe_api_tests)
