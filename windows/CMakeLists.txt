# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(vibekits LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "vibekits")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects. Flutter's current Windows plugins still use
# cppwinrt's <experimental/coroutine> compatibility layer. Newer MSVC releases
# turn that SDK deprecation into a hard error unless the compatibility warning
# is explicitly acknowledged. Keep the definition project-wide because plugin
# targets are generated after this file and do not all call our helper below.
add_definitions(
  -DUNICODE
  -D_UNICODE
  -D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS
)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# VibeKits packet capture helper. WinDivert is bundled beside this executable,
# so live capture does not depend on a separately installed Npcap/WinPcap.
set(WINDIVERT_DIR "${CMAKE_SOURCE_DIR}/../native/windivert/WinDivert-2.2.2-A")
add_executable(vibekits_packet_capture "runner/packet_capture_helper.cpp")
target_compile_features(vibekits_packet_capture PUBLIC cxx_std_17)
target_compile_definitions(vibekits_packet_capture PRIVATE "NOMINMAX")
target_include_directories(vibekits_packet_capture PRIVATE "${WINDIVERT_DIR}/include")
target_link_libraries(vibekits_packet_capture PRIVATE
  "${WINDIVERT_DIR}/x64/WinDivert.lib" "ws2_32.lib")

# Minimal generic ONNX bridge used by local OCR. It dynamically loads the
# onnxruntime.dll already bundled by sherpa_onnx_windows, avoiding duplicate
# runtime versions in the Release directory.
add_library(vibekits_onnx SHARED "runner/onnx_bridge.cpp")
apply_standard_settings(vibekits_onnx)
target_include_directories(vibekits_onnx PRIVATE
  "${CMAKE_SOURCE_DIR}/../native/onnxruntime/include")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(TARGETS vibekits_packet_capture RUNTIME
  DESTINATION "${CMAKE_INSTALL_PREFIX}/tools/packet_capture" COMPONENT Runtime)
install(FILES
  "${WINDIVERT_DIR}/x64/WinDivert.dll"
  "${WINDIVERT_DIR}/x64/WinDivert64.sys"
  "${WINDIVERT_DIR}/LICENSE"
  "${WINDIVERT_DIR}/README"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/tools/packet_capture"
  COMPONENT Runtime)

