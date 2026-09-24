#!/usr/bin/env python3
"""Build the PAD-only toolchain candidate without redistributing SDK android.jar.

Inputs are the previously verified Termux toolchain snapshot and the official
dex2jar v2.4 release archive. Output remains a candidate until device and
third-party license gates pass.
"""

from __future__ import annotations

import argparse
import hashlib
import shutil
import zipfile
from pathlib import Path

BASE_SHA256 = "367d0f2327bf28b57509351fd06afb38656e7e9b2562a9ad46e72720c91f1452"
DEX2JAR_SHA256 = "ee7c45eb3c1d2474a6145d8d447e651a736a22d9664b6d3d3be5a5a817dda23a"
DEX_PREFIX = "dex-tools-v2.4/"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def add(source: zipfile.ZipFile, source_name: str, target: zipfile.ZipFile, target_name: str) -> None:
    info = source.getinfo(source_name)
    if info.is_dir():
        return
    if target_name.startswith("/") or ".." in Path(target_name).parts:
        raise ValueError(f"unsafe archive path: {target_name}")
    with source.open(info) as incoming, target.open(target_name, "w") as outgoing:
        shutil.copyfileobj(incoming, outgoing, 1024 * 1024)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", required=True, type=Path)
    parser.add_argument("--dex2jar", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if sha256(args.base) != BASE_SHA256:
        raise ValueError("base toolchain SHA-256 mismatch")
    if sha256(args.dex2jar) != DEX2JAR_SHA256:
        raise ValueError("dex2jar release SHA-256 mismatch")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    tmp = args.output.with_suffix(args.output.suffix + ".next")
    try:
        with zipfile.ZipFile(args.base) as base, zipfile.ZipFile(args.dex2jar) as dex, \
                zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as output:
            names = set()
            for name in base.namelist():
                if name == "android.jar":
                    continue
                if name in names:
                    raise ValueError(f"duplicate entry: {name}")
                add(base, name, output, name)
                names.add(name)
            for name in dex.namelist():
                if not (name.startswith(DEX_PREFIX + "lib/") and name.endswith(".jar")) and name not in {
                    DEX_PREFIX + "lib/open-source-license.txt",
                    DEX_PREFIX + "LICENSE.txt",
                    DEX_PREFIX + "NOTICE.txt",
                }:
                    continue
                target = "dex2jar/" + name[len(DEX_PREFIX):]
                if target in names:
                    raise ValueError(f"duplicate entry: {target}")
                add(dex, name, output, target)
                names.add(target)
        tmp.replace(args.output)
    finally:
        tmp.unlink(missing_ok=True)
    with zipfile.ZipFile(args.output) as output:
        assert "android.jar" not in output.namelist()
        assert "dex2jar/lib/dex-tools-v2.4.jar" in output.namelist()
        print(f"entries={len(output.namelist())} bytes={args.output.stat().st_size} sha256={sha256(args.output)}")


if __name__ == "__main__":
    main()
