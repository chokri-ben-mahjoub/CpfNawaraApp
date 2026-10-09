import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_providers.dart';
import '../config/shared_config.dart';
import '../data/local_database.dart';
import '../data/wells_repository.dart';
import '../models/user_role.dart';
import '../plant/plant_repository.dart';
import '../team/team_service.dart';
import 'firebase_config.dart';
import 'firebase_config_provider.dart';
import 'firebase_rest.dart';
import 'sync_engine.dart';

const _sessionKey = 'sync_session';
const _lastSyncKey = 'sync_last_success';
const _memberKey = 'sync_member';

/// Délai entre une modification locale et son envoi (regroupe les saisies
/// rapprochées).
const _pushDelay = Duration(seconds: 2);

/// Synchronisation périodique tant que l'app est ouverte (reçoit les saisies
/// faites sur les autres appareils).
const _period = Duration(seconds: 60);

enum SyncPhase { signedOut, idle, syncing, offline, error }

/// Place du compte dans l'équipe (document `users/{uid}`).
enum MemberStatus {
  /// Pas encore vérifié (hors ligne depuis la connexion...).
  unknown,
  active,

  /// Demande d'accès en attente de validation par un administrateur.
  pending,

  /// Désactivé par un administrateur.
  inactive,

  /// Compte sans fiche dans l'équipe (accès à demander).
  missing,
}

class SyncState {
  final SyncPhase phase;
  final String? email;
  final DateTime? lastSyncAt;

  /// Clé de traduction de la dernière erreur (voir `app_strings.dart`).
  final String? errorKey;

  /// Fiche du compte dans l'équipe (rôle, actif), gardée en cache pour
  /// connaître le rôle hors ligne.
  final TeamMember? member;
  final MemberStatus memberStatus;

  const SyncState({
    required this.phase,
    this.email,
    this.lastSyncAt,
    this.errorKey,
    this.member,
    this.memberStatus = MemberStatus.unknown,
  });

  static const signedOut = SyncState(phase: SyncPhase.signedOut);

  bool get isSignedIn => phase != SyncPhase.signedOut;

  SyncState copyWith({
    SyncPhase? phase,
    DateTime? lastSyncAt,
    String? Function()? errorKey,
    TeamMember? Function()? member,
    MemberStatus? memberStatus,
  }) => SyncState(
    phase: phase ?? this.phase,
    email: email,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    errorKey: errorKey != null ? errorKey() : this.errorKey,
    member: member != null ? member() : this.member,
    memberStatus: memberStatus ?? this.memberStatus,
  );
}

MemberStatus memberStatusOf(TeamMember? member) {
  if (member == null) return MemberStatus.missing;
  if (member.active) return MemberStatus.active;
  return member.pending ? MemberStatus.pending : MemberStatus.inactive;
}

class _PrefsSyncStore implements SyncStore {
  @override
  Future<String?> read(String key) async => (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }
}

/// Compte d'équipe (e-mail + mot de passe) et synchronisation automatique :
/// après chaque saisie, toutes les 60 s quand l'app est ouverte, et à chaque
/// retour au premier plan.
///
/// Sans projet Firebase configuré ([config] nul), l'app reste en mode
/// personnel : rien n'est synchronisé.
class SyncController extends StateNotifier<SyncState> {
  SyncController(this._ref, {FirebaseRestConfig? config})
    : config = config,
      team = config == null ? null : TeamService(config),
      _engine = config == null
          ? null
          : SyncEngine(
              openDatabase: () => LocalDatabase.instance.database,
              firestore: FirestoreRest(config),
              config: config,
              store: _PrefsSyncStore(),
            ),
      super(SyncState.signedOut) {
    _ready = _restore();
  }

  final Ref _ref;
  final FirebaseRestConfig? config;
  final TeamService? team;
  final SyncEngine? _engine;
  late final Future<void> _ready;
  AuthSession? _session;
  StreamSubscription<void>? _changes;
  Timer? _debounce;
  Timer? _periodic;
  bool _running = false;
  bool _again = false;

