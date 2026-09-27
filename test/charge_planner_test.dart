import 'package:flutter_test/flutter_test.dart';
import 'package:myauto_pilot/core/charge_plan/charge_planner.dart';
import 'package:myauto_pilot/core/models/charge_plan_config.dart';

// Semaine de reference : lundi 2026-09-21 .. dimanche 2026-09-27.
DateTime at(int day, int hour, [int minute = 0]) => DateTime(2026, 9, day, hour, minute);

ChargeWindow w(String start, String end) =>
    ChargeWindow(start: ClockTime.tryParse(start)!, end: ClockTime.tryParse(end)!);

/// Plages d'exemple : 01:00-07:00 et 13:00-16:00 du mardi au vendredi,
/// samedi/dimanche/lundi entierement HC.
ChargeCalendar sampleCalendar() {
  final weekday = DaySchedule(windows: [w('01:00', '07:00'), w('13:00', '16:00')]);
  return ChargeCalendar(days: {
    1: const DaySchedule(allDay: true),
    2: weekday,
    3: weekday,
    4: weekday,
    5: weekday,
    6: const DaySchedule(allDay: true),
    7: const DaySchedule(allDay: true),
  });
}

ChargePlanConfig config({
  Map<int, ReadyTarget> targets = const {},
  OneOffTarget? oneOff,
  double? capacity = 52,
  double? power = 7.4,
}) =>
    ChargePlanConfig(
      batteryCapacityKwh: capacity,
      chargePowerKw: power,
      calendar: sampleCalendar(),
      agendas: [TargetAgenda(id: 'a', name: 'Habituel', targets: targets)],
      activeAgendaId: 'a',
      oneOffTarget: oneOff,
    );

