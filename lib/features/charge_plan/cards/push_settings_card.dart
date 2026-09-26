import 'package:flutter/material.dart';

import '../../../core/models/charge_plan_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../charge_plan_pickers.dart';
import '../charge_plan_providers.dart';

/// Reglages : quand envoyer une plage a la voiture.
class PushSettingsCard extends StatefulWidget {
  const PushSettingsCard({super.key, required this.config, required this.controller});

  final ChargePlanConfig config;
  final ChargePlanConfigController controller;

  @override
  State<PushSettingsCard> createState() => _PushSettingsCardState();
}

class _PushSettingsCardState extends State<PushSettingsCard> {
  // Valeurs pendant le glissement du curseur ; sauvegardees au lacher.
  late int _pushLead = widget.config.pushLeadMinutes;

  static String _duration(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    if (h == 0) return '$m min';
    return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      title: 'Envoi à la voiture',
      icon: Icons.send_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingSlider(
            title: 'Envoi de la plage',
            value: _pushLead,
            label: '${_duration(_pushLead)} avant son début',
            min: 30,
            max: 480,
            step: 15,
            // Ligne du temps : loin avant la plage a gauche, proche a droite.
            reversed: true,
            onChanged: (v) => setState(() => _pushLead = v),
            onChangeEnd: (v) => widget.controller.edit((c) => c.copyWith(pushLeadMinutes: v)),
          ),
          const SizedBox(height: 4),
          const Text(
            'Sans objectif, l\'heure « prête à » envoyée à la voiture est fixée 1 h avant l\'envoi, '
            'active ce seul jour : déjà passée à la réception, elle n\'est jamais atteinte.',
            style: hintStyle,
          ),
        ],
      ),
    );
  }
}

class _SettingSlider extends StatelessWidget {
  const _SettingSlider({
    required this.title,
    required this.value,
    required this.label,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    required this.onChangeEnd,
    this.reversed = false,
  });

  final String title;
  final int value;
  final String label;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onChangeEnd;

  /// Grandes valeurs a gauche, petites a droite.
  final bool reversed;

  /// Position du curseur <-> valeur (symetrique quand [reversed]).
  int _flip(int v) => reversed ? min + max - v : v;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
            Text(label, style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
          ],
        ),
        Slider(
          value: _flip(value.clamp(min, max)).toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: (max - min) ~/ step,
          activeColor: AppColors.accent,
          inactiveColor: AppColors.surfaceHigh,
          onChanged: (v) => onChanged(_flip(v.round())),
          onChangeEnd: (v) => onChangeEnd(_flip(v.round())),
        ),
      ],
    );
  }
}
