import 'package:uuid/uuid.dart';

import '../models/user_role.dart';
import '../sync/firebase_config.dart';
import '../sync/firebase_rest.dart';
import '../sync/firestore_value.dart';

/// Membre de l'équipe : document `users/{uid}` (email, nom, role, actif).
class TeamMember {
  final String uid;
  final String email;
  final String name;
  final UserRole role;
  final bool active;

  /// Clé de service (laboratoire, production...), facultative.
  final String service;

  /// Demande d'accès en attente (compte créé depuis l'app, pas encore validé
  /// par un administrateur).
  final bool pending;
  final DateTime? createdAt;

  const TeamMember({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    required this.active,
    this.service = '',
    this.pending = false,
    this.createdAt,
  });

  TeamMember copyWith({String? name, UserRole? role, bool? active, String? service, bool? pending}) => TeamMember(
    uid: uid,
    email: email,
    name: name ?? this.name,
    role: role ?? this.role,
    active: active ?? this.active,
    service: service ?? this.service,
    pending: pending ?? this.pending,
    createdAt: createdAt,
  );

  static TeamMember fromDocument(Map<String, Object?> doc) {
    final uid = (doc['name'] as String).split('/').last;
    return fromFields(uid, decodeFields(doc['fields'] as Map<String, Object?>?));
  }

  static TeamMember fromFields(String uid, Map<String, Object?> f) => TeamMember(
    uid: uid,
    email: '${f['email'] ?? ''}',
    name: '${f['nom'] ?? ''}',
    role: UserRoleX.fromStorageKey(f['role'] as String?),
    active: f['actif'] == true,
    service: '${f['service'] ?? ''}',
    pending: f['demande'] == true,
    createdAt: DateTime.tryParse('${f['createdAt'] ?? ''}')?.toLocal(),
  );

  /// Champs Firestore (hors dates, posées par le serveur).
  Map<String, Object?> get fields => {
    'email': email,
    'nom': name,
    'role': role.storageKey,
    'actif': active,
    'service': service,
    'demande': pending,
  };

  Map<String, Object?> toJson() => {'uid': uid, ...fields};

  static TeamMember? fromJson(Map<String, Object?> json) {
    final uid = json['uid'];
    if (uid is! String) return null;
    return fromFields(uid, json);
  }
}

/// Entrée du journal d'audit (`audit/{id}`) : qui a modifié quoi et quand.
class AuditEntry {
  final String id;
  final String uid;
  final String email;
  final String name;

  /// `save`, `delete`, `user_create`, `user_update`, `setup`.
  final String action;

  /// Table (ex: `wells`) ou `users`.
  final String table;
  final String docId;

  /// Description lisible (ex: "PN-01 · BSW = 0.8 %").
  final String label;

  /// Heure du serveur à l'enregistrement.
  final DateTime at;

  const AuditEntry({
    required this.id,
    required this.uid,
    required this.email,
    required this.name,
    required this.action,
    required this.table,
    required this.docId,
    required this.label,
    required this.at,
  });

  static AuditEntry fromDocument(Map<String, Object?> doc) {
    final f = decodeFields(doc['fields'] as Map<String, Object?>?);
    final changedAt = (f['changedAt'] as num?)?.toInt();
    return AuditEntry(
      id: (doc['name'] as String).split('/').last,
      uid: '${f['uid'] ?? ''}',
      email: '${f['email'] ?? ''}',
      name: '${f['nom'] ?? ''}',
      action: '${f['action'] ?? ''}',
      table: '${f['table'] ?? ''}',
      docId: '${f['docId'] ?? ''}',
      label: '${f['label'] ?? ''}',
      at:
          DateTime.tryParse('${f['at'] ?? ''}')?.toLocal() ??
          (changedAt == null ? DateTime.fromMillisecondsSinceEpoch(0) : DateTime.fromMillisecondsSinceEpoch(changedAt)),
    );
  }
}

/// Auteur des modifications (pour le journal d'audit).
class AuditActor {
  final String uid;
  final String email;
  final String name;
  const AuditActor({required this.uid, required this.email, required this.name});
}

