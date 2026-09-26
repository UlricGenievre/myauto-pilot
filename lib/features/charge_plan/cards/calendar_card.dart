import 'package:flutter/material.dart';

import '../../../core/models/charge_plan_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../charge_plan_pickers.dart';
import '../charge_plan_providers.dart';

/// Saisie "par plage" : chaque plage distincte (ex. 01:15-06:15) est saisie
/// une fois avec les jours ou elle s'applique, plus une ligne speciale
/// "Toute la journee". Le stockage reste par jour (`ChargeCalendar`) : cette
/// vue regroupe les jours qui partagent la meme plage, et chaque
/// modification est reecrite jour par jour.
class CalendarCard extends StatelessWidget {
  const CalendarCard({super.key, required this.config, required this.controller});

  final ChargePlanConfig config;
  final ChargePlanConfigController controller;

  static const _allDays = {1, 2, 3, 4, 5, 6, 7};

  /// Plages distinctes (par heures de debut/fin) et jours ou elles
  /// s'appliquent, triees par heure de debut.
  static List<(ChargeWindow, Set<int>)> _rules(ChargeCalendar calendar) {
    final byKey = <String, (ChargeWindow, Set<int>)>{};
    for (final day in _allDays) {
      for (final window in calendar.dayOf(day).windows) {
        final key = '${window.start.minutes}-${window.end.minutes}';
        byKey.putIfAbsent(key, () => (window, <int>{})).$2.add(day);
      }
    }
    return byKey.values.toList()..sort((a, b) => a.$1.start.compareTo(b.$1.start));
  }

  static bool _same(ChargeWindow a, ChargeWindow b) => a.start == b.start && a.end == b.end;

  /// Remplace, sur tous les jours, [old] par [replacement] (ou le retire si
  /// null), puis l'ajoute aux jours [addDays].
  static ChargeCalendar _apply(
    ChargeCalendar calendar, {
    ChargeWindow? old,
    ChargeWindow? replacement,
    Set<int> addDays = const {},
  }) {
    var result = calendar;
    for (final day in _allDays) {
      final schedule = calendar.dayOf(day);
      final windows = <ChargeWindow>[];
      void addOnce(ChargeWindow w) {
        if (!windows.any((existing) => _same(existing, w))) windows.add(w);
      }

      for (final w in schedule.windows) {
        if (old != null && _same(w, old)) {
          if (replacement != null) addOnce(replacement);
        } else {
          addOnce(w);
        }
      }
      final target = replacement ?? old;
      if (addDays.contains(day) && target != null && !windows.any((w) => _same(w, target))) {
        windows.add(target);
      }
      windows.sort((a, b) => a.start.compareTo(b.start));
      result = result.withDay(day, schedule.copyWith(windows: windows));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final calendar = config.calendar;
    final allDayDays = {for (final day in _allDays) if (calendar.dayOf(day).allDay) day};
    final rules = _rules(calendar);

    void save(ChargeCalendar Function(ChargeCalendar c) change) =>
        controller.edit((c) => c.copyWith(calendar: change(c.calendar)));

    return DashboardCard(
      title: 'Plages de charge',
      icon: Icons.bolt_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Saisissez chaque plage d\'heures creuses une fois, puis les jours où elle s\'applique. '
            'Une plage qui passe minuit appartient au jour où elle commence.',
            style: hintStyle,
          ),
          const SizedBox(height: 12),
          _RuleRow(
            title: const Text('Toute la journée', style: TextStyle(fontWeight: FontWeight.w700)),
            days: allDayDays,
            onToggleDay: (day, on) => save((c) => c.withDay(day, c.dayOf(day).copyWith(allDay: on))),
          ),
          for (final (window, days) in rules) ...[
            const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),
            _RuleRow(
              title: TimeChip(
                label: '${window.start.format()} → ${window.end.format()}',
                onTap: () async {
                  final edited = await pickChargeWindow(context, initial: window);
                  if (edited != null) save((c) => _apply(c, old: window, replacement: edited));
                },
                onDeleted: () => save((c) => _apply(c, old: window)),
              ),
              days: days,
              // Jours "toute la journee" : la plage y reste enregistree mais
              // n'est pas utilisee tant que le jour est entierement HC.
              dimmedDays: allDayDays,
              onToggleDay: (day, on) => save(
                (c) => on
                    ? _apply(c, old: window, replacement: window, addDays: {day})
                    : c.withDay(
                        day,
                        c.dayOf(day).copyWith(windows: c.dayOf(day).windows.where((w) => !_same(w, window)).toList()),
                      ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.add, color: AppColors.accent),
            label: const Text('Ajouter une plage'),
            onPressed: () async {
              final added = await pickChargeWindow(context);
              if (added == null) return;
              // Par defaut sur tous les jours qui ne sont pas deja entierement
              // HC ; decocher ensuite ceux qui ne sont pas concernes.
              final days = _allDays.difference(allDayDays);
              save((c) => _apply(c, addDays: days.isEmpty ? _allDays : days, replacement: added));
            },
          ),
          if (rules.isNotEmpty)
            const Text('Une plage décochée sur tous les jours est supprimée.', style: hintStyle),
        ],
      ),
    );
  }
}

/// Ligne "plage + jours" : un titre (libelle ou pastille horaire) et les 7
/// jours cliquables.
class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.title, required this.days, required this.onToggleDay, this.dimmedDays = const {}});

  final Widget title;
  final Set<int> days;
  final Set<int> dimmedDays;
  final void Function(int day, bool on) onToggleDay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        const SizedBox(height: 10),
        WeekDaySelector(
          selected: days,
          dimmed: dimmedDays,
          dimmedHint: 'toute la journée',
          onToggle: onToggleDay,
        ),
      ],
    );
  }
}
