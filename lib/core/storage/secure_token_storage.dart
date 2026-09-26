import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/renault_api_settings.dart';

/// Stocke les jetons d'authentification (login token Gigya, JWT Kamereon,
/// identifiants de compte/vehicule) dans le keystore/keychain du telephone.
class SecureTokenStorage {
  SecureTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _gigyaLoginTokenKey = 'gigya_login_token';
  static const _kamereonJwtKey = 'kamereon_jwt';
  static const _personIdKey = 'person_id';
  static const _accountIdKey = 'account_id';
  static const _apiSettingsKey = 'renault_api_settings';
  static const _lastKeyCheckKey = 'renault_last_key_check';

  Future<void> saveSession({
    required String gigyaLoginToken,
    required String kamereonJwt,
    required String personId,
    required String accountId,
  }) async {
    await Future.wait([
      _storage.write(key: _gigyaLoginTokenKey, value: gigyaLoginToken),
      _storage.write(key: _kamereonJwtKey, value: kamereonJwt),
      _storage.write(key: _personIdKey, value: personId),
      _storage.write(key: _accountIdKey, value: accountId),
    ]);
  }

  Future<String?> get gigyaLoginToken => _storage.read(key: _gigyaLoginTokenKey);
  Future<String?> get kamereonJwt => _storage.read(key: _kamereonJwtKey);
  Future<String?> get personId => _storage.read(key: _personIdKey);
  Future<String?> get accountId => _storage.read(key: _accountIdKey);

  Future<bool> get hasSession async => (await kamereonJwt) != null;

  /// Cles et serveurs Renault du pays du compte (cf. `ApiConfig`).
  Future<RenaultApiSettings?> get apiSettings async {
    final raw = await _storage.read(key: _apiSettingsKey);
    if (raw == null) return null;
    try {
      return RenaultApiSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  Future<void> saveApiSettings(RenaultApiSettings settings) =>
      _storage.write(key: _apiSettingsKey, value: jsonEncode(settings.toJson()));

  /// Derniere recherche de nouvelles cles (limite la frequence des essais).
  Future<DateTime?> get lastKeyCheck async => DateTime.tryParse(await _storage.read(key: _lastKeyCheckKey) ?? '');

  Future<void> saveLastKeyCheck(DateTime? at) => at == null
      ? _storage.delete(key: _lastKeyCheckKey)
      : _storage.write(key: _lastKeyCheckKey, value: at.toIso8601String());

  /// Efface uniquement la session : pas `deleteAll()`, qui supprimerait aussi
  /// le parametrage de charge stocke dans le meme keystore
  /// (`ChargePlanStorage`).
  Future<void> clear() => Future.wait([
        for (final key in [
          _gigyaLoginTokenKey,
          _kamereonJwtKey,
          _personIdKey,
          _accountIdKey,
          // Le pays (et donc ses cles) se rechoisit a la connexion suivante.
          _apiSettingsKey,
          _lastKeyCheckKey,
        ])
          _storage.delete(key: key),
      ]);
}
