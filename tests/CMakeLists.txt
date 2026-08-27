add_executable(tbe_core_tests
    core_tests.cpp
)

target_link_libraries(tbe_core_tests PRIVATE tbe_core)

add_test(NAME tbe_core_tests COMMAND tbe_core_tests)

add_executable(tbe_api_tests
    api_tests.cpp
)

target_link_libraries(tbe_api_tests PRIVATE tbe_capi)
target_include_directories(tbe_api_tests PRIVATE
    ${CMAKE_SOURCE_DIR}/src/core/include
    ${CMAKE_SOURCE_DIR}/src/api/src
)

add_test(NAME tbe_api_tests COMMAND tbe_api_tests)

add_executable(tbe_ifc_fixture_tests
    ifc_fixture_tests.cpp
)

target_link_libraries(tbe_ifc_fixture_tests PRIVATE tbe_core)

add_test(
    NAME tbe_ifc_fixture_tests
    COMMAND tbe_ifc_fixture_tests
        "${CMAKE_SOURCE_DIR}/tests/fixtures/ifc/wall-with-opening-and-window.ifc"
        "${CMAKE_SOURCE_DIR}/tests/fixtures/ifc/Building-Architecture.ifc"
        "${CMAKE_SOURCE_DIR}/tests/fixtures/ifc/Building-Architecture-IFC4X3.ifc"
        "${CMAKE_SOURCE_DIR}/tests/fixtures/ifc/multi-storey-containment.ifc"
)
