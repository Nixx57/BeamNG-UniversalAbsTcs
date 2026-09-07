$modRoot = $PSScriptRoot
$archivePath = Join-Path (Split-Path $modRoot -Parent) 'universalAbsTcs_v0.1.zip'
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) 'universalAbsTcs_package'

if (Test-Path $archivePath) { Remove-Item $archivePath -Force }
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }

New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
Copy-Item (Join-Path $modRoot 'lua') -Destination $tempDir -Recurse
Copy-Item (Join-Path $modRoot 'ui') -Destination $tempDir -Recurse

Compress-Archive -Path (Join-Path $tempDir '*') -DestinationPath $archivePath -CompressionLevel Optimal -Force
Get-Item $archivePath | Select-Object FullName, Length

Remove-Item $tempDir -Recurse -Force