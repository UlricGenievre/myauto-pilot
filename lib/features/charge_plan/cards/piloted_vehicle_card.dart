import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vehicle.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../vehicle/vehicle_providers.dart';
import '../charge_plan_pickers.dart';
import '../charge_plan_providers.dart';

/// Nom du vehicule pilote, ou null s'il n'est pas dans la liste du compte.
String? pilotedVehicleName(WidgetRef ref) {
  final vin = ref.watch(chargePlanConfigProvider).value?.vehicleVin;
  final vehicles = ref.watch(vehiclesProvider).value ?? const <Vehicle>[];
  for (final vehicle in vehicles) {
    if (vehicle.vin == vin) return vehicle.displayName;
  }
  return null;
}

/// A la place du pilotage quand le vehicule affiche n'est pas le vehicule
/// pilote (un seul a la fois) : le dit, et permet de piloter celui-ci a la
/// place.
class PilotedVehicleCard extends ConsumerStatefulWidget {
  const PilotedVehicleCard({super.key});

  @override
  ConsumerState<PilotedVehicleCard> createState() => _PilotedVehicleCardState();
}

class _PilotedVehicleCardState extends ConsumerState<PilotedVehicleCard> {
  bool _switching = false;

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedVehicleProvider);
    if (selected == null) return const SizedBox.shrink();
    final piloted = pilotedVehicleName(ref) ?? 'un autre véhicule';

    return DashboardCard(
      title: 'Véhicule non piloté',
      icon: Icons.swap_horiz_rounded,
      help: 'L\'app pilote un seul véhicule à la fois : plages envoyées, programme dédié, charge immédiate et '
          'objectif exceptionnel valent pour lui seul.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Le pilotage est réglé pour $piloted. Pour le retrouver, sélectionnez-le en haut de l\'écran.',
            style: hintStyle,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.swap_horiz_rounded, color: AppColors.accent),
            label: Text('Piloter ${selected.displayName} à la place'),
            onPressed: _switching ? null : () => _switch(selected, piloted),
          ),
        ],
      ),
    );
  }

  Future<void> _switch(Vehicle vehicle, String piloted) async {
    final name = vehicle.displayName;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Piloter $name ?'),
        content: Text(
          'Le pilotage de $piloted s\'arrête : l\'envoi auto est coupé, et ce qui lui a déjà été envoyé y reste.\n\n'
          'À régler à nouveau pour $name : programme dédié, batterie et objectif exceptionnel. Plages, agendas, '
          'seuils de charge et délai d\'envoi sont gardés.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Piloter')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _switching = true);
    final refusal = await ref.read(chargePlanConfigProvider.notifier).switchVehicle(vehicle);
    if (!mounted) return;
    setState(() => _switching = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(refusal ?? 'Pilotage réglé pour $name : choisissez son programme dédié dans les réglages.'),
    ));
  }
}
