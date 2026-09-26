import '../../core/api/api_config.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/gigya_client.dart';
import '../../core/api/kamereon_client.dart';
import '../../core/api/renault_api_settings.dart';
import '../../core/api/renault_keys_source.dart';
import '../../core/debug/dev_log.dart';
import '../../core/storage/secure_token_storage.dart';

/// Session active : JWT courant + identifiants de compte.
class AuthSession {
  const AuthSession({required this.jwt, required this.personId, required this.accountId});

  final String jwt;
  final String personId;
  final String accountId;
}

/// Issue d'une recherche de nouvelles cles Renault.
enum KeysUpdateResult {
  /// Nouvelles cles trouvees, testees et adoptees.
  updated,

  /// `renault-api` donne les memes cles que celles en place.
  unchanged,

  /// Recherche deja faite recemment (cf. [AuthRepository.keyCheckInterval]).
  tooSoon,

  /// Fichier injoignable/illisible, pays absent, ou nouvelles cles refusees.
  failed,
}

/// Orchestre le login (Gigya) puis la resolution du compte Kamereon, et
/// persiste la session pour les demarrages suivants.
///
/// Gere aussi les cles Renault du pays du compte : choisies a la connexion,
/// rechargees au demarrage (y compris dans les reveils), et remplacees
/// automatiquement si Renault les refuse (cf. [recoverFromKeyRejection]).
class AuthRepository {
  AuthRepository({
    GigyaClient? gigyaClient,
    KamereonClient? kamereonClient,
    SecureTokenStorage? storage,
    RenaultKeysSource? keysSource,
    this.onKeysEvent,
  })  : _gigyaClient = gigyaClient ?? GigyaClient(),
        _kamereonClient = kamereonClient ?? KamereonClient(),
        _storage = storage ?? SecureTokenStorage(),
        _keysSource = keysSource ?? RenaultKeysSource();

  final GigyaClient _gigyaClient;
  final KamereonClient _kamereonClient;
  final SecureTokenStorage _storage;
  final RenaultKeysSource _keysSource;

  /// Prevenir l'utilisateur d'une mise a jour (ou d'un echec) des cles
  /// suite a un refus de Renault (notification sur Android).
  final void Function(String title, String body)? onKeysEvent;

  /// Au plus une recherche automatique de nouvelles cles sur cette duree,
  /// pour ne pas interroger GitHub en boucle si Renault est simplement en
  /// panne.
  static const keyCheckInterval = Duration(hours: 6);

  Future<KeysUpdateResult>? _pendingKeyRecovery;

  /// [settings] : cles et serveurs du pays choisi a l'ecran de connexion
  /// (tout juste charges depuis `renault-api`).
  Future<AuthSession> login({
    required String email,
    required String password,
    required RenaultApiSettings settings,
  }) async {
    ApiConfig.use(settings);
    final gigyaSession = await _gigyaClient.login(email: email, password: password);
    final jwt = await _gigyaClient.getJwt(gigyaSession.loginToken);
    final accountId = await _kamereonClient.fetchAccountId(
      jwt: jwt,
      personId: gigyaSession.personId,
    );

    await _storage.saveApiSettings(settings);
    await _storage.saveSession(
      gigyaLoginToken: gigyaSession.loginToken,
      kamereonJwt: jwt,
      personId: gigyaSession.personId,
      accountId: accountId,
    );

    return AuthSession(jwt: jwt, personId: gigyaSession.personId, accountId: accountId);
  }

  /// Au demarrage de l'app (ou d'un reveil) : recharge les cles du pays du
  /// compte, puis un JWT frais. Le JWT stocke (cf. [refreshJwt]) a de bonnes
  /// chances d'etre deja expire (duree de vie ~15 min) : on repart toujours
  /// du login token Gigya, qui reste valide bien plus longtemps. C'est ce
  /// qui permet de ne pas redemander les identifiants a chaque relancement.
  ///
  /// Null sans session ou sans cles enregistrees (connexion necessaire).
  Future<AuthSession?> restoreSession() async {
    final settings = await _storage.apiSettings;
    if (settings == null) return null;
    ApiConfig.use(settings);
    return refreshJwt();
  }

