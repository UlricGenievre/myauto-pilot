import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/kamereon_client.dart';
import '../vehicle/vehicle_providers.dart';
import '../vehicle_status/vehicle_status_providers.dart';

class RemoteActionState {
  const RemoteActionState({this.pendingAction, this.error});

  final VehicleAction? pendingAction;
  final String? error;

  bool isPending(VehicleAction action) => pendingAction == action;
}

class RemoteActionsController extends Notifier<RemoteActionState> {
  @override
  RemoteActionState build() => const RemoteActionState();

  Future<void> trigger(VehicleAction action) async {
    final repository = ref.read(vehicleRepositoryProvider);
    final vehicle = ref.read(selectedVehicleProvider);
    if (repository == null || vehicle == null) return;

    state = RemoteActionState(pendingAction: action);
    try {
      await repository.sendAction(vehicle.vin, action);
      state = const RemoteActionState();
      // Relecture de l'etat (la voiture peut mettre un moment a le refleter).
      if (action == VehicleAction.hvacStart || action == VehicleAction.hvacStop) ref.invalidate(hvacStatusProvider);
      if (action == VehicleAction.chargeStart || action == VehicleAction.chargePause) {
        ref.invalidate(batteryStatusProvider);
      }
    } on ApiException catch (e) {
      state = RemoteActionState(error: e.message);
    }
  }
}

final remoteActionsControllerProvider =
    NotifierProvider<RemoteActionsController, RemoteActionState>(RemoteActionsController.new);
