import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_providers.dart';
import '../backup/backup_service.dart';
import '../config/shared_config.dart';
import '../data/local_database.dart';
import '../data/wells_repository.dart';
import '../export/download_saver.dart';
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
const _companyKey = 'sync_company';

/// Entreprise dont les données sont sur cet appareil (projet/entreprise) :
/// changer d'entreprise efface d'abord les données locales.
const _deviceCompanyKey = 'device_company';

/// Délai entre une modification locale et son envoi (regroupe les saisies
/// rapprochées).
const _pushDelay = Duration(seconds: 2);

/// Synchronisation périodique tant que l'app est ouverte (reçoit les saisies
/// faites sur les autres appareils ; une seule lecture quand rien n'a changé).
const _period = Duration(seconds: 60);

/// Relecture de la fiche du membre (rôle, actif) au plus tous les…
const _memberRefresh = Duration(minutes: 5);

enum SyncPhase { signedOut, idle, syncing, offline, error }

/// Place du compte dans son entreprise.
enum MemberStatus {
  /// Pas encore vérifié (hors ligne depuis la connexion...).
  unknown,
  active,

  /// Ancienne demande d'accès en attente (avant les invitations).
  pending,

  /// Désactivé par un administrateur.
  inactive,

  /// Retiré de l'entreprise.
  missing,

  /// Compte connecté qui n'appartient à aucune entreprise : en créer une ou
  /// en rejoindre une avec un code d'invitation.
  noCompany,
}

class SyncState {
  final SyncPhase phase;
  final String? email;
  final DateTime? lastSyncAt;

  /// Clé de traduction de la dernière erreur (voir `app_strings.dart`).
  final String? errorKey;

  /// Entreprise et fiche du compte, gardées en cache pour fonctionner hors
  /// ligne.
  final Company? company;
  final TeamMember? member;
  final MemberStatus memberStatus;

  const SyncState({
    required this.phase,
    this.email,
    this.lastSyncAt,
    this.errorKey,
    this.company,
    this.member,
    this.memberStatus = MemberStatus.unknown,
  });

  static const signedOut = SyncState(phase: SyncPhase.signedOut);

  bool get isSignedIn => phase != SyncPhase.signedOut;

