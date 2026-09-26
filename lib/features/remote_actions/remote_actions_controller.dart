import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/kamereon_client.dart';
import '../vehicle/vehicle_providers.dart';

class RemoteActionState {
  const RemoteActionState({this.pendingAction, this.error});

  final VehicleAction? pendingAction;
  final String? error;

  bool isPending(VehicleAction action) => pendingAction == action;
}

class RemoteActionsController extends StateNotifier<RemoteActionState> {
  RemoteActionsController(this._ref) : super(const RemoteActionState());

  final Ref _ref;

  Future<void> trigger(VehicleAction action) async {
    final repository = _ref.read(vehicleRepositoryProvider);
    final vehicle = _ref.read(selectedVehicleProvider);
    if (repository == null || vehicle == null) return;

    state = RemoteActionState(pendingAction: action);
    try {
      await repository.sendAction(vehicle.vin, action);
      state = const RemoteActionState();
    } on ApiException catch (e) {
      state = RemoteActionState(error: e.message);
    }
  }
}

final remoteActionsControllerProvider =
    StateNotifierProvider<RemoteActionsController, RemoteActionState>((ref) {
  return RemoteActionsController(ref);
});