  /// Le JWT Gigya expire vite (~15 min). On le renouvelle a partir du
  /// login token, qui lui reste valide plus longtemps. Si Renault refuse la
  /// cle Gigya, on tente une fois de recuperer les nouvelles cles.
  Future<AuthSession?> refreshJwt() async {
    final loginToken = await _storage.gigyaLoginToken;
    final personId = await _storage.personId;
    final accountId = await _storage.accountId;
    if (loginToken == null || personId == null || accountId == null) return null;

    String jwt;
    try {
      jwt = await _gigyaClient.getJwt(loginToken);
    } on ApiException catch (e) {
      if (!e.keyRejected || await recoverFromKeyRejection() != KeysUpdateResult.updated) rethrow;
      jwt = await _gigyaClient.getJwt(loginToken);
    }
    await _storage.saveSession(
      gigyaLoginToken: loginToken,
      kamereonJwt: jwt,
      personId: personId,
      accountId: accountId,
    );
    return AuthSession(jwt: jwt, personId: personId, accountId: accountId);
  }

  /// Renault a refuse une cle : recupere celles du pays du compte dans
  /// `renault-api`, les teste pour de vrai (JWT + appel Kamereon) et ne les
  /// adopte que si ca marche. Au plus une fois par [keyCheckInterval]
  /// (sauf [force], ex. bouton "Verifier les cles"). Les appels simultanes
  /// partagent la meme recherche.
  Future<KeysUpdateResult> recoverFromKeyRejection({bool force = false}) =>
      _pendingKeyRecovery ??= _recoverKeys(force: force).whenComplete(() => _pendingKeyRecovery = null);

  Future<KeysUpdateResult> _recoverKeys({required bool force}) async {
    final current = ApiConfig.settings ?? await _storage.apiSettings;
    if (current == null) return KeysUpdateResult.failed;

    final lastCheck = await _storage.lastKeyCheck;
    if (!force && lastCheck != null && DateTime.now().difference(lastCheck) < keyCheckInterval) {
      return KeysUpdateResult.tooSoon;
    }
    await _storage.saveLastKeyCheck(DateTime.now());

    final RenaultApiSettings? candidate;
    try {
      candidate = await _keysSource.fetch(current.locale);
    } on ApiException catch (e) {
      _report(force, 'Clés Renault refusées', 'Impossible de vérifier les nouvelles clés : ${e.message}');
      return KeysUpdateResult.failed;
    }
    if (candidate == null) {
      _report(force, 'Clés Renault refusées', 'Le pays ${renaultLocaleName(current.locale)} n\'existe plus dans renault-api.');
      return KeysUpdateResult.failed;
    }
    if (candidate.sameValuesAs(current)) {
      _report(force, 'Clés Renault refusées',
          'Renault refuse les clés actuelles et renault-api n\'a pas encore les nouvelles. Nouvel essai dans quelques heures.');
      return KeysUpdateResult.unchanged;
    }

    // Essai reel avant adoption ; retour aux cles en place si ca echoue.
    ApiConfig.use(candidate);
    try {
      final loginToken = await _storage.gigyaLoginToken;
      final personId = await _storage.personId;
      if (loginToken == null || personId == null) throw const ApiException('Session absente');
      final jwt = await _gigyaClient.getJwt(loginToken);
      await _kamereonClient.fetchAccountId(jwt: jwt, personId: personId);
      await _storage.saveApiSettings(candidate);
      _report(force, 'Clés Renault mises à jour', 'Nouvelles clés récupérées et testées : tout refonctionne.');
      return KeysUpdateResult.updated;
    } catch (_) {
      ApiConfig.use(current);
      _report(force, 'Clés Renault refusées', 'Les nouvelles clés de renault-api ne fonctionnent pas non plus.');
      return KeysUpdateResult.failed;
    }
  }

  /// Recherche automatique (suite a un refus) : notifiee. Verification
  /// manuelle ([manual]) : le resultat est affiche par l'ecran appelant.
  void _report(bool manual, String title, String body) {
    DevLog.send('keys_event', {'manual': manual, 'title': title, 'body': body});
    if (!manual) onKeysEvent?.call(title, body);
  }

  Future<void> logout() => _storage.clear();
}
