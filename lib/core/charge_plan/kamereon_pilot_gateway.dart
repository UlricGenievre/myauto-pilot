import '../../features/auth/auth_repository.dart';
import '../api/kamereon_client.dart';
import '../models/vehicle_schedule.dart';
import 'charge_pilot.dart';

/// [PilotVehicleGateway] branche sur l'API Kamereon, avec une session
/// reconstruite depuis le stockage (JWT toujours rafraichi, comme au
/// demarrage de l'app) : utilisable depuis un reveil, sans Riverpod.
class KamereonPilotGateway implements PilotVehicleGateway {
  KamereonPilotGateway._(AuthSession session, AuthRepository authRepository)
      : _jwt = session.jwt,
        _accountId = session.accountId {
    _client = KamereonClient(
      onUnauthorized: () async {
        final refreshed = await authRepository.refreshJwt();
        if (refreshed != null) _jwt = refreshed.jwt;
        return refreshed?.jwt;
      },
      onKeyRejected: () async => await authRepository.recoverFromKeyRejection() == KeysUpdateResult.updated,
    );
  }

  String _jwt;
  final String _accountId;
  late final KamereonClient _client;

  /// Null si l'utilisateur n'est pas connecte. [onKeysEvent] : notification
  /// d'une mise a jour automatique des cles Renault.
  static Future<KamereonPilotGateway?> open({
    AuthRepository? authRepository,
    void Function(String title, String body)? onKeysEvent,
  }) async {
    final auth = authRepository ?? AuthRepository(onKeysEvent: onKeysEvent);
    final session = await auth.restoreSession();
    return session == null ? null : KamereonPilotGateway._(session, auth);
  }

  @override
  Future<int?> fetchSoc(String vin) async =>
      (await _client.fetchBatteryStatus(jwt: _jwt, accountId: _accountId, vin: vin)).batteryLevel;

  @override
  Future<VehicleSchedule> fetchSchedule(String vin) =>
      _client.fetchVehicleSchedule(jwt: _jwt, accountId: _accountId, vin: vin);

  @override
  Future<void> updateSchedule(String vin, Map<String, dynamic> settings) =>
      _client.updateVehicleSchedule(jwt: _jwt, accountId: _accountId, vin: vin, settings: settings);
}
