import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../background/pilot_runtime.dart';
import '../../../core/charge_plan/charge_planner.dart';
import '../../../core/charge_plan/pilot_state.dart';
import '../../../core/models/battery_status.dart';
import '../../../core/models/charge_plan_config.dart';
import '../../../core/models/vehicle_support.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatting.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../auth/auth_controller.dart';
import '../../vehicle/vehicle_providers.dart';
import '../../vehicle_status/vehicle_status_providers.dart';
import '../charge_plan_pickers.dart';
import '../charge_plan_providers.dart';

/// Charge immediate jusqu'a un niveau choisi, pilotage automatique actif ou
/// non, sans confirmation. Affiche aussi la charge immediate en cours (y
/// compris celle jusqu'au minimum), avec un bouton pour l'arreter.
class ImmediateChargeCard extends ConsumerStatefulWidget {
  const ImmediateChargeCard({super.key, required this.config, required this.controller});

  final ChargePlanConfig config;
  final ChargePlanConfigController controller;

  @override
  ConsumerState<ImmediateChargeCard> createState() => _ImmediateChargeCardState();
}

class _ImmediateChargeCardState extends ConsumerState<ImmediateChargeCard> {
  late int _target = widget.config.maxChargePercent ?? 100;

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final state = ref.watch(pilotStateProvider).value;
    final now = DateTime.now();
    final boost = state?.boost;
    final active = boost != null && boost.activeAt(now) ? boost : null;

