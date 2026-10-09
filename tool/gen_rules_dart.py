"""Recopie firestore.rules dans lib/core/team/firestore_rules.dart (texte
copiable depuis l'app : Administration > Projet Firebase).

    python tool/gen_rules_dart.py
"""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
rules = (root / 'firestore.rules').read_text(encoding='utf-8')
assert '"""' not in rules
dart = (
    '// Généré par tool/gen_rules_dart.py à partir de firestore.rules — ne pas\n'
    '// modifier à la main (test/admin_test.dart vérifie que les deux sont\n'
    '// identiques).\n\n'
    '/// Règles de sécurité Firestore à publier dans la console Firebase.\n'
    'const firestoreRules = r"""' + rules + '""";\n'
)
(root / 'lib' / 'core' / 'team' / 'firestore_rules.dart').write_text(dart, encoding='utf-8', newline='\n')
print('ok')
