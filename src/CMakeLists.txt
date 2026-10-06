cmake_minimum_required(VERSION 3.10)
project(AutoTranslatorNative CXX)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Force 32-bit x86 build for Windower 4 / FFXI compatibility
if(CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(WARNING "Building for 32-bit (x86) is required for Final Fantasy XI / Windower 4!")
endif()

add_library(AutoTranslatorNative SHARED
    at_native.cpp
    at_native.h
)

target_link_libraries(AutoTranslatorNative PRIVATE winhttp user32)

set_target_properties(AutoTranslatorNative PROPERTIES
    PREFIX ""
    OUTPUT_NAME "AutoTranslatorNative"
)
