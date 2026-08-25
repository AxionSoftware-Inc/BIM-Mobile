add_library(tbe_api
    src/EngineApi.cpp
    src/RuntimeSceneCache.cpp
)

set_target_properties(tbe_api PROPERTIES POSITION_INDEPENDENT_CODE ON)

target_include_directories(tbe_api
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_compile_features(tbe_api PUBLIC cxx_std_20)
target_link_libraries(tbe_api PRIVATE tbe_core)

add_library(tbe_capi
    src/EngineCApi.cpp
)

set_target_properties(tbe_capi PROPERTIES POSITION_INDEPENDENT_CODE ON)

target_include_directories(tbe_capi
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_compile_features(tbe_capi PUBLIC cxx_std_20)
target_link_libraries(tbe_capi PUBLIC tbe_api)

set(TBE_CAPI_SHARED_SOURCES
    src/EngineCApi.cpp
)

# Android's Filament view consumes the compiled runtime cache through JNI
# direct buffers. Keep the desktop C ABI free of JNI dependencies.
if(ANDROID)
    list(APPEND TBE_CAPI_SHARED_SOURCES src/AndroidBimCacheJni.cpp)
endif()

add_library(tbe_capi_shared SHARED ${TBE_CAPI_SHARED_SOURCES})

set_target_properties(tbe_capi_shared PROPERTIES
    OUTPUT_NAME tbe_capi
    POSITION_INDEPENDENT_CODE ON
)

if(WIN32)
    # The Flutter desktop/integration test loader opens the shared C ABI
    # directly. Export the C entry points from the MSVC DLL just as ELF and
    # Mach-O toolchains do by default for this target.
    set_target_properties(tbe_capi_shared PROPERTIES
        WINDOWS_EXPORT_ALL_SYMBOLS ON
    )
endif()

target_include_directories(tbe_capi_shared
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_compile_features(tbe_capi_shared PUBLIC cxx_std_20)
target_link_libraries(tbe_capi_shared PUBLIC tbe_api)

if(MSVC)
    target_compile_options(tbe_api PRIVATE /W4)
    target_compile_options(tbe_capi PRIVATE /W4)
    target_compile_options(tbe_capi_shared PRIVATE /W4)
else()
    target_compile_options(tbe_api PRIVATE -Wall -Wextra -Wpedantic)
    target_compile_options(tbe_capi PRIVATE -Wall -Wextra -Wpedantic)
    target_compile_options(tbe_capi_shared PRIVATE -Wall -Wextra -Wpedantic)
endif()
