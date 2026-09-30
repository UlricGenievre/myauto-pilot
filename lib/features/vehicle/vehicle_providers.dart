import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/vehicle.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_repository.dart';
import '../demo/demo_data.dart';
import 'vehicle_repository.dart';

/// Repository lie a la session active. Se recree automatiquement quand la
/// session change (ex: apres un refresh de JWT).
///
/// Le refresh sur 401 en cours de session est gere au niveau HTTP par
/// [KamereonClient] (intercepteur Dio), pas ici : on lui passe juste le
/// moyen d'obtenir un JWT frais (`AuthController.refreshSession`). Les
/// appelants (providers plus bas, ecrans) n'ont donc rien de particulier a
/// faire pour en beneficier.
final vehicleRepositoryProvider = Provider<VehicleRepository?>((ref) {
  final authState = ref.watch(authControllerProvider);
  if (authState is AuthDemo) return DemoVehicleRepository();
  if (authState is! AuthAuthenticated) return null;
  return VehicleRepository(
    session: authState.session,
    onUnauthorized: () async {
      final session = await ref.read(authControllerProvider.notifier).refreshSession();
      return session?.jwt;
    },
    onKeyRejected: () async =>
        await ref.read(authRepositoryProvider).recoverFromKeyRejection() == KeysUpdateResult.updated,
  );
});

final vehiclesProvider = FutureProvider<List<Vehicle>>((ref) async {
  final repository = ref.watch(vehicleRepositoryProvider);
  if (repository == null) return const [];
  return repository.fetchVehicles();
});

/// Vehicule actuellement affiche dans l'app (choisi par l'utilisateur si le
/// compte a plusieurs vehicules). Remis a zero a chaque changement de nature
/// de session (deconnexion, connexion, demonstration) : pas de vehicule d'un
/// autre compte ou fictif qui resterait selectionne.
final selectedVehicleProvider = NotifierProvider<SelectedVehicleController, Vehicle?>(SelectedVehicleController.new);

class SelectedVehicleController extends Notifier<Vehicle?> {
  @override
  Vehicle? build() {
    ref.watch(authControllerProvider.select((state) => state.runtimeType));
    return null;
  }

  void select(Vehicle vehicle) => state = vehicle;
}
