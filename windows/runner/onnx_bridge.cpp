#include <windows.h>

#include <cstdint>
#include <cstring>
#include <mutex>
#include <new>
#include <string>
#include <vector>

#include "onnxruntime_c_api.h"

namespace {

thread_local std::string g_last_error;

struct OrtBridgeSession {
  HMODULE runtime = nullptr;
  const OrtApi* api = nullptr;
  OrtEnv* env = nullptr;
  OrtSession* session = nullptr;
  OrtMemoryInfo* memory_info = nullptr;
  std::string input_name;
  std::string output_name;
  std::mutex run_mutex;
};

struct OrtBridgeResult {
  std::vector<float> data;
  std::vector<int64_t> shape;
};

bool SetStatusError(const OrtApi* api, OrtStatus* status,
                    const char* operation) {
  if (status == nullptr) return false;
  const char* message = api == nullptr ? nullptr : api->GetErrorMessage(status);
  g_last_error = operation;
  if (message != nullptr && message[0] != '\0') {
    g_last_error.append(": ").append(message);
  }
  if (api != nullptr) api->ReleaseStatus(status);
  return true;
}

void ReleaseSession(OrtBridgeSession* bridge) {
  if (bridge == nullptr) return;
  if (bridge->api != nullptr) {
    if (bridge->memory_info != nullptr) {
      bridge->api->ReleaseMemoryInfo(bridge->memory_info);
    }
    if (bridge->session != nullptr) bridge->api->ReleaseSession(bridge->session);
    if (bridge->env != nullptr) bridge->api->ReleaseEnv(bridge->env);
  }
  if (bridge->runtime != nullptr) FreeLibrary(bridge->runtime);
  delete bridge;
}

}  // namespace

extern "C" __declspec(dllexport) const char* vibekits_ort_last_error() {
  return g_last_error.c_str();
}

extern "C" __declspec(dllexport) void* vibekits_ort_create_session(
    const wchar_t* runtime_path, const wchar_t* model_path, int thread_count) {
  g_last_error.clear();
  if (runtime_path == nullptr || model_path == nullptr) {
    g_last_error = "Runtime and model paths are required";
    return nullptr;
  }

  OrtBridgeSession* bridge = new (std::nothrow) OrtBridgeSession();
  if (bridge == nullptr) {
    g_last_error = "Unable to allocate ONNX session state";
    return nullptr;
  }

  bridge->runtime = LoadLibraryW(runtime_path);
  if (bridge->runtime == nullptr) {
    g_last_error = "Unable to load onnxruntime.dll (Windows error " +
                   std::to_string(GetLastError()) + ")";
    ReleaseSession(bridge);
    return nullptr;
  }

  using OrtGetApiBaseFunction = const OrtApiBase*(ORT_API_CALL*)();
  auto get_api_base = reinterpret_cast<OrtGetApiBaseFunction>(
      GetProcAddress(bridge->runtime, "OrtGetApiBase"));
  if (get_api_base == nullptr) {
    g_last_error = "onnxruntime.dll does not export OrtGetApiBase";
    ReleaseSession(bridge);
    return nullptr;
  }

  const OrtApiBase* api_base = get_api_base();
  bridge->api = api_base == nullptr ? nullptr : api_base->GetApi(ORT_API_VERSION);
  if (bridge->api == nullptr) {
    g_last_error = "ONNX Runtime C API version is incompatible";
    ReleaseSession(bridge);
    return nullptr;
  }

  if (SetStatusError(bridge->api,
                     bridge->api->CreateEnv(ORT_LOGGING_LEVEL_WARNING,
                                            "vibekits-ocr", &bridge->env),
                     "CreateEnv")) {
    ReleaseSession(bridge);
    return nullptr;
  }

  OrtSessionOptions* options = nullptr;
  if (SetStatusError(bridge->api, bridge->api->CreateSessionOptions(&options),
                     "CreateSessionOptions")) {
    ReleaseSession(bridge);
    return nullptr;
  }

  const int safe_threads = thread_count < 1 ? 1 : thread_count;
  bool option_failed = SetStatusError(
      bridge->api,
      bridge->api->SetIntraOpNumThreads(options, safe_threads),
      "SetIntraOpNumThreads");
  if (!option_failed) {
    option_failed = SetStatusError(
        bridge->api,
        bridge->api->SetSessionGraphOptimizationLevel(options, ORT_ENABLE_ALL),
        "SetSessionGraphOptimizationLevel");
  }
  if (!option_failed) {
    option_failed = SetStatusError(
        bridge->api,
        bridge->api->CreateSession(bridge->env, model_path, options,
                                   &bridge->session),
        "CreateSession");
  }
  bridge->api->ReleaseSessionOptions(options);
  if (option_failed) {
    ReleaseSession(bridge);
    return nullptr;
  }

  OrtAllocator* allocator = nullptr;
  if (SetStatusError(bridge->api,
                     bridge->api->GetAllocatorWithDefaultOptions(&allocator),
                     "GetAllocatorWithDefaultOptions")) {
    ReleaseSession(bridge);
    return nullptr;
  }

  char* input_name = nullptr;
  char* output_name = nullptr;
  bool name_failed = SetStatusError(
      bridge->api,
      bridge->api->SessionGetInputName(bridge->session, 0, allocator,
                                       &input_name),
      "SessionGetInputName");
  if (!name_failed) {
    name_failed = SetStatusError(
        bridge->api,
        bridge->api->SessionGetOutputName(bridge->session, 0, allocator,
                                          &output_name),
        "SessionGetOutputName");
  }
  if (!name_failed) {
    bridge->input_name = input_name == nullptr ? "" : input_name;
    bridge->output_name = output_name == nullptr ? "" : output_name;
  }
  if (input_name != nullptr) bridge->api->AllocatorFree(allocator, input_name);
  if (output_name != nullptr) bridge->api->AllocatorFree(allocator, output_name);
  if (name_failed || bridge->input_name.empty() || bridge->output_name.empty()) {
    if (!name_failed) g_last_error = "Model input or output name is empty";
    ReleaseSession(bridge);
    return nullptr;
  }

  if (SetStatusError(
          bridge->api,
          bridge->api->CreateCpuMemoryInfo(OrtArenaAllocator,
                                           OrtMemTypeDefault,
                                           &bridge->memory_info),
          "CreateCpuMemoryInfo")) {
    ReleaseSession(bridge);
    return nullptr;
  }
  return bridge;
}

