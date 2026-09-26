import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/kamereon_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/action_control.dart';
import 'remote_actions_controller.dart';

class RemoteActionsScreen extends ConsumerWidget {
  const RemoteActionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(remoteActionsControllerProvider);
    final controller = ref.read(remoteActionsControllerProvider.notifier);

    return ListView(
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
          childAspectRatio: 0.95,
          children: [
            ActionControl(
              icon: Icons.ac_unit_rounded,
              label: 'Préclimatisation',
              isPending: state.isPending(VehicleAction.hvacStart),
              onStart: () => controller.trigger(VehicleAction.hvacStart),
              onStop: () => controller.trigger(VehicleAction.hvacStop),
            ),
            ActionControl(
              icon: Icons.bolt_rounded,
              label: 'Charge',
              isPending: state.isPending(VehicleAction.chargeStart),
              onStart: () => controller.trigger(VehicleAction.chargeStart),
              onStop: () => controller.trigger(VehicleAction.chargePause),
            ),
          ],
        ),
      ],
    );
  }
}
