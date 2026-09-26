import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/vehicle_schedule.dart';
import '../vehicle/vehicle_providers.dart';

final vehicleScheduleProvider = FutureProvider.autoDispose<VehicleSchedule?>((ref) async {
  final repository = ref.watch(vehicleRepositoryProvider);
  final vehicle = ref.watch(selectedVehicleProvider);
  if (repository == null || vehicle == null) return null;
  return repository.fetchVehicleSchedule(vehicle.vin);
});