    return DashboardCard(
      title: 'Charge immédiate',
      icon: Icons.bolt_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (active != null)
            ..._active(active, config)
          else if (state?.manualChargeTarget != null)
            Text('Charge jusqu\'à ${state!.manualChargeTarget} % en cours d\'envoi à la voiture…',
                style: hintStyle.copyWith(color: AppColors.accent))
          else
            ..._form(config, now),
          // Pilotage actif : le resultat est affiche dans sa carte.
          if (!config.enabled && state?.lastResult != null) ...[
            const SizedBox(height: 8),
            _LastResult(state: state!),
          ],
        ],
      ),
    );
  }

  List<Widget> _active(ImmediateCharge active, ChargePlanConfig config) => [
        Text(
          'En cours jusqu\'à ${formatTimeOfDay(active.end)}'
          '${active.targetPercent != null ? ', ${active.manual ? 'pour atteindre' : 'jusqu\'au minimum de'} ${active.targetPercent} %' : ''}.',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          active.merged
              ? 'Prolongée jusqu\'à la fin de la plage d\'heures creuses.'
              : config.enabled && active.displaced != null
                  ? 'La plage d\'heures creuses sera renvoyée ensuite.'
                  : 'Les réglages de charge d\'avant seront remis ensuite.',
          style: hintStyle,
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.stop_circle_outlined, color: AppColors.accent),
          label: const Text('Arrêter'),
          onPressed: () async {
            await stopImmediateCharge();
            _snack('Arrêt en cours : le résultat arrivera par notification.');
            ref.invalidate(pilotStateProvider);
          },
        ),
      ];

  List<Widget> _form(ChargePlanConfig config, DateTime now) {
    final battery = ref.watch(batteryStatusProvider).value;
    final soc = battery?.batteryLevel;
    final vehicle = ref.watch(selectedVehicleProvider);
    final support = VehicleSupport.of(vehicle?.modelCode ?? config.vehicleModelCode);
    final demo = ref.watch(demoModeProvider);
    final plan = soc == null
        ? null
        : ChargePlanner(config)
            .immediateCharge(now, socPercent: soc, targetPercent: _target, mergeWithWindows: config.enabled);

    final blocker = demo
        ? 'Non disponible en démonstration.'
        : !pilotSupported
            ? 'Disponible sur le téléphone uniquement.'
            : !support.canWrite
                ? 'Modèle de véhicule non pris en charge pour l\'écriture.'
                : config.dedicatedProgramIndex == null
                    ? 'Choisissez d\'abord le programme dédié (Réglages).'
                    : config.batteryCapacityKwh == null || config.chargePowerKw == null
                        ? 'Renseignez d\'abord la capacité de la batterie et la puissance de charge (Réglages).'
                        : soc == null
                            ? 'Niveau de batterie inconnu.'
                            : battery!.plugState != PlugState.plugged
                                ? 'Voiture non branchée.'
                                : soc >= _target
                                    ? 'Batterie déjà à $soc %.'
                                    : null;

    return [
      const Text('Lance la charge maintenant, même en heures pleines, jusqu\'au niveau choisi.', style: hintStyle),
      const SizedBox(height: 8),
      PercentSlider(value: _target, onChanged: (p) => setState(() => _target = p)),
      Text(
        blocker ??
            'Batterie à $soc % : fin vers ${formatTimeOfDay(plan!.command.windowEnd)}'
                '${plan.mergedWith != null ? ', prolongée jusqu\'à la fin de la plage d\'heures creuses' : ''}.',
        style: hintStyle.copyWith(color: blocker == null ? AppColors.textSecondary : AppColors.error),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        icon: const Icon(Icons.bolt_rounded, color: AppColors.accent),
        label: const Text('Charger maintenant'),
        onPressed: blocker != null || plan == null ? null : () => _start(vehicle?.vin, vehicle?.modelCode, soc!, plan),
      ),
    ];
  }

  Future<void> _start(String? vin, String? modelCode, int soc, ImmediateChargePlan plan) async {
    if (widget.config.effectiveSafeMode && !await _confirm(soc, plan)) return;
    // Vehicule a ecrire : celui du pilotage, renseigne ici s'il n'a jamais
    // ete active (les reveils tournent sans "vehicule selectionne").
    if (vin != null && (widget.config.vehicleVin != vin || widget.config.vehicleModelCode != modelCode)) {
      await widget.controller.edit((c) => c.copyWith(vehicleVin: vin, vehicleModelCode: modelCode));
    }
    await requestPilotPermissions();
    await startImmediateCharge(_target);
    _snack('Charge immédiate en cours d\'envoi : le résultat arrivera par notification.');
    ref.invalidate(pilotStateProvider);
  }

  /// Mode securise : meme contenu qu'une proposition par notification, dans
  /// l'app puisqu'elle est ouverte. Le calcul est refait a l'envoi avec le
  /// niveau du moment.
  Future<bool> _confirm(int soc, ImmediateChargePlan plan) async {
    final config = widget.config;
    final sent = ref.read(pilotStateProvider).value?.sent;
    final command = plan.command;
    final start = formatTimeOfDay(DateTime.now());
    final end = formatTimeOfDay(command.windowEnd);
    final lines = [
      'Batterie à $soc %, voiture branchée. Lancer la charge pour atteindre $_target % ?',
      if (plan.mergedWith != null)
        'Charge immédiate de $start à $end, prolongée jusqu\'à la fin de la plage d\'heures creuses.'
      else ...[
        'Charge immédiate de $start à $end environ, en heures pleines.',
        if (!config.enabled)
          'Les réglages de charge d\'avant seront ensuite remis automatiquement.'
        else if (sent != null && !sent.id.startsWith(ChargePlanner.immediateIdPrefix))
          'La plage d\'heures creuses sera ensuite renvoyée automatiquement.',
      ],
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Charge immédiate à lancer'),
        content: Text(lines.join('\n\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lancer')),
        ],
      ),
    );
    return ok == true;
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _LastResult extends StatelessWidget {
  const _LastResult({required this.state});

  final PilotState state;

  @override
  Widget build(BuildContext context) {
    final ok = state.lastResultOk == true;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(ok ? Icons.check_circle_outline : Icons.error_outline,
            size: 18, color: ok ? AppColors.success : AppColors.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${state.lastResultAt != null ? '${formatDayTime(state.lastResultAt!)} · ' : ''}${state.lastResult}',
            style: hintStyle,
          ),
        ),
      ],
    );
  }
}
