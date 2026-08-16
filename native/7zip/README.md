# 7-Zip 26.02 x64 archive backend

Unmodified files extracted from the official Windows x64 installer:

- Source: <https://www.7-zip.org/a/7z2602-x64.exe>
- Release date: 2026-06-25
- Installer SHA-256: `6745fa76dc2ea031596d8678f6f6b99c3c1b435b4164a63485adbbc7b8d82ef0`
- `7z.exe` SHA-256: `83967f1b02b43c4efeda302795722c809e0e81b8307de73558d10484d5676a7d`
- `7z.dll` SHA-256: `69fd4df057985c40e510e2fac182881c7f85e90aa13ec703f763a8fdb2ce61f8`

`7z.exe` and `7z.dll` are shipped together so the app can list and extract the
full format set, including RAR/RAR5, ISO/UDF, ZSTD, CAB, WIM, DMG and disk
images. Vibekits does not implement or expose RAR creation.

The upstream `License.txt` is distributed with the binaries. Most 7-Zip code
is LGPL-2.1-or-later; RAR decompression is also subject to the unRAR license
restriction stated in that file. The restriction prohibits using the sources
to recreate the proprietary RAR compression algorithm.
