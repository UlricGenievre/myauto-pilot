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
      child: inForce == null && upcoming == null && !boostActive
          ? const Text('Définissez des plages de charge pour voir le calcul.', style: hintStyle)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (boostActive)
                  _ImmediateSummary(boost: boost)
                else if (inForce != null)
                  _CommandSummary(
                    label: 'En vigueur',
                    command: inForce,
                    status: _inForceStatus(inForce, state, inForceSent),
                  ),
                if (changedOutside != null)
                  _ChangedOutside(car: changedOutside, resending: state!.confirmedId == sent!.id),
                if ((boostActive || inForce != null) && upcoming != null)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider()),
                if (upcoming != null)
                  _CommandSummary(
                    label: 'Prochain envoi',
                    command: upcoming,
                    // Deja dans la voiture : plage atteinte par une charge
                    // immediate prolongee jusqu'a sa fin.
                    status: (sent?.covers(upcoming, config.fingerprint) ?? false)
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

/// Ou en est l'envoi de la plage en vigueur ([pending] : a faire ou a
/// confirmer, mis en evidence).
({String text, bool pending}) _inForceStatus(ChargeCommand command, PilotState? state, bool sent) {
  if (state == null) return (text: 'Envoi ${formatDayTime(command.pushAt)}', pending: false);
  if (sent) {
    return (text: 'Envoyé ${formatDayTime(state.sent!.sentAt ?? command.pushAt, separator: ' à ')}', pending: false);
  }
  if (state.confirmedId == command.id) return (text: 'Envoi en cours…', pending: true);
  if (state.pendingId == command.id) return (text: 'À confirmer (voir la notification)', pending: true);
  if (state.ignoredId == command.id) return (text: 'Ignorée', pending: false);
  if (state.sentId == command.id) return (text: 'À renvoyer : le paramétrage a changé la plage', pending: true);
  return (text: 'À envoyer', pending: true);
}

String _window(DateTime start, DateTime end, int durationMinutes) => durationMinutes >= 1440
    ? '00:00 → 00:00 (24 h)'
    : '${formatTimeOfDay(start)} → ${formatTimeOfDay(end)}';

/// Charge immediate en cours : c'est sa plage qui est dans la voiture, a
/// la place de celle du calendrier.
class _ImmediateSummary extends StatelessWidget {
  const _ImmediateSummary({required this.boost});

  final ImmediateCharge boost;

  @override
  Widget build(BuildContext context) {
    final start = boost.windowStart;
    final target = boost.targetPercent;
    final displaced = boost.displaced;
    final displacedStart = displaced?.windowStart;
    final displacedDuration = displaced?.durationMinutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('EN VIGUEUR', style: hintStyle.copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          start != null
              ? 'Charge immédiate ${formatTimeOfDay(start)} → ${formatTimeOfDay(boost.end)}'
              : 'Charge immédiate jusqu\'à ${formatTimeOfDay(boost.end)}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (target != null) ...[
          const SizedBox(height: 2),
          Text(boost.manual ? 'Jusqu\'à $target %' : 'Jusqu\'au minimum de $target %'),
        ],
        const SizedBox(height: 2),
        Text('Envoyée ${formatDayTime(boost.sentAt, separator: ' à ')}', style: hintStyle),
        if (boost.merged)
          Text('Prolongée jusqu\'à la fin de la plage d\'heures creuses.', style: hintStyle.copyWith(color: AppColors.accent))
        else if (displacedStart != null && displacedDuration != null)
          Text(
            'Plage d\'heures creuses '
            '${_window(displacedStart, displacedStart.add(Duration(minutes: displacedDuration)), displacedDuration)} '
            'renvoyée à ${formatTimeOfDay(boost.end)}.',
            style: hintStyle.copyWith(color: AppColors.accent),
          ),
      ],
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
  const _CommandSummary({required this.label, required this.command, required this.status});

  final String label;
  final ChargeCommand command;

  /// Etat de l'envoi ([pending] : a faire ou a confirmer).
  final ({String text, bool pending}) status;

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
        Text(status.text, style: status.pending ? hintStyle.copyWith(color: AppColors.accent) : hintStyle),
        if (command.extendedMinutes > 0)
          Text('Élargie de ${command.extendedMinutes} min hors heures creuses pour tenir l\'objectif.',
              style: hintStyle.copyWith(color: AppColors.accent)),
        if (command.note != null) Text(command.note!, style: hintStyle.copyWith(color: AppColors.accent)),
      ],
    );
  }
}