  bool get isConfigured => config != null;

  Future<void> _restore() async {
    if (config == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    final session = raw == null ? null : AuthSession.fromJson(jsonDecode(raw) as Map<String, Object?>);
    if (session == null) return;
    final last = prefs.getString(_lastSyncKey);
    final memberRaw = prefs.getString(_memberKey);
    final member = memberRaw == null
        ? null
        : TeamMember.fromJson(Map<String, Object?>.from(jsonDecode(memberRaw) as Map));
    _session = session;
    state = SyncState(
      phase: SyncPhase.idle,
      email: session.email,
      lastSyncAt: last == null ? null : DateTime.tryParse(last),
      member: member?.uid == session.uid ? member : null,
      memberStatus: member?.uid == session.uid ? memberStatusOf(member) : MemberStatus.unknown,
    );
    _startAutoSync();
  }

  TeamService get _team {
    final t = team;
    if (t == null) throw StateError('Projet Firebase non configuré');
    return t;
  }

  /// Session valide (renouvelée si besoin) du compte connecté.
  Future<AuthSession> freshSession() async {
    await _ready;
    var session = _session;
    if (session == null) throw const SyncAuthException('NOT_SIGNED_IN');
    if (session.needsRefresh) {
      session = await _team.auth.refresh(session);
      await _saveSession(session);
    }
    return session;
  }

  /// Nom affiché du compte (fiche d'équipe, sinon profil local).
  String get _displayName {
    final name = state.member?.name ?? '';
    if (name.isNotEmpty) return name;
    final local = _ref.read(profileProvider)?.fullName ?? '';
    return local.isNotEmpty ? local : (state.email ?? '').split('@').first;
  }

  /// Crée un compte. Premier compte du projet : administrateur ; sinon,
  /// demande d'accès à valider par un administrateur.
  Future<MemberStatus> createAccount(String email, String password, {required String name}) async {
    await _ready;
    final session = await _team.auth.signUp(email, password);
    final setupDone = await _team.isSetupDone(session);
    final member = setupDone
        ? await _team.requestAccess(session, name: name)
        : await _team.bootstrapAdmin(session, name: name);
    await _connected(session, member);
    return memberStatusOf(member);
  }

  /// Connexion à un compte existant. Si le projet n'a encore aucun
  /// administrateur, ce compte le devient.
  Future<MemberStatus> signIn(String email, String password) async {
    await _ready;
    final session = await _team.auth.signIn(email, password);
    var member = await _team.member(session);
    if (member == null && !await _team.isSetupDone(session)) {
      final name = _ref.read(profileProvider)?.fullName ?? '';
      member = await _team.bootstrapAdmin(session, name: name.isEmpty ? email.split('@').first : name);
    }
    await _connected(session, member);
    return memberStatusOf(member);
  }

  /// Compte connu de Firebase mais sans fiche d'équipe : demande d'accès.
  Future<void> requestAccess(String name) async {
    final session = await freshSession();
    final member = await _team.requestAccess(session, name: name);
    await _setMember(member);
  }

  /// Relit la fiche du compte (après validation par l'administrateur...).
  Future<MemberStatus> refreshMember() async {
    final session = await freshSession();
    final member = await _team.member(session);
    await _setMember(member);
    if (member?.active == true) unawaited(syncNow());
    return memberStatusOf(member);
  }

  Future<void> sendPasswordReset(String email) => _team.sendPasswordReset(email);

  Future<void> _connected(AuthSession session, TeamMember? member) async {
    await _saveSession(session);
    state = SyncState(phase: SyncPhase.idle, email: session.email);
    await _setMember(member);
    _startAutoSync();
    if (member?.active == true) {
      await _engine!.prepareFirstSync(session.uid, writable: member!.role.writableTables);
      await syncNow();
    }
  }

  Future<void> _setMember(TeamMember? member) async {
    final prefs = await SharedPreferences.getInstance();
    if (member == null) {
      await prefs.remove(_memberKey);
    } else {
      await prefs.setString(_memberKey, jsonEncode(member.toJson()));
    }
    if (!mounted) return;
    state = state.copyWith(member: () => member, memberStatus: memberStatusOf(member));
  }

  /// Déconnecte le compte sur cet appareil : les données restent sur
  /// l'appareil, elles ne sont simplement plus synchronisées.
  Future<void> signOut() async {
    _stopAutoSync();
    _session = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    await prefs.remove(_lastSyncKey);
    await prefs.remove(_memberKey);
    state = SyncState.signedOut;
  }

  Future<void> _saveSession(AuthSession session) async {
    _session = session;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, jsonEncode(session.toJson()));
  }

