# Version web de PuitsTrack, utilisable hors ligne.
#   powershell -ExecutionPolicy Bypass -File tool\build_web.ps1
# Résultat : build\web (à publier tel quel, ex: firebase deploy --only hosting)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  flutter build web --release --no-web-resources-cdn
  if ($LASTEXITCODE -ne 0) { throw 'flutter build web a échoué' }
  python tool\gen_offline_sw.py
  if ($LASTEXITCODE -ne 0) { throw 'gen_offline_sw.py a échoué' }
} finally {
  Pop-Location
}
