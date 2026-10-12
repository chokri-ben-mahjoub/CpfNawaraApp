import 'dart:math';

import 'package:uuid/uuid.dart';

import '../models/user_role.dart';
import '../sync/firebase_config.dart';
import '../sync/firebase_rest.dart';
import '../sync/firestore_value.dart';

/// Entreprise cliente (`companies/{id}`) : ses membres et ses données sont
/// rangés sous ce document.
class Company {
  final String id;
  final String name;
  final String ownerUid;
  const Company({required this.id, required this.name, required this.ownerUid});

  /// Chemin Firestore des données de l'entreprise.
  String get path => 'companies/$id';

  static Company fromDocument(Map<String, Object?> doc) {
    final f = decodeFields(doc['fields'] as Map<String, Object?>?);
    return Company(
      id: (doc['name'] as String).split('/').last,
      name: '${f['name'] ?? ''}',
      ownerUid: '${f['ownerUid'] ?? ''}',
    );
  }

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'ownerUid': ownerUid};

  static Company? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String) return null;
    return Company(id: id, name: '${json['name'] ?? ''}', ownerUid: '${json['ownerUid'] ?? ''}');
  }
}

/// Membre d'une entreprise : `companies/{cid}/members/{uid}` (email, nom,
/// role, actif).
class TeamMember {
  final String uid;
  final String email;
  final String name;
  final UserRole role;
  final bool active;

  /// Clé de service (laboratoire, production...), facultative.
  final String service;

  /// Ancienne demande d'accès (avant les invitations) ; conservé pour la
  /// lecture des fiches existantes.
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

  /// Champs Firestore modifiables (hors dates, posées par le serveur).
  Map<String, Object?> get fields => {
    'email': email,
    'nom': name,
    'role': role.storageKey,
    'actif': active,
    'service': service,
  };

  Map<String, Object?> toJson() => {'uid': uid, ...fields};

  static TeamMember? fromJson(Map<String, Object?> json) {
    final uid = json['uid'];
    if (uid is! String) return null;
    return fromFields(uid, json);
  }
}

/// Invitation à rejoindre une entreprise : code à usage unique, rôle
/// attribué, e-mail imposé ou non, expiration.
class Invite {
  final String code;
  final String companyId;
  final String companyName;
  final UserRole role;

  /// Vide : n'importe quel e-mail peut utiliser le code.
  final String email;
  final DateTime expiresAt;
  final bool used;
  final String usedBy;

  const Invite({
    required this.code,
    required this.companyId,
    required this.companyName,
    required this.role,
    required this.email,
    required this.expiresAt,
    this.used = false,
    this.usedBy = '',
  });

  bool get expired => DateTime.now().isAfter(expiresAt);

  /// Code affiché (ABCD-EFGH).
  String get displayCode => formatInviteCode(code);

  static Invite fromFields(String code, Map<String, Object?> f) => Invite(
    code: code,
    companyId: '${f['companyId'] ?? ''}',
    companyName: '${f['companyName'] ?? ''}',
    role: UserRoleX.fromStorageKey(f['role'] as String?),
    email: '${f['email'] ?? ''}',
    expiresAt: DateTime.fromMillisecondsSinceEpoch((f['expiresAt'] as num?)?.toInt() ?? 0),
    used: f['used'] == true,
    usedBy: '${f['usedBy'] ?? ''}',
  );
}

const _inviteAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// Code d'invitation affiché par groupes de 4 (ABCD-EFGH).
String formatInviteCode(String code) =>
    code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : code;

/// Code saisi (ou lu dans un QR code) ramené à sa forme enregistrée.
String normalizeInviteCode(String text) {
  final match = RegExp(r'invite[=:]\s*"?([A-Za-z0-9-]+)').firstMatch(text);
  final raw = match?.group(1) ?? text;
  return raw.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
}

bool isValidInviteCode(String code) => RegExp('^[$_inviteAlphabet]{8}\$').hasMatch(code);

/// Entrée du journal d'audit (`companies/{cid}/audit/{id}`).
class AuditEntry {
  final String id;
  final String uid;
  final String email;
  final String name;

