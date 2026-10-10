import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../background/pilot_runtime.dart';
import '../../../core/charge_plan/charge_planner.dart';
import '../../../core/charge_plan/pilot_state.dart';
import '../../../core/models/charge_plan_config.dart';
import '../../../core/models/vehicle_schedule.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatting.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../schedule/schedule_providers.dart';
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
    final soc = ref.watch(batteryStatusProvider).value?.batteryLevel;
    final now = DateTime.now();
    final planner = ChargePlanner(config);
    final inForce = planner.commandInForce(now, socPercent: soc);
    final upcoming = planner.upcomingCommand(now, socPercent: soc);
    final state = config.enabled ? ref.watch(pilotStateProvider).value : null;
    final sent = state?.sent;
    final inForceSent = inForce != null && (sent?.covers(inForce, config.fingerprint) ?? false);
    // Plage envoyee remplacee depuis (MyRenault...) : pendant une charge
    // immediate, c'est elle qui est dans la voiture, rien a signaler.
    final carSchedule = ref.watch(vehicleScheduleProvider).value;
    final boost = state?.boost;
    final boostActive =
        boost != null && boost.activeAt(now) && (carSchedule == null || boost.inCar(carSchedule) != false);
    final changedOutside =
        inForceSent && !boostActive && carSchedule != null && _differs(carSchedule, sent!) ? carSchedule : null;

    return DashboardCard(
      title: 'Charge pilotée',
      icon: Icons.insights_outlined,
      child: inForce == null && upcoming == null
          ? const Text('Définissez des plages de charge pour voir le calcul.', style: hintStyle)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (inForce != null) _CommandSummary(label: 'En vigueur', command: inForce, sent: inForceSent),
                if (changedOutside != null)
                  _ChangedOutside(car: changedOutside, resending: state!.confirmedId == sent!.id),
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

/// La plage de la voiture n'est plus celle envoyee ([sent]) ; faux si l'une
/// des deux est illisible.
bool _differs(VehicleSchedule car, CommandMark sent) {
  final start = sent.windowStart;
  final duration = sent.durationMinutes;
  return start != null && duration != null && car.hasChargeWindow(start, duration) == false;
}

/// Plage modifiee hors app : laquelle, et un bouton pour renvoyer celle de
/// l'app. Pour garder la modification, il suffit de ne rien faire (le
/// prochain envoi prevu la remplacera).
class _ChangedOutside extends StatelessWidget {
  const _ChangedOutside({required this.car, required this.resending});

  final VehicleSchedule car;
  final bool resending;

  @override
  Widget build(BuildContext context) {
    final start = ClockTime.tryParse(car.chargeWindowStart)!;
    final duration = car.chargeWindowDurationMinutes!;
    final window = duration == 1440
        ? '00:00 → 00:00 (24 h)'
        : '${start.format()} → ${ClockTime((start.minutes + duration) % 1440).format()}';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Modifié hors app avec $window.', style: hintStyle.copyWith(color: AppColors.accent)),
          if (resending)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Renvoi en cours…', style: hintStyle),
            )
          else
            Consumer(
              builder: (context, ref, _) => TextButton.icon(
                icon: const Icon(Icons.replay_rounded, color: AppColors.accent),
                label: const Text('Renvoyer'),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () async {
                  await resendPilotCommand();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Renvoi en cours : le résultat arrivera par notification.'),
                    ));
                  }
                  ref.invalidate(pilotStateProvider);
                },
              ),
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
