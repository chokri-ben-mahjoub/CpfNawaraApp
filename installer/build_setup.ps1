# Génère installer\Output\CPF-Laboratory-NAWARA-Setup-<version>.exe en une commande :
#   powershell -ExecutionPolicy Bypass -File installer\build_setup.ps1
#
# 1. flutter build windows --release
# 2. copie les DLL Visual C++ (msvcp140, vcruntime140, vcruntime140_1) dans
#    le dossier Release : l'app tourne sur un PC neuf sans "VC++ Redistributable"
# 3. compile installer\puitstrack.iss avec Inno Setup 6


$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build windows a échoué" }

$release = Join-Path $root 'build\windows\x64\runner\Release'
$dlls = 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll'

# DLL redistribuables livrées avec Visual Studio (dossier VC\Redist), sinon
# celles du système.
$crt = $null
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $vs = & $vswhere -latest -prerelease -products * -property installationPath
    if ($vs) {
        $crt = Get-ChildItem "$vs\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT" -Directory -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1
    }
}
foreach ($dll in $dlls) {
    $src = if ($crt -and (Test-Path (Join-Path $crt.FullName $dll))) { Join-Path $crt.FullName $dll }
           else { Join-Path "$env:WINDIR\System32" $dll }
    Copy-Item $src $release -Force
    Write-Host "DLL copiée : $src"
}

$version = (Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value

$iscc = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw "Inno Setup 6 introuvable. Installez-le : winget install JRSoftware.InnoSetup" }

& $iscc "/DAppVersion=$version" (Join-Path $PSScriptRoot 'puitstrack.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno Setup a échoué" }

Write-Host "`nInstallateur : $(Join-Path $PSScriptRoot "Output\CPF-Laboratory-NAWARA-Setup-$version.exe")"