const _uuid = Uuid();

/// Écriture d'une entrée du journal d'audit, à ajouter à un `commit`.
Map<String, Object?> auditWrite(
  FirebaseRestConfig config,
  AuditActor actor, {
  required String action,
  required String table,
  required String docId,
  required String label,
  int? changedAt,
}) => {
  'update': {
    'name': config.documentName('audit/${_uuid.v4()}'),
    'fields': encodeFields({
      'uid': actor.uid,
      'email': actor.email,
      'nom': actor.name,
      'action': action,
      'table': table,
      'docId': docId,
      'label': label,
      'changedAt': changedAt ?? DateTime.now().millisecondsSinceEpoch,
    }),
  },
  'currentDocument': {'exists': false},
  'updateTransforms': [
    {'fieldPath': 'at', 'setToServerValue': 'REQUEST_TIME'},
  ],
};

/// État des règles de sécurité Firestore, testé depuis l'app.
enum RulesStatus { ok, notPublished, databaseMissing }

/// Gestion de l'équipe par les API REST : premier administrateur,
/// demandes d'accès, comptes créés par l'administrateur (sans le
/// déconnecter), rôles, désactivation, journal d'audit.
class TeamService {
  final FirebaseRestConfig config;
  final FirebaseAuthRest auth;
  final FirestoreRest firestore;

  TeamService(this.config) : auth = FirebaseAuthRest(config), firestore = FirestoreRest(config);

  AuditActor actorOf(AuthSession session, String name) =>
      AuditActor(uid: session.uid, email: session.email, name: name);

  Future<TeamMember?> member(AuthSession session, [String? uid]) async {
    final doc = await firestore.getDocument(session.idToken, 'users/${uid ?? session.uid}');
    return doc == null ? null : TeamMember.fromDocument(doc);
  }

  /// Vrai si un administrateur a déjà été créé dans ce projet.
  Future<bool> isSetupDone(AuthSession session) async =>
      await firestore.getDocument(session.idToken, 'config/setup') != null;

  /// Teste les règles publiées : le document `config/rules_v2` n'existe
  /// jamais, mais les règles de PuitsTrack autorisent à le lire (réponse
  /// "introuvable") — d'anciennes règles ou les règles par défaut refusent.
  Future<RulesStatus> probeRules(AuthSession session) async {
    try {
      await firestore.getDocument(session.idToken, 'config/rules_v2');
      return RulesStatus.ok;
    } on SyncServerException catch (e) {
      if (e.isDatabaseMissing) return RulesStatus.databaseMissing;
      if (e.isPermissionDenied) return RulesStatus.notPublished;
      rethrow;
    }
  }

  /// Premier compte du projet : devient administrateur (une seule fois,
  /// garanti par les règles et la précondition sur `config/setup`).
  Future<TeamMember> bootstrapAdmin(AuthSession session, {required String name, String service = ''}) async {
    final member = TeamMember(
      uid: session.uid,
      email: session.email,
      name: name,
      role: UserRole.admin,
      active: true,
      service: service,
    );
    await firestore.commit(session.idToken, [
      {
        'update': {
          'name': config.documentName('config/setup'),
          'fields': encodeFields({'ownerUid': session.uid, 'ownerEmail': session.email}),
        },
        'currentDocument': {'exists': false},
        'updateTransforms': [
          {'fieldPath': 'createdAt', 'setToServerValue': 'REQUEST_TIME'},
        ],
      },
      _memberWrite(member, created: true),
      auditWrite(
        config,
        actorOf(session, name),
        action: 'setup',
        table: 'users',
        docId: session.uid,
        label: '${member.email} · ${member.role.storageKey}',
      ),
    ]);
    return member;
  }

  /// Compte créé depuis l'app alors qu'un administrateur existe déjà :
  /// demande d'accès (lecteur inactif) à valider par l'administrateur.
  Future<TeamMember> requestAccess(AuthSession session, {required String name}) async {
    final member = TeamMember(
      uid: session.uid,
      email: session.email,
      name: name,
      role: UserRole.reader,
      active: false,
      pending: true,
    );
    await firestore.commit(session.idToken, [_memberWrite(member, created: true)]);
    return member;
  }

