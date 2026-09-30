import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/charge_plan/charge_planner.dart';
import '../../../core/models/charge_plan_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatting.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../vehicle_status/vehicle_status_providers.dart';
import '../charge_plan_pickers.dart';
import '../charge_plan_providers.dart';

/// Ce que l'app envoie (ou enverra) a la voiture avec le parametrage actuel :
/// plage en vigueur et prochain envoi.
class PreviewCard extends ConsumerWidget {
  const PreviewCard({super.key, required this.config});

  final ChargePlanConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final soc = ref.watch(batteryStatusProvider).valueOrNull?.batteryLevel;
    final now = DateTime.now();
    final planner = ChargePlanner(config);
    final inForce = planner.commandInForce(now, socPercent: soc);
    final upcoming = planner.upcomingCommand(now, socPercent: soc);
    final sent = config.enabled ? ref.watch(pilotStateProvider).valueOrNull?.sent : null;
    final inForceSent = inForce != null && (sent?.covers(inForce, config.fingerprint) ?? false);

    return DashboardCard(
      title: 'Charge pilotée',
      icon: Icons.insights_outlined,
      child: inForce == null && upcoming == null
          ? const Text('Définissez des plages de charge pour voir le calcul.', style: hintStyle)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (inForce != null) _CommandSummary(label: 'En vigueur', command: inForce, sent: inForceSent),
                if (inForce != null && upcoming != null)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider()),
                if (upcoming != null) _CommandSummary(label: 'Prochain envoi', command: upcoming),
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

class _CommandSummary extends StatelessWidget {
  const _CommandSummary({required this.label, required this.command, this.sent = false});

  final String label;
  final ChargeCommand command;

  /// Deja envoyee a la voiture (a son heure d'envoi prevue).
  final bool sent;

  @override
  Widget build(BuildContext context) {
    final target = command.target;
    final window = command.durationMinutes >= 1440
        ? 'Charge 00:00 → 00:00 (24 h)'
        : 'Charge ${formatDayTime(command.windowStart)} → ${formatTimeOfDay(command.windowEnd)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: hintStyle.copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(window, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (!command.defaultReadyAt) ...[
          const SizedBox(height: 2),
          Text(
            'Prête à ${formatDayTime(command.readyAt)}'
            '${target != null ? ' · objectif ${target.targetPercent} %${target.isOneOff ? ' (exceptionnel)' : ''}' : ''}'
            '${command.climate ? ' · climatisée à ${command.climateTemperature} °C' : ''}',
          ),
        ],
        const SizedBox(height: 2),
        Text(
          sent ? 'Envoyé ${formatDayTime(command.pushAt, separator: ' à ')}' : 'Envoi ${formatDayTime(command.pushAt)}',
          style: hintStyle,
        ),
        if (command.extendedMinutes > 0)
          Text('Élargie de ${command.extendedMinutes} min hors heures creuses pour tenir l\'objectif.',
              style: hintStyle.copyWith(color: AppColors.accent)),
        if (command.note != null) Text(command.note!, style: hintStyle.copyWith(color: AppColors.accent)),
      ],
    );
  }
}
