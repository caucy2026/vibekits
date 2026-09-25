---
name: vibekits-remote-simulator
description: "Use when the user gives a 6–16 digit VibeKits device ID and asks to debug that remote computer/device, especially Mac-to-Android-PAD remote ADB, or inspect apps, logs, system, transfers and software through 远程仿真. Connect through VibeKits P2P/relay, never a remote-desktop UI."
---

# VibeKits remote simulator

A device ID and an authorized remote-simulation endpoint are enough to start. The user need not name this skill or say “远程仿真”: “帮我调试远程设备 ID …” and equivalent requests should trigger it. Do not ask for its IP, SSH user, password, private key, relay address, or RustDesk password. The remote device must have enabled simulation and granted the required first-time consent; never bypass that or OS privacy controls.

## Inside VibeKits Harness

1. Use the registered VibeKits MCP tools directly. Call `vibekits.simulator.connect` with `{"routingId":"<ID>"}`. Do not launch RustDesk/KEMI remote desktop, a browser tunnel, an external SSH client, or a shell helper merely to connect.
2. Validate the structured result, not just tool transport success. Require `connected: true`, the requested routing ID, a verified device identity and `transport: p2p_or_relay`. Check `vibekits.simulator.connection_status` when needed. Treat an SSH host-key change or consent failure as a stop, not a reason to try another route.
3. When tool availability or arguments are unclear, call `vibekits.simulator.catalog` and follow the returned schemas. Use `vibekits.simulator.call` for the remote `vibekits.device.*` tools. Prefer purpose-built process, application, log, crash-report and UI-inspection tools to `vibekits.simulator.ssh_exec`.
4. For a read-only inventory, obtain installed apps with `vibekits.device.applications` using a bounded limit. Obtain OS/host details from connection metadata or a narrow read-only query when no dedicated tool exists. For a UI defect, compare the installed build, process state, bounded logs, target window/AX state and a diagnostic frame where permission allows; do not infer a cause merely from a successful connection.
5. Only perform the installation, removal, app control, UI action, transfer or settings change that the current request actually authorizes. An install result alone is not verification: check version, launch state and the reported behavior on the target. Keep the affected app's working functionality and rollback path in scope.
6. Call `vibekits.simulator.disconnect` on completion or a blocking error. Report what was actually observed, which route/identity was verified, what changed, and which claims remain unverified.

## Windows script execution

After the Windows device ID is connected and SSH is ready, use `vibekits.simulator.ssh_exec` for a short PowerShell script. Encode the script as UTF-16LE Base64 and pass one exact command: `powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand <base64>`. This avoids dependence on whether Windows OpenSSH starts `cmd.exe` or PowerShell and preserves Unicode and quoting. Check `ok`, `exitCode`, `stdout` and `stderr`; do not treat transport success as script success. For a longer `.ps1`, upload the exact file with `vibekits.simulator.upload_file`, execute that returned remote path with `powershell.exe -NoProfile -NonInteractive -File`, and verify the intended output. Do not change execution policy, bypass security prompts or open a desktop session.

Keep the whole workflow silent in the background and independent of Harness chat rendering. Never expose bridge tokens, credentials, private keys or authorization headers. Do not claim to have clicked a button when only a screenshot or source review was possible.

For an external macOS controller that lacks registered Harness MCP tools, read [references/tool-contract.md](references/tool-contract.md) and use the bundled `scripts/invoke.rb` against the local loopback VibeKits bridge. This fallback is not the Harness path and does not require the remote-desktop UI. For an Android PAD controlled from that Mac, follow the tested end-to-end [Mac → PAD remote ADB guide](references/mac-pad-remote-adb.md), including the dynamic local ADB serial, dual-screen targeting, reconnect after a host APK upgrade, and disconnect.

For a brand-new Mac and Android PAD, begin with the [first-install and remote ADB checklist](references/new-mac-pad-first-run.md). It identifies the public KEMI Market download pages, the cloud skill directory, the PAD release gate, and the exact handoff to the remote ADB guide. Do not treat an older market APK as having features that were added only in later device-tested candidates.
