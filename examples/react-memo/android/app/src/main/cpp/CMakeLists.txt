cmake_minimum_required(VERSION 3.22.1)
project(orbit_react_memo C)

set(ANDROID_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../..")
get_filename_component(ANDROID_ROOT "${ANDROID_ROOT}" ABSOLUTE)
set(AJNI_ROOT "${ANDROID_ROOT}/.mooncakes/Nanaloveyuki/ajni")
if(NOT EXISTS "${AJNI_ROOT}/src/android/ajni_bridge.c")
  message(FATAL_ERROR "Ajni sources were not found. Run 'moon update' from ${ANDROID_ROOT}.")
endif()

if(DEFINED ENV{MOON_HOME})
  set(MOON_HOME "$ENV{MOON_HOME}")
elseif(DEFINED ENV{USERPROFILE})
  set(MOON_HOME "$ENV{USERPROFILE}/.moon")
elseif(DEFINED ENV{HOME})
  set(MOON_HOME "$ENV{HOME}/.moon")
else()
  message(FATAL_ERROR "MoonBit home was not found. Set MOON_HOME before building.")
endif()

find_program(MOON_EXECUTABLE moon REQUIRED)
set(MOONBIT_APP_SOURCE "${CMAKE_CURRENT_BINARY_DIR}/orbit_android.c")
set(MOONBIT_RUNTIME_SOURCES
  "${MOON_HOME}/lib/runtime/runtime.c"
  "${MOON_HOME}/lib/runtime/utf.c"
  "${MOON_HOME}/lib/runtime/env.c"
  "${MOON_HOME}/lib/runtime/sync_io.c"
  "${MOON_HOME}/lib/runtime/backtrace.c"
)
if(NOT EXISTS "${MOON_HOME}/lib/runtime/runtime.c")
  set(MOONBIT_RUNTIME_SOURCES "${MOON_HOME}/lib/runtime.c")
endif()

set(AJNI_BRIDGE_SOURCE "${AJNI_ROOT}/src/android/ajni_bridge.c")
set(AJNI_WEBVIEW_BRIDGE_SOURCE "${AJNI_ROOT}/src/webview/ajni_webview_bridge.c")
list(GET MOONBIT_RUNTIME_SOURCES 0 MOONBIT_RUNTIME_SOURCE)
if(NOT EXISTS "${MOONBIT_RUNTIME_SOURCE}")
  message(FATAL_ERROR "MoonBit runtime was not found under ${MOON_HOME}.")
endif()

add_custom_target(generate_orbit_android
  COMMAND "${CMAKE_COMMAND}" -E env MOONVIEW_NATIVE_BACKEND=android
    "${MOON_EXECUTABLE}" build --target native --release .
  COMMAND "${CMAKE_COMMAND}"
    "-DANDROID_ROOT=${ANDROID_ROOT}"
    "-DOUTPUT=${MOONBIT_APP_SOURCE}"
    -P "${CMAKE_CURRENT_LIST_DIR}/CopyMoonBitSource.cmake"
  WORKING_DIRECTORY "${ANDROID_ROOT}"
  DEPENDS
    "${ANDROID_ROOT}/main.mbt"
    "${ANDROID_ROOT}/generated_page.mbt"
    "${ANDROID_ROOT}/moon.mod"
    "${ANDROID_ROOT}/moon.pkg"
    "${AJNI_BRIDGE_SOURCE}"
    "${AJNI_WEBVIEW_BRIDGE_SOURCE}"
  BYPRODUCTS "${MOONBIT_APP_SOURCE}"
  COMMENT "Generating Orbit Memo Android MoonBit source"
  VERBATIM
)

set_source_files_properties("${MOONBIT_APP_SOURCE}" PROPERTIES GENERATED TRUE)
add_library(ajni SHARED
  "${AJNI_BRIDGE_SOURCE}"
  "${AJNI_WEBVIEW_BRIDGE_SOURCE}"
  "${MOONBIT_APP_SOURCE}"
  ${MOONBIT_RUNTIME_SOURCES}
)
add_dependencies(ajni generate_orbit_android)
target_compile_definitions(ajni PRIVATE AJNI_USE_MOONBIT_EXPORTS=1 AJNI_FEATURE_WEBVIEW=1)
target_include_directories(ajni PRIVATE "${MOON_HOME}/include")
set_source_files_properties("${AJNI_BRIDGE_SOURCE}" PROPERTIES COMPILE_OPTIONS "-Wall;-Wextra;-Werror")
set_source_files_properties("${AJNI_WEBVIEW_BRIDGE_SOURCE}" PROPERTIES COMPILE_OPTIONS "-Wall;-Wextra;-Werror")
set_source_files_properties(${MOONBIT_RUNTIME_SOURCES} PROPERTIES COMPILE_OPTIONS "-include;${AJNI_ROOT}/src/android/android_compat.h")
target_link_libraries(ajni android log)
