# V1.9.0-dev.144 Windows self-contained acceptance (2026-09-01)

## Scope

- Synced cloud `main` through `f349191` before building.
- Built `1.9.0-dev.144+2144` as Windows x64 Release with all build output and caches on drive D.
- The deliverable is the complete application directory (or its ZIP), not the EXE by itself.

## Verification

- `flutter analyze --no-pub`: no issues.
- Targeted Git proxy, Harness session/status IPC, LMCP capacity and MCP commander scheduler tests: 17 passed, 4 platform skips, 0 failed.
- `flutter build windows --release --no-pub`: passed.
- `tool/verify_windows_bundle.ps1`: passed; all 29 required runtime entries are present and bundled Git reports `2.55.0.windows.3`.
- The copied `bin` deliverable passed the same bundle verifier independently.
- Standalone launch used a working directory outside the deliverable, a PATH containing only Windows system directories, and no Git or Android SDK environment variables. The app remained responsive and its Harness Node processes resolved from `tools/harness` inside the deliverable.

## Runtime boundary

The bundle carries the project-controlled Git, Node/Harness sidecars, ADB, 7-Zip, Mihomo, QEMU, WinDivert, ONNX/OCR assets and Flutter data. It does not need the source tree, Flutter SDK, system Git/Node/ADB, npm, or `npx` after packaging. Windows WebView2 remains an operating-system GUI runtime dependency; no loose project file is required beside the complete delivered directory.

## Artifact

- Directory: `bin/Vibekits-1.9.0-dev.144-2144-windows-x64/`
- Copy or archive the complete directory for distribution; do not distribute `vibekits.exe` alone.
