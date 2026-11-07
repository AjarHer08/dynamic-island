# Membuat installer .exe. Jalankan di Windows (Flutter + Visual Studio C++ + Inno Setup 6):
#   powershell -ExecutionPolicy Bypass -File scripts\build_windows.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$v = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value -split '\+')[0]
flutter build windows --release
$iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) { $iscc = 'iscc' }
& $iscc "/DAppVersion=$v" installer\dynamic_island.iss
Write-Host "Selesai: dist\dynamic-island-$v-setup.exe"
