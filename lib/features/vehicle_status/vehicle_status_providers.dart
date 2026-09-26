import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/battery_status.dart';
import '../../core/models/cockpit.dart';
import '../vehicle/vehicle_providers.dart';

final batteryStatusProvider = FutureProvider.autoDispose<BatteryStatus?>((ref) async {
  final repository = ref.watch(vehicleRepositoryProvider);
  final vehicle = ref.watch(selectedVehicleProvider);
  if (repository == null || vehicle == null) return null;
  return repository.fetchBatteryStatus(vehicle.vin);
});

final cockpitProvider = FutureProvider.autoDispose<Cockpit?>((ref) async {
  final repository = ref.watch(vehicleRepositoryProvider);
  final vehicle = ref.watch(selectedVehicleProvider);
  if (repository == null || vehicle == null) return null;
  return repository.fetchCockpit(vehicle.vin);
});
