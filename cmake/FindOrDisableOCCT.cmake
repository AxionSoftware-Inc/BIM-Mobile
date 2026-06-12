if(NOT TBE_ENABLE_OCCT)
    return()
endif()

find_package(OpenCASCADE QUIET)

if(OpenCASCADE_FOUND)
    message(STATUS "Open CASCADE found: ${OpenCASCADE_VERSION}")
else()
    message(STATUS "Open CASCADE not found; building with fallback geometry backend")
endif()

