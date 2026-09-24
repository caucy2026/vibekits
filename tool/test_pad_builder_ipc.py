#!/usr/bin/env python3
"""Real-device regression for PAD builder Binder calls and UI responsiveness."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


COMPONENT = "com.vibekits.vibekits.component.builder"
PROBE = "com.vibekits.vibekits.builderprobeclient"
SIGNER = "c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8"


def run(args, check=True):
    result = subprocess.run(args, text=True, capture_output=True, check=False)
    if check and result.returncode:
        raise RuntimeError("command failed: {}: {}".format(args[0], result.stderr.strip()))
    return result.stdout


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def classify(log):
    if "ANR of " + PROBE in log:
        return "failed"
    if re.search(r"PAD_BUILDER_IPC_PROBE: (?:failed|client_error|runtime_failed|task_timeout|start_rejected|bind_failed)", log):
        return "failed"
    if re.search(r"PAD_BUILDER_IPC_PROBE: completed bytes=\d+ package=com\.vibekits\.builderipcprobe sha256=[0-9a-f]{64}", log):
        return "passed"
    return "running"


def self_test():
    completed = "PAD_BUILDER_IPC_PROBE: completed bytes=8535 package=com.vibekits.builderipcprobe sha256=" + "a" * 64
    assert classify(completed) == "passed"
    assert classify("ANR of " + PROBE + "\n" + completed) == "failed"
    assert classify("PAD_BUILDER_IPC_PROBE: client_error=RemoteException") == "failed"
    assert classify("PAD_BUILDER_IPC_PROBE: progress=building step=dex") == "running"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--serial", required=True)
    parser.add_argument("--component-apk", type=Path, required=True)
    parser.add_argument("--probe-apk", type=Path, required=True)
    parser.add_argument("--evidence-dir", type=Path, required=True)
    parser.add_argument("--timeout-seconds", type=int, default=120)
    parser.add_argument("--runs", type=int, default=1,
                        help="run again after force-stopping the probe to verify cached component startup")
    args = parser.parse_args()
    self_test()
    if args.timeout_seconds < 10 or args.timeout_seconds > 300:
        parser.error("timeout must be between 10 and 300 seconds")
    if args.runs not in (1, 2):
        parser.error("runs must be 1 or 2")

    sdk = Path(os.environ.get("ANDROID_HOME", "/Users/newlink/android-sdk"))
    adb = str(sdk / "platform-tools/adb")
    aapt = str(sdk / "build-tools/35.0.0/aapt")
    apksigner = str(sdk / "build-tools/35.0.0/apksigner")
    target = [adb, "-s", args.serial]
    artifacts = [(COMPONENT, args.component_apk), (PROBE, args.probe_apk)]
    for package, path in artifacts:
        if not path.is_file():
            parser.error("APK missing: " + str(path))
        badge = run([aapt, "dump", "badging", str(path)]).splitlines()[0]
        if "name='{}'".format(package) not in badge:
            parser.error("unexpected package in " + str(path))
        signature = run([apksigner, "verify", "--print-certs", str(path)])
        if "Signer #1 certificate SHA-256 digest: " + SIGNER not in signature:
            parser.error("unexpected signer in " + str(path))

    if args.serial not in run([adb, "devices", "-l"]):
        parser.error("device is not connected")
    if run(target + ["shell", "getprop", "ro.product.cpu.abi"]).strip() != "arm64-v8a":
        parser.error("device is not arm64-v8a")
    for package, _ in artifacts:
        if "package:" + package in run(target + ["shell", "pm", "list", "packages", package]):
            parser.error("refusing to replace an existing package: " + package)

    args.evidence_dir.mkdir(parents=True, exist_ok=True)
    receipt = {
        "serial": args.serial,
        "artifacts": [{"package": package, "path": str(path), "bytes": path.stat().st_size,
                       "sha256": digest(path)} for package, path in artifacts],
        "state": "incomplete",
        "runs": [],
    }
    installed = []
    try:
        for package, path in artifacts:
            if "Success" not in run(target + ["install", str(path)]):
                raise RuntimeError("install did not succeed: " + package)
            installed.append(package)
        all_logs = []
        for index in range(args.runs):
            if index:
                time.sleep(2)  # device logcat timestamps have one-second precision
            stamp = run(target + ["shell", "date", "+%m-%dT%H:%M:%S.000"]).strip().replace("T", " ")
            started = time.monotonic()
            run(target + ["shell", "am", "start", "-n", PROBE + "/.ProbeClientActivity"])
            deadline = started + args.timeout_seconds
            while True:
                log = run(target + ["logcat", "-d", "-T", stamp])
                relevant = "\n".join(
                    line for line in log.splitlines()
                    if "PAD_BUILDER_IPC_PROBE" in line or "ANR of " + PROBE in line
                )
                state = classify(relevant)
                if state != "running" or time.monotonic() >= deadline:
                    state = state if state != "running" else "timeout"
                    receipt["runs"].append({"index": index + 1, "state": state,
                                            "elapsedSeconds": round(time.monotonic() - started, 2)})
                    all_logs.append("=== run {} ===\n{}".format(index + 1, relevant))
                    break
                time.sleep(2)
            run(target + ["shell", "am", "force-stop", PROBE], check=False)
            if state != "passed":
                break
        receipt["state"] = "passed" if len(receipt["runs"]) == args.runs and all(
            item["state"] == "passed" for item in receipt["runs"]
        ) else "failed"
        (args.evidence_dir / "pad-builder-ipc.log").write_text("\n".join(all_logs) + "\n")
    except Exception as error:
        receipt["state"] = "infrastructure_failure"
        receipt["error"] = str(error)
    finally:
        run(target + ["shell", "am", "force-stop", PROBE], check=False)
        for package in reversed(installed):
            run(target + ["uninstall", package], check=False)
        receipt["remainingPackages"] = run(target + ["shell", "pm", "list", "packages", COMPONENT]).strip()
        (args.evidence_dir / "pad-builder-ipc.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"state": receipt["state"], "evidence": str(args.evidence_dir)}, ensure_ascii=False))
    return 0 if receipt["state"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
