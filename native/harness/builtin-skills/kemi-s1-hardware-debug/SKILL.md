---
name: kemi-s1-hardware-debug
description: "Diagnose KEMI S1/huanglong hardware end to end through VibeKits Harness: continuously monitor the automatically discovered serial console, operate Android through a caller-provided ADB address, correlate both channels, use Git to trace evidence into HiV730 source, and write a Markdown analysis report. Use when asked about the KEMI S1 hardware-debug skill or asked to connect, monitor, operate, diagnose, source-analyze, or report on an S1; do not use for unrelated devices."
---

# KEMI S1 hardware debugging

This is a Harness-executable capability, not merely a device profile. It combines four linked abilities for a KEMI S1 (`huanglong`) target:

- discover the changing CH340 serial port and continuously monitor console/kernel output;
- connect to the supplied ADB address and inspect or operate Android;
- correlate serial and ADB evidence by timestamp and failure signature;
- inspect the relevant Git source and produce a persistent Markdown diagnosis.

When asked whether you know this skill, answer with those four abilities and the input still needed. Do not claim that live connections have succeeded until tool evidence exists. The operator normally provides only the current ADB address or `host:port`; never assume a saved IP or COM name.

## Required workflow

1. Refresh the live Harness/MCP catalog and use its current JSON Schemas. Use `vibekits.adb.*` and `vibekits.serial.*`; do not replace them with shell, system ADB, PowerShell serial access, or guessed parameters.
2. Normalize an address without a port to `5555`, call `adb.connect`, then `adb.list_devices`. Lock every later ADB call to that exact verified serial. Stop if it is unauthorized/offline or not KEMI S1/huanglong.
3. Call `serial.list_ports`. Rank current physical USB ports by CH340/CH341 description, USB transport, VID `0x1A86` (`6790`) and PID `0x7523` (`29987`). COM names can change; `COM33` is historical evidence only.
4. Use the verified console configuration: `115200 baud, 8 data bits, no parity, 1 stop bit, no flow control`. Do not probe other frame formats unless this profile fails on every matching candidate.
5. Try matching candidates one at a time with a bounded read-only console command. Send a unique marker plus `getprop` for model, manufacturer, device and Android release. Accept a port only after its response contains the marker, readable values and a console prompt; opening a handle or receiving zero bytes is not success.
6. Read the same four properties through the selected ADB serial and compare normalized values exactly. Current family evidence is model `huanglong`, manufacturer `HL2.0`, device `hi3781v730`, Android `12`; report drift instead of forcing these values.
7. For monitoring, open the advertised long-running serial session before reproducing the problem, read it incrementally without restarting the session, and keep timestamps/task IDs. Run ADB Logcat or other asynchronous diagnostics in parallel when useful. Stop and close all sessions at task completion or cancellation.
8. Use ADB operations required by the task only after identity passes. Read-only inspection is implicit; installs, launches, file transfer, process control, reboot, repeated stress actions, or settings changes must be explicitly requested or already part of the assigned test.
9. Always complete the Git linkage at least through the live HiV730 manifest: verify the remote/ref, read `default.xml` or the checked-out `.repo/manifest.xml`, and map collected serial/ADB evidence to the smallest candidate repository paths. If evidence contains a fault signature, continue into only those repositories; otherwise stop at a clearly labelled baseline routing result. Never equate repository mapping with root-cause proof.
10. Always write the final result to a `.md` file under the current task's approved workspace (prefer `docs/diagnostics/`). Include sanitized raw-evidence paths, serial/ADB correlation, Git findings, conclusion, fix proposal, verification and unresolved items. Return the absolute report path.

Read [references/s1-profile.md](references/s1-profile.md) before executing a live S1 task. It contains exact parameters, long-running monitoring rules, matching and fallback logic, Git routing, and the required Markdown report contract. Before any Git/source step, also read [references/hiv730-project-routing.md](references/hiv730-project-routing.md); it is the portable troubleshooting map distilled from `HIV730_ANDROID_PROJECT_GUIDE.md`.

## Boundaries

- Device and source mutations remain scoped to the current task. Flashing, bootloader work, destructive resets, credential changes, publishing, or source changes require explicit authority. Ordinary requested ADB actions such as install/launch/log collection do not need a second confirmation when already stated in the task.
- Local Harness uses the APP's local authority. Remote LMCP callers still require pairing and persisted provider-side scope.
- Do not send identifiers, logs, source, credentials, or network details to an external model without authorization for that transmission. The local VibeKits tool bridge can perform deterministic connection and comparison locally.
- Never print or store passwords, private keys, tokens, bridge credentials, or signing material.

## Completion

Completion requires a Markdown report, not only chat text. Report separately: live catalog, ADB connection/identity and operations, serial discovery and continuous-monitor interval, marker round trip, four-field comparison, timestamp correlation, requested diagnostics, Git source mapping, confidence-labelled conclusion, proposed fix and verification, session cleanup, and absolute report/evidence paths. One working channel cannot compensate for the other failing.

