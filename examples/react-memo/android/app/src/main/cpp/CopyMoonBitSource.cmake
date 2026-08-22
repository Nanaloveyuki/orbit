file(GLOB_RECURSE candidates
  "${ANDROID_ROOT}/_build/native/release/build/*/orbit-react-memo-android.c"
)

set(matches "")
foreach(candidate IN LISTS candidates)
  file(TO_CMAKE_PATH "${candidate}" normalized)
  if(normalized MATCHES "/orbit-react-memo-android/orbit-react-memo-android\\.c$")
    list(APPEND matches "${candidate}")
  endif()
endforeach()

list(LENGTH matches match_count)
if(NOT match_count EQUAL 1)
  message(FATAL_ERROR "Expected one generated Android source, found ${match_count}: ${matches}")
endif()

list(GET matches 0 source)
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${source}" "${OUTPUT}"
  COMMAND_ERROR_IS_FATAL ANY
)
