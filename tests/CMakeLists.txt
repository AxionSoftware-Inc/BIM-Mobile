add_executable(tbe_core_tests
    core_tests.cpp
)

target_link_libraries(tbe_core_tests PRIVATE tbe_core)

add_test(NAME tbe_core_tests COMMAND tbe_core_tests)

