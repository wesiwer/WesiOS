cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# The binary icon is kept as a base64 text payload so repository APIs that only
# accept UTF-8 can preserve it. Materialize it during CMake configuration.
set(APP_ICON_B64 "${CMAKE_CURRENT_SOURCE_DIR}/resources/app_icon.ico.b64")
set(APP_ICON "${CMAKE_CURRENT_SOURCE_DIR}/resources/app_icon.ico")
if(EXISTS "${APP_ICON_B64}")
  execute_process(
    COMMAND certutil -f -decode "${APP_ICON_B64}" "${APP_ICON}"
    RESULT_VARIABLE APP_ICON_DECODE_RESULT
    OUTPUT_QUIET
    ERROR_QUIET
  )
  if(NOT APP_ICON_DECODE_RESULT EQUAL 0)
    message(FATAL_ERROR "Failed to materialize WesiOS Windows icon")
  endif()
endif()

add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

apply_standard_settings(${BINARY_NAME})

target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

add_dependencies(${BINARY_NAME} flutter_assemble)
