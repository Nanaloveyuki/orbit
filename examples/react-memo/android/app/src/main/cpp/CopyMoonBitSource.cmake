execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env MOONVIEW_NATIVE_BACKEND=android
    "${MOON_EXECUTABLE}" build --target native --release --output-json .
  WORKING_DIRECTORY "${ANDROID_ROOT}"
  OUTPUT_VARIABLE build_output
  RESULT_VARIABLE build_result
)
if(NOT build_result STREQUAL "0")
  message(FATAL_ERROR "MoonBit Android build failed (${build_result}):\n${build_output}")
endif()

string(REGEX MATCHALL "[^\r\n]+" build_messages "${build_output}")
foreach(message IN LISTS build_messages)
  string(JSON kind ERROR_VARIABLE json_error GET "${message}" "$message_type")
  if(kind STREQUAL "artifact")
    string(JSON package GET "${message}" package)
    if(NOT package STREQUAL "Nanaloveyuki/orbit-react-memo-android")
      continue()
    endif()
    string(JSON archive GET "${message}" path)
    get_filename_component(build_dir "${archive}" DIRECTORY)
    set(source "${build_dir}/orbit-react-memo-android.c")
    break()
  endif()
endforeach()

if(NOT DEFINED source OR NOT EXISTS "${source}")
  message(FATAL_ERROR "MoonBit did not report the generated Android source:\n${build_output}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${source}" "${OUTPUT}"
  COMMAND_ERROR_IS_FATAL ANY
)
