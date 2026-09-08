# HiV730 evidence-to-source routing

This is the portable debugging subset of `HIV730_ANDROID_PROJECT_GUIDE.md` (source document observed 2026-08-28). Use it after serial and ADB evidence have been timestamp-correlated. The live manifest is authoritative when this reference and the server differ.

## Manifest-first invariant

- Project: Android 12 multi-repository tree managed by `repo`.
- Gerrit web: `http://172.21.16.194:8092/`.
- SSH: `172.21.16.194:29420`.
- Manifest repository: `HiV730/manifest.git`; expected manifest/default project branch: `master`.
- Read live refs and `default.xml` first. Resolve every local `path` to its exact Gerrit `name`; do not invent repository names from directory names.
- Never run an unparameterized `repo sync`, download all AOSP, or clone the entire tree for diagnosis.
- Authentication, account approval, SSH-key creation/upload, first-login and trusted host-fingerprint confirmation remain user/admin actions. Never read or expose private keys or credentials.

## Evidence routing table

| Serial/ADB evidence | First candidate paths | Expand only when the call chain proves it |
| --- | --- | --- |
| Newlink package/process (`NL*`, package name, app exception) | `vendor/newlink/packages/apps/<App>` | `vendor/newlink/middleware`, `vendor/newlink/frameworks` |
| Newlink system service, Java API or Binder client | `vendor/newlink/middleware`, `vendor/newlink/frameworks` | `frameworks`, `vendor/huanglong/aosp_ext` |
| Display, black screen, HWC, HDMI, SurfaceFlinger vendor failure | `vendor/huanglong/hardware`, `vendor/huanglong/interfaces`, `vendor/huanglong/haldefault` | `frameworks`, `hardware`, then `vendor/huanglong/linux` |
| Audio, camera, sensors, power HAL/service | `vendor/huanglong/hardware`, `vendor/huanglong/interfaces`, `vendor/huanglong/haldefault` | `vendor/huanglong/modules`, relevant AOSP `hardware`/`frameworks` |
| Kernel panic/oops, driver tag, watchdog reset, DTS/node/property | `vendor/huanglong/linux`, `vendor/device/mp_linux` | `vendor/open_source/common-kernel-5.10` |
| Bootloader, bootargs, early serial boot failure | `vendor/huanglong/bootloader`, `vendor/open_source/u-boot` | `vendor/huanglong/minorimages`, `vendor/device/mp_linux` |
| Product property, package inclusion, BoardConfig/device.mk | `vendor/configs`, `vendor/device/mp`, `vendor/device/feature` | `vendor/device/sepolicy`, `vendor/device/mp_linux` |
| SELinux denial (`avc: denied`) | `vendor/device/sepolicy` plus the owning service/app repository | AOSP `system`/`frameworks` policy only when type ownership proves it |
| Wi-Fi/Bluetooth vendor HAL/driver | `vendor/thirdparty/wifi_bt`, `vendor/huanglong/hardware` | `vendor/huanglong/linux`, AOSP `hardware` |
| GPU/render/graphics driver | `vendor/thirdparty/gpu`, `vendor/huanglong/hardware` | `frameworks`, `vendor/huanglong/linux` |
| Runtime/native crash | owning app/service first | `art`, `bionic`, `system`, `frameworks` only when stack frames require them |

Important known paths include `vendor/huanglong/modules`, `vendor/huanglong/aosp_ext`, `vendor/huanglong/mcu`, `vendor/newlink/hardware`, `vendor/newlink/external`, and `vendor/newlink/prebuilts/apps`. Treat names inferred from this map as candidates until confirmed in the live manifest.

## Source expansion algorithm

1. Extract exact tags, process/package, exception/panic text, service/interface, property, device-tree node and top stack frames from correlated serial/ADB evidence.
2. Read live manifest and produce a table: evidence → subsystem → manifest path → repository name → reason → confidence.
3. Select the smallest first candidate. Read its `AGENTS.md` (including deeper applicable files), `README*`, and build entry (`Android.bp`, `Android.mk`, Gradle, `device.mk`, or `BoardConfig*`) before analyzing implementation.
4. Expand one layer only when imports, Binder/HAL interfaces, stack frames, build dependencies or kernel call paths demonstrate the edge. Record that evidence.
5. For healthy baselines, stop after manifest verification and candidate mapping. For failures, cite repository/ref/SHA/file/line and label the conclusion `confirmed`, `probable`, or `unresolved`.
6. Recommend the smallest fix and a reproduction-specific device regression using both serial and ADB. Do not compile, deploy, flash or edit source unless the current task requests it.

## Common minimal sets

- Newlink app: its single `vendor/newlink/packages/apps/<App>` repository; add middleware/frameworks only on a proven dependency.
- Framework behavior: `frameworks`, `vendor/newlink/frameworks`, `vendor/huanglong/aosp_ext`.
- Display/HWC: Huanglong hardware/interfaces/haldefault; add AOSP graphics or kernel only when shown by evidence.
- Kernel/DTS: `vendor/huanglong/linux`, `vendor/device/mp_linux`; add common kernel 5.10 only for shared-kernel code.
- Product/preinstall/SELinux: `vendor/configs`, `vendor/device/mp`, `vendor/device/feature`, `vendor/device/sepolicy`.

The Markdown report must show this routing decision even if Git stops at the manifest. A statement such as “no anomaly, Git not used” is incomplete for a requested serial/ADB/Git linkage task; instead show that the manifest was verified and why deeper source retrieval was unnecessary.

