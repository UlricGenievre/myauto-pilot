import 'package:flutter/material.dart';

import '../../../core/models/charge_plan_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatting.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../charge_plan_pickers.dart';
import '../charge_plan_providers.dart';

class OneOffCard extends StatelessWidget {
  const OneOffCard({super.key, required this.config, required this.controller});

  final ChargePlanConfig config;
  final ChargePlanConfigController controller;

  @override
  Widget build(BuildContext context) {
    final oneOff = config.oneOffTarget;
    final isActive = oneOff != null && oneOff.readyAt.isAfter(DateTime.now());

    return DashboardCard(
      title: 'Objectif exceptionnel',
      icon: Icons.priority_high_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isActive) ...[
            Text('Prête ${formatDayTime(oneOff.readyAt)} à ${oneOff.targetPercent} %',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Remplace l\'objectif de l\'agenda ce jour-là, puis s\'efface.', style: hintStyle),
          ] else
            const Text('Aucun. Pour un besoin ponctuel ("demain 7h à 100 %").', style: hintStyle),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                icon: Icon(isActive ? Icons.edit_outlined : Icons.add, color: AppColors.accent),
                label: Text(isActive ? 'Modifier' : 'Ajouter'),
                onPressed: () async {
                  final picked = await showDialog<OneOffTarget>(
                    context: context,
                    builder: (_) => _OneOffDialog(initial: isActive ? oneOff : null),
                  );
                  if (picked != null) await controller.edit((c) => c.copyWith(oneOffTarget: picked));
                },
              ),
              if (oneOff != null)
                TextButton(
                  onPressed: () => controller.edit((c) => c.copyWith(clearOneOffTarget: true)),
                  child: const Text('Supprimer'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Choix du jour (aujourd'hui, demain et les 3 jours suivants : un
/// objectif exceptionnel est un besoin proche, des pastilles suffisent), de
/// l'heure et du pourcentage.
class _OneOffDialog extends StatefulWidget {
  const _OneOffDialog({this.initial});

  final OneOffTarget? initial;

  @override
  State<_OneOffDialog> createState() => _OneOffDialogState();
}

class _OneOffDialogState extends State<_OneOffDialog> {
  /// Aujourd'hui, demain et les 3 jours suivants.
  static const _dayCount = 5;

  late final DateTime _today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  late int _dayOffset = widget.initial != null
      ? DateTime(widget.initial!.readyAt.year, widget.initial!.readyAt.month, widget.initial!.readyAt.day)
          .difference(_today)
          .inDays
          .clamp(0, _dayCount - 1)
      : 1;
  late ClockTime _time = widget.initial != null
      ? ClockTime.hm(widget.initial!.readyAt.hour, widget.initial!.readyAt.minute)
      : ClockTime.hm(7, 0);
  late int _percent = widget.initial?.targetPercent ?? 100;

  DateTime get _readyAt => _time.onDay(DateTime(_today.year, _today.month, _today.day + _dayOffset));

  @override
  Widget build(BuildContext context) {
    final valid = _readyAt.isAfter(DateTime.now());
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Objectif exceptionnel'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var offset = 0; offset < _dayCount; offset++)
                ChoiceChip(
                  label: Text(_dayLabel(offset)),
                  selected: _dayOffset == offset,
                  selectedColor: AppColors.accent,
                  labelStyle: TextStyle(
                    color: _dayOffset == offset ? AppColors.onAccent : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) => setState(() => _dayOffset = offset),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TimeChip(
            label: 'Prête à ${_time.format()}',
            onTap: () async {
              final time = await pickClockTime(context, initial: _time, title: 'Prête à');
              if (time != null) setState(() => _time = time);
            },
          ),
          const SizedBox(height: 8),
          PercentSlider(value: _percent, onChanged: (p) => setState(() => _percent = p)),
          if (!valid) Text('Cette heure est déjà passée.', style: hintStyle.copyWith(color: AppColors.error)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        TextButton(
          onPressed: valid
              ? () => Navigator.of(context).pop(OneOffTarget(targetPercent: _percent, readyAt: _readyAt))
              : null,
          child: const Text('OK'),
        ),
      ],
    );
  }

  String _dayLabel(int offset) {
    if (offset == 0) return 'Aujourd\'hui';
    if (offset == 1) return 'Demain';
    final day = DateTime(_today.year, _today.month, _today.day + offset);
    return '${dayName(day.weekday).substring(0, 3)}. ${day.day}';
  }
}
