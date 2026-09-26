import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/charge_plan/charge_planner.dart';
import '../../../core/models/charge_plan_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatting.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../../home_tab.dart';
import '../../vehicle_status/vehicle_status_providers.dart';
import '../charge_plan_pickers.dart';
import '../charge_plan_providers.dart';

/// Resume du pilotage sur l'onglet Etat : prochaine charge, objectif, etat
/// du pilotage automatique. Un appui ouvre l'onglet Pilotage.
class PilotSummaryCard extends ConsumerWidget {
  const PilotSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(chargePlanConfigProvider).valueOrNull;
    if (config == null) return const SizedBox.shrink();
    final soc = ref.watch(batteryStatusProvider).valueOrNull?.batteryLevel;
    final pilotState = config.enabled ? ref.watch(pilotStateProvider).valueOrNull : null;

    return GestureDetector(
      onTap: () => ref.read(homeTabProvider.notifier).state = HomeTab.pilot,
      child: DashboardCard(
        title: 'Pilotage de charge',
        icon: Icons.bolt_outlined,
        child: Row(
          children: [
            Expanded(child: _content(config, soc, pendingConfirmation: pilotState?.pendingId != null)),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _content(ChargePlanConfig config, int? soc, {required bool pendingConfirmation}) {
    final hasWindows = config.calendar.days.values.any((d) => d.allDay || d.windows.isNotEmpty);
    if (!hasWindows) {
      return const Text(
        'Pas encore configuré : définissez vos heures creuses dans Réglages.',
        style: hintStyle,
      );
    }

    final now = DateTime.now();
    final planner = ChargePlanner(config);
    final inForce = planner.commandInForce(now, socPercent: soc);
    // La plage en vigueur tant qu'elle n'est pas terminee, sinon la suivante.
    final next = inForce != null && inForce.windowEnd.isAfter(now)
        ? inForce
        : planner.upcomingCommand(now, socPercent: soc);
    final charging = next != null && !next.windowStart.isAfter(now);
    final targets = planner.targets(now, now.add(const Duration(hours: 48)));
    final target = targets.isEmpty ? null : targets.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (next != null) ...[
          Text(charging ? 'Plage en cours' : 'Prochaine charge', style: hintStyle),
          const SizedBox(height: 2),
          Text(_window(next), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
        if (target != null) ...[
          const SizedBox(height: 6),
          Text(
            'Objectif : ${target.targetPercent} % ${formatDayTime(target.readyAt)}'
            '${target.climate ? ', climatisée à ${target.climateTemperature} °C' : ''}'
            '${target.isOneOff ? ' (exceptionnel)' : ''}',
          ),
        ],
        const SizedBox(height: 6),
        Text(
          !config.enabled
              ? 'Pilotage automatique désactivé'
              : config.safeMode
                  ? 'Pilotage automatique · mode sécurisé'
                  : 'Pilotage automatique',
          style: hintStyle,
        ),
        if (pendingConfirmation)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Une plage attend votre confirmation.',
              style: hintStyle.copyWith(color: AppColors.accent, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }

  static String _window(ChargeCommand command) => command.durationMinutes >= 1440
      ? '${formatDayTime(command.windowStart)} → 24 h'
      : '${formatDayTime(command.windowStart)} → ${formatTimeOfDay(command.windowEnd)}';
}
