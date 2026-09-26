import '../../core/api/kamereon_client.dart';
import '../../core/models/battery_status.dart';
import '../../core/models/cockpit.dart';
import '../../core/models/hvac_status.dart';
import '../../core/models/vehicle.dart';
import '../../core/models/vehicle_location.dart';
import '../../core/models/vehicle_schedule.dart';
import '../auth/auth_repository.dart';

/// Facade au-dessus de [KamereonClient] qui porte la session courante
/// (jwt + accountId), pour eviter de la repasser a chaque appel.
class VehicleRepository {
  VehicleRepository({
    required AuthSession session,
    KamereonClient? client,
    Future<String?> Function()? onUnauthorized,
    Future<bool> Function()? onKeyRejected,
  })  : _session = session,
        _client = client ?? KamereonClient(onUnauthorized: onUnauthorized, onKeyRejected: onKeyRejected);

  final AuthSession _session;
  final KamereonClient _client;

  Future<List<Vehicle>> fetchVehicles() =>
      _client.fetchVehicles(jwt: _session.jwt, accountId: _session.accountId);

  Future<BatteryStatus> fetchBatteryStatus(String vin) =>
      _client.fetchBatteryStatus(jwt: _session.jwt, accountId: _session.accountId, vin: vin);

  Future<Cockpit> fetchCockpit(String vin) =>
      _client.fetchCockpit(jwt: _session.jwt, accountId: _session.accountId, vin: vin);

  Future<HvacStatus> fetchHvacStatus(String vin) =>
      _client.fetchHvacStatus(jwt: _session.jwt, accountId: _session.accountId, vin: vin);

  Future<VehicleLocation> fetchLocation(String vin) =>
      _client.fetchLocation(jwt: _session.jwt, accountId: _session.accountId, vin: vin);

  Future<VehicleSchedule> fetchVehicleSchedule(String vin) =>
      _client.fetchVehicleSchedule(jwt: _session.jwt, accountId: _session.accountId, vin: vin);

  Future<VehicleSchedule> updateVehicleSchedule(String vin, Map<String, dynamic> settings) =>
      _client.updateVehicleSchedule(jwt: _session.jwt, accountId: _session.accountId, vin: vin, settings: settings);

  Future<void> sendAction(String vin, VehicleAction action) =>
      _client.sendAction(jwt: _session.jwt, accountId: _session.accountId, vin: vin, action: action);
}
