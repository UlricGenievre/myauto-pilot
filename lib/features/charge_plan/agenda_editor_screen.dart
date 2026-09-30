import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/charge_plan_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/dashboard_card.dart';
import 'charge_plan_pickers.dart';
import 'charge_plan_providers.dart';

/// Edition d'un agenda d'objectifs : nom + un objectif optionnel par jour.
/// Chaque modification est sauvegardee immediatement.
class AgendaEditorScreen extends ConsumerWidget {
  const AgendaEditorScreen({super.key, required this.agendaId});

  final String agendaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(chargePlanConfigProvider).value;
    final agenda = config?.agendas.where((a) => a.id == agendaId).firstOrNull;

    if (agenda == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }

    Future<void> save(TargetAgenda updated) => ref.read(chargePlanConfigProvider.notifier).edit(
          (c) => c.copyWith(agendas: [for (final a in c.agendas) a.id == agendaId ? updated : a]),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(agenda.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Renommer',
            icon: const Icon(Icons.edit_outlined, color: AppColors.textSecondary),
            onPressed: () async {
              final name = await askAgendaName(context, initial: agenda.name);
              if (name != null) await save(agenda.copyWith(name: name));
            },
          ),
          IconButton(
            tooltip: 'Supprimer',
            icon: const Icon(Icons.delete_outline, color: AppColors.textSecondary),
            onPressed: () async {
              final navigator = Navigator.of(context);
              await ref.read(chargePlanConfigProvider.notifier).edit(
                    (c) => c.copyWith(
                      agendas: c.agendas.where((a) => a.id != agendaId).toList(),
                      clearActiveAgenda: c.activeAgendaId == agendaId,
                    ),
                  );
              navigator.pop();
            },
          ),
        ],
      ),
      body: ListView(
        // Marge de la barre de navigation Android : l'app s'affiche dessous
        // (plein ecran impose depuis Android 15).
        padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          DashboardCard(
            title: 'Objectifs par jour',
            icon: Icons.flag_outlined,
            child: Column(
              children: [
                for (var day = 1; day <= 7; day++) ...[
                  if (day > 1) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider()),
                  _DayTargetRow(
                    day: day,
                    target: agenda.targets[day],
                    onChanged: (target) {
                      final targets = {...agenda.targets};
                      if (target == null) {
                        targets.remove(day);
                      } else {
                        targets[day] = target;
                      }
                      save(agenda.copyWith(targets: targets));
                    },
                    onCopy: () async {
                      final source = agenda.targets[day];
                      if (source == null) return;
                      final days = await showDialog<Set<int>>(
                        context: context,
                        builder: (_) => _CopyDaysDialog(sourceDay: day, target: source),
                      );
                      if (days == null || days.isEmpty) return;
                      await save(agenda.copyWith(targets: {...agenda.targets, for (final d in days) d: source}));
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayTargetRow extends StatelessWidget {
  const _DayTargetRow({required this.day, required this.target, required this.onChanged, required this.onCopy});

  final int day;
  final ReadyTarget? target;
  final ValueChanged<ReadyTarget?> onChanged;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final current = target;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (current != null)
              // Icone + nom du jour : bouton "copier cet objectif vers d'autres jours".
              InkWell(
                onTap: onCopy,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.content_copy_outlined, size: 16, color: AppColors.accent),
                      const SizedBox(width: 6),
                      Text(dayName(day), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              )
            else
              Text(dayName(day), style: const TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            if (current != null)
              TimeChip(
                label: 'Prête à ${current.readyAt.format()}',
                onTap: () async {
                  final time = await pickClockTime(context, initial: current.readyAt, title: 'Prête à');
                  if (time != null) onChanged(current.copyWith(readyAt: time));
                },
              ),
            Switch(
              value: current != null,
              activeTrackColor: AppColors.accent,
              onChanged: (on) =>
                  onChanged(on ? ReadyTarget(targetPercent: 80, readyAt: ClockTime.hm(7, 30)) : null),
            ),
          ],
        ),
        if (current != null) ...[
          PercentSlider(
            value: current.targetPercent,
            onChanged: (p) => onChanged(current.copyWith(targetPercent: p)),
          ),
          ClimateSelector(
            climate: current.climate,
            temperature: current.climateTemperature,
            onChanged: (on, temperature) =>
                onChanged(current.copyWith(climate: on, climateTemperature: temperature)),
          ),
        ] else
          const Text('Pas d\'objectif', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}

/// Choix des jours vers lesquels copier l'objectif de [sourceDay] (les
/// objectifs deja presents sur ces jours sont remplaces).
class _CopyDaysDialog extends StatefulWidget {
  const _CopyDaysDialog({required this.sourceDay, required this.target});

  final int sourceDay;
  final ReadyTarget target;

  @override
  State<_CopyDaysDialog> createState() => _CopyDaysDialogState();
}

class _CopyDaysDialogState extends State<_CopyDaysDialog> {
  final _selected = <int>{};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Copier vers…'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.target.targetPercent} % prête à ${widget.target.readyAt.format()}'
            '${widget.target.climate ? ', climatisée à ${widget.target.climateTemperature} °C' : ''} '
            '(${dayName(widget.sourceDay).toLowerCase()}). Remplace l\'objectif des jours sélectionnés.',
            style: hintStyle,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.maxFinite,
            child: WeekDaySelector(
              selected: _selected,
              locked: {widget.sourceDay},
              lockedHint: 'objectif copié',
              onToggle: (day, on) => setState(() => on ? _selected.add(day) : _selected.remove(day)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        TextButton(
          onPressed: _selected.isEmpty ? null : () => Navigator.of(context).pop(_selected),
          child: const Text('Copier'),
        ),
      ],
    );
  }
}

/// Saisie du nom d'un agenda (null si annule ou vide).
Future<String?> askAgendaName(BuildContext context, {String initial = ''}) async {
  final name = await showDialog<String>(context: context, builder: (_) => _NameDialog(initial: initial));
  final trimmed = name?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Nom de l\'agenda'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Habituel, Vacances...'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        TextButton(onPressed: () => Navigator.of(context).pop(_controller.text), child: const Text('OK')),
      ],
    );
  }
}
