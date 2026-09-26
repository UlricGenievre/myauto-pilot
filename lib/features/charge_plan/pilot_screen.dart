import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../schedule/schedule_providers.dart';
import '../schedule/vehicle_schedule_cards.dart';
import 'cards/auto_pilot_card.dart';
import 'cards/one_off_card.dart';
import 'cards/preview_card.dart';
import 'cards/vehicle_support_card.dart';
import 'charge_plan_providers.dart';

/// Onglet "Pilotage" : l'usage quotidien (ce qui va etre envoye, etat du
/// pilotage automatique, objectif exceptionnel) et ce que la voiture a
/// effectivement recu. Le parametrage de fond est dans Reglages (roue
/// dentee).
class PilotScreen extends ConsumerWidget {
  const PilotScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncConfig = ref.watch(chargePlanConfigProvider);

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surfaceHigh,
      onRefresh: () async {
        ref.invalidate(vehicleScheduleProvider);
        await refreshPilot(ref.invalidate);
      },
      child: asyncConfig.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error', style: const TextStyle(color: AppColors.error))),
        data: (config) {
          final controller = ref.read(chargePlanConfigProvider.notifier);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              const VehicleSupportCard(),
              PreviewCard(config: config),
              const SizedBox(height: 16),
              AutoPilotCard(config: config, controller: controller),
              const SizedBox(height: 16),
              OneOffCard(config: config, controller: controller),
              const SizedBox(height: 28),
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 12),
                child: Text('Dans la voiture', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              const VehicleScheduleCards(),
            ],
          );
        },
      ),
    );
  }
}
