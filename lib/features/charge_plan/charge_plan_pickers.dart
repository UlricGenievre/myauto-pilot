import 'package:flutter/material.dart';

import '../../core/models/charge_plan_config.dart';
import '../../core/theme/app_theme.dart';

/// Texte secondaire des cartes de pilotage/reglages.
const hintStyle = TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500);

const dayNames = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];

/// Nom du jour ISO (1 = lundi).
String dayName(int weekday) => dayNames[weekday - 1];

/// Selecteur d'heure standard Material, en 24 h (libelles en francais via
/// les `localizationsDelegates` de l'app), ouvert sur l'horloge ; la saisie
/// au clavier reste accessible par le bouton de la fenetre.
Future<ClockTime?> pickClockTime(BuildContext context, {required ClockTime initial, String? title}) async {
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: initial.hour % 24, minute: initial.minute),
    helpText: title ?? 'Choisir une heure',
    initialEntryMode: TimePickerEntryMode.dial,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  );
  if (picked == null) return null;
  return ClockTime.hm(picked.hour, picked.minute);
}

/// Saisie d'une plage : heure de debut puis heure de fin.
Future<ChargeWindow?> pickChargeWindow(BuildContext context, {ChargeWindow? initial}) async {
  final start = await pickClockTime(context, initial: initial?.start ?? ClockTime.hm(22, 0), title: 'Début de la plage');
  if (start == null || !context.mounted) return null;
  final end = await pickClockTime(context, initial: initial?.end ?? ClockTime.hm(6, 0), title: 'Fin de la plage');
  if (end == null) return null;
  return ChargeWindow(start: start, end: end);
}

/// Curseur de pourcentage cible (10..100 %, pas de 5).
class PercentSlider extends StatelessWidget {
  const PercentSlider({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 10,
            max: 100,
            divisions: 18,
            activeColor: AppColors.accent,
            inactiveColor: AppColors.surfaceHigh,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text('$value %', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

/// Pastille cliquable affichant une heure ou une plage.
class TimeChip extends StatelessWidget {
  const TimeChip({super.key, required this.label, required this.onTap, this.onDeleted});

  final String label;
  final VoidCallback onTap;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      backgroundColor: AppColors.surfaceHigh,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onPressed: onTap,
      onDeleted: onDeleted,
      deleteIconColor: AppColors.textSecondary,
    );
  }
}

/// Les 7 jours (L..D) en pastilles rondes cliquables, jaunes quand
/// selectionnes. Partage par la saisie des plages et la copie d'objectifs.
///
/// [dimmed] : jours estompes mais cliquables (ex. journee entierement HC,
/// precisee par [dimmedHint] dans l'infobulle). [locked] : jours affiches
/// selectionnes mais non cliquables (ex. jour source d'une copie).
class WeekDaySelector extends StatelessWidget {
  const WeekDaySelector({
    super.key,
    required this.selected,
    required this.onToggle,
    this.dimmed = const {},
    this.dimmedHint,
    this.locked = const {},
    this.lockedHint,
  });

  final Set<int> selected;
  final void Function(int day, bool on) onToggle;
  final Set<int> dimmed;
  final String? dimmedHint;
  final Set<int> locked;
  final String? lockedHint;

  static const _letters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(7, (index) {
        final day = index + 1;
        final isLocked = locked.contains(day);
        final active = isLocked || selected.contains(day);
        final isDimmed = dimmed.contains(day);
        final hint = isLocked ? lockedHint : (isDimmed ? dimmedHint : null);
        return Expanded(
          child: Tooltip(
            message: dayName(day) + (hint != null ? ' ($hint)' : ''),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: isLocked ? null : () => onToggle(day, !active),
              child: Opacity(
                opacity: isDimmed || isLocked ? 0.35 : 1,
                child: Container(
                  height: 34,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? AppColors.accent : AppColors.surfaceHigh,
                  ),
                  child: Text(
                    _letters[index],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: active ? AppColors.onAccent : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
