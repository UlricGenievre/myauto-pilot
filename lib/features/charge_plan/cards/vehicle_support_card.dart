import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vehicle_support.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../vehicle/vehicle_providers.dart';
import '../charge_plan_pickers.dart';

/// Bandeau de l'onglet Pilotage pour un modele non verifie : pilotage en
/// mode securise impose (modele compatible) ou lecture seule. Rien pour un
/// modele verifie.
class VehicleSupportCard extends ConsumerWidget {
  const VehicleSupportCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicle = ref.watch(selectedVehicleProvider);
    if (vehicle == null) return const SizedBox.shrink();
    final support = VehicleSupport.of(vehicle.modelCode);
    if (support == VehicleSupport.verified) return const SizedBox.shrink();

    final code = vehicle.modelCode ?? 'inconnu';
    final compatible = support == VehicleSupport.compatible;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DashboardCard(
        title: compatible ? 'Modèle non encore vérifié' : 'Lecture seule',
        icon: compatible ? Icons.science_outlined : Icons.visibility_outlined,
        child: Text(
          compatible
              ? 'Votre ${vehicle.model} (code $code) utilise le même accès que les modèles vérifiés, mais le '
                  'pilotage n\'y a jamais été testé : chaque envoi vous sera proposé avant d\'être fait. '
                  'Signalez-nous si tout fonctionne pour que votre modèle soit ajouté aux modèles vérifiés.'
              : 'L\'app ne sait pas encore piloter la charge de votre ${vehicle.model} (code $code) : rien n\'est '
                  'envoyé à la voiture. Vous pouvez signaler votre modèle pour qu\'il soit étudié.',
          style: hintStyle.copyWith(color: compatible ? AppColors.accent : AppColors.textSecondary),
        ),
      ),
    );
  }
}
