import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/vehicle_location.dart';
import '../vehicle/vehicle_providers.dart';

final vehicleLocationProvider = FutureProvider.autoDispose<VehicleLocation?>((ref) async {
  final repository = ref.watch(vehicleRepositoryProvider);
  final vehicle = ref.watch(selectedVehicleProvider);
  if (repository == null || vehicle == null) return null;
  return repository.fetchLocation(vehicle.vin);
});
