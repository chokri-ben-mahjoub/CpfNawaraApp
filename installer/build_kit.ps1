# Kit d'installation PuitsTrack pour un client (à copier sur une clé USB).
# Chaque client crée son entreprise depuis l'app (données séparées dans le
# projet PuitsTrack) : aucune configuration Firebase de son côté.
#   powershell -ExecutionPolicy Bypass -File installer\build_kit.ps1
# Compile l'APK, le Setup Windows et la version web, puis assemble
# dist\PuitsTrack-<version>\ et dist\PuitsTrack-Kit-<version>.zip.
# -SkipBuild : réutilise les derniers builds.
param([switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $SkipBuild) {
  Push-Location $root
  try {
    flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw 'flutter build apk a échoué' }
    & "$root\installer\build_setup.ps1"
    & "$root\tool\build_web.ps1"
  } finally {
    Pop-Location
  }
}
$version = ((Get-Content "$root\pubspec.yaml" | Select-String '^version:').ToString() -replace 'version:\s*', '' -replace '\+.*', '').Trim()
$kit = "$root\dist\PuitsTrack-$version"
$zip = "$root\dist\PuitsTrack-Kit-$version.zip"

$apk = "$root\build\app\outputs\flutter-apk\app-release.apk"
$setup = "$root\installer\Output\PuitsTrack-Setup-$version.exe"
$web = "$root\build\web"
foreach ($f in @($apk, $setup, "$web\index.html", "$web\offline_sw.js")) {
  if (-not (Test-Path $f)) { throw "Fichier manquant : $f (lancez d'abord les builds)" }
}
if ((Get-Content "$web\offline_sw.js" -Raw) -match '__CACHE_VERSION__') {
  throw 'Version web sans mode hors ligne : lancez tool\build_web.ps1'
}

if (Test-Path $kit) { Remove-Item -Recurse -Force $kit }
New-Item -ItemType Directory -Force "$kit\Android", "$kit\Windows", "$kit\Web" | Out-Null
Copy-Item $apk "$kit\Android\PuitsTrack.apk"
Copy-Item $setup "$kit\Windows\PuitsTrack-Setup.exe"
Compress-Archive -Path "$web\*" -DestinationPath "$kit\Web\PuitsTrack-web.zip"
(Get-Content "$root\installer\kit\LISEZ-MOI.html" -Raw -Encoding UTF8) -replace '__VERSION__', "v$version" |
  Set-Content "$kit\LISEZ-MOI.html" -Encoding UTF8

if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path "$kit\*" -DestinationPath $zip
Write-Host ("Kit : {0}" -f $kit)
Write-Host ("Zip : {0} ({1:N1} Mo)" -f $zip, ((Get-Item $zip).Length / 1MB))
