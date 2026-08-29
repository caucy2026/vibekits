param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')]
  [string]$DeviceId,
  [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Test-PrivateIPv4([string]$Value) {
  $parsed = $null
  if (-not [Net.IPAddress]::TryParse($Value, [ref]$parsed) -or
      $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
    return $false
  }
  $bytes = $parsed.GetAddressBytes()
  return $bytes[0] -eq 10 -or
    ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
    ($bytes[0] -eq 192 -and $bytes[1] -eq 168)
}

$parts = @($env:SSH_CONNECTION -split '\s+' | Where-Object { $_ })
if ($parts.Count -ne 4) {
  [Console]::Error.WriteLine('VibeKits LAN MCP requires an authenticated SSH connection.')
  exit 10
}
$clientIp = $parts[0]
$serverIp = $parts[2]
if (-not (Test-PrivateIPv4 $clientIp) -or -not (Test-PrivateIPv4 $serverIp)) {
  [Console]::Error.WriteLine('VibeKits LAN MCP accepts private IPv4 connections only.')
  exit 11
}

if ($ValidateOnly) {
  [Console]::Out.WriteLine((@{
    ok = $true
    transport = 'ssh-stdio'
    deviceId = $DeviceId
    clientIp = $clientIp
    serverIp = $serverIp
    controlApproval = 'vibekits-app'
  } | ConvertTo-Json -Compress))
  exit 0
}

$launcher = Join-Path $PSScriptRoot 'start_vibekits_mcp.ps1'
if (-not (Test-Path -LiteralPath $launcher)) {
  [Console]::Error.WriteLine('The local VibeKits MCP launcher is missing.')
  exit 12
}

# SSH authenticates the enrolled device. The local launcher still talks only
# to the loopback bridge; every risky tool remains subject to APP approval.
& $launcher
exit $LASTEXITCODE
