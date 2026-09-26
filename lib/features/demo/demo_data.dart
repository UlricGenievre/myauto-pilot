import 'dart:convert';

import '../../core/api/kamereon_client.dart';
import '../../core/charge_plan/pilot_state.dart';
import '../../core/models/battery_status.dart';
import '../../core/models/charge_plan_config.dart';
import '../../core/models/cockpit.dart';
import '../../core/models/hvac_status.dart';
import '../../core/models/vehicle.dart';
import '../../core/models/vehicle_location.dart';
import '../../core/models/vehicle_schedule.dart';
import '../../core/storage/charge_plan_storage.dart';
import '../vehicle/vehicle_repository.dart';

/// Mode demonstration : vehicule fictif, sans compte MyRenault ni aucun
/// appel aux serveurs Renault (decouverte de l'app, relecture par les
/// stores). Les ecritures sont simulees en memoire et oubliees a la sortie.

const demoVehicle = Vehicle(vin: 'VF1DEMONSTRATION1', brand: 'Renault', model: 'Rafale', modelCode: 'XHN1CP');

/// Latence simulee des appels, pour que l'interface se comporte comme en
/// usage reel (indicateurs de chargement).
const _latency = Duration(milliseconds: 400);

class DemoVehicleRepository implements VehicleRepository {
  DemoVehicleRepository() : _schedule = _initialSchedule();

  Map<String, dynamic> _schedule;

  @override
  Future<List<Vehicle>> fetchVehicles() async {
    await Future<void>.delayed(_latency);
    return const [demoVehicle];
  }

  @override
  Future<BatteryStatus> fetchBatteryStatus(String vin) async {
    await Future<void>.delayed(_latency);
    return BatteryStatus(
      batteryLevel: 46,
      rangeKm: 205,
      plugState: PlugState.plugged,
      chargeState: ChargeState.waitingPlanned,
      batteryTemperature: 18,
      lastUpdated: DateTime.now().subtract(const Duration(minutes: 12)),
      batteryCapacityKwh: 80,
      availableEnergyKwh: 36.8,
    );
  }

  @override
  Future<Cockpit> fetchCockpit(String vin) async {
    await Future<void>.delayed(_latency);
    return const Cockpit(totalMileageKm: 12480, fuelQuantityLiters: 31, fuelAutonomyKm: 540);
  }

  bool _hvacOn = false;

  @override
  Future<HvacStatus> fetchHvacStatus(String vin) async {
    await Future<void>.delayed(_latency);
    return HvacStatus(
      isOn: _hvacOn,
      internalTemperature: _hvacOn ? 20 : 14.5,
      externalTemperature: 12,
      socThreshold: 15,
      lastUpdated: DateTime.now().subtract(const Duration(minutes: 5)),
    );
  }

  @override
  Future<VehicleLocation> fetchLocation(String vin) async {
    await Future<void>.delayed(_latency);
    return VehicleLocation(
      latitude: 45.7578,
      longitude: 4.8320,
      lastUpdated: DateTime.now().subtract(const Duration(minutes: 35)),
    );
  }

  @override
  Future<VehicleSchedule> fetchVehicleSchedule(String vin) async {
    await Future<void>.delayed(_latency);
    return VehicleSchedule.fromJson(_copy(_schedule));
  }

  @override
  Future<VehicleSchedule> updateVehicleSchedule(String vin, Map<String, dynamic> settings) async {
    await Future<void>.delayed(_latency);
    _schedule = {..._copy(settings), 'lastSettingsUpdateTimestamp': DateTime.now().toUtc().toIso8601String()};
    return VehicleSchedule.fromJson(_copy(_schedule));
  }

  @override
  Future<void> sendAction(String vin, VehicleAction action) async {
    await Future<void>.delayed(_latency * 2);
    if (action == VehicleAction.hvacStart) _hvacOn = true;
    if (action == VehicleAction.hvacStop) _hvacOn = false;
  }

  static Map<String, dynamic> _copy(Map<String, dynamic> json) =>
      jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

  /// Meme forme que la reponse `ev/settings` d'un vrai vehicule : plage
  /// unique 01:30 + 6 h, programme habituel actif, le 3e reserve a l'app.
  static Map<String, dynamic> _initialSchedule() => {
        'lastSettingsUpdateTimestamp':
            DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String(),
        'delegatedActivated': false,
        'chargeModeRq': 'SCHEDULED',
        'chargeTimeStart': '01:30',
        'chargeDuration': 360,
        'preconditioningTemperature': 21,
        'programs': [
          for (final (active, time, weekdaysOnly) in [
            (true, '07:30:00', true),
            (false, '09:00:00', false),
            (false, '07:30:00', false),
          ])
            {
              'programActivationStatus': active,
              'programType': 'CHARGE',
              'programDepartureTime': time,
              for (final (i, day) in ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
                  .indexed)
                'programActivation$day': !weekdaysOnly || i < 5,
            },
        ],
      };
}

/// Parametrage d'exemple : heures creuses de nuit et de midi, dimanche
/// entier, agenda "Habituel" actif.
ChargePlanConfig demoChargePlanConfig() {
  final nightAndNoon = DaySchedule(windows: [
    ChargeWindow(start: ClockTime.hm(1, 30), end: ClockTime.hm(7, 30)),
    ChargeWindow(start: ClockTime.hm(12, 30), end: ClockTime.hm(14, 30)),
  ]);
  return ChargePlanConfig(
    batteryCapacityKwh: 80,
    chargePowerKw: 7.4,
    calendar: ChargeCalendar(days: {
      for (var day = 1; day <= 6; day++) day: nightAndNoon,
      7: const DaySchedule(allDay: true),
    }),
    agendas: [
      TargetAgenda(id: 'demo-habituel', name: 'Habituel', targets: {
        for (var day = 1; day <= 5; day++) day: ReadyTarget(targetPercent: 80, readyAt: ClockTime.hm(7, 30)),
      }),
      TargetAgenda(id: 'demo-vacances', name: 'Vacances', targets: {
        6: ReadyTarget(targetPercent: 100, readyAt: ClockTime.hm(9, 0), climate: true),
      }),
    ],
    activeAgendaId: 'demo-habituel',
    dedicatedProgramIndex: 2,
    vehicleVin: demoVehicle.vin,
    vehicleModelCode: demoVehicle.modelCode,
  );
}

/// Stockage en memoire du parametrage : la demonstration ne touche pas au
/// stockage du telephone (ni donc aux reveils du pilotage reel).
class DemoChargePlanStorage implements ChargePlanStorage {
  ChargePlanConfig _config = demoChargePlanConfig();
  PilotState _state = const PilotState();

  @override
  Future<ChargePlanConfig> load() async => _config;

  @override
  Future<void> save(ChargePlanConfig config) async => _config = config;

  @override
  Future<PilotState> loadState() async => _state;

  @override
  Future<void> saveState(PilotState state) async => _state = state;
}