  /// `save`, `delete`, `user_create`, `user_update`, `user_remove`,
  /// `invite_create`, `invite_use`, `setup`.
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

/// Écriture d'une entrée du journal d'audit de l'entreprise [scope]
/// (`companies/{cid}`), à ajouter à un `commit`.
Map<String, Object?> auditWrite(
  FirebaseRestConfig config,
  String scope,
  AuditActor actor, {
  required String action,
  required String table,
  required String docId,
  required String label,
  int? changedAt,
}) => {
  'update': {
    'name': config.documentName('$scope/audit/${_uuid.v4()}'),
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

/// Le compte appartient déjà à une entreprise.
class AlreadyInCompanyException implements Exception {
  const AlreadyInCompanyException();
}

/// Code d'invitation inconnu, expiré, déjà utilisé ou réservé à un autre
/// e-mail ([reason] : `unknown`, `expired`, `used`, `email`).
class InviteException implements Exception {
  final String reason;
  const InviteException(this.reason);

  @override
  String toString() => 'InviteException($reason)';
}

/// Gestion des entreprises et de leurs membres, entièrement depuis l'app :
/// création d'une entreprise (son créateur en devient l'administrateur),
/// invitations par code, comptes créés par l'administrateur, rôles,
/// désactivation, journal d'audit.
///
/// Les opérations sur les comptes eux-mêmes (désactiver la connexion,
/// supprimer, changer le mot de passe) passent par les Cloud Functions
/// (Firebase Admin SDK, voir `functions/index.js`) quand elles sont
/// déployées ; sinon l'app se replie sur ce que permettent les règles
/// Firestore (fiche désactivée : plus aucun accès aux données).
class TeamService {
  final FirebaseRestConfig config;
  final FirebaseAuthRest auth;
  final FirestoreRest firestore;
  final FunctionsRest functions;

  TeamService(this.config)
    : auth = FirebaseAuthRest(config),
      firestore = FirestoreRest(config),
      functions = FunctionsRest(config);

  AuditActor actorOf(AuthSession session, String name) =>
      AuditActor(uid: session.uid, email: session.email, name: name);

  Map<String, Object?> _write(
    String path,
    Map<String, Object?> fields, {
    List<String>? mask,
    bool create = false,
    List<String> serverTimes = const [],
  }) => {
    'update': {'name': config.documentName(path), 'fields': encodeFields(fields)},
    'updateMask': ?(mask == null ? null : {'fieldPaths': mask}),
    if (create) 'currentDocument': {'exists': false},
    if (serverTimes.isNotEmpty)
      'updateTransforms': [
        for (final f in serverTimes) {'fieldPath': f, 'setToServerValue': 'REQUEST_TIME'},
      ],
  };

  Map<String, Object?> _delete(String path) => {'delete': config.documentName(path)};

  // ------------------------------------------------------------ Lecture

  /// Entreprise du compte (`accounts/{uid}`), ou `null`.
  Future<String?> companyIdOf(AuthSession session) async {
    final doc = await firestore.getDocument(session.idToken, 'accounts/${session.uid}');
    if (doc == null) return null;
    final id = decodeFields(doc['fields'] as Map<String, Object?>?)['companyId'];
    return id is String && id.isNotEmpty ? id : null;
  }

  Future<Company?> company(AuthSession session, String cid) async {
    final doc = await firestore.getDocument(session.idToken, 'companies/$cid');
    return doc == null ? null : Company.fromDocument(doc);
  }

  Future<TeamMember?> member(AuthSession session, String cid, [String? uid]) async {
    final doc = await firestore.getDocument(session.idToken, 'companies/$cid/members/${uid ?? session.uid}');
    return doc == null ? null : TeamMember.fromDocument(doc);
  }

  /// Teste les règles publiées : `config/rules_v3` n'existe jamais, mais les
  /// règles de PuitsTrack autorisent à le lire (réponse "introuvable") —
  /// d'anciennes règles ou les règles par défaut refusent.
  Future<RulesStatus> probeRules(AuthSession session) async {
    try {
      await firestore.getDocument(session.idToken, 'config/rules_v3');
      return RulesStatus.ok;
    } on SyncServerException catch (e) {
      if (e.isDatabaseMissing) return RulesStatus.databaseMissing;
      if (e.isPermissionDenied) return RulesStatus.notPublished;
      rethrow;
    }
  }

  // --------------------------------------------- Création / adhésion

  /// Crée une entreprise dont le compte devient l'administrateur.
  Future<(Company, TeamMember)> createCompany(
    AuthSession session, {
    required String companyName,
    required String name,
    String service = '',
  }) async {
    if (await companyIdOf(session) != null) throw const AlreadyInCompanyException();
    final cid = _uuid.v4().replaceAll('-', '').substring(0, 20);
    final company = Company(id: cid, name: companyName, ownerUid: session.uid);
    final member = TeamMember(
      uid: session.uid,
      email: session.email,
      name: name,
      role: UserRole.admin,
      active: true,
      service: service,
    );
    await firestore.commit(session.idToken, [
      _write(
        company.path,
        {'name': companyName, 'ownerUid': session.uid},
        create: true,
        serverTimes: ['createdAt', 'updatedAt'],
      ),
      _write('${company.path}/members/${session.uid}', member.fields, create: true, serverTimes: ['createdAt', 'updatedAt']),
      _write('accounts/${session.uid}', {'companyId': cid, 'email': session.email}, create: true),
      auditWrite(
        config,
        company.path,
        actorOf(session, name),
        action: 'setup',
        table: 'users',
        docId: session.uid,
        label: '$companyName · ${session.email}',
      ),
    ]);
    return (company, member);
  }

  /// Aperçu d'un code d'invitation (avant même de créer son compte).
  Future<Invite?> previewInvite(String code) async {
    final normalized = normalizeInviteCode(code);
    if (!isValidInviteCode(normalized)) return null;
    final doc = await firestore.getDocument(null, 'inviteCodes/$normalized');
    if (doc == null) return null;
    return Invite.fromFields(normalized, decodeFields(doc['fields'] as Map<String, Object?>?));
  }

  /// Rejoint l'entreprise de l'invitation [code] avec le rôle qu'elle
  /// attribue.
  Future<(Company, TeamMember)> joinWithInvite(AuthSession session, String code, {required String name}) async {
    final normalized = normalizeInviteCode(code);
    final preview = await previewInvite(normalized);
    if (preview == null) throw const InviteException('unknown');
    if (await companyIdOf(session) != null) throw const AlreadyInCompanyException();
    final cid = preview.companyId;
    final detail = await firestore.getDocument(session.idToken, 'companies/$cid/invites/$normalized');
    if (detail == null) throw const InviteException('unknown');
    final invite = Invite.fromFields(normalized, decodeFields(detail['fields'] as Map<String, Object?>?));
    if (invite.used) throw const InviteException('used');
    if (invite.expired) throw const InviteException('expired');
    if (invite.email.isNotEmpty && invite.email.toLowerCase() != session.email.toLowerCase()) {
      throw const InviteException('email');
    }
    final member = TeamMember(uid: session.uid, email: session.email, name: name, role: invite.role, active: true);
    final scope = 'companies/$cid';
    await firestore.commit(session.idToken, [
      _write('$scope/members/${session.uid}', {
        ...member.fields,
        'invite': normalized,
      }, create: true, serverTimes: ['createdAt', 'updatedAt']),
      _write(
        '$scope/invites/$normalized',
        {'used': true, 'usedBy': session.uid},
        mask: ['used', 'usedBy'],
        serverTimes: ['usedAt'],
      ),
      _write('accounts/${session.uid}', {'companyId': cid, 'email': session.email}, create: true),
      auditWrite(
        config,
        scope,
        actorOf(session, name),
        action: 'invite_use',
        table: 'users',
        docId: session.uid,
        label: '${session.email} · ${invite.role.storageKey} · ${invite.displayCode}',
      ),
    ]);
    return (Company(id: cid, name: preview.companyName, ownerUid: ''), member);
  }

  /// Le membre modifie son propre nom.
  Future<void> renameSelf(AuthSession session, String cid, String name) => firestore.commit(session.idToken, [
    _write('companies/$cid/members/${session.uid}', {'nom': name}, mask: ['nom'], serverTimes: ['updatedAt']),
  ]);

  /// Nouveau nom de l'entreprise (administrateur).
  Future<void> renameCompany(AuthSession admin, Company company, String name) => firestore.commit(admin.idToken, [
    _write(company.path, {'name': name, 'ownerUid': company.ownerUid}, mask: ['name'], serverTimes: ['updatedAt']),
  ]);

  // ---------------------------------------------------------- Membres

  /// Membres de l'entreprise (administrateur), triés par nom.
  Future<List<TeamMember>> listMembers(AuthSession admin, String cid) async {
    final docs = await firestore.runQuery(admin.idToken, 'companies/$cid', {
      'from': [
        {'collectionId': 'members'},
      ],
      'limit': 500,
    });
    return docs.map(TeamMember.fromDocument).toList()..sort(
      (a, b) => (a.name.isEmpty ? a.email : a.name).toLowerCase().compareTo((b.name.isEmpty ? b.email : b.name).toLowerCase()),
    );
  }

  // ------------------------------------------- Cloud Functions (option)

  bool? _functionsOk;
  DateTime? _functionsCheckedAt;

  /// Vrai si les Cloud Functions d'administration sont déployées (vérifié
  /// au plus toutes les 10 minutes).
  Future<bool> functionsAvailable(AuthSession session) async {
    final checked = _functionsCheckedAt;
    if (_functionsOk != null && checked != null && DateTime.now().difference(checked) < const Duration(minutes: 10)) {
      return _functionsOk!;
    }
    try {
      await functions.call(session.idToken, 'ping', const {});
      _functionsOk = true;
    } on FunctionUnavailableException {
      _functionsOk = false;
    } on SyncNetworkException {
      _functionsOk = false;
    } on FunctionCallException {
      _functionsOk = true;
    }
    _functionsCheckedAt = DateTime.now();
    return _functionsOk!;
  }

  /// Crée un compte (e-mail + mot de passe provisoire) et l'ajoute à
  /// l'entreprise, sans déconnecter l'administrateur.
  Future<TeamMember> createMember(
    AuthSession admin,
    String cid, {
    required String adminName,
    required String email,
    required String password,
    required String name,
    required UserRole role,
    String service = '',
  }) async {
    if (await functionsAvailable(admin)) {
      final result = await functions.call(admin.idToken, 'createMember', {
        'companyId': cid,
        'email': email,
        'password': password,
        'name': name,
        'role': role.storageKey,
        'service': service,
      });
      final uid = (result as Map)['uid'] as String;
      return TeamMember(uid: uid, email: email.toLowerCase(), name: name, role: role, active: true, service: service);
    }
    // Sans serveur : inscription REST dont la session n'est jamais utilisée.
    final created = await FirebaseAuthRest(config).signUp(email, password);
    final member = TeamMember(
      uid: created.uid,
      email: created.email,
      name: name,
      role: role,
      active: true,
      service: service,
    );
    final scope = 'companies/$cid';
    await firestore.commit(admin.idToken, [
      _write('$scope/members/${member.uid}', member.fields, create: true, serverTimes: ['createdAt', 'updatedAt']),
      _write('accounts/${member.uid}', {'companyId': cid, 'email': member.email}, create: true),
      auditWrite(
        config,
        scope,
        actorOf(admin, adminName),
        action: 'user_create',
        table: 'users',
        docId: member.uid,
        label: '${member.email} · ${role.storageKey}',
      ),
    ]);
    return member;
  }

  /// Modifie un membre (nom, rôle, service, actif). Avec les Cloud
  /// Functions, la désactivation bloque aussi la connexion du compte.
  Future<void> updateMember(
    AuthSession admin,
    String cid, {
    required String adminName,
    required TeamMember member,
    bool? previousActive,
  }) async {
    final scope = 'companies/$cid';
    await firestore.commit(admin.idToken, [
      _write('$scope/members/${member.uid}', member.fields, mask: member.fields.keys.toList(), serverTimes: ['updatedAt']),
      auditWrite(
        config,
        scope,
        actorOf(admin, adminName),
        action: 'user_update',
        table: 'users',
        docId: member.uid,
        label: '${member.email} · ${member.role.storageKey} · ${member.active ? 'actif' : 'inactif'}',
      ),
    ]);
    if (previousActive != null && previousActive != member.active && await functionsAvailable(admin)) {
      await functions.call(admin.idToken, 'setMemberActive', {
        'companyId': cid,
        'uid': member.uid,
        'active': member.active,
      });
    }
  }

  /// Retire un membre de l'entreprise. Avec les Cloud Functions, son compte
  /// est supprimé ; sinon il n'a simplement plus accès à rien.
  Future<void> removeMember(AuthSession admin, String cid, {required String adminName, required TeamMember member}) async {
    if (await functionsAvailable(admin)) {
      await functions.call(admin.idToken, 'deleteMember', {'companyId': cid, 'uid': member.uid});
      return;
    }
    final scope = 'companies/$cid';
    await firestore.commit(admin.idToken, [
      _delete('$scope/members/${member.uid}'),
      _delete('accounts/${member.uid}'),
      auditWrite(
        config,
        scope,
        actorOf(admin, adminName),
        action: 'user_remove',
        table: 'users',
        docId: member.uid,
        label: member.email,
      ),
    ]);
  }

  /// Nouveau mot de passe choisi par l'administrateur (Cloud Functions
  /// seulement, sinon [FunctionUnavailableException]).
  Future<void> setMemberPassword(AuthSession admin, String cid, {required String uid, required String password}) async {
    if (!await functionsAvailable(admin)) throw const FunctionUnavailableException();
    await functions.call(admin.idToken, 'setMemberPassword', {'companyId': cid, 'uid': uid, 'password': password});
  }

  /// E-mail de réinitialisation du mot de passe (envoyé par Firebase).
  Future<void> sendPasswordReset(String email) => auth.sendPasswordReset(email);

  // ------------------------------------------------------ Invitations

  /// Nouveau code d'invitation (7 jours, usage unique).
  Future<Invite> createInvite(
    AuthSession admin,
    Company company, {
    required String adminName,
    required UserRole role,
    String email = '',
    Duration validity = const Duration(days: 7),
  }) async {
    final random = Random.secure();
    final code = List.generate(8, (_) => _inviteAlphabet[random.nextInt(_inviteAlphabet.length)]).join();
    final invite = Invite(
      code: code,
      companyId: company.id,
      companyName: company.name,
      role: role,
      email: email.trim().toLowerCase(),
      expiresAt: DateTime.now().add(validity),
    );
    final fields = {
      'companyId': company.id,
      'companyName': company.name,
      'role': role.storageKey,
      'email': invite.email,
      'expiresAt': invite.expiresAt.millisecondsSinceEpoch,
    };
    await firestore.commit(admin.idToken, [
      _write('${company.path}/invites/$code', {
        ...fields,
        'used': false,
        'usedBy': '',
        'createdBy': admin.uid,
      }, create: true, serverTimes: ['createdAt']),
      _write('inviteCodes/$code', fields, create: true),
      auditWrite(
        config,
        company.path,
        actorOf(admin, adminName),
        action: 'invite_create',
        table: 'users',
        docId: code,
        label: '${invite.displayCode} · ${role.storageKey}${invite.email.isEmpty ? '' : ' · ${invite.email}'}',
      ),
    ]);
    return invite;
  }

  Future<List<Invite>> listInvites(AuthSession admin, String cid) async {
    final docs = await firestore.runQuery(admin.idToken, 'companies/$cid', {
      'from': [
        {'collectionId': 'invites'},
      ],
      'limit': 200,
    });
    return [
      for (final doc in docs)
        Invite.fromFields((doc['name'] as String).split('/').last, decodeFields(doc['fields'] as Map<String, Object?>?)),
    ]..sort((a, b) => b.expiresAt.compareTo(a.expiresAt));
  }

  Future<void> deleteInvite(AuthSession admin, String cid, String code) => firestore.commit(admin.idToken, [
    _delete('companies/$cid/invites/$code'),
    _delete('inviteCodes/$code'),
  ]);

  // ------------------------------------------------------------ Audit

  /// Dernières entrées du journal d'audit (administrateur).
  Future<List<AuditEntry>> audit(AuthSession admin, String cid, {int limit = 300}) async {
    final docs = await firestore.runQuery(admin.idToken, 'companies/$cid', {
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
}
