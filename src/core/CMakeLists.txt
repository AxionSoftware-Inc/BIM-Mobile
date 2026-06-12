add_library(tbe_core
    src/Command.cpp
    src/Document.cpp
    src/DocumentJson.cpp
    src/Element.cpp
    src/GeometryService.cpp
    src/JobSystem.cpp
    src/Project.cpp
)

find_package(Threads REQUIRED)

target_include_directories(tbe_core
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

include(FindOrDisableOCCT)

if(OpenCASCADE_FOUND)
    target_compile_definitions(tbe_core PUBLIC TBE_HAS_OCCT=1)
    target_include_directories(tbe_core SYSTEM PUBLIC ${OpenCASCADE_INCLUDE_DIR})
    target_link_libraries(tbe_core PUBLIC ${OpenCASCADE_LIBRARIES})
else()
    target_compile_definitions(tbe_core PUBLIC TBE_HAS_OCCT=0)
endif()

target_compile_features(tbe_core PUBLIC cxx_std_20)
target_link_libraries(tbe_core PUBLIC Threads::Threads)

if(MSVC)
    target_compile_options(tbe_core PRIVATE /W4)
else()
    target_compile_options(tbe_core PRIVATE -Wall -Wextra -Wpedantic)
endif()
