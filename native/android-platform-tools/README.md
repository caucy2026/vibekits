# Android Platform-Tools runtime

Vibekits bundles the official Google Android Debug Bridge Windows runtime so
ADB features do not depend on an Android SDK installed on the host.

- Upstream: https://developer.android.com/tools/releases/platform-tools
- License/notice: `windows/NOTICE.txt`
- Runtime files: `adb.exe`, `AdbWinApi.dll`, `AdbWinUsbApi.dll`

Only the files required by ADB are shipped. `fastboot` and unrelated SDK tools
are intentionally excluded from the application bundle.