  void _startAutoSync() {
    _changes ??= LocalDatabase.instance.changes.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(_pushDelay, syncNow);
    });
    _periodic ??= Timer.periodic(_period, (_) => syncNow());
  }

  void _stopAutoSync() {
    _changes?.cancel();
    _changes = null;
    _debounce?.cancel();
    _periodic?.cancel();
    _periodic = null;
  }

  /// Vérifie la fiche du compte, puis récupère les modifications de
  /// l'équipe et envoie celles de cet appareil que le rôle autorise. Sans
  /// effet si aucun compte n'est connecté.
  Future<void> syncNow() async {
    await _ready;
    if (_session == null || _engine == null) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    state = state.copyWith(phase: SyncPhase.syncing);
    try {
      do {
        _again = false;
        final session = await freshSession();
        var member = await _team.member(session);
        // Installation faite avant la gestion d'équipe : le premier compte
        // connecté devient administrateur.
        if (member == null && !await _team.isSetupDone(session)) {
          member = await _team.bootstrapAdmin(session, name: _displayName);
          await _engine.prepareFirstSync(session.uid, writable: member.role.writableTables);
        }
        await _setMember(member);
        if (member == null || !member.active) {
          final status = memberStatusOf(member);
          state = state.copyWith(
            phase: SyncPhase.error,
            errorKey: () => switch (status) {
              MemberStatus.pending => 'syncErrorPending',
              MemberStatus.inactive => 'syncErrorInactive',
              _ => 'syncErrorNoMember',
            },
          );
          return;
        }
        await _engine.prepareFirstSync(session.uid, writable: member.role.writableTables);
        final report = await _engine.sync(
          session,
          writable: member.role.writableTables,
          actor: _team.actorOf(session, member.name),
        );
        if (report.pulled > 0) {
          await _ref.read(wellsControllerProvider.notifier).reload();
          await _ref.read(plantControllerProvider.notifier).reload();
          await _ref.read(sharedConfigProvider.notifier).reload();
        }
      } while (_again && _session != null);
      final now = DateTime.now();
      (await SharedPreferences.getInstance()).setString(_lastSyncKey, now.toIso8601String());
      if (_session != null && mounted) {
        state = state.copyWith(phase: SyncPhase.idle, lastSyncAt: now, errorKey: () => null);
      }
    } on SyncNetworkException {
      if (mounted) state = state.copyWith(phase: SyncPhase.offline, errorKey: () => 'syncOffline');
    } on SyncAuthException {
      // Jeton de rafraîchissement refusé (mot de passe changé, compte
      // supprimé...) : il faut se reconnecter.
      if (mounted) state = state.copyWith(phase: SyncPhase.error, errorKey: () => 'syncErrorSession');
    } on SyncServerException catch (e) {
      if (mounted) {
        state = state.copyWith(
          phase: SyncPhase.error,
          errorKey: () => e.isDatabaseMissing
              ? 'syncErrorDatabase'
              : e.statusCode == 403
              ? 'syncErrorRules'
              : 'syncErrorServer',
        );
      }
    } catch (_) {
      if (mounted) state = state.copyWith(phase: SyncPhase.error, errorKey: () => 'syncErrorServer');
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    _stopAutoSync();
    super.dispose();
  }
}

final syncControllerProvider = StateNotifierProvider<SyncController, SyncState>((ref) {
  final config = ref.watch(firebaseConfigProvider);
  return SyncController(ref, config: config);
});
