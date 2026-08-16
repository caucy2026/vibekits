# ONNX Runtime bridge

Vibekits uses a small Windows bridge around the ONNX Runtime C API already bundled by `sherpa_onnx_windows`. The bridge avoids shipping a second conflicting `onnxruntime.dll` and exposes only float-tensor session creation/run/release operations needed by local OCR.

`include/onnxruntime_c_api.h` is the unmodified Microsoft header pinned to ONNX Runtime `v1.27.1`, matching the Windows DLL currently delivered by `sherpa_onnx_windows 1.13.5`.

Source: <https://github.com/microsoft/onnxruntime/blob/v1.27.1/include/onnxruntime/core/session/onnxruntime_c_api.h>

License: MIT. See `LICENSE` in this directory.
