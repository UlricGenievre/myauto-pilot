import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/charge_plan_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../schedule/schedule_providers.dart';
import '../charge_plan_pickers.dart';
import '../charge_plan_providers.dart';

class DedicatedProgramCard extends ConsumerWidget {
  const DedicatedProgramCard({super.key, required this.config, required this.controller});

  final ChargePlanConfig config;
  final ChargePlanConfigController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSchedule = ref.watch(vehicleScheduleProvider);
    return DashboardCard(
      title: 'Programme dédié',
      icon: Icons.schedule_outlined,
      child: asyncSchedule.when(
        loading: () => const SizedBox(height: 60, child: Center(child: CircularProgressIndicator())),
        error: (error, _) => Text('Erreur : $error', style: const TextStyle(color: AppColors.error)),
        data: (schedule) {
          if (schedule == null || schedule.programs.isEmpty) {
            return const Text('Aucun programme lu sur le véhicule.', style: hintStyle);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Le programme que l\'app pourra modifier (heure "prête à"). Les autres ne seront jamais touchés.',
                style: hintStyle,
              ),
              const SizedBox(height: 4),
              RadioGroup<int>(
                groupValue: config.dedicatedProgramIndex,
                onChanged: (index) {
                  if (index != null) controller.edit((c) => c.copyWith(dedicatedProgramIndex: index));
                },
                child: Column(
                  children: [
                    for (var i = 0; i < schedule.programs.length; i++)
                      RadioListTile<int>(
                        value: i,
                        contentPadding: EdgeInsets.zero,
                        activeColor: AppColors.accent,
                        title: Text(
                          'Programme ${i + 1} · prête à ${ClockTime.tryParse(schedule.programs[i].departureTime)?.format() ?? '?'}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        secondary: StatusPill(isActive: schedule.programs[i].isActive),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
