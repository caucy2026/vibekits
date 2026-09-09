# RustDesk transport provenance

VibeKits uses a source-built, headless subset of RustDesk only as a network
carrier: HBBS rendezvous, peer-to-peer hole punching, and HBBR byte relay.
VibeKits does not ship or expose desktop capture, remote input, clipboard,
file-transfer, terminal, or generic port-forward product features through the
Harness API.

Current source checkout:

- repository: `https://github.com/caucy2026/rust-desk.git`
- commit: `e86d764ddf4acc9e9175e1b2e6a9f9903c202b6e`
- VibeKits Android ABI currently imported: `arm64-v8a`
- required JNI symbols are verified by `tool/import_rustdesk_harness_transport.sh`

The application must remain self-contained. macOS and Windows releases bundle
`vibekits-harness-relay` beside the main executable. Android bundles
`librustdesk.so` and `libc++_shared.so` in the APK and starts it only from the
private, non-exported `:vibekits_harness` service. Runtime discovery of another
installed RustDesk/KEMI application is forbidden.

The upstream GNU AGPL license is preserved as `LICENCE` in this directory.
Whenever the transport source changes, rebuild it from the pinned checkout,
run the importer, record the new commit and hashes, then rebuild and test every
shipping platform. A copied binary without this provenance and symbol gate is
not a releasable input.
