import 'api_exception.dart';
import 'renault_api_settings.dart';

/// Acces aux cles et serveurs Renault du pays du compte.
///
/// L'app les charge depuis le projet open source `renault-api` a la
/// connexion (choix du pays), les garde dans le stockage securise et les met
/// a jour seule si Renault les change (cf. `renault_keys_source.dart`).
/// Chaque isolate (app, reveils, notifications) les charge au demarrage via
/// `AuthRepository.restoreSession`.
///
/// Les clients lisent ces valeurs a chaque appel : une mise a jour des cles
/// s'applique immediatement, sans recreer les clients.
abstract final class ApiConfig {
  static RenaultApiSettings? _settings;

  /// Reglages en cours, ou null tant qu'aucun pays n'est choisi.
  static RenaultApiSettings? get settings => _settings;

  static void use(RenaultApiSettings? settings) => _settings = settings;

  static RenaultApiSettings get _required =>
      _settings ?? (throw const ApiException('Clés Renault non chargées : reconnectez-vous.'));

  /// Ex. "FR" (parametre `country` de Kamereon).
  static String get country => _required.country;

  static String get gigyaApiKey => _required.gigyaKey;
  static String get gigyaBaseUrl => _required.gigyaUrl;
  static String get kamereonApiKey => _required.kamereonKey;
  static String get kamereonBaseUrl => _required.kamereonUrl;
}
