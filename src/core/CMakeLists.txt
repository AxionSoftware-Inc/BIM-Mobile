add_library(tbe_core_geometry
    src/GeometryService.cpp
)

add_library(tbe_core_analysis OBJECT
    src/DocumentAnalysis.cpp
)

add_library(tbe_core_persistence OBJECT
    src/DocumentJson.cpp
)

add_library(tbe_core
    src/Command.cpp
    src/Document.cpp
    src/Element.cpp
    src/IfcExchange.cpp
    src/JobSystem.cpp
    src/Project.cpp
    src/ProjectCatalog.cpp
    src/Units.cpp
)

set_target_properties(tbe_core_geometry PROPERTIES POSITION_INDEPENDENT_CODE ON)
set_target_properties(tbe_core_analysis PROPERTIES POSITION_INDEPENDENT_CODE ON)
set_target_properties(tbe_core_persistence PROPERTIES POSITION_INDEPENDENT_CODE ON)
set_target_properties(tbe_core PROPERTIES POSITION_INDEPENDENT_CODE ON)

target_sources(tbe_core PRIVATE $<TARGET_OBJECTS:tbe_core_analysis>)
target_sources(tbe_core PRIVATE $<TARGET_OBJECTS:tbe_core_persistence>)

find_package(Threads REQUIRED)

target_include_directories(tbe_core_geometry
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_include_directories(tbe_core
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_include_directories(tbe_core_analysis
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_include_directories(tbe_core_persistence
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

include(FindOrDisableOCCT)

if(OpenCASCADE_FOUND)
    target_compile_definitions(tbe_core_geometry PUBLIC TBE_HAS_OCCT=1)
    target_include_directories(tbe_core_geometry SYSTEM PUBLIC ${OpenCASCADE_INCLUDE_DIR})
    target_link_libraries(tbe_core_geometry PUBLIC ${OpenCASCADE_LIBRARIES})
else()
    target_compile_definitions(tbe_core_geometry PUBLIC TBE_HAS_OCCT=0)
endif()

target_compile_features(tbe_core_geometry PUBLIC cxx_std_20)
target_compile_features(tbe_core_analysis PUBLIC cxx_std_20)
target_compile_features(tbe_core_persistence PUBLIC cxx_std_20)
target_compile_features(tbe_core PUBLIC cxx_std_20)
target_link_libraries(tbe_core PUBLIC Threads::Threads tbe_core_geometry)

if(MSVC)
    target_compile_options(tbe_core_geometry PRIVATE /W4)
    target_compile_options(tbe_core_analysis PRIVATE /W4)
    target_compile_options(tbe_core_persistence PRIVATE /W4)
    target_compile_options(tbe_core PRIVATE /W4)
else()
    target_compile_options(tbe_core_geometry PRIVATE -Wall -Wextra -Wpedantic)
    target_compile_options(tbe_core_analysis PRIVATE -Wall -Wextra -Wpedantic)
    target_compile_options(tbe_core_persistence PRIVATE -Wall -Wextra -Wpedantic)
    target_compile_options(tbe_core PRIVATE -Wall -Wextra -Wpedantic)
endif()
