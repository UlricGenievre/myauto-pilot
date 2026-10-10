import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../background/pilot_runtime.dart';
import '../../../core/models/charge_plan_config.dart';
import '../../../core/models/vehicle_support.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatting.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../../core/widgets/toggle_button.dart';
import '../../auth/auth_controller.dart';
import '../../vehicle/vehicle_providers.dart';
import '../charge_plan_pickers.dart';
import '../charge_plan_providers.dart';

/// Boutons du pilotage (envoi auto, mode securise) et etat d'execution :
/// prochain envoi, confirmation en attente, dernier resultat. L'aide ("?")
/// explique chaque bouton.
class AutoPilotCard extends ConsumerStatefulWidget {
  const AutoPilotCard({super.key, required this.config, required this.controller});

  final ChargePlanConfig config;
  final ChargePlanConfigController controller;

  @override
  ConsumerState<AutoPilotCard> createState() => _AutoPilotCardState();
}

class _AutoPilotCardState extends ConsumerState<AutoPilotCard> {
  @override
  Widget build(BuildContext context) {
    final config = widget.config;
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
    // Pourquoi l'envoi auto ne peut pas etre active (null : il peut l'etre).
    final blocker = canEnable || config.enabled
        ? null
        : demo
            ? 'Envoi auto non disponible en démonstration.'
            : !pilotSupported
                ? 'Envoi auto disponible sur le téléphone uniquement.'
                : !support.canWrite
                    ? 'Modèle de véhicule non pris en charge pour l\'envoi auto.'
                    : 'Pour l\'envoi auto, définissez d\'abord ${missing.join(' et ')}.';

    return DashboardCard(
      title: 'Pilotage automatique',
      icon: Icons.autorenew_rounded,
      help: 'Envoi auto des plages : la plage est envoyée à la voiture $leadText avant chaque plage d\'heures '
          'creuses.\n\n'
          '${support.forcesSafeMode ? 'Mode sécurisé : obligatoire tant que votre modèle n\'est pas vérifié, chaque '
              'envoi attend votre confirmation.' : 'Mode sécurisé : chaque envoi est proposé par notification et n\'est '
              'fait qu\'après votre confirmation. Il s\'applique aussi à la charge immédiate (confirmation dans '
              'l\'app).'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ToggleButton(
                  label: 'Envoi auto',
                  value: config.enabled,
                  onChanged: canEnable || config.enabled ? _setEnabled : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ToggleButton(
                  label: 'Mode sécurisé',
                  value: config.safeMode || support.forcesSafeMode,
                  locked: support.forcesSafeMode,
                  onChanged: (on) => widget.controller.edit((c) => c.copyWith(safeMode: on)),
                ),
              ),
            ],
          ),
          if (blocker != null) ...[
            const SizedBox(height: 8),
            Text(blocker, style: hintStyle),
          ],
          if (support.forcesSafeMode) ...[
            const SizedBox(height: 8),
            const Text('Mode sécurisé imposé tant que votre modèle n\'est pas vérifié.', style: hintStyle),
          ],
          if (config.enabled && pilotSupported) ...[
            _PermissionWarnings(safeMode: config.effectiveSafeMode),
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider()),
            _PilotStatus(safeMode: config.effectiveSafeMode),
          ],
        ],
      ),
    );
  }

  Future<void> _setEnabled(bool on) async {
    final vehicle = ref.read(selectedVehicleProvider);
    final vin = vehicle?.vin;
    if (on) {
      if (vin == null) return;
      final granted = await requestPilotPermissions();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Notifications refusées : le mode sécurisé ne pourra pas vous demander de confirmation.'),
        ));
      }
      if (!await exactAlarmsAllowed() && mounted) await _askExactAlarms(context);
    }
    await widget.controller.edit((c) => c.copyWith(enabled: on, vehicleVin: vin, vehicleModelCode: vehicle?.modelCode));
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

/// Alertes si une autorisation Android dont depend le pilotage manque, avec
/// un bouton pour la donner. Reverifie au retour dans l'app (l'utilisateur a
/// pu changer les reglages Android entre-temps) ; reveils exacts retrouves :
/// reprogrammation immediate.
class _PermissionWarnings extends ConsumerStatefulWidget {
  const _PermissionWarnings({required this.safeMode});

  final bool safeMode;

  @override
  ConsumerState<_PermissionWarnings> createState() => _PermissionWarningsState();
}

class _PermissionWarningsState extends ConsumerState<_PermissionWarnings> {
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
    ref.invalidate(notificationsAllowedProvider);
    final exactBefore = ref.read(exactAlarmsAllowedProvider).value;
    ref.invalidate(exactAlarmsAllowedProvider);
    final exactNow = await ref.read(exactAlarmsAllowedProvider.future);
    if (exactNow && exactBefore == false) await refreshPilot(ref.invalidate);
  }

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(notificationsAllowedProvider).value;
    final exactAlarms = ref.watch(exactAlarmsAllowedProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (notifications == false)
          _warning(
            Icons.notifications_off_outlined,
            widget.safeMode
                ? 'Notifications désactivées : les plages à confirmer ne s\'affichent pas, rien ne sera envoyé.'
                : 'Notifications désactivées : vous ne serez pas informé du résultat des envois.',
            requestNotifications,
          ),
        if (exactAlarms == false)
          _warning(
            Icons.alarm_off_rounded,
            'Réveils à l\'heure exacte non autorisés : les envois peuvent être retardés par Android.',
            requestExactAlarms,
          ),
      ],
    );
  }

  Widget _warning(IconData icon, String text, Future<bool> Function() request) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: hintStyle),
                TextButton(
                  onPressed: () async {
                    await request();
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
    final state = ref.watch(pilotStateProvider).value;
    if (state == null) return const SizedBox(height: 40, child: Center(child: CircularProgressIndicator()));
    final pending = state.pendingId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state.nextWakeAt != null ? 'Prochain envoi : ${formatDayTime(state.nextWakeAt!)}' : 'Aucun envoi programmé.',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (state.boostProposed) ...[
          const SizedBox(height: 8),
          Text('Batterie sous le minimum, voiture branchée (voir la notification).',
              style: hintStyle.copyWith(color: AppColors.accent)),
          Row(
            children: [
              TextButton(
                onPressed: () async {
                  await confirmMinimumCharge();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Charge immédiate en cours d\'envoi : le résultat arrivera par notification.'),
                    ));
                  }
                  ref.invalidate(pilotStateProvider);
                },
                style: TextButton.styleFrom(foregroundColor: AppColors.accent),
                child: const Text('Déclencher la charge'),
              ),
              TextButton(
                onPressed: () async {
                  await ignoreMinimumCharge();
                  ref.invalidate(pilotStateProvider);
                },
                child: const Text('Ignorer'),
              ),
            ],
          ),
        ],
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
