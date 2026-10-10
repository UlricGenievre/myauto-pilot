import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/battery_status.dart';
import '../../core/models/cockpit.dart';
import '../../core/models/hvac_status.dart';
import '../about/disclaimer.dart';
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

/// Etat de la climatisation. Erreur (endpoint absent sur certains modeles)
/// traitee comme "inconnu" : l'information est secondaire.
final hvacStatusProvider = FutureProvider.autoDispose<HvacStatus?>((ref) async {
  final repository = ref.watch(vehicleRepositoryProvider);
  final vehicle = ref.watch(selectedVehicleProvider);
  if (repository == null || vehicle == null) return null;
  try {
    return await repository.fetchHvacStatus(vehicle.vin);
  } on Object {
    return null;
  }
});

/// Informations de la carte "Vehicule" de l'onglet Etat.
enum VehicleTile {
  mileage('Kilométrage'),
  fuel('Carburant'),
  cabin('Température de l\'habitacle'),
  batteryTemperature('Température de la batterie');

  const VehicleTile(this.label);

  final String label;
}

/// Informations masquees par l'utilisateur dans la carte "Vehicule".
final hiddenVehicleTilesProvider =
    AsyncNotifierProvider<HiddenVehicleTilesController, Set<VehicleTile>>(HiddenVehicleTilesController.new);

class HiddenVehicleTilesController extends AsyncNotifier<Set<VehicleTile>> {
  @override
  Future<Set<VehicleTile>> build() async {
    final names = await ref.read(appPrefsProvider).hiddenVehicleTiles;
    return {for (final tile in VehicleTile.values) if (names.contains(tile.name)) tile};
  }

  Future<void> setVisible(VehicleTile tile, bool visible) async {
    final hidden = {...?state.value};
    visible ? hidden.remove(tile) : hidden.add(tile);
    state = AsyncData(hidden);
    await ref.read(appPrefsProvider).setHiddenVehicleTiles({for (final t in hidden) t.name});
  }
}
