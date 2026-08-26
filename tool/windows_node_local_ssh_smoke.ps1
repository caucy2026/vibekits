param(
  [string]$UserName = 'kemi-test',
  [string]$AuthorizedKeysPath = 'C:\Users\kemi-test\.ssh\authorized_keys',
  [Parameter(Mandatory = $true)]
  [string]$ExpectedHostKeyFingerprint
)

$ErrorActionPreference = 'Stop'
$sshd = "$env:WINDIR\System32\OpenSSH\sshd.exe"
$ssh = "$env:WINDIR\System32\OpenSSH\ssh.exe"
$sshKeygen = "$env:WINDIR\System32\OpenSSH\ssh-keygen.exe"
$sshKeyscan = "$env:WINDIR\System32\OpenSSH\ssh-keyscan.exe"
$user = Get-LocalUser -Name $UserName
$userSid = $user.SID.Value
$operatorSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$sshDirectory = Split-Path -Parent $AuthorizedKeysPath
$temporaryRoot = Join-Path $env:TEMP "vibekits-node-ssh-smoke-$PID"
$temporaryKey = Join-Path $temporaryRoot 'id_ed25519'
$knownHosts = Join-Path $temporaryRoot 'known_hosts'
$originalLines = @()
$originalCaptured = $false
$testOutput = $null
$testExitCode = $null

function Invoke-Icacls([string[]]$Arguments) {
  & icacls.exe @Arguments | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "icacls failed: $($Arguments -join ' ')" }
}

function Grant-EditAccess {
  New-Item -ItemType Directory -Path $sshDirectory -Force | Out-Null
  & takeown.exe /F $sshDirectory /A /R /D Y | Out-Null
  Invoke-Icacls @(
    $sshDirectory,
    '/inheritance:r',
    '/grant:r',
    '*S-1-5-32-544:(OI)(CI)F',
    "*$operatorSid`:(OI)(CI)F",
    "*$userSid`:(OI)(CI)F",
    '*S-1-5-18:(OI)(CI)F'
  )
  if (Test-Path -LiteralPath $AuthorizedKeysPath) {
    & takeown.exe /F $AuthorizedKeysPath /A | Out-Null
    Invoke-Icacls @(
      $AuthorizedKeysPath,
      '/grant:r',
      '*S-1-5-32-544:F',
      "*$operatorSid`:F",
      "*$userSid`:F",
      '*S-1-5-18:F'
    )
  }
}

function Set-KeyLines([string[]]$Lines) {
  Grant-EditAccess
  [IO.File]::WriteAllText(
    $AuthorizedKeysPath,
    (($Lines | Where-Object { $_.Trim() }) -join "`n") + "`n",
    [Text.UTF8Encoding]::new($false)
  )
  Invoke-Icacls @($AuthorizedKeysPath, '/inheritance:r')
  Invoke-Icacls @(
    $AuthorizedKeysPath,
    '/grant:r',
    "*$userSid`:F",
    '*S-1-5-18:F'
  )
  Invoke-Icacls @($AuthorizedKeysPath, '/setowner', "*$userSid")
  Invoke-Icacls @(
    $sshDirectory,
    '/grant:r',
    "*$userSid`:(OI)(CI)F",
    '*S-1-5-18:(OI)(CI)F'
  )
  Invoke-Icacls @($sshDirectory, '/setowner', "*$userSid")
  Invoke-Icacls @($AuthorizedKeysPath, '/remove:g', '*S-1-5-32-544')
  Invoke-Icacls @($sshDirectory, '/remove:g', '*S-1-5-32-544')
  if ($operatorSid -ne $userSid -and $operatorSid -ne 'S-1-5-18') {
    Invoke-Icacls @($AuthorizedKeysPath, '/remove:g', "*$operatorSid")
    Invoke-Icacls @($sshDirectory, '/remove:g', "*$operatorSid")
  }
}

try {
  Grant-EditAccess
  if (Test-Path -LiteralPath $AuthorizedKeysPath) {
    $originalLines = @(Get-Content -LiteralPath $AuthorizedKeysPath | Where-Object { $_.Trim() })
  }
  $originalCaptured = $true

  New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
  & $sshKeygen -q -t ed25519 -N '' -f $temporaryKey -C 'vibekits-local-auth-smoke'
  if ($LASTEXITCODE -ne 0) { throw 'Temporary ssh-keygen failed' }
  $temporaryPublicKey = (Get-Content -LiteralPath "$temporaryKey.pub" -Raw).Trim()
  Set-KeyLines @($originalLines + $temporaryPublicKey)

  & $sshd -t
  if ($LASTEXITCODE -ne 0) { throw 'sshd_config validation failed' }
  Restart-Service sshd

  $scan = & $sshKeyscan -T 5 -t ed25519 -p 22 127.0.0.1 2>$null
  [IO.File]::WriteAllLines($knownHosts, [string[]]$scan, [Text.UTF8Encoding]::new($false))
  $scannedFingerprint = (& $sshKeygen -lf $knownHosts -E sha256) -join ' '
  if ($scannedFingerprint -notmatch [regex]::Escape($ExpectedHostKeyFingerprint)) {
    throw "Unexpected localhost host key: $scannedFingerprint"
  }

  $testOutput = (& $ssh `
    -o BatchMode=yes `
    -o IdentitiesOnly=yes `
    -o StrictHostKeyChecking=yes `
    -o "UserKnownHostsFile=$knownHosts" `
    -i $temporaryKey `
    -p 22 `
    "$UserName@127.0.0.1" `
    whoami 2>&1) -join "`n"
  $testExitCode = $LASTEXITCODE
  if ($testExitCode -ne 0) { throw "Local SSH authentication failed: $testOutput" }
} finally {
  Stop-Service sshd -Force -ErrorAction SilentlyContinue
  if ($originalCaptured) { Set-KeyLines $originalLines }
  Start-Service sshd -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath $temporaryRoot) {
    $resolvedTemporary = (Resolve-Path -LiteralPath $temporaryRoot).Path
    $resolvedTempParent = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
    if ((Split-Path -Parent $resolvedTemporary) -ne $resolvedTempParent -or
        (Split-Path -Leaf $resolvedTemporary) -notlike 'vibekits-node-ssh-smoke-*') {
      throw "Refusing to remove unexpected temporary path: $resolvedTemporary"
    }
    Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force
  }
}

[pscustomobject]@{
  ok = $testExitCode -eq 0
  user = $UserName
  output = $testOutput
  authorizedKeys = $AuthorizedKeysPath
  temporaryKeyRemoved = -not (Test-Path -LiteralPath $temporaryRoot)
  sshd = (Get-Service sshd).Status.ToString()
} | ConvertTo-Json -Compress
