"""Incrémente la version à chaque build web (appelé par tool/build_web.ps1).

Passe de X.Y.Z+N à X.Y.(Z+1)+(N+1) dans pubspec.yaml, puis reporte le numéro
dans lib/core/app_info.dart (Réglages › À propos) et web/release_notes.json
(fenêtre « Nouvelle version disponible »). Les notes de version restent à
rédiger à la main dans release_notes.json.
"""
import json, re, pathlib

root = pathlib.Path(__file__).resolve().parent.parent

pub = root / 'pubspec.yaml'
text = pub.read_text(encoding='utf-8')
m = re.search(r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)[ \t]*$', text, re.M)
assert m, 'version: introuvable dans pubspec.yaml'
major, minor, patch, build = map(int, m.groups())
version = f'{major}.{minor}.{patch + 1}'
text = text[:m.start()] + f'version: {version}+{build + 1}' + text[m.end():]
pub.write_text(text, encoding='utf-8', newline='')

info = root / 'lib' / 'core' / 'app_info.dart'
t = info.read_text(encoding='utf-8')
t, n = re.subn(r"const appVersion = '[^']*';", f"const appVersion = '{version}';", t)
assert n == 1, 'appVersion introuvable dans app_info.dart'
info.write_text(t, encoding='utf-8', newline='')

notes = root / 'web' / 'release_notes.json'
data = json.loads(notes.read_text(encoding='utf-8'))
data['version'] = version
notes.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

print(f'Version : {version}+{build + 1}')
