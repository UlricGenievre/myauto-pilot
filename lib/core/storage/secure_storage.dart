import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stockage chiffre commun a toute l'app (session, pilotage, preferences).
/// Sur Android, les donnees ecrites par une version plus ancienne du plugin
/// sont migrees vers les chiffrements actuels a la premiere lecture, avec
/// une copie de secours tant que la migration n'est pas terminee.
const appSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(migrateWithBackup: true),
);