  SyncState copyWith({
    SyncPhase? phase,
    DateTime? lastSyncAt,
    String? Function()? errorKey,
    Company? Function()? company,
    TeamMember? Function()? member,
    MemberStatus? memberStatus,
  }) => SyncState(
    phase: phase ?? this.phase,
    email: email,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    errorKey: errorKey != null ? errorKey() : this.errorKey,
    company: company != null ? company() : this.company,
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

/// Compte (e-mail + mot de passe) dans une entreprise et synchronisation
/// automatique : après chaque saisie, toutes les 60 s quand l'app est
/// ouverte, et à chaque retour au premier plan.
///
/// Sans projet Firebase ([config] nul), l'app reste en mode personnel.
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
  DateTime? _memberCheckedAt;

  bool get isConfigured => config != null;

  Future<void> _restore() async {
    if (config == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    final session = raw == null ? null : AuthSession.fromJson(jsonDecode(raw) as Map<String, Object?>);
    if (session == null) return;
    final last = prefs.getString(_lastSyncKey);
    final memberRaw = prefs.getString(_memberKey);
    final companyRaw = prefs.getString(_companyKey);
    final member = memberRaw == null
        ? null
        : TeamMember.fromJson(Map<String, Object?>.from(jsonDecode(memberRaw) as Map));
    final company = companyRaw == null
        ? null
        : Company.fromJson(Map<String, Object?>.from(jsonDecode(companyRaw) as Map));
    _session = session;
    final known = member?.uid == session.uid && company != null;
    state = SyncState(
      phase: SyncPhase.idle,
      email: session.email,
      lastSyncAt: last == null ? null : DateTime.tryParse(last),
      company: known ? company : null,
      member: known ? member : null,
      memberStatus: known ? memberStatusOf(member) : MemberStatus.unknown,
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

  /// Nom affiché du compte (fiche de l'entreprise, sinon profil local).
  String get displayName {
    final name = state.member?.name ?? '';
    if (name.isNotEmpty) return name;
    final local = _ref.read(profileProvider)?.fullName ?? '';
    return local.isNotEmpty ? local : (state.email ?? '').split('@').first;
  }

  // ------------------------------------------------- Compte / entreprise

  /// Ouvre la session : compte existant ([createAccount] faux) ou nouveau.
  Future<AuthSession> _login(String email, String password, {required bool createAccount}) async {
    await _ready;
    // Nouvel essai après un échec (code d'invitation refusé...) : le compte
    // est déjà créé et connecté.
    final current = _session;
    if (current != null && current.email.toLowerCase() == email.trim().toLowerCase()) return freshSession();
    final session = createAccount ? await _team.auth.signUp(email, password) : await _team.auth.signIn(email, password);
    await _saveSession(session);
    state = SyncState(phase: SyncPhase.idle, email: session.email);
    return session;
  }

  /// Nouveau client : crée le compte (ou utilise un compte existant) et son
  /// entreprise, dont il devient l'administrateur.
  Future<MemberStatus> createCompany({
    required String email,
    required String password,
    required String companyName,
    required String name,
    bool existingAccount = false,
  }) async {
    final session = await _login(email, password, createAccount: !existingAccount);
    final (company, member) = await _team.createCompany(session, companyName: companyName, name: name);
    await _connected(session, company, member);
    return MemberStatus.active;
  }

  /// Compte déjà connecté (sans entreprise) : crée son entreprise.
  Future<MemberStatus> createCompanyForCurrent({required String companyName, required String name}) async {
    final session = await freshSession();
    final (company, member) = await _team.createCompany(session, companyName: companyName, name: name);
    await _connected(session, company, member);
    return MemberStatus.active;
  }

  /// Rejoint une entreprise avec un code d'invitation (nouveau compte ou
  /// compte existant).
  Future<MemberStatus> joinCompany({
    required String code,
    required String email,
    required String password,
    required String name,
    bool existingAccount = false,
  }) async {
    final session = await _login(email, password, createAccount: !existingAccount);
    final (company, member) = await _team.joinWithInvite(session, code, name: name);
    await _connected(session, company, member);
    return MemberStatus.active;
  }

  /// Compte déjà connecté (sans entreprise) : rejoint une entreprise.
  Future<MemberStatus> joinCompanyForCurrent({required String code, required String name}) async {
    final session = await freshSession();
    final (company, member) = await _team.joinWithInvite(session, code, name: name);
    await _connected(session, company, member);
    return MemberStatus.active;
  }

  /// Connexion à un compte existant ; son entreprise est retrouvée
  /// automatiquement.
  Future<MemberStatus> signIn(String email, String password) async {
    final session = await _login(email, password, createAccount: false);
    final cid = await _team.companyIdOf(session);
    if (cid == null) {
      await _setCompany(null, null, MemberStatus.noCompany);
      _startAutoSync();
      return MemberStatus.noCompany;
    }
    final company = await _team.company(session, cid);
    final member = await _team.member(session, cid);
    await _connected(session, company, member);
    return memberStatusOf(member);
  }

  /// Relit la fiche du compte (après une réactivation par l'admin...).
  Future<MemberStatus> refreshMember() async {
    final session = await freshSession();
    final status = await _refreshMembership(session, force: true);
    if (status == MemberStatus.active) unawaited(syncNow());
    return status;
  }

  Future<void> sendPasswordReset(String email) => _team.sendPasswordReset(email);

  /// Après connexion à une entreprise : données de l'appareil prêtes, puis
  /// première synchronisation.
  Future<void> _connected(AuthSession session, Company? company, TeamMember? member) async {
    await _setCompany(company, member, company == null ? MemberStatus.noCompany : memberStatusOf(member));
    _memberCheckedAt = DateTime.now();
    _startAutoSync();
    if (company != null && member?.active == true) {
      await _bindDevice(company);
      await _engine!.prepareFirstSync(company.path, session.uid, writable: member!.role.writableTables);
      await syncNow();
    }
  }

  /// Un appareil ne garde les données que d'une seule entreprise : s'il en
  /// change, ses données locales sont sauvegardées puis effacées avant la
  /// synchronisation (elles ne partent jamais dans l'autre entreprise).
  Future<void> _bindDevice(Company company) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${config!.projectId}/${company.id}';
    final bound = prefs.getString(_deviceCompanyKey);
    if (bound != null && bound != key) {
      if (DownloadSaver.supportsAutoBackup) {
        try {
          await DownloadSaver.save(
            fileName: 'puitstrack_avant_changement_entreprise.json',
            mimeType: backupMimeType,
            bytes: await BackupService.encode(),
            subFolder: backupFolder,
            overwrite: true,
            requestPermission: false,
          );
        } catch (_) {}
      }
      await LocalDatabase.instance.resetToSeed();
      await _reloadData();
    }
    await prefs.setString(_deviceCompanyKey, key);
  }

  Future<void> _setCompany(Company? company, TeamMember? member, MemberStatus status) async {
    final prefs = await SharedPreferences.getInstance();
    if (member == null) {
      await prefs.remove(_memberKey);
    } else {
      await prefs.setString(_memberKey, jsonEncode(member.toJson()));
    }
    if (company == null) {
      await prefs.remove(_companyKey);
    } else {
      await prefs.setString(_companyKey, jsonEncode(company.toJson()));
    }
    if (!mounted) return;
    state = state.copyWith(company: () => company, member: () => member, memberStatus: status);
  }

  /// Relit l'entreprise et la fiche du compte (au plus toutes les 5 minutes
  /// sauf [force]).
  Future<MemberStatus> _refreshMembership(AuthSession session, {bool force = false}) async {
    final checked = _memberCheckedAt;
    if (!force && checked != null && state.company != null && DateTime.now().difference(checked) < _memberRefresh) {
      return state.memberStatus;
    }
    final cid = state.company?.id ?? await _team.companyIdOf(session);
    if (cid == null) {
      await _setCompany(null, null, MemberStatus.noCompany);
      _memberCheckedAt = DateTime.now();
      return MemberStatus.noCompany;
    }
    final member = await _team.member(session, cid);
    final company = member == null ? state.company : (await _team.company(session, cid)) ?? state.company;
    final status = memberStatusOf(member);
    await _setCompany(company ?? Company(id: cid, name: '', ownerUid: ''), member, status);
    _memberCheckedAt = DateTime.now();
    if (status == MemberStatus.active && company != null) await _bindDevice(company);
    if (status == MemberStatus.active) unawaited(syncProfilePhoto());
    return status;
  }

  /// Photo de profil partagée entre les appareils du compte : celle de la
  /// fiche de membre si elle est plus récente que celle de l'appareil, sinon
  /// celle de l'appareil est envoyée. Sans réseau, nouvel essai à la
  /// prochaine relecture de la fiche.
  Future<void> syncProfilePhoto() async {
    final member = state.member;
    final cid = state.company?.id;
    final profile = _ref.read(profileProvider);
    if (member == null || cid == null || profile == null || state.memberStatus != MemberStatus.active) return;
    try {
      if (member.photoAt > profile.photoAt) {
        final photo = member.photo;
        await _ref
            .read(profileProvider.notifier)
            .setPhoto(photo == null ? null : base64Decode(photo), at: member.photoAt);
      } else if (profile.photoAt > member.photoAt) {
        final photo = profile.photo == null ? null : base64Encode(profile.photo!);
        await _team.setOwnPhoto(await freshSession(), cid, photo, profile.photoAt);
        final current = state.member;
        if (current != null && mounted) {
          await _setCompany(
            state.company,
            current.copyWith(photo: () => photo, photoAt: profile.photoAt),
            state.memberStatus,
          );
        }
      }
    } catch (_) {
      // Hors ligne ou photo illisible : nouvel essai plus tard.
    }
  }

  /// Déconnecte le compte sur cet appareil : les données restent sur
  /// l'appareil, elles ne sont simplement plus synchronisées.
  Future<void> signOut() async {
    _stopAutoSync();
    _session = null;
    _memberCheckedAt = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    await prefs.remove(_lastSyncKey);
    await prefs.remove(_memberKey);
    await prefs.remove(_companyKey);
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

  Future<void> _reloadData() async {
    await _ref.read(wellsControllerProvider.notifier).reload();
    await _ref.read(plantControllerProvider.notifier).reload();
    await _ref.read(sharedConfigProvider.notifier).reload();
  }

  /// Vérifie l'adhésion du compte, puis récupère les modifications de
  /// l'entreprise et envoie celles de cet appareil que le rôle autorise.
  /// Sans effet si aucun compte n'est connecté.
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
        final status = await _refreshMembership(session);
        final company = state.company;
        final member = state.member;
        if (status != MemberStatus.active || company == null || member == null) {
          state = state.copyWith(
            phase: SyncPhase.error,
            errorKey: () => switch (status) {
              MemberStatus.noCompany => 'syncErrorNoCompany',
              MemberStatus.pending => 'syncErrorPending',
              MemberStatus.inactive => 'syncErrorInactive',
              _ => 'syncErrorNoMember',
            },
          );
          return;
        }
        await _engine.prepareFirstSync(company.path, session.uid, writable: member.role.writableTables);
        final report = await _engine.sync(
          session,
          scope: company.path,
          writable: member.role.writableTables,
          actor: _team.actorOf(session, member.name),
        );
        if (report.pulled > 0) await _reloadData();
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
      // désactivé ou supprimé...) : il faut se reconnecter.
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
