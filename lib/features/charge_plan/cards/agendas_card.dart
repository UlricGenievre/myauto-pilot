import 'package:flutter/material.dart';

import '../../../core/models/charge_plan_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../agenda_editor_screen.dart';
import '../charge_plan_pickers.dart';
import '../charge_plan_providers.dart';

class AgendasCard extends StatelessWidget {
  const AgendasCard({super.key, required this.config, required this.controller});

  final ChargePlanConfig config;
  final ChargePlanConfigController controller;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      title: 'Agendas d\'objectifs',
      icon: Icons.event_repeat_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Un seul agenda actif à la fois. Touchez la pastille pour l\'activer.', style: hintStyle),
          const SizedBox(height: 8),
          for (final agenda in config.agendas)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(agenda.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(_summary(agenda), style: hintStyle),
              leading: GestureDetector(
                onTap: () => controller.edit(
                  (c) => c.activeAgendaId == agenda.id
                      ? c.copyWith(clearActiveAgenda: true)
                      : c.copyWith(activeAgendaId: agenda.id),
                ),
                child: StatusPill(isActive: config.activeAgendaId == agenda.id),
              ),
              trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => AgendaEditorScreen(agendaId: agenda.id)),
              ),
            ),
          TextButton.icon(
            icon: const Icon(Icons.add, color: AppColors.accent),
            label: const Text('Nouvel agenda'),
            onPressed: () async {
              final name = await askAgendaName(context);
              if (name == null) return;
              final agenda = TargetAgenda(id: DateTime.now().microsecondsSinceEpoch.toString(), name: name);
              await controller.edit(
                (c) => c.copyWith(
                  agendas: [...c.agendas, agenda],
                  activeAgendaId: c.activeAgendaId ?? agenda.id,
                ),
              );
              if (context.mounted) {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => AgendaEditorScreen(agendaId: agenda.id)),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  String _summary(TargetAgenda agenda) {
    if (agenda.targets.isEmpty) return 'Aucun objectif';
    final days = agenda.targets.keys.toList()..sort();
    return days
        .map((d) {
          final t = agenda.targets[d]!;
          return '${dayName(d).substring(0, 3)}. ${t.targetPercent} % ${t.readyAt.format()}${t.climate ? ' clim ${t.climateTemperature}°' : ''}';
        })
        .join(' · ');
  }
}