void main() {
  group('ClockTime', () {
    test('parse HH:MM et HH:MM:SS', () {
      expect(ClockTime.tryParse('07:45')!.minutes, 465);
      expect(ClockTime.tryParse('09:00:00')!.minutes, 540);
      expect(ClockTime.tryParse('25:00'), isNull);
    });
  });

  group('ChargePlanConfig JSON', () {
    test('aller-retour sans perte', () {
      final original = config(
        targets: {1: ReadyTarget(targetPercent: 80, readyAt: ClockTime.hm(7, 30))},
        oneOff: OneOffTarget(targetPercent: 100, readyAt: at(24, 7)),
      ).copyWith(dedicatedProgramIndex: 1);
      final copy = ChargePlanConfig.fromJson(original.toJson());
      expect(copy.toJson(), original.toJson());
    });
  });

  group('occurrences', () {
    test('samedi-dimanche-lundi fusionnes en un seul bloc HC complet', () {
      final planner = ChargePlanner(config());
      final occs = planner.occurrences(at(26, 0), at(29, 0)).where((o) => o.allDay).toList();
      expect(occs.first.start, at(26, 0));
      expect(occs.first.end, at(29, 0)); // mardi 00:00
    });

    test('plage de la veille qui touche le bloc absorbee (leadIn)', () {
      final cal = sampleCalendar().withDay(5, DaySchedule(windows: [w('22:00', '00:00')]));
      final planner = ChargePlanner(ChargePlanConfig(calendar: cal));
      final block = planner.occurrences(at(25, 12), at(27, 0)).firstWhere((o) => o.allDay);
      expect(block.leadInStart, at(25, 22));
    });
  });

  group('commandes', () {
    test('plage normale : envoi 4 h avant, pret a = 1 h avant l\'envoi, ce seul jour', () {
      final cmd = ChargePlanner(config()).commandInForce(at(22, 9, 30))!; // mardi
      expect(cmd.kind, ChargeCommandKind.window);
      expect(cmd.windowStart, at(22, 13));
      expect(cmd.durationMinutes, 180);
      expect(cmd.pushAt, at(22, 9));
      expect(cmd.readyAt, at(22, 8)); // envoi 09:00
      expect(cmd.readyDay, 2);
      expect(cmd.target, isNull);
    });

    test('ne remplace pas une plage en cours (envoi a la fin de la precedente)', () {
      // Plages rapprochees : 01:00-07:00 puis 09:00-11:00.
      final cal = sampleCalendar().withDay(3, DaySchedule(windows: [w('01:00', '07:00'), w('09:00', '11:00')]));
      final cmds = ChargePlanner(ChargePlanConfig(calendar: cal)).commands(at(23, 0));
      final second = cmds.firstWhere((c) => c.windowStart == at(23, 9));
      expect(second.pushAt, at(23, 7));
    });

    test('veille de journee HC complete : 00:00-12:00, pret a 1 h avant l\'envoi', () {
      final cmd = ChargePlanner(config()).upcomingCommand(at(25, 18))!; // vendredi soir
      expect(cmd.kind, ChargeCommandKind.allDayMorning);
      expect(cmd.pushAt, at(25, 20));
      expect(cmd.windowStart, at(26, 0));
      expect(cmd.durationMinutes, 720);
      expect(cmd.readyAt, at(25, 19)); // envoi vendredi 20:00
      expect(cmd.readyDay, 5);
    });

    test('journee HC complete vers 10:00 : 00:00 + 1440 min', () {
      final cmd = ChargePlanner(config()).commandInForce(at(26, 10, 5))!; // samedi
      expect(cmd.kind, ChargeCommandKind.allDayFull);
      expect(cmd.pushAt, at(26, 10));
      expect(cmd.chargeTimeStart.format(), '00:00');
      expect(cmd.durationMinutes, 1440);
      expect(cmd.readyAt, at(26, 9)); // 1 h avant l'envoi, samedi seulement
      expect(cmd.readyDay, 6);
      // Aucune autre commande pendant le reste du bloc (dimanche, lundi).
      expect(ChargePlanner(config()).commandInForce(at(27, 15))!.id, cmd.id);
    });

    test('sortie du bloc : envoi avant minuit, plage non avancee sans objectif', () {
      final cmd = ChargePlanner(config()).upcomingCommand(at(28, 18))!; // lundi soir
      expect(cmd.kind, ChargeCommandKind.window);
      expect(cmd.pushAt, at(28, 21)); // mardi 01:00 - 4 h, avant lundi 23:00
      // Pas de charge sur les heures pleines de mardi 00:00-01:00.
      expect(cmd.windowStart, at(29, 1));
      expect(cmd.windowEnd, at(29, 7));
      expect(cmd.extendedMinutes, 0);
    });

    test('sortie du bloc : objectif insuffisant, debut avance jusqu\'a l\'envoi au plus', () {
      // 10 % -> 100 % : 401 min pour 360 min de plage, echeance 07:00 (pas
      // de prolongation possible) : debut avance de 45 min (arrondi).
      final cfg = config(targets: {2: ReadyTarget(targetPercent: 100, readyAt: ClockTime.hm(7, 0))});
      final cmd = ChargePlanner(cfg).upcomingCommand(at(28, 18), socPercent: 10)!;
      expect(cmd.pushAt, at(28, 21));
      expect(cmd.windowStart, at(29, 0, 15));
      expect(cmd.windowEnd, at(29, 7));
      expect(cmd.extendedMinutes, 45);
    });

    test('objectif atteignable : pas d\'elargissement, pret a = objectif', () {
      final cfg = config(targets: {3: ReadyTarget(targetPercent: 80, readyAt: ClockTime.hm(7, 30))});
      final cmd = ChargePlanner(cfg).upcomingCommand(at(22, 20), socPercent: 40)!; // mardi soir
      expect(cmd.windowStart, at(23, 1));
      expect(cmd.extendedMinutes, 0);
      expect(cmd.readyAt, at(23, 7, 30));
      expect(cmd.target!.targetPercent, 80);
    });

    test('objectif insuffisant : fin prolongee jusqu\'a l\'objectif puis debut avance', () {
      // 10 % -> 100 % : 85 % a 7,4 kW + 5 % (au-dela de 95 %) a 3,7 kW
      // = 358,4 + 42,2 -> 401 min pour 360 min de plage.
      final cfg = config(targets: {3: ReadyTarget(targetPercent: 100, readyAt: ClockTime.hm(7, 15))});
      final cmd = ChargePlanner(cfg).upcomingCommand(at(22, 20), socPercent: 10)!;
      // Deficit de 41 min arrondi a 45 : 15 min apres (jusqu'a 07:15), 30 min avant.
      expect(cmd.windowEnd, at(23, 7, 15));
      expect(cmd.windowStart, at(23, 0, 30));
      expect(cmd.extendedMinutes, 45);
      expect(cmd.note, isNull);
    });

    test('objectif ponctuel prioritaire sur l\'agenda le meme jour', () {
      final cfg = config(
        targets: {3: ReadyTarget(targetPercent: 60, readyAt: ClockTime.hm(9, 0))},
        oneOff: OneOffTarget(targetPercent: 100, readyAt: at(23, 7)),
      );
      final cmd = ChargePlanner(cfg).upcomingCommand(at(22, 20), socPercent: 50)!;
      expect(cmd.target!.isOneOff, isTrue);
      expect(cmd.readyAt, at(23, 7));
    });

    test('objectif servi par une plage ulterieure : pret a par defaut', () {
      // Objectif mercredi 18:00 : la plage de nuit n'est pas la derniere avant.
      final cfg = config(targets: {3: ReadyTarget(targetPercent: 80, readyAt: ClockTime.hm(18, 0))});
      final cmd = ChargePlanner(cfg).upcomingCommand(at(22, 20), socPercent: 70)!;
      expect(cmd.windowStart, at(23, 1));
      expect(cmd.target, isNull);
      expect(cmd.readyAt, at(22, 20)); // envoi mardi 21:00
    });

    test('capacite inconnue : pas d\'elargissement, note explicative', () {
      final cfg = config(
        capacity: null,
        targets: {3: ReadyTarget(targetPercent: 100, readyAt: ClockTime.hm(7, 15))},
      );
      final cmd = ChargePlanner(cfg).upcomingCommand(at(22, 20), socPercent: 10)!;
      expect(cmd.extendedMinutes, 0);
      expect(cmd.note, isNotNull);
    });

    test('delai d\'envoi reglable : envoi 2 h avant', () {
      final cfg = config().copyWith(pushLeadMinutes: 120);
      final cmd = ChargePlanner(cfg).upcomingCommand(at(22, 10, 30))!; // mardi
      expect(cmd.windowStart, at(22, 13));
      expect(cmd.pushAt, at(22, 11));
      expect(cmd.readyAt, at(22, 10));
    });

    test('exemple de l\'utilisateur : plage de nuit envoyee mercredi 21:15 -> pret a mercredi 20:15', () {
      final cal = ChargeCalendar(days: {4: DaySchedule(windows: [w('01:15', '06:15')])});
      final cmd = ChargePlanner(ChargePlanConfig(calendar: cal)).upcomingCommand(at(23, 18))!; // mercredi
      expect(cmd.windowStart, at(24, 1, 15));
      expect(cmd.pushAt, at(23, 21, 15));
      expect(cmd.readyAt, at(23, 20, 15));
      expect(cmd.readyDay, 3);
    });

    test('delai d\'envoi reglable aussi pour la veille d\'une journee HC complete', () {
      final cfg = config().copyWith(pushLeadMinutes: 90);
      final cmd = ChargePlanner(cfg).upcomingCommand(at(25, 18))!; // vendredi soir
      expect(cmd.kind, ChargeCommandKind.allDayMorning);
      expect(cmd.pushAt, at(25, 22, 30));
    });

    test('fin de charge ralentie : seule la tranche au-dela de 95 % compte double', () {
      // Plage de nuit 01:00-07:00 (360 min), objectif mercredi 07:00.
      ChargeCommand forTarget(int percent, int soc) => ChargePlanner(
            config(targets: {3: ReadyTarget(targetPercent: percent, readyAt: ClockTime.hm(7, 0))}),
          ).upcomingCommand(at(22, 20), socPercent: soc)!;
      // 15 % -> 95 % : 80 % a pleine puissance = 337 min, tient dans la plage.
      expect(forTarget(95, 15).extendedMinutes, 0);
      // 15 % -> 100 % : 337 + 5 % a mi-puissance (42 min) = 380 min -> elargie.
      expect(forTarget(100, 15).extendedMinutes, greaterThan(0));
      // Deja a 97 % : seuls 3 % a mi-puissance (26 min).
      expect(forTarget(100, 97).extendedMinutes, 0);
    });

    test('calendrier vide : aucune commande', () {
      expect(const ChargePlanner(ChargePlanConfig()).upcomingCommand(at(22, 12)), isNull);
      expect(const ChargePlanner(ChargePlanConfig()).commandInForce(at(22, 12)), isNull);
    });
  });
}
