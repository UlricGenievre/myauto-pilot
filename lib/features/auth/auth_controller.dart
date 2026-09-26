import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../background/pilot_runtime.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/renault_api_settings.dart';
import '../../core/api/renault_keys_source.dart';
import 'auth_repository.dart';

/// Cles et serveurs Renault de tous les pays, telecharges depuis
/// `renault-api` a l'ouverture de l'ecran de connexion (cles toujours
/// fraiches a chaque connexion).
final renaultLocalesProvider = FutureProvider.autoDispose<List<RenaultApiSettings>>(
  (ref) => RenaultKeysSource().fetchAll(),
);

/// Les mises a jour automatiques des cles Renault sont notifiees (Android).
final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(onKeysEvent: showPilotInfo));

sealed class AuthState {
  const AuthState();
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.session);
  final AuthSession session;
}

/// Mode demonstration : vehicule fictif, aucun appel a Renault (cf.
/// `features/demo/`). Non persiste : l'app redemarre sur l'ecran de connexion.
class AuthDemo extends AuthState {
  const AuthDemo();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated({this.error});
  final String? error;
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository) : super(const AuthInitial()) {
    _tryRestoreSession();
  }

  final AuthRepository _repository;

  /// Reutilise le refresh en cours s'il y en a deja un : sans ca, plusieurs
  /// appels Kamereon qui expirent au meme moment (cas frequent, l'app tire
  /// plusieurs endpoints en parallele au chargement d'un ecran) declenchent
  /// chacun leur propre aller-retour vers Gigya au lieu de partager le
  /// meme JWT frais.
  Future<AuthSession?>? _pendingRefresh;

  Future<void> _tryRestoreSession() async {
    try {
      final session = await _repository.restoreSession();
      state = session != null ? AuthAuthenticated(session) : const AuthUnauthenticated();
    } catch (_) {
      state = const AuthUnauthenticated();
    }
  }

  Future<void> login({required String email, required String password, required RenaultApiSettings settings}) async {
    state = const AuthLoading();
    try {
      final session = await _repository.login(email: email, password: password, settings: settings);
      state = AuthAuthenticated(session);
    } on ApiException catch (e) {
      state = AuthUnauthenticated(error: e.message);
    }
  }

  /// Rafraichit le JWT (branche sur l'intercepteur 401 de [KamereonClient],
  /// cf. `vehicleRepositoryProvider`), ou deconnecte si le login token est
  /// lui aussi expire.
  Future<AuthSession?> refreshSession() {
    return _pendingRefresh ??= _doRefresh().whenComplete(() => _pendingRefresh = null);
  }

  Future<AuthSession?> _doRefresh() async {
    final session = await _repository.refreshJwt();
    if (session != null) {
      state = AuthAuthenticated(session);
    } else {
      state = const AuthUnauthenticated(error: 'Session expirée, merci de te reconnecter.');
    }
    return session;
  }

  void startDemo() => state = const AuthDemo();

  Future<void> logout() async {
    if (state is! AuthDemo) await _repository.logout();
    state = const AuthUnauthenticated();
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref.watch(authRepositoryProvider));
});

final demoModeProvider = Provider<bool>((ref) => ref.watch(authControllerProvider) is AuthDemo);
