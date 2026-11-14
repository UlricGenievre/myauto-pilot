import '../../core/api/kamereon_client.dart';
import '../../core/models/battery_health.dart';
import '../../core/models/battery_status.dart';
import '../../core/models/cockpit.dart';
import '../../core/models/hvac_status.dart';
import '../../core/models/vehicle.dart';
import '../../core/models/vehicle_location.dart';
import '../../core/models/vehicle_schedule.dart';
import '../auth/auth_repository.dart';

/// Facade au-dessus de [KamereonClient] qui porte la session courante
/// (jwt + compte par defaut), pour eviter de la repasser a chaque appel.
/// Chaque appel sur un vehicule passe par le compte de ce vehicule.
class VehicleRepository {
  VehicleRepository({
    required this._session,
    KamereonClient? client,
    Future<String?> Function()? onUnauthorized,
    Future<bool> Function()? onKeyRejected,
  }) : _client = client ?? KamereonClient(onUnauthorized: onUnauthorized, onKeyRejected: onKeyRejected);

  final AuthSession _session;
  final KamereonClient _client;

  String _account(Vehicle vehicle) => vehicle.accountId ?? _session.accountId;

  /// Vehicules de tous les comptes du profil.
  Future<List<Vehicle>> fetchVehicles() => _client.fetchAllVehicles(
      jwt: _session.jwt, personId: _session.personId, defaultAccountId: _session.accountId);

  Future<BatteryStatus> fetchBatteryStatus(Vehicle vehicle) =>
      _client.fetchBatteryStatus(jwt: _session.jwt, accountId: _account(vehicle), vin: vehicle.vin);

  Future<BatteryHealth?> fetchBatteryHealth(Vehicle vehicle) => _client.fetchBatteryHealth(
      jwt: _session.jwt, accountId: _account(vehicle), vin: vehicle.vin, deliveryDate: vehicle.deliveryDate);

  Future<Cockpit> fetchCockpit(Vehicle vehicle) =>
      _client.fetchCockpit(jwt: _session.jwt, accountId: _account(vehicle), vin: vehicle.vin);

  Future<HvacStatus> fetchHvacStatus(Vehicle vehicle) =>
      _client.fetchHvacStatus(jwt: _session.jwt, accountId: _account(vehicle), vin: vehicle.vin);

  Future<VehicleLocation> fetchLocation(Vehicle vehicle) =>
      _client.fetchLocation(jwt: _session.jwt, accountId: _account(vehicle), vin: vehicle.vin);

  Future<VehicleSchedule> fetchVehicleSchedule(Vehicle vehicle) =>
      _client.fetchVehicleSchedule(jwt: _session.jwt, accountId: _account(vehicle), vin: vehicle.vin);

  Future<VehicleSchedule> updateVehicleSchedule(Vehicle vehicle, Map<String, dynamic> settings) => _client
      .updateVehicleSchedule(jwt: _session.jwt, accountId: _account(vehicle), vin: vehicle.vin, settings: settings);

  Future<void> sendAction(Vehicle vehicle, VehicleAction action) =>
      _client.sendAction(jwt: _session.jwt, accountId: _account(vehicle), vin: vehicle.vin, action: action);
}
