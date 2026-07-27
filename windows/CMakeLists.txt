cmake_minimum_required(VERSION 3.14)
project(wesios LANGUAGES CXX)

set(BINARY_NAME "wesios")

cmake_policy(SET CMP0063 NEW)

set(CMAKE_INSTALL_RPATH "\$ORIGIN/lib")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(FLUTTER_MANAGED_DIR "\${CMAKE_CURRENT_SOURCE_DIR}/flutter")

add_subdirectory(\${FLUTTER_MANAGED_DIR})

add_executable(\${BINARY_NAME} WIN32
  "flutter/generated_plugin_registrant.cc"
  "flutter/generated_plugins.cmake"
  "runner/main.cpp"
  "runner/flutter_window.cpp"
  "runner/utils.cpp"
  "runner/win32_window.cpp"
  "runner/resource.h"
  "runner/wesios.rc"
)

apply_standard_settings(\${BINARY_NAME})

target_link_libraries(\${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_include_directories(\${BINARY_NAME} PRIVATE "\${CMAKE_SOURCE_DIR}")

add_dependencies(\${BINARY_NAME} flutter_assemble)
