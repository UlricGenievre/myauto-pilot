import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/charge_plan/charge_planner.dart';
import '../../../core/models/charge_plan_config.dart';
import '../../../core/utils/date_formatting.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../vehicle_status/vehicle_status_providers.dart';
import '../charge_plan_pickers.dart';
import 'in_force_summary.dart';

/// Ce que l'app envoie (ou enverra) a la voiture avec le parametrage actuel :
/// plage en vigueur et prochain envoi.
class PreviewCard extends ConsumerWidget {
  const PreviewCard({super.key, required this.config});

  final ChargePlanConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final soc = ref.watch(batteryStatusProvider).value?.batteryLevel;
    final now = DateTime.now();
    final view = InForceView.watch(ref, config, soc: soc, now: now);
    final upcoming = ChargePlanner(config).upcomingCommand(now, socPercent: soc);

    return DashboardCard(
      title: 'Charge pilotée',
      icon: Icons.insights_outlined,
      child: view.isEmpty && upcoming == null
          ? const Text('Définissez des plages de charge pour voir le calcul.', style: hintStyle)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InForceSummary(view: view),
                if (!view.isEmpty && upcoming != null)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider()),
                if (upcoming != null)
                  CommandSummary(
                    label: 'Prochain envoi',
                    command: upcoming,
                    // Deja dans la voiture : plage atteinte par une charge
                    // immediate prolongee jusqu'a sa fin.
                    status: (view.state?.sent?.covers(upcoming, config.fingerprint) ?? false)
                        ? (text: 'Déjà envoyée avec la charge immédiate', pending: false)
                        : (text: 'Envoi ${formatDayTime(upcoming.pushAt)}', pending: false),
                  ),
                const SizedBox(height: 12),
                Text(
                  soc != null ? 'Calcul fait avec une batterie à $soc %.' : 'Niveau de batterie inconnu.',
                  style: hintStyle,
                ),
              ],
            ),
    );
  }
}
