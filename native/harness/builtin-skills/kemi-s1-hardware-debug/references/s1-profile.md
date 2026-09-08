# KEMI S1 / huanglong verified profile

## Input and discovery

The operator provides only `adbAddress`: an IPv4 address, hostname, or `host:port`. If no port is supplied, use `5555`. Never request or assume a COM port before discovery.

Always refresh the live catalog before calls. The names below are stable internal IDs; exported names and schemas come from the live provider.

1. `vibekits.adb.connect {"address":"<adbAddress>"}`
2. `vibekits.adb.list_devices {}`
3. `vibekits.serial.list_ports {}`
4. Rank current candidates using CH340/CH341 description, `transport=usb`, `vendorId=6790` (`0x1A86`) and `productId=29987` (`0x7523`).
5. Try each matching candidate with `vibekits.serial.transact`:

```json
{
  "port": "<discovered-port>",
  "baudRate": 115200,
  "dataBits": 8,
  "stopBits": 1,
  "parity": "none",
  "flowControl": "none",
  "mode": "text",
  "data": "echo <unique-marker>; getprop ro.product.model; getprop ro.product.manufacturer; getprop ro.product.device; getprop ro.build.version.release; echo <unique-end-marker>\r\n",
  "waitMs": 5000
}
```

Accept the port only when the delimited response contains four readable values and a console prompt. Continue to the next enumerated candidate on open failure, zero bytes, missing marker, undecodable output, or mismatched identity. Never scan invented COM names.

For the exact serial returned by ADB, call `vibekits.adb.command` four times with `arguments=["shell","getprop","<property>"]` for `ro.product.model`, `ro.product.manufacturer`, `ro.product.device`, and `ro.build.version.release`. Trim CR/LF and compare all four values.

`serial.auto_detect` can help with an unknown noisy console, but a quiet console can return zero bytes and zero confidence. For S1, the verified 115200/8-N-1/no-flow-control profile plus marker round trip is decisive.

## Verified evidence

On 2026-09-07, caller-supplied ADB `192.168.3.75:5555` and dynamically discovered `COM33`/CH340/`1A86:7523` both returned:

- model `huanglong`
- manufacturer `HL2.0`
- device `hi3781v730`
- Android `12`

The serial transaction sent 174 bytes and received 810 bytes with markers and `console:/ $`. These are identity expectations and historical evidence, not fixed IP or COM configuration.

## Diagnostics after identity passes

- Boot/reboot: serial continuous log plus ADB `boot_id`, boot reason, pstore/ramoops and bounded dmesg.
- Crash/ANR: ADB main/events/crash Logcat, ANR traces, tombstones and activity/process state, with serial tail.
- Black screen: SurfaceFlinger/display/HWC/GPU evidence plus serial/kernel tail.
- Install/launch stress: asynchronous task/session tools, explicit iterations, stage evidence, abort thresholds, cancellation and cleanup.

Never manufacture serial success from ADB-only data. Preserve bounded raw evidence and a normalized comparison.

## Continuous serial and ADB operation

For a reproduced failure, start the serial monitoring session first and record its start time and session ID. Consume incremental chunks through the live MCP schema; do not repeatedly open the COM port because that can lose boot output or collide with another owner. Start an ADB Logcat/task session when Android is reachable, retain its task ID, and correlate both streams using host timestamps plus recognizable boot/crash markers. ADB disappearing while serial continues is itself evidence.

ADB is the Android control plane. After the exact serial is verified, use its advertised Harness tools for the task's requested actions, including shell commands, package install/uninstall, launch/force-stop, push/pull, screenshots, Logcat, reboot, and bounded repetition. Inspect the live schema before every new tool family. Record command, target serial, start/end time, exit/result, and artifact path. Never silently switch to another attached device.

Serial is the independent system/boot evidence plane. Prefer read-only console commands and continuous capture. Do not send reboot, bootloader, flash, destructive shell, or configuration commands unless the task explicitly authorizes that mutation.

## HiV730 source routing

Recovered historical project coordinates:

- SSH manifest: `ssh://172.21.16.194:29420/HiV730/manifest.git`
- Gerrit HTTP manifest: `http://172.21.16.194:8092/HiV730/manifest.git`
- historical master SHA: `7ed6ea64eb96ea379aacdcd3319eac38d2257e82`
- manifest: `default.xml`

These private-network coordinates do not prove current reachability or authorization. Refresh refs first. Preserve SSH host-key verification; the historical SSH attempt failed closed on an unknown host key. The HTTP endpoint previously supported read-only refs and manifest retrieval.

For every linkage task, use bounded VibeKits Git tools: `git.list_remote_refs`, then `git.read_remote_file` to read the live manifest (`default.xml`) and verify its default revision and exact project `name`/`path`. This baseline manifest inspection is required even when the device is healthy. Map the serial/ADB evidence to the smallest candidate paths using [hiv730-project-routing.md](hiv730-project-routing.md). Only after collecting a real failure signature may `git.clone_minimal` fetch an explicit candidate repository/ref/depth for file/line analysis. Never run an unbounded `repo sync` or clone the whole HiV730 tree by default.

Source analysis must connect evidence to code. Search for exact exception text, service/process name, kernel tag, property, package, HAL/interface, or device-tree node. Record repository, ref/SHA, file and line range, and explain why the code can produce the observed serial/ADB sequence. Label the result `confirmed`, `probable`, or `unresolved`; source proximity alone is not proof. Suggest the smallest code/configuration change and a device-side regression test. Do not edit source unless the assigned task asks for a fix.

## Evidence result

Create `docs/diagnostics/KEMI_S1_<YYYYMMDD_HHMMSS>_<short-topic>.md` inside the approved workspace, or the nearest approved documentation directory. Use this contract:

1. task, scope, timestamp/timezone and target;
2. MCP provider/tool catalog version and exact live tool names used;
3. ADB identity and requested operations with results;
4. serial discovery, USB identity, frame parameters and monitored interval;
5. time-correlated ADB/serial event table;
6. sanitized raw artifacts and their absolute paths/hashes when useful;
7. Git manifest remote/ref/SHA, evidence-to-repository routing, and—when a fault justifies source retrieval—file/line findings;
8. conclusion with confidence and evidence for/against;
9. proposed minimal fix and concrete verification steps;
10. blocked/unresolved items and session cleanup state.

Return the absolute Markdown path in the final response. If Git/source access is unavailable, still write the report and mark source analysis blocked with the exact sanitized reason; never fabricate it.

