import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/vehicle_schedule.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_formatting.dart';
import '../../core/widgets/dashboard_card.dart';
import '../../core/widgets/status_pill.dart';
import 'schedule_providers.dart';

/// Ce que la voiture a reellement recu (plage de charge + programmes), relu
/// sur `ev/settings`. Affiche en bas de l'onglet Pilotage.
class VehicleScheduleCards extends ConsumerWidget {
  const VehicleScheduleCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSchedule = ref.watch(vehicleScheduleProvider);
    return Column(
      children: [
        _ChargeWindowCard(asyncSchedule: asyncSchedule),
        const SizedBox(height: 16),
        _ProgramsCard(asyncSchedule: asyncSchedule),
      ],
    );
  }
}

class _ProgramsCard extends StatelessWidget {
  const _ProgramsCard({required this.asyncSchedule});

  final AsyncValue<VehicleSchedule?> asyncSchedule;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      title: 'Programmes',
      icon: Icons.schedule_outlined,
      child: asyncSchedule.when(
        data: (schedule) {
          if (schedule == null) {
            return const Text('Aucun véhicule sélectionné.', style: TextStyle(color: AppColors.textSecondary));
          }
          if (schedule.programs.isEmpty) {
            return const Text('Aucun programme configuré.', style: TextStyle(color: AppColors.textSecondary));
          }
          return Column(
            children: [
              for (var i = 0; i < schedule.programs.length; i++) ...[
                if (i > 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(),
                  ),
                _ProgramRow(program: schedule.programs[i]),
              ],
            ],
          );
        },
        loading: () => const SizedBox(height: 60, child: Center(child: CircularProgressIndicator())),
        error: (error, _) => Text('Erreur : $error', style: const TextStyle(color: AppColors.error)),
      ),
    );
  }
}

class _ProgramRow extends StatelessWidget {
  const _ProgramRow({required this.program});

  final VehicleProgram program;

  @override
  Widget build(BuildContext context) {
    final departure = parseTimeOfDay(program.departureTime);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              program.kind.includesClimate ? Icons.ac_unit_rounded : Icons.bolt_rounded,
              size: 18,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              departure != null ? 'Prête à ${formatTimeOfDay(departure)}' : 'Heure inconnue',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            StatusPill(isActive: program.isActive),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 26),
          child: Text(
            _kindLabel(program.kind),
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(height: 14),
        _WeekGrid(activeDays: program.activeDays),
      ],
    );
  }

  String _kindLabel(ProgramKind kind) {
    switch (kind) {
      case ProgramKind.charge:
        return 'Charge seule';
      case ProgramKind.preconditioning:
        return 'Préclimatisation seule';
      case ProgramKind.chargeAndPreconditioning:
        return 'Charge + préclimatisation';
      case ProgramKind.unknown:
        return 'Type inconnu';
    }
  }
}

class _ChargeWindowCard extends StatelessWidget {
  const _ChargeWindowCard({required this.asyncSchedule});

  final AsyncValue<VehicleSchedule?> asyncSchedule;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      title: 'Plage de charge',
      icon: Icons.bolt_outlined,
      help: 'Commune à tous les programmes. Active seulement si au moins un programme est actif.',
      child: asyncSchedule.when(
        data: (schedule) {
          if (schedule == null) {
            return const Text('Aucun véhicule sélectionné.', style: TextStyle(color: AppColors.textSecondary));
          }
          final start = parseTimeOfDay(schedule.chargeWindowStart);
          final end = addMinutesToTimeOfDay(schedule.chargeWindowStart, schedule.chargeWindowDurationMinutes);
          final hasActiveProgram = schedule.programs.any((p) => p.isActive);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    start != null && end != null
                        ? '${formatTimeOfDay(start)} → ${formatTimeOfDay(end)}'
                        : 'Heures inconnues',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const Spacer(),
                  StatusPill(
                    isActive: hasActiveProgram,
                    activeLabel: 'Active',
                    inactiveLabel: 'Inactive',
                  ),
                ],
              ),
            ],
          );
        },
        loading: () => const SizedBox(height: 60, child: Center(child: CircularProgressIndicator())),
        error: (error, _) => Text('Erreur : $error', style: const TextStyle(color: AppColors.error)),
      ),
    );
  }
}

/// Grille des 7 jours de la semaine (L-D), jour mis en avant quand le
/// programme/la plage s'y applique.
class _WeekGrid extends StatelessWidget {
  const _WeekGrid({required this.activeDays});

  final Set<int> activeDays;

  static const _dayLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(7, (index) {
        final day = index + 1;
        final active = activeDays.contains(day);
        return Expanded(
          child: Container(
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? AppColors.accent : AppColors.surfaceHigh,
            ),
            child: Text(
              _dayLetters[index],
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? AppColors.onAccent : AppColors.textSecondary,
              ),
            ),
          ),
        );
      }),
    );
  }
}
