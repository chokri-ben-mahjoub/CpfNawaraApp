# Mise en ligne de CPF Laboratory NAWARA (projet Firebase "puitstrack") en une
# commande :
#   powershell -ExecutionPolicy Bypass -File tool\deploy.ps1            # règles + site web
#   powershell -ExecutionPolicy Bypass -File tool\deploy.ps1 -Functions # + Cloud Functions (forfait Blaze)
# Prérequis, une seule fois : firebase login (compte Google propriétaire du projet).
# Déploie deux sites : cpflaboratorynawara.web.app (l'app, site principal) et
# puitstrack.web.app (site par défaut du projet, imposé par Firebase et non
# supprimable — ne sert plus qu'une page de redirection, voir web_redirect/).
param([switch]$Functions, [switch]$SkipWebBuild, [string]$Project = 'puitstrack')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$firebase = (Get-Command firebase -ErrorAction SilentlyContinue).Source
if (-not $firebase) { $firebase = "$env:APPDATA\npm\firebase.cmd" }
if (-not (Test-Path $firebase)) { throw 'Firebase CLI introuvable : npm install -g firebase-tools' }

Push-Location $root
try {
  python tool\gen_rules_dart.py
  if (-not $SkipWebBuild) { & "$root\tool\build_web.ps1" }
  $only = 'firestore:rules,hosting'
  if ($Functions) {
    Push-Location "$root\functions"
    npm install --no-audit --no-fund
    Pop-Location
    $only += ',functions'
  }
  & $firebase deploy --only $only --project $Project
  if ($LASTEXITCODE -ne 0) { throw 'firebase deploy a échoué (firebase login fait ?)' }
  Write-Host "`nEn ligne : https://puitstrack.web.app"
  Write-Host "En ligne : https://cpflaboratorynawara.web.app"
} finally {
  Pop-Location
}
