cmake_minimum_required(VERSION 3.14)

set(EPHEMERAL_DIR "\${CMAKE_CURRENT_SOURCE_DIR}/ephemeral")

set(WRAPPER_ROOT "\${EPHEMERAL_DIR}/cpp_client_wrapper")

set(FLUTTER_LIBRARY "\${EPHEMERAL_DIR}/flutter_windows.dll.lib")

set(FLUTTER_ICU_DATA_FILE "\${EPHEMERAL_DIR}/icudtl.dat")

set(FLUTTER_LIBRARY_PRIVATE_HEADERS
  "\${WRAPPER_ROOT}/include"
  "\${WRAPPER_ROOT}/include/flutter"
  "\${WRAPPER_ROOT}/include/third_party"
)

add_library(flutter INTERFACE)
target_include_directories(flutter INTERFACE
  "\${EPHEMERAL_DIR}/cpp_client_wrapper/include"
)
target_link_libraries(flutter INTERFACE "\${FLUTTER_LIBRARY}")

add_dependencies(flutter flutter_assemble)

add_library(flutter_wrapper_app STATIC
  "\${WRAPPER_ROOT}/engine_method_result.cc"
  "\${WRAPPER_ROOT}/standard_codec.cc"
  "\${WRAPPER_ROOT}/plugin_registrar.cc"
  "\${WRAPPER_ROOT}/flutter_engine.cc"
  "\${WRAPPER_ROOT}/flutter_view_controller.cc"
)
target_link_libraries(flutter_wrapper_app PUBLIC flutter)
target_include_directories(flutter_wrapper_app PUBLIC
  "\${WRAPPER_ROOT}/include"
)

set(FLUTTER_RESOURCE_DIR "\${EPHEMERAL_DIR}")

set(PROJECT_BUILD_DIR "\${PROJECT_DIR}/build/" CACHE PATH "")
set(AOT_LIBRARY "\${PROJECT_DIR}/build/windows/app.so" CACHE FILE "" )

list(APPEND FLUTTER_LIBRARY_HEADERS
  "flutter_export.h"
  "flutter_windows.h"
  "flutter_messenger.h"
  "flutter_plugin_registrar.h"
  "flutter_texture_registrar.h"
)

set(INSTALL_BUNDLE_LIB_DIR "\${CMAKE_INSTALL_PREFIX}/lib")

install(CODE "file(REMOVE_RECURSE '\${INSTALL_BUNDLE_LIB_DIR}/\${BINARY_NAME}')" COMPONENT Runtime)
