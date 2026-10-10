import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_storage.dart';

/// Preferences de l'app independantes de la session (conservees a la
/// deconnexion).
class AppPrefs {
  AppPrefs({FlutterSecureStorage? storage}) : _storage = storage ?? appSecureStorage;

  final FlutterSecureStorage _storage;

  static const _disclaimerKey = 'disclaimer_accepted';
  static const _tutorialKey = 'tutorial_pending';
  static const _hiddenVehicleTilesKey = 'hidden_vehicle_tiles';

  Future<bool> get disclaimerAccepted async => await _storage.read(key: _disclaimerKey) == 'true';

  /// Accepter l'avertissement programme le tutoriel : seul un nouveau
  /// premier lancement le voit, pas les installations ou l'avertissement
  /// etait deja accepte.
  Future<void> acceptDisclaimer() async {
    await _storage.write(key: _tutorialKey, value: 'true');
    await _storage.write(key: _disclaimerKey, value: 'true');
  }

  /// Tutoriel a afficher (reste vrai si l'app est fermee pendant le tutoriel).
  Future<bool> get tutorialPending async => await _storage.read(key: _tutorialKey) == 'true';

  Future<void> finishTutorial() => _storage.delete(key: _tutorialKey);

  /// Informations masquees dans la carte "Vehicule" de l'onglet Etat
  /// (identifiants libres) : on retient celles masquees, pour qu'une
  /// information ajoutee plus tard soit affichee par defaut.
  Future<Set<String>> get hiddenVehicleTiles async {
    final raw = await _storage.read(key: _hiddenVehicleTilesKey);
    return raw == null || raw.isEmpty ? {} : raw.split(',').toSet();
  }

  Future<void> setHiddenVehicleTiles(Set<String> hidden) =>
      _storage.write(key: _hiddenVehicleTilesKey, value: hidden.join(','));
}
