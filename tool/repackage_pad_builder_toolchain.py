#!/usr/bin/env python3
"""Build the PAD-only toolchain candidate without redistributing SDK android.jar.

Inputs are the previously verified Termux toolchain snapshot and the official
dex2jar v2.4 release archive. Output remains a candidate until device and
third-party license gates pass.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import shutil
import tarfile
import zipfile
from pathlib import Path

BASE_SHA256 = "367d0f2327bf28b57509351fd06afb38656e7e9b2562a9ad46e72720c91f1452"
DEX2JAR_SHA256 = "ee7c45eb3c1d2474a6145d8d447e651a736a22d9664b6d3d3be5a5a817dda23a"
PACKAGES_SHA256 = "347d39b9138688014104481fbe0e1382ca89b034586ce6d68917fe272f30b2ee"
REPLACEMENTS = {
    "lib/libc++_shared.so": ("libc++", "30", "libc++_30_aarch64.deb",
        "53d0b84a7ba7459024257cb94d5b136fe13ef858567f65a8064b35950799f2ca",
        "./data/data/com.termux/files/usr/lib/libc++_shared.so"),
    "lib/libz.so.1": ("zlib", "1.3.2", "zlib_1.3.2_aarch64.deb",
        "75e7d0af17fcc3b40004309fdc00a1ddb9ae08346dce5e269902c34ac3966ac9",
        "./data/data/com.termux/files/usr/lib/libz.so.1.3.2"),
}
DEX_PREFIX = "dex-tools-v2.4/"
DEX_JARS = {
    "asm-9.5.jar",
    "asm-analysis-9.5.jar",
    "asm-commons-9.5.jar",
    "asm-tree-9.5.jar",
    "asm-util-9.5.jar",
    "d2j-base-cmd-v2.4.jar",
    "dex-ir-v2.4.jar",
    "dex-reader-api-v2.4.jar",
    "dex-reader-v2.4.jar",
    "dex-tools-v2.4.jar",
    "dex-translator-v2.4.jar",
}


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


def package_records(path: Path) -> dict[tuple[str, str], dict[str, str]]:
    if sha256(path) != PACKAGES_SHA256:
        raise ValueError("Termux Packages.gz SHA-256 mismatch")
    records = {}
    with gzip.open(path, "rt") as stream:
        for paragraph in stream.read().split("\n\n"):
            fields = dict(line.split(": ", 1) for line in paragraph.splitlines() if ": " in line)
            if "Package" in fields and "Version" in fields:
                records[(fields["Package"], fields["Version"])] = fields
    return records


def deb_member(path: Path, member_name: str) -> bytes:
    with path.open("rb") as stream:
        if stream.read(8) != b"!<arch>\n":
            raise ValueError(f"invalid deb archive: {path}")
        while header := stream.read(60):
            if len(header) != 60 or header[58:60] != b"`\n":
                raise ValueError(f"invalid deb member: {path}")
            name = header[:16].decode("ascii").strip().rstrip("/")
            length = int(header[48:58].decode("ascii"))
            payload = stream.read(length)
            if length % 2:
                stream.read(1)
            if name.startswith("data.tar."):
                with tarfile.open(fileobj=io.BytesIO(payload), mode="r:*") as archive:
                    item = archive.getmember(member_name)
                    if not item.isfile():
                        raise ValueError(f"not a file: {member_name}")
                    return archive.extractfile(item).read()
    raise ValueError(f"missing deb payload: {member_name}")


def verified_replacements(directory: Path, index: Path) -> dict[str, bytes]:
    records = package_records(index)
    result = {}
    for target, (package, version, filename, expected_sha, source_name) in REPLACEMENTS.items():
        record = records.get((package, version))
        if not record or Path(record.get("Filename", "")).name != filename or record.get("SHA256") != expected_sha:
            raise ValueError(f"Termux package index mismatch: {package} {version}")
        deb = directory / filename
        if sha256(deb) != expected_sha:
            raise ValueError(f"Termux deb SHA-256 mismatch: {filename}")
        result[target] = deb_member(deb, source_name)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", required=True, type=Path)
    parser.add_argument("--dex2jar", required=True, type=Path)
    parser.add_argument("--termux-packages", required=True, type=Path)
    parser.add_argument("--termux-debs", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if sha256(args.base) != BASE_SHA256:
        raise ValueError("base toolchain SHA-256 mismatch")
    if sha256(args.dex2jar) != DEX2JAR_SHA256:
        raise ValueError("dex2jar release SHA-256 mismatch")
    replacements = verified_replacements(args.termux_debs, args.termux_packages)
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
                if name in replacements:
                    info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                    info.compress_type = zipfile.ZIP_DEFLATED
                    info.external_attr = 0o644 << 16
                    output.writestr(info, replacements[name])
                else:
                    add(base, name, output, name)
                names.add(name)
            if not set(replacements).issubset(names):
                raise ValueError("base toolchain lacks a replacement target")
            for name in dex.namelist():
                if name not in {DEX_PREFIX + "lib/" + jar for jar in DEX_JARS} and name not in {
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
        assert {"dex2jar/lib/" + jar for jar in DEX_JARS}.issubset(output.namelist())
        assert len([name for name in output.namelist() if name.startswith("dex2jar/lib/") and name.endswith(".jar")]) == len(DEX_JARS)
        print(f"entries={len(output.namelist())} bytes={args.output.stat().st_size} sha256={sha256(args.output)}")


if __name__ == "__main__":
    main()
