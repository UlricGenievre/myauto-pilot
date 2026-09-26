import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Preferences de l'app independantes de la session (conservees a la
/// deconnexion).
class AppPrefs {
  AppPrefs({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _disclaimerKey = 'disclaimer_accepted';

  Future<bool> get disclaimerAccepted async => await _storage.read(key: _disclaimerKey) == 'true';

  Future<void> acceptDisclaimer() => _storage.write(key: _disclaimerKey, value: 'true');
}
