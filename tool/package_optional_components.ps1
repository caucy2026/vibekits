param(
  [Parameter(Mandatory=$true)][string]$BundlePath,
  [Parameter(Mandatory=$true)][string]$OutputPath,
  [Parameter(Mandatory=$true)][ValidateRange(1,2147483647)][int]$VersionCode
)
$ErrorActionPreference='Stop'
$bundle=(Resolve-Path -LiteralPath $BundlePath).Path
if(-not [IO.Path]::IsPathRooted($OutputPath)){throw 'OutputPath must be absolute'}
$hostFile=Join-Path $bundle 'vibekits.exe'
$hostSignature=Get-AuthenticodeSignature -LiteralPath $hostFile
$hostCertificate=[Security.Cryptography.X509Certificates.X509Certificate2]::new([Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile($hostFile))
if($hostSignature.Status -ne 'Valid'){throw 'Sign and verify the host before packaging components'}
$sevenZip=Join-Path $bundle 'tools\7zip\7z.exe'
if(-not (Test-Path -LiteralPath $sevenZip)){throw 'Verified bundle 7zip is required'}
$map=@{virtual_machine='qemu';network_proxy='mihomo'}
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$results=@()
foreach($id in @('virtual_machine','network_proxy')) {
  $runtime=$map[$id]
  $source=Join-Path $bundle "tools\$runtime"
  if(-not (Test-Path -LiteralPath $source)){throw "Prepared component runtime missing: $id"}
  $stage=Join-Path $OutputPath "$id-$VersionCode"
  $zip=Join-Path $OutputPath "Vibekits-$id-windows-x64-$VersionCode.zip"
  if((Test-Path -LiteralPath $stage) -or (Test-Path -LiteralPath $zip)){throw 'Use a fresh output directory; do not overwrite release artifacts'}
  New-Item -ItemType Directory -Path $stage | Out-Null
  Copy-Item -LiteralPath $source -Destination (Join-Path $stage $runtime) -Recurse
  $files=[ordered]@{}
  foreach($file in Get-ChildItem -LiteralPath $stage -File -Recurse | Sort-Object FullName) {
    if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse points are not permitted'}
    if($file.Extension -in @('.exe','.dll')) {
      $sig=Get-AuthenticodeSignature -LiteralPath $file.FullName
      $embedded=[Security.Cryptography.X509Certificates.X509Certificate2]::new([Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile($file.FullName))
      if($sig.Status -ne 'Valid' -or $embedded.Thumbprint -ne $hostCertificate.Thumbprint){throw "Component binary needs the intended publisher signature: $($file.Name)"}
      $stream=[IO.File]::OpenRead($file.FullName)
      try {
        $reader=New-Object IO.BinaryReader($stream)
        if($reader.ReadUInt16() -ne 0x5a4d){throw 'Invalid PE image'}
        $stream.Position=0x3c;$offset=$reader.ReadUInt32();$stream.Position=$offset
        if($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664){throw 'Component must contain Windows x64 binaries'}
      } finally {$stream.Dispose()}
    }
    $relative=$file.FullName.Substring($stage.Length+1).Replace('\','/')
    $files[$relative]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  }
  $manifest=[ordered]@{schema_version=1;host_package_name='com.caucy.vibekits';component_id=$id;standalone=$false;os_type='windows';architecture='x64';version_code=$VersionCode;files=$files}
  [IO.File]::WriteAllText((Join-Path $stage 'component-manifest.json'),($manifest | ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))
  [IO.File]::WriteAllText((Join-Path $stage 'component.json'),(@{component_id=$id;host_package_name='com.caucy.vibekits';version_code=$VersionCode} | ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
  & $sevenZip a -tzip -mx=1 $zip "$stage\*"
  if($LASTEXITCODE -ne 0){throw 'Component ZIP creation failed'}
  & $sevenZip t $zip
  if($LASTEXITCODE -ne 0){throw 'Component ZIP verification failed'}
  $results += [pscustomobject]@{component_id=$id;path=$zip;bytes=(Get-Item $zip).Length;sha256=(Get-FileHash $zip).Hash.ToLowerInvariant()}
}
$results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputPath 'component-packages.json')
