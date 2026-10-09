"""Remplit build/web/offline_sw.js (liste des fichiers à garder hors ligne +
version) après `flutter build web`.

    python tool/gen_offline_sw.py

Appelé par tool/build_web.ps1. La version est une empreinte de tous les
fichiers : chaque nouveau build change offline_sw.js, ce qui fait installer
le nouveau cache par les navigateurs.
"""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
web = root / 'build' / 'web'
sw = web / 'offline_sw.js'
assert sw.exists(), 'Lancez d\'abord : flutter build web --release --no-web-resources-cdn'

# Non mis en cache d'avance : symboles de débogage, moteurs de rendu non
# utilisés par ce build (dart2js + CanvasKit) — la variante de CanvasKit
# réellement chargée par le navigateur est ajoutée au premier lancement.
EXCLUDED_NAMES = {'.last_build_id', 'flutter_service_worker.js', 'offline_sw.js'}


def excluded(rel: str) -> bool:
    name = rel.rsplit('/', 1)[-1]
    return name in EXCLUDED_NAMES or rel.endswith('.symbols') or rel.startswith('canvaskit/')


files = sorted(
    p.relative_to(web).as_posix()
    for p in web.rglob('*')
    if p.is_file() and not excluded(p.relative_to(web).as_posix())
)
digest = hashlib.sha256()
for rel in files + sorted(p.relative_to(web).as_posix() for p in (web / 'canvaskit').rglob('*.wasm')):
    digest.update(rel.encode())
    digest.update(hashlib.sha256((web / rel).read_bytes()).digest())
version = digest.hexdigest()[:16]

# 'index.html' en tête, puis la racine du site (page d'accueil).
precache = ['index.html', './'] + [f for f in files if f != 'index.html']
text = sw.read_text(encoding='utf-8')
assert '/*PRECACHE*/' in text and '__CACHE_VERSION__' in text, 'offline_sw.js déjà rempli ?'
text = text.replace('[/*PRECACHE*/]', json.dumps(precache, indent=2)).replace('__CACHE_VERSION__', version)
sw.write_text(text, encoding='utf-8', newline='\n')
size = sum((web / f).stat().st_size for f in files) / 1024 / 1024
print(f'offline_sw.js : {len(precache)} fichiers ({size:.1f} Mo), version {version}')
