import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../background/pilot_runtime.dart';
import '../../../core/models/charge_plan_config.dart';
import '../../../core/models/vehicle_support.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatting.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../auth/auth_controller.dart';
import '../../vehicle/vehicle_providers.dart';
import '../charge_plan_pickers.dart';
import '../charge_plan_providers.dart';

/// Interrupteurs du pilotage (actif, mode securise) et etat d'execution :
/// prochain envoi, confirmation en attente, dernier resultat.
class AutoPilotCard extends ConsumerWidget {
  const AutoPilotCard({super.key, required this.config, required this.controller});

  final ChargePlanConfig config;
  final ChargePlanConfigController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasWindows = config.calendar.days.values.any((d) => d.allDay || d.windows.isNotEmpty);
    final missing = [
      if (!hasWindows) 'des plages de charge',
      if (config.dedicatedProgramIndex == null) 'le programme dédié',
    ];
    final vehicle = ref.watch(selectedVehicleProvider);
    final support = VehicleSupport.of(vehicle?.modelCode ?? config.vehicleModelCode);
    final demo = ref.watch(demoModeProvider);
    final canEnable = pilotSupported && !demo && missing.isEmpty && support.canWrite;
    final lead = config.pushLeadMinutes;
    final leadText = lead % 60 == 0 ? '${lead ~/ 60} h' : '${lead ~/ 60} h ${(lead % 60).toString().padLeft(2, '0')}';

    return DashboardCard(
      title: 'Pilotage automatique',
      icon: Icons.autorenew_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: config.enabled,
            activeTrackColor: AppColors.accent,
            onChanged: canEnable || config.enabled ? (on) => _setEnabled(context, ref, on) : null,
            title: const Text('Envoyer les plages de charge automatiquement'),
            subtitle: Text(
              demo
                  ? 'Non disponible en démonstration : aucun envoi n\'est programmé.'
                  : !pilotSupported
                  ? 'Disponible sur le téléphone uniquement (réveils et notifications Android).'
                  : !support.canWrite
                      ? 'Modèle de véhicule non pris en charge pour le pilotage.'
                      : missing.isNotEmpty
                          ? 'Définissez d\'abord ${missing.join(' et ')}.'
                          : 'La plage est envoyée à la voiture $leadText avant chaque plage d\'heures creuses.',
              style: hintStyle,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: config.safeMode || support.forcesSafeMode,
            activeTrackColor: AppColors.accent,
            onChanged: support.forcesSafeMode ? null : (on) => controller.edit((c) => c.copyWith(safeMode: on)),
            title: const Text('Mode sécurisé'),
            subtitle: Text(
              support.forcesSafeMode
                  ? 'Obligatoire tant que votre modèle n\'est pas vérifié : chaque envoi attend votre confirmation.'
                  : 'Chaque envoi est proposé par notification et n\'est fait qu\'après votre confirmation.',
              style: hintStyle,
            ),
          ),
          if (config.enabled && pilotSupported) ...[
            const _ExactAlarmWarning(),
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider()),
            _PilotStatus(safeMode: config.effectiveSafeMode),
          ],
        ],
      ),
    );
  }

  Future<void> _setEnabled(BuildContext context, WidgetRef ref, bool on) async {
    final vehicle = ref.read(selectedVehicleProvider);
    final vin = vehicle?.vin;
    if (on) {
      if (vin == null) return;
      final granted = await requestPilotPermissions();
      if (!granted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Notifications refusées : le mode sécurisé ne pourra pas vous demander de confirmation.'),
        ));
      }
      if (!await exactAlarmsAllowed() && context.mounted) await _askExactAlarms(context);
    }
    await controller.edit((c) => c.copyWith(enabled: on, vehicleVin: vin, vehicleModelCode: vehicle?.modelCode));
    await refreshPilot(ref.invalidate);
  }
}

/// Explique puis ouvre le reglage Android "Alarmes et rappels".
Future<void> _askExactAlarms(BuildContext context) async {
  final open = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Envois à l\'heure exacte'),
      content: const Text(
        'Pour envoyer chaque plage à l\'heure prévue, même téléphone en veille, autorisez MyAuto Pilot dans '
        'le réglage Android « Alarmes et rappels ». Sans cette autorisation, les envois peuvent être retardés.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Plus tard')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ouvrir le réglage')),
      ],
    ),
  );
  if (open == true) await requestExactAlarms();
}

/// Alerte si les reveils exacts ne sont pas autorises. Reverifie au retour
/// dans l'app (l'utilisateur a pu changer le reglage Android entre-temps) et
/// reprogramme alors les reveils en exact.
class _ExactAlarmWarning extends ConsumerStatefulWidget {
  const _ExactAlarmWarning();

  @override
  ConsumerState<_ExactAlarmWarning> createState() => _ExactAlarmWarningState();
}

class _ExactAlarmWarningState extends ConsumerState<_ExactAlarmWarning> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _recheck);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _recheck() async {
    final before = ref.read(exactAlarmsAllowedProvider).valueOrNull;
    ref.invalidate(exactAlarmsAllowedProvider);
    final now = await ref.read(exactAlarmsAllowedProvider.future);
    if (now && before == false) await refreshPilot(ref.invalidate);
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(exactAlarmsAllowedProvider).valueOrNull != false) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.alarm_off_rounded, size: 18, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Réveils à l\'heure exacte non autorisés : les envois peuvent être retardés par Android.',
                  style: hintStyle,
                ),
                TextButton(
                  onPressed: () async {
                    await requestExactAlarms();
                    await _recheck();
                  },
                  style: TextButton.styleFrom(foregroundColor: AppColors.accent, padding: EdgeInsets.zero),
                  child: const Text('Autoriser'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PilotStatus extends ConsumerWidget {
  const _PilotStatus({required this.safeMode});

  final bool safeMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pilotStateProvider).valueOrNull;
    if (state == null) return const SizedBox(height: 40, child: Center(child: CircularProgressIndicator()));
    final pending = state.pendingId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state.nextWakeAt != null ? 'Prochain envoi : ${formatDayTime(state.nextWakeAt!)}' : 'Aucun envoi programmé.',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (pending != null && safeMode) ...[
          const SizedBox(height: 8),
          Text('Une plage attend votre confirmation (voir la notification).',
              style: hintStyle.copyWith(color: AppColors.accent)),
          Row(
            children: [
              TextButton(
                onPressed: () async {
                  await confirmPilotCommand(pending);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Envoi en cours : le résultat arrivera par notification.'),
                    ));
                  }
                  ref.invalidate(pilotStateProvider);
                },
                style: TextButton.styleFrom(foregroundColor: AppColors.accent),
                child: const Text('Envoyer'),
              ),
              TextButton(
                onPressed: () async {
                  await ignorePilotCommand(pending);
                  ref.invalidate(pilotStateProvider);
                },
                child: const Text('Ignorer'),
              ),
            ],
          ),
        ],
        if (state.lastResult != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                state.lastResultOk == true ? Icons.check_circle_outline : Icons.error_outline,
                size: 18,
                color: state.lastResultOk == true ? AppColors.success : AppColors.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${state.lastResultAt != null ? '${formatDayTime(state.lastResultAt!)} · ' : ''}${state.lastResult}',
                  style: hintStyle,
                ),
              ),
            ],
          ),
        ],
        TextButton.icon(
          icon: const Icon(Icons.refresh, color: AppColors.accent),
          label: const Text('Recalculer maintenant'),
          onPressed: () => refreshPilot(ref.invalidate),
        ),
      ],
    );
  }
}