  /// Le membre modifie son propre nom.
  Future<void> renameSelf(AuthSession session, String name) => firestore.commit(session.idToken, [
    {
      'update': {
        'name': config.documentName('users/${session.uid}'),
        'fields': encodeFields({'nom': name}),
      },
      'updateMask': {
        'fieldPaths': ['nom'],
      },
      'updateTransforms': [
        {'fieldPath': 'updatedAt', 'setToServerValue': 'REQUEST_TIME'},
      ],
    },
  ]);

  /// Liste des membres (administrateur), triés par nom.
  Future<List<TeamMember>> listMembers(AuthSession admin) async {
    final docs = await firestore.runQuery(admin.idToken, '', {
      'from': [
        {'collectionId': 'users'},
      ],
      'limit': 500,
    });
    return docs.map(TeamMember.fromDocument).toList()..sort(
      (a, b) => (a.name.isEmpty ? a.email : a.name).toLowerCase().compareTo(
        (b.name.isEmpty ? b.email : b.name).toLowerCase(),
      ),
    );
  }

  /// Crée un compte (e-mail + mot de passe provisoire) sans déconnecter
  /// l'administrateur : la session du nouveau compte, renvoyée par
  /// l'inscription, n'est jamais utilisée ni enregistrée.
  Future<TeamMember> createMember(
    AuthSession admin, {
    required String adminName,
    required String email,
    required String password,
    required String name,
    required UserRole role,
    String service = '',
  }) async {
    final created = await FirebaseAuthRest(config).signUp(email, password);
    final member = TeamMember(
      uid: created.uid,
      email: created.email,
      name: name,
      role: role,
      active: true,
      service: service,
    );
    await firestore.commit(admin.idToken, [
      _memberWrite(member, created: true),
      auditWrite(
        config,
        actorOf(admin, adminName),
        action: 'user_create',
        table: 'users',
        docId: member.uid,
        label: '${member.email} · ${role.storageKey}',
      ),
    ]);
    return member;
  }

  /// Modifie un membre (nom, rôle, service, actif) — administrateur.
  Future<void> updateMember(AuthSession admin, {required String adminName, required TeamMember member}) =>
      firestore.commit(admin.idToken, [
        {
          'update': {'name': config.documentName('users/${member.uid}'), 'fields': encodeFields(member.fields)},
          'updateMask': {'fieldPaths': member.fields.keys.toList()},
          'updateTransforms': [
            {'fieldPath': 'updatedAt', 'setToServerValue': 'REQUEST_TIME'},
          ],
        },
        auditWrite(
          config,
          actorOf(admin, adminName),
          action: 'user_update',
          table: 'users',
          docId: member.uid,
          label: '${member.email} · ${member.role.storageKey} · ${member.active ? 'actif' : 'inactif'}',
        ),
      ]);

  /// E-mail de réinitialisation du mot de passe (envoyé par Firebase).
  Future<void> sendPasswordReset(String email) => auth.sendPasswordReset(email);

  /// Dernières entrées du journal d'audit (administrateur).
  Future<List<AuditEntry>> audit(AuthSession admin, {int limit = 300}) async {
    final docs = await firestore.runQuery(admin.idToken, '', {
      'from': [
        {'collectionId': 'audit'},
      ],
      'orderBy': [
        {
          'field': {'fieldPath': 'at'},
          'direction': 'DESCENDING',
        },
      ],
      'limit': limit,
    });
    return docs.map(AuditEntry.fromDocument).toList();
  }

  Map<String, Object?> _memberWrite(TeamMember member, {required bool created}) => {
    'update': {'name': config.documentName('users/${member.uid}'), 'fields': encodeFields(member.fields)},
    if (created) 'currentDocument': {'exists': false},
    'updateTransforms': [
      if (created) {'fieldPath': 'createdAt', 'setToServerValue': 'REQUEST_TIME'},
      {'fieldPath': 'updatedAt', 'setToServerValue': 'REQUEST_TIME'},
    ],
  };
}
