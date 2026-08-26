cmake_minimum_required(VERSION 3.22.1)
project(vibekits_onnx LANGUAGES CXX)

add_library(vibekits_onnx SHARED vibekits_onnx.cpp)
target_include_directories(
  vibekits_onnx
  PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../native/onnxruntime/include
)
target_compile_features(vibekits_onnx PRIVATE cxx_std_17)
target_compile_options(vibekits_onnx PRIVATE -fvisibility=hidden)
target_link_libraries(vibekits_onnx PRIVATE dl log)
