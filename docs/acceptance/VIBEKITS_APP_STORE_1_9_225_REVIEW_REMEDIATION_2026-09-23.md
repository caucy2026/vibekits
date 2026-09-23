# VibeKits Mac App Store 1.9.225 review remediation

- Product: VibeKits; platform: macOS; channel: Apple App Store.
- Base source: `5a5fb88bc257d695829234245c5befa8effb3ebe` (latest `main` when work began).
- Isolated worktree/branch: `release/app-store-review-20260923`.
- Apple App ID: `6809822607`; bundle ID: `com.caucy.vibekits`; team: `26T5WV4GLP`.
- Version/build: `1.9.225 (2226)`; minimum macOS 12.0; arm64 and x86_64.
- Exported package: `/Volumes/ORICO/kemi-build-cache/vibekits-app-store-dev225/export/Vibekits.pkg`.
- Package size: 57,159,640 bytes; SHA-256: `e1437fafb88782ba030d8e20651fc099a29985178cab028b574a28b02aa8322e`.
- Apple processed build ID: `866e02df-39b8-44e2-8d3b-32a59725f647`; binary status: verified.
- Submission ID: `9ada6dbb-0712-49bc-9082-9dc79e808d57` (resubmission of rejected record).
- Persistent state after page reload, 2026-09-23 10:25 CST: **Waiting for Review**. This is not publication.

## Rejection and correction

Apple rejected 1.9.162 (2169) on 2026-09-21 under Guideline 2.3.8 because the icon appeared to be a placeholder and Guideline 1.5 because the old support URL did not allow users to request support. The Store-only build now uses an original, complete `AppIconStore` at all macOS icon sizes; the normal/direct-distribution icon is untouched. The Support URL is `https://github.com/caucy2026/vibekits/issues`, a public product-specific issue tracker. The listing description was aligned with the actual archive and document features, and reviewer notes specify both fixes and deterministic offline review steps.

## Gates and limits

- `flutter analyze` on the Store entry point and related pages passed.
- `flutter test test/app_store_surface_test.dart` passed (2 tests).
- Xcode archive and export succeeded using Cloud Managed Apple Distribution. App Store Connect reports the uploaded binary as verified, with App Sandbox and only user-selected read-write file access.
- Exported package contains a dedicated `AppIconStore.icns`; no Harness/tool runtime or forbidden plugin frameworks were found in the archive.
- The archive and exported App Store package could not be directly launched on this workstation outside the App Store due to local trust/receipt handling (`open` returned `kLSNoExecutableErr`). Do not count this as a local install/launch pass. Public install/launch remains to be verified after approval.
- Xcode warned that the archive lacked a dSYM for a binary labeled `A`; upload succeeded and Apple verified the binary. Investigate only if Apple or crash-symbolication testing identifies an impact.

## Next state gate

Reopen the exact App Store Connect submission. On rejection, read the new full message before changing the build. Mark published only after an anonymous product page exposes version 1.9.225 and install/launch succeeds.