extern "C" __declspec(dllexport) void vibekits_ort_release_session(
    void* session) {
  ReleaseSession(static_cast<OrtBridgeSession*>(session));
}

extern "C" __declspec(dllexport) void* vibekits_ort_run_float(
    void* session, float* input_data, size_t input_length,
    const int64_t* input_shape, size_t input_rank) {
  g_last_error.clear();
  auto* bridge = static_cast<OrtBridgeSession*>(session);
  if (bridge == nullptr || input_data == nullptr || input_shape == nullptr ||
      input_length == 0 || input_rank == 0) {
    g_last_error = "Invalid ONNX inference input";
    return nullptr;
  }

  std::lock_guard<std::mutex> guard(bridge->run_mutex);
  OrtValue* input_value = nullptr;
  if (SetStatusError(
          bridge->api,
          bridge->api->CreateTensorWithDataAsOrtValue(
              bridge->memory_info, input_data, input_length * sizeof(float),
              input_shape, input_rank, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
              &input_value),
          "CreateTensorWithDataAsOrtValue")) {
    return nullptr;
  }

  const char* input_names[] = {bridge->input_name.c_str()};
  const char* output_names[] = {bridge->output_name.c_str()};
  const OrtValue* input_values[] = {input_value};
  OrtValue* output_value = nullptr;
  OrtStatus* run_status = bridge->api->Run(
      bridge->session, nullptr, input_names, input_values, 1, output_names, 1,
      &output_value);
  bridge->api->ReleaseValue(input_value);
  if (SetStatusError(bridge->api, run_status, "Run")) return nullptr;

  OrtTensorTypeAndShapeInfo* type_shape = nullptr;
  bool output_failed = SetStatusError(
      bridge->api,
      bridge->api->GetTensorTypeAndShape(output_value, &type_shape),
      "GetTensorTypeAndShape");
  size_t rank = 0;
  size_t element_count = 0;
  if (!output_failed) {
    output_failed = SetStatusError(
        bridge->api, bridge->api->GetDimensionsCount(type_shape, &rank),
        "GetDimensionsCount");
  }
  std::vector<int64_t> output_shape(rank);
  if (!output_failed && rank > 0) {
    output_failed = SetStatusError(
        bridge->api,
        bridge->api->GetDimensions(type_shape, output_shape.data(), rank),
        "GetDimensions");
  }
  if (!output_failed) {
    output_failed = SetStatusError(
        bridge->api,
        bridge->api->GetTensorShapeElementCount(type_shape, &element_count),
        "GetTensorShapeElementCount");
  }
  void* raw_output = nullptr;
  if (!output_failed) {
    output_failed = SetStatusError(
        bridge->api, bridge->api->GetTensorMutableData(output_value, &raw_output),
        "GetTensorMutableData");
  }

  OrtBridgeResult* result = nullptr;
  if (!output_failed) {
    result = new (std::nothrow) OrtBridgeResult();
    if (result == nullptr) {
      g_last_error = "Unable to allocate ONNX output";
      output_failed = true;
    } else {
      const float* floats = static_cast<const float*>(raw_output);
      result->data.assign(floats, floats + element_count);
      result->shape = std::move(output_shape);
    }
  }

  if (type_shape != nullptr) bridge->api->ReleaseTensorTypeAndShapeInfo(type_shape);
  bridge->api->ReleaseValue(output_value);
  if (output_failed) {
    delete result;
    return nullptr;
  }
  return result;
}

extern "C" __declspec(dllexport) const float* vibekits_ort_result_data(
    void* result) {
  auto* value = static_cast<OrtBridgeResult*>(result);
  return value == nullptr || value->data.empty() ? nullptr : value->data.data();
}

extern "C" __declspec(dllexport) size_t vibekits_ort_result_length(
    void* result) {
  auto* value = static_cast<OrtBridgeResult*>(result);
  return value == nullptr ? 0 : value->data.size();
}

extern "C" __declspec(dllexport) size_t vibekits_ort_result_rank(
    void* result) {
  auto* value = static_cast<OrtBridgeResult*>(result);
  return value == nullptr ? 0 : value->shape.size();
}

extern "C" __declspec(dllexport) int64_t vibekits_ort_result_dimension(
    void* result, size_t index) {
  auto* value = static_cast<OrtBridgeResult*>(result);
  return value == nullptr || index >= value->shape.size() ? -1
                                                          : value->shape[index];
}

extern "C" __declspec(dllexport) void vibekits_ort_release_result(
    void* result) {
  delete static_cast<OrtBridgeResult*>(result);
}