install(TARGETS vibekits_onnx RUNTIME DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# Current full 7-Zip console backend. 7z.dll supplies RAR/ISO/ZSTD and the
# broader format set that the standalone 7za executable intentionally omits.
install(FILES
  "${CMAKE_SOURCE_DIR}/../native/7zip/7z.exe"
  "${CMAKE_SOURCE_DIR}/../native/7zip/7z.dll"
  "${CMAKE_SOURCE_DIR}/../native/7zip/License.txt"
  "${CMAKE_SOURCE_DIR}/../native/7zip/readme.txt"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/tools/7zip"
  COMPONENT Runtime)

# Clash Verge-compatible Mihomo core. The private copy is always used so proxy
# tasks do not depend on another Clash installation or PATH.
set(MIHOMO_RUNTIME_DIR "${CMAKE_SOURCE_DIR}/../native/mihomo/windows/runtime")
if(EXISTS "${MIHOMO_RUNTIME_DIR}/vibekits-mihomo-runtime.json")
  install(DIRECTORY "${MIHOMO_RUNTIME_DIR}/"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/tools/mihomo" COMPONENT Runtime)
  install(FILES "${CMAKE_SOURCE_DIR}/../native/mihomo/LICENSE.txt"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/tools/mihomo" COMPONENT Runtime)
elseif(CMAKE_BUILD_TYPE STREQUAL "Release")
  message(FATAL_ERROR "Bundled Mihomo is missing. Run tool/prepare_mihomo_runtime.ps1.")
endif()

# Compact QEMU package keeps only x86_64 system emulation, qemu-img, runtime
# DLLs and firmware data instead of every architecture supplied upstream.
set(QEMU_RUNTIME_DIR "${CMAKE_SOURCE_DIR}/../native/qemu/windows/runtime")
if(EXISTS "${QEMU_RUNTIME_DIR}/vibekits-qemu-runtime.json")
  install(DIRECTORY "${QEMU_RUNTIME_DIR}/"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/tools/qemu" COMPONENT Runtime)
elseif(CMAKE_BUILD_TYPE STREQUAL "Release")
  message(FATAL_ERROR "Bundled QEMU is missing. Run tool/prepare_qemu_runtime.ps1.")
endif()

# The official DeepSeek Harness is prepared ahead of the Release build by
# tool/prepare_harness_runtime.ps1. Runtime startup never invokes npm/npx.
set(HARNESS_RUNTIME_DIR "${CMAKE_SOURCE_DIR}/../native/harness/windows/runtime")
if(EXISTS "${HARNESS_RUNTIME_DIR}/harness-runtime.json")
  # CMake's per-file install walker takes many minutes for Harness' 32k npm
  # files on Windows. Robocopy performs the same incremental directory copy
  # substantially faster and treats exit codes 0..7 as success.
  file(TO_CMAKE_PATH "$ENV{SystemRoot}/System32/robocopy.exe" ROBOCOPY_EXECUTABLE)
  install(CODE "
    execute_process(
      COMMAND \"${ROBOCOPY_EXECUTABLE}\"
        \"${HARNESS_RUNTIME_DIR}\"
        \"$<TARGET_FILE_DIR:${BINARY_NAME}>/tools/harness\"
        /E /NFL /NDL /NJH /NJS /NP
      RESULT_VARIABLE HARNESS_COPY_RESULT)
    if(HARNESS_COPY_RESULT GREATER 7)
      message(FATAL_ERROR \"Harness runtime copy failed: \${HARNESS_COPY_RESULT}\")
    endif()
  " COMPONENT Runtime)
  install(FILES "${CMAKE_SOURCE_DIR}/../native/harness/vibekits-mcp-server.mjs"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/tools/harness"
    COMPONENT Runtime)
  install(FILES "${CMAKE_SOURCE_DIR}/../native/harness/vibekits-codex-mcp.mjs"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/tools/harness"
    COMPONENT Runtime)
  install(FILES "${CMAKE_SOURCE_DIR}/../native/harness/vibekits-approval.mjs"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/tools/harness"
    COMPONENT Runtime)
  install(FILES "${CMAKE_SOURCE_DIR}/../native/harness/vibekits-parent-watchdog.mjs"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/tools/harness"
    COMPONENT Runtime)
  install(FILES "${CMAKE_SOURCE_DIR}/../native/harness/vibekits-session-rebind.mjs"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/tools/harness"
    COMPONENT Runtime)
  install(FILES
    "${CMAKE_SOURCE_DIR}/../tool/start_vibekits_mcp.ps1"
    "${CMAKE_SOURCE_DIR}/../tool/start_vibekits_mcp_ssh.ps1"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/tools/harness"
    COMPONENT Runtime)
  install(FILES
    "${CMAKE_SOURCE_DIR}/../tool/lmcp_reference_peer.mjs"
    "${CMAKE_SOURCE_DIR}/../docs/schemas/lmcp-discovery-1.0.schema.json"
    "${CMAKE_SOURCE_DIR}/../docs/schemas/lmcp-app-manifest-1.0.schema.json"
    "${CMAKE_SOURCE_DIR}/../examples/lmcp/future-app.manifest.json"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/tools/lmcp"
    COMPONENT Runtime)
  install(FILES "${CMAKE_SOURCE_DIR}/../native/harness/vibekits-android-stress-mcp.mjs"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/tools/harness"
    COMPONENT Runtime)
  if(EXISTS "${CMAKE_SOURCE_DIR}/../native/lark_cli/windows/runtime/lark-cli.exe")
    install(FILES "${CMAKE_SOURCE_DIR}/../native/lark_cli/windows/runtime/lark-cli.exe"
      DESTINATION "${CMAKE_INSTALL_PREFIX}/tools/lark-cli"
      COMPONENT Runtime)
  endif()
elseif(CMAKE_BUILD_TYPE STREQUAL "Release")
  message(FATAL_ERROR
    "Bundled Harness runtime is missing. Run tool/prepare_harness_runtime.ps1 before Release packaging.")
endif()

# Git for Windows MinGit is explicitly intended for embedding. The application
# always resolves this private copy and never requires Git on the user's PATH.
set(GIT_RUNTIME_DIR "${CMAKE_SOURCE_DIR}/../native/git/windows/runtime")
if(EXISTS "${GIT_RUNTIME_DIR}/vibekits-git-runtime.json")
  install(DIRECTORY "${GIT_RUNTIME_DIR}/"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/tools/git"
    COMPONENT Runtime)
elseif(CMAKE_BUILD_TYPE STREQUAL "Release")
  message(FATAL_ERROR
    "Bundled Git runtime is missing. Run tool/prepare_git_runtime.ps1 before Release packaging.")
endif()

# Official GitHub CLI. The private runtime makes MCP/Harness gh calls work on a
# clean machine without requiring a PATH installation.
set(GITHUB_CLI_RUNTIME_DIR "${CMAKE_SOURCE_DIR}/../native/github_cli/windows/runtime")
if(EXISTS "${GITHUB_CLI_RUNTIME_DIR}/bin/gh.exe" AND
   EXISTS "${GITHUB_CLI_RUNTIME_DIR}/vibekits-github-cli-runtime.json")
  install(DIRECTORY "${GITHUB_CLI_RUNTIME_DIR}/"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/tools/github-cli"
    COMPONENT Runtime)
elseif(CMAKE_BUILD_TYPE STREQUAL "Release")
  message(FATAL_ERROR
    "Bundled GitHub CLI is missing. Run tool/prepare_github_cli_runtime.ps1 before Release packaging.")
endif()

# Official Google Android Platform-Tools runtime. Keeping adb and both of its
# Windows DLL dependencies beside each other makes the ADB workspace fully
# self-contained and avoids relying on ANDROID_HOME or PATH.
install(FILES
  "${CMAKE_SOURCE_DIR}/../native/android-platform-tools/windows/adb.exe"
  "${CMAKE_SOURCE_DIR}/../native/android-platform-tools/windows/AdbWinApi.dll"
  "${CMAKE_SOURCE_DIR}/../native/android-platform-tools/windows/AdbWinUsbApi.dll"
  "${CMAKE_SOURCE_DIR}/../native/android-platform-tools/windows/NOTICE.txt"
  "${CMAKE_SOURCE_DIR}/../native/android-platform-tools/windows/source.properties"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/tools/adb"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
