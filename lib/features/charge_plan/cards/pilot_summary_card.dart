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
import 'in_force_summary.dart';

/// Resume du pilotage sur l'onglet Etat : ce qui est en vigueur (meme bloc
/// que l'onglet Pilotage, bouton Renvoyer compris), prochain envoi,
/// objectif, etat du pilotage automatique. Un appui ouvre l'onglet
/// Pilotage.
class PilotSummaryCard extends ConsumerWidget {
  const PilotSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(chargePlanConfigProvider).value;
    if (config == null) return const SizedBox.shrink();
    final soc = ref.watch(batteryStatusProvider).value?.batteryLevel;
    final now = DateTime.now();
    final view = InForceView.watch(ref, config, soc: soc, now: now);

    return GestureDetector(
      onTap: () => ref.read(homeTabProvider.notifier).select(HomeTab.pilot),
      child: DashboardCard(
        title: 'Pilotage de charge',
        icon: Icons.bolt_outlined,
        child: Row(
          children: [
            Expanded(child: _content(config, soc, view, now)),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  /// Meme bloc "En vigueur" que l'onglet Pilotage (charge immediate, etat
  /// de l'envoi, plage modifiee hors app), puis le prochain envoi,
  /// l'objectif et le mode du pilotage.
  Widget _content(ChargePlanConfig config, int? soc, InForceView view, DateTime now) {
    final hasWindows = config.calendar.days.values.any((d) => d.allDay || d.windows.isNotEmpty);
    if (!hasWindows) {
      return const Text(
        'Pas encore configuré : définissez vos heures creuses dans Réglages.',
        style: hintStyle,
      );
    }

    final planner = ChargePlanner(config);
    final upcoming = planner.upcomingCommand(now, socPercent: soc);
    final targets = planner.targets(now, now.add(const Duration(hours: 48)));
    final target = targets.isEmpty ? null : targets.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InForceSummary(view: view),
        if (upcoming != null) ...[
          if (!view.isEmpty) const SizedBox(height: 8),
          Text('Prochain envoi ${formatDayTime(upcoming.pushAt)} : ${_window(upcoming)}', style: hintStyle),
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
              : config.effectiveSafeMode
                  ? 'Pilotage automatique · mode sécurisé'
                  : 'Pilotage automatique',
          style: hintStyle,
        ),
      ],
    );
  }

  static String _window(ChargeCommand command) => command.durationMinutes >= 1440
      ? '${formatDayTime(command.windowStart)} → 24 h'
      : '${formatDayTime(command.windowStart)} → ${formatTimeOfDay(command.windowEnd)}';
}
