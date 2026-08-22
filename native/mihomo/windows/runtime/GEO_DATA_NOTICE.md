# Mihomo GeoData notice

These runtime data files are included so the bundled Mihomo can evaluate
GEOIP/GEOSITE rules without downloading files during first launch:

- `Country.mmdb`
- `geoip.dat`
- `geosite.dat`

Upstream generation and release project:
<https://github.com/MetaCubeX/meta-rules-dat>

The exact SHA-256 and byte length of every bundled file are recorded in
`vibekits-mihomo-runtime.json`. They were taken from the installed Clash Verge
Rev bundle used for the Windows acceptance run. Update them only through
`tool/prepare_mihomo_runtime.ps1`, which rejects unexpected hashes.

These are generated network classification databases, not Vibekits source
code. Their upstream notices and data-source terms remain applicable.
