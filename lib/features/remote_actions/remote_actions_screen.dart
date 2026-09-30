import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/kamereon_client.dart';
import '../../core/models/hvac_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_formatting.dart';
import '../../core/widgets/action_control.dart';
import '../vehicle_status/vehicle_status_providers.dart';
import 'remote_actions_controller.dart';

class RemoteActionsScreen extends ConsumerWidget {
  const RemoteActionsScreen({super.key});

  static String? _hvacText(HvacStatus? hvac) {
    if (hvac == null) return null;
    String temp(double t) => '${t.toStringAsFixed(t % 1 == 0 ? 0 : 1).replaceAll('.', ',')} °C';
    return [
      if (hvac.isOn != null) hvac.isOn! ? 'En marche' : 'Arrêtée',
      if (hvac.internalTemperature != null) 'habitacle ${temp(hvac.internalTemperature!)}',
      if (hvac.externalTemperature != null) 'dehors ${temp(hvac.externalTemperature!)}',
      if (hvac.isStale() && (hvac.internalTemperature != null || hvac.externalTemperature != null))
        'mesuré ${formatRelativeDateTime(hvac.lastUpdated!)}',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(remoteActionsControllerProvider);
    final controller = ref.read(remoteActionsControllerProvider.notifier);
    final hvac = ref.watch(hvacStatusProvider).value;
    final hvacText = _hvacText(hvac);

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surfaceHigh,
      onRefresh: () async => ref.invalidate(hvacStatusProvider),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(state.error!, style: const TextStyle(color: AppColors.error)),
            ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.85,
            children: [
              ActionControl(
                icon: Icons.ac_unit_rounded,
                label: 'Préclimatisation',
                status: hvacText == null || hvacText.isEmpty ? null : hvacText,
                isPending: state.isPending(VehicleAction.hvacStart) || state.isPending(VehicleAction.hvacStop),
                onStart: () => controller.trigger(VehicleAction.hvacStart),
                onStop: () => controller.trigger(VehicleAction.hvacStop),
              ),
              ActionControl(
                icon: Icons.bolt_rounded,
                label: 'Charge',
                isPending: state.isPending(VehicleAction.chargeStart) || state.isPending(VehicleAction.chargePause),
                onStart: () => controller.trigger(VehicleAction.chargeStart),
                onStop: () => controller.trigger(VehicleAction.chargePause),
              ),
              ActionControl(
                icon: Icons.campaign_outlined,
                label: 'Klaxon',
                status: 'Retrouver la voiture',
                startLabel: 'Klaxonner',
                isPending: state.isPending(VehicleAction.horn),
                onStart: () => controller.trigger(VehicleAction.horn),
              ),
              ActionControl(
                icon: Icons.highlight_outlined,
                label: 'Phares',
                status: 'Retrouver la voiture',
                startLabel: 'Faire clignoter',
                isPending: state.isPending(VehicleAction.lights),
                onStart: () => controller.trigger(VehicleAction.lights),
              ),
            ],
          ),
          if (hvac?.socThreshold case final threshold?)
            Padding(
              padding: const EdgeInsets.only(top: 16, left: 4),
              child: Text(
                'La voiture refuse de climatiser sous $threshold % de batterie (hors charge).',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}
