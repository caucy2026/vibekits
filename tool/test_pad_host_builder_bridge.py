#!/usr/bin/env python3
"""Verify an installed PAD builder through the signed host's production Binder bridge."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

COMPONENT = "com.vibekits.vibekits.component.builder"
TEST_PACKAGE = "com.vibekits.vibekits.test"
RUNNER = TEST_PACKAGE + "/com.vibekits.vibekits.PadBuilderBridgeInstrumentation"
GAME_PACKAGE = "com.vibekits.whacdemo"
SIGNER = "c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8"


def run(argv: list[str], timeout: int = 240) -> str:
    result = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, check=False)
    if result.returncode:
        raise RuntimeError(f"command failed ({result.returncode}): {argv[0]}: {result.stderr[-500:]}")
    return result.stdout


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def result_fields(output: str, expected_sha: str) -> dict[str, object]:
    fields = dict(re.findall(r"^INSTRUMENTATION_RESULT: ([A-Za-z0-9]+)=([^\n]+)$", output, re.M))
    if (fields.get("status") != "passed" or fields.get("packageName") != GAME_PACKAGE
            or fields.get("sha256") != expected_sha or fields.get("bytes") != "25053"
            or "INSTRUMENTATION_CODE: -1" not in output):
        raise AssertionError(f"host bridge result mismatch: {fields}")
    return fields


def self_test() -> None:
    good = ("INSTRUMENTATION_RESULT: bytes=25053\n"
            "INSTRUMENTATION_RESULT: packageName=com.vibekits.whacdemo\n"
            "INSTRUMENTATION_RESULT: sha256=" + "a" * 64 + "\n"
            "INSTRUMENTATION_RESULT: status=passed\nINSTRUMENTATION_CODE: -1\n")
    assert result_fields(good, "a" * 64)["status"] == "passed"
    for bad in [good.replace("status=passed", "status=failed"),
                good.replace("INSTRUMENTATION_CODE: -1", "INSTRUMENTATION_CODE: 0"),
                good.replace("a" * 64, "b" * 64)]:
        try:
            result_fields(bad, "a" * 64)
        except AssertionError:
            pass
        else:
            raise AssertionError("negative control incorrectly passed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--serial", required=True)
    parser.add_argument("--adb-server-port", type=int, default=5037)
    parser.add_argument("--component-apk", required=True, type=Path)
    parser.add_argument("--host-test-apk", required=True, type=Path)
    parser.add_argument("--expected-game-sha256", required=True)
    parser.add_argument("--evidence-dir", required=True, type=Path)
    args = parser.parse_args()
    self_test()
    if not re.fullmatch(r"[0-9a-f]{64}", args.expected_game_sha256):
        parser.error("expected game SHA-256 must be 64 lowercase hex characters")
    sdk = Path("/Users/newlink/android-sdk")
    adb = [str(sdk / "platform-tools/adb"), "-P", str(args.adb_server_port)]
    device = adb + ["-s", args.serial]
    aapt = str(sdk / "build-tools/35.0.0/aapt")
    apksigner = str(sdk / "build-tools/35.0.0/apksigner")
    for path, package in [(args.component_apk, COMPONENT), (args.host_test_apk, TEST_PACKAGE)]:
        if not path.is_file():
            parser.error(f"APK missing: {path}")
        badge = run([aapt, "dump", "badging", str(path)]).splitlines()[0]
        if f"name='{package}'" not in badge:
            parser.error(f"unexpected package in {path}")
        signature = run([apksigner, "verify", "--print-certs", str(path)])
        if "Signer #1 certificate SHA-256 digest: " + SIGNER not in signature:
            parser.error(f"unexpected signer in {path}")
    if args.serial not in run(adb + ["devices", "-l"]):
        parser.error("device is not connected")
    existing = run(device + ["shell", "pm", "list", "packages", TEST_PACKAGE])
    if "package:" + TEST_PACKAGE in existing:
        parser.error("refusing to replace an existing host test APK")
    args.evidence_dir.mkdir(parents=True, exist_ok=True)
    receipt: dict[str, object] = {
        "serial": args.serial,
        "startedAt": datetime.now(timezone.utc).isoformat(),
        "componentApk": {"path": str(args.component_apk), "bytes": args.component_apk.stat().st_size,
                         "sha256": digest(args.component_apk)},
        "hostTestApk": {"path": str(args.host_test_apk), "sha256": digest(args.host_test_apk)},
        "expectedGameSha256": args.expected_game_sha256,
        "runs": [],
        "state": "incomplete",
    }
    test_installed = False
    try:
        package_state = run(device + ["shell", "dumpsys", "package", COMPONENT])
        version = re.search(r"versionCode=(\d+)", package_state)
        if not version or int(version.group(1)) < 6:
            raise AssertionError("installed builder versionCode is below 6")
        receipt["installedVersionCode"] = int(version.group(1))
        path_output = run(device + ["shell", "pm", "path", COMPONENT]).strip().splitlines()
        if len(path_output) != 1 or not path_output[0].startswith("package:"):
            raise AssertionError("component APK path is not unique")
        pulled = args.evidence_dir / "installed-component.apk"
        run(device + ["pull", path_output[0][len("package:"):], str(pulled)])
        receipt["installedApkSha256"] = digest(pulled)
        pulled.unlink()
        if receipt["installedApkSha256"] != receipt["componentApk"]["sha256"]:
            raise AssertionError("installed component bytes differ from candidate")
        run(device + ["install", str(args.host_test_apk)])
        test_installed = True
        for index in range(2):
            output = run(device + ["shell", "am", "instrument", "-w", "-e", "realGame", "true", RUNNER])
            (args.evidence_dir / f"instrument-{index + 1}.txt").write_text(output)
            receipt["runs"].append(result_fields(output, args.expected_game_sha256))
        receipt["state"] = "passed"
    except Exception as error:
        receipt["state"] = "failed"
        receipt["error"] = str(error)
    finally:
        if test_installed:
            try:
                run(device + ["uninstall", TEST_PACKAGE], timeout=30)
                receipt["testApkRemoved"] = True
            except Exception as error:
                receipt["testApkRemoved"] = False
                receipt["cleanupError"] = str(error)
                receipt["state"] = "failed"
        receipt["finishedAt"] = datetime.now(timezone.utc).isoformat()
        (args.evidence_dir / "receipt.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"state": receipt["state"], "evidence": str(args.evidence_dir)}))
    return 0 if receipt["state"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
