import '../models/charge_plan_config.dart';

/// Une occurrence concrete de plage de charge (dates reelles), issue du
/// calendrier hebdomadaire.
class WindowOccurrence {
  const WindowOccurrence({required this.start, required this.end, this.allDay = false, this.leadInStart});

  final DateTime start;
  final DateTime end;

  /// Bloc de journee(s) entierement HC : [start] est alors le minuit du
  /// premier jour du bloc, [end] le minuit qui suit le dernier.
  final bool allDay;

  /// Pour un bloc [allDay] : debut d'une plage normale qui le precede sans
  /// interruption (ex. vendredi 22:00 avant un samedi HC complet), absorbee
  /// dans le bloc.
  final DateTime? leadInStart;

  @override
  String toString() => 'WindowOccurrence($start -> $end${allDay ? ', allDay' : ''})';
}

/// Un objectif "pret a X % a telle date/heure", deja resolu (agenda actif ou
/// objectif ponctuel).
class EffectiveTarget {
  const EffectiveTarget({
    required this.targetPercent,
    required this.readyAt,
    required this.isOneOff,
    this.climate = false,
    this.climateTemperature = defaultClimateTemperature,
  });

  final int targetPercent;
  final DateTime readyAt;
  final bool isOneOff;

  /// Habitacle climatise a [readyAt], a [climateTemperature] °C.
  final bool climate;
  final int climateTemperature;

  @override
  String toString() =>
      'EffectiveTarget($targetPercent % @ $readyAt${isOneOff ? ', ponctuel' : ''}${climate ? ', clim' : ''})';
}

enum ChargeCommandKind {
  /// Plage normale du calendrier (eventuellement elargie).
  window,

  /// Veille d'une journee HC complete : plage 00:00-12:00.
  allDayMorning,

  /// Journee HC complete, vers 10:00 : plage 00:00 -> 00:00 (1440 min).
  allDayFull,
}

/// Ce que l'app doit envoyer a la voiture (plage unique + heure "pret a" du
/// programme dedie), et quand.
class ChargeCommand {
  const ChargeCommand({
    required this.id,
    required this.kind,
    required this.pushAt,
    required this.windowStart,
    required this.durationMinutes,
    required this.readyAt,
    this.target,
    this._climate,
    this._climateTemperature,
    this.extendedMinutes = 0,
    this.note,
    DateTime? validUntil,
  }) : validUntil = validUntil ?? windowStart;

  /// Identifiant stable par occurrence (independant du SOC), pour ne pas
  /// renvoyer deux fois la meme commande.
  final String id;
  final ChargeCommandKind kind;

  /// Heure a partir de laquelle envoyer (deja passee = a envoyer tout de
  /// suite).
  final DateTime pushAt;

  /// Fin de validite : moment ou la commande suivante prend le relais.
  final DateTime validUntil;

  final DateTime windowStart;
  final int durationMinutes;

  /// Heure "pret a" a mettre dans le programme dedie.
  final DateTime readyAt;

  /// Objectif servi par cette plage (null = heure "pret a" par defaut).
  final EffectiveTarget? target;

  /// Programme dedie en charge + preclimatisation (habitacle pret a
  /// [readyAt]) plutot qu'en charge seule. Par defaut, celui de [target].
  bool get climate => _climate ?? target?.climate ?? false;
  final bool? _climate;

  /// Temperature d'habitacle a ecrire avec la climatisation. Par defaut,
  /// celle de [target] ; null sans climatisation.
  int? get climateTemperature => climate ? (_climateTemperature ?? target?.climateTemperature) : null;
  final int? _climateTemperature;

  /// Minutes ajoutees hors plage HC pour tenir l'objectif.
  final int extendedMinutes;

  /// Explication a afficher (objectif inatteignable, donnees manquantes...).
  final String? note;

  DateTime get windowEnd => windowStart.add(Duration(minutes: durationMinutes));

  /// Valeur de `chargeTimeStart` ("HH:MM").
  ClockTime get chargeTimeStart => ClockTime.hm(windowStart.hour, windowStart.minute);

  /// Contenu effectivement envoye a la voiture (debut, duree, heure "pret
  /// a") : deux commandes de meme [id] peuvent differer si le parametrage a
  /// change entre-temps (objectif ajoute ou supprime...).
  String get signature =>
      '${chargeTimeStart.format()}+$durationMinutes>J${readyAt.weekday} ${ClockTime.hm(readyAt.hour, readyAt.minute).format()}'
      '${climate ? ' clim${climateTemperature ?? ''}' : ''}';

  /// Jour ISO (1 = lundi) ou le programme dedie est actif : celui de
  /// l'heure "pret a", et lui seul (pas de preparation non desiree les
  /// autres jours).
  int get readyDay => readyAt.weekday;

  ChargeCommand _copy({DateTime? validUntil}) => ChargeCommand(
        id: id,
        kind: kind,
        pushAt: pushAt,
        windowStart: windowStart,
        durationMinutes: durationMinutes,
        readyAt: readyAt,
        target: target,
        climate: climate,
        climateTemperature: climateTemperature,
        extendedMinutes: extendedMinutes,
        note: note,
        validUntil: validUntil ?? this.validUntil,
      );

  @override
  String toString() =>
      'ChargeCommand($id, push $pushAt, ${chargeTimeStart.format()} +${durationMinutes}min, pret $readyAt'
      '${extendedMinutes > 0 ? ', +${extendedMinutes}min' : ''})';
}

/// Logique pure du pilotage de charge : a partir du parametrage et de
/// l'heure courante, determine la prochaine plage a envoyer a la voiture.
/// Aucune I/O : testable unitairement et reutilisable depuis les reveils en
/// arriere-plan.
class ChargePlanner {
  const ChargePlanner(this.config);

  final ChargePlanConfig config;

  /// Delai d'envoi avant le debut d'une plage (reglable, 4 h par defaut).
  Duration get pushLead => Duration(minutes: config.pushLeadMinutes);

  /// Heure d'envoi de la plage 24 h le jour d'une journee HC complete.
  static final allDayFullPushTime = ClockTime.hm(10, 0);

  /// Fin de la plage envoyee la veille d'une journee HC complete.
  static final allDayMorningEnd = ClockTime.hm(12, 0);

  /// Sans objectif, heure "pret a" = ce delai avant l'envoi lui-meme, le
  /// jour de l'envoi (programme actif ce seul jour) : deja passee quand la
  /// voiture la recoit, donc jamais atteinte. Meme regle pour toutes les
  /// plages.
  static const defaultReadyBeforePush = Duration(hours: 1);

  /// Marge avant la fin d'un bloc HC complet pour envoyer la plage suivante,
  /// afin que la plage 24 h ne deborde jamais en heures pleines.
  static const allDayExitMargin = Duration(hours: 1);

  /// Au-dela de ce niveau, la charge ralentit (equilibrage des cellules) :
  /// le calcul de duree y compte [slowChargePowerDivisor] fois moins de
  /// puissance.
  static const slowChargeFromPercent = 95;
  static const slowChargePowerDivisor = 2;

  static const _horizonDays = 9;
  static const _roundingMinutes = 15;

  // --- Occurrences de plages -------------------------------------------------

  /// Plages concretes qui recouvrent [from, to[, triees et fusionnees
  /// (plages qui se touchent/chevauchent, jours HC complets consecutifs).
  List<WindowOccurrence> occurrences(DateTime from, DateTime to) {
    final raw = <WindowOccurrence>[];
    final firstDay = _startOfDay(from).subtract(const Duration(days: 1));
    for (var day = firstDay; !day.isAfter(to); day = _nextDay(day)) {
      final schedule = config.calendar.dayOf(day.weekday);
      if (schedule.allDay) {
        raw.add(WindowOccurrence(start: day, end: _nextDay(day), allDay: true));
        continue;
      }
      for (final window in schedule.windows) {
        final start = window.start.onDay(day);
        final end = window.end.minutes > window.start.minutes ? window.end.onDay(day) : window.end.onDay(_nextDay(day));
        raw.add(WindowOccurrence(start: start, end: end));
      }
    }
    raw.sort((a, b) => a.start.compareTo(b.start));

    // 1) Fusion des blocs HC complets consecutifs, et des plages normales
    //    qui se chevauchent entre elles.
    final merged = <WindowOccurrence>[];
    for (final occ in raw) {
      if (merged.isNotEmpty) {
        final last = merged.last;
        if (last.allDay && occ.allDay && !occ.start.isAfter(last.end)) {
          merged[merged.length - 1] = WindowOccurrence(start: last.start, end: _maxDate(last.end, occ.end), allDay: true);
          continue;
        }
        if (!last.allDay && !occ.allDay && !occ.start.isAfter(last.end)) {
          merged[merged.length - 1] = WindowOccurrence(start: last.start, end: _maxDate(last.end, occ.end));
          continue;
        }
      }
      merged.add(occ);
    }

    // 2) Une plage normale qui touche le debut d'un bloc HC complet y est
    //    absorbee (leadInStart). Une plage normale entierement incluse dans
    //    un bloc disparait. Celles qui commencent apres la fin du bloc
    //    restent separees : la plage 24 h ne doit pas deborder dessus.
    final result = <WindowOccurrence>[];
    for (final occ in merged) {
      if (occ.allDay && result.isNotEmpty && !result.last.allDay && !result.last.end.isBefore(occ.start)) {
        final leadIn = result.removeLast();
        result.add(WindowOccurrence(start: occ.start, end: occ.end, allDay: true, leadInStart: leadIn.start));
        continue;
      }
      if (!occ.allDay && result.isNotEmpty && result.last.allDay && !occ.end.isAfter(result.last.end)) {
        continue;
      }
      result.add(occ);
    }

    return result.where((o) => o.end.isAfter(from) && o.start.isBefore(to)).toList();
  }

  // --- Objectifs ---------------------------------------------------------------

  /// Objectifs dont l'echeance tombe dans ]from, to] : agenda actif, avec
  /// l'objectif ponctuel qui remplace celui de l'agenda le meme jour.
  List<EffectiveTarget> targets(DateTime from, DateTime to) {
    final result = <EffectiveTarget>[];
    final agenda = config.activeAgenda;
    final oneOff = config.oneOffTarget;
    for (var day = _startOfDay(from); !day.isAfter(to); day = _nextDay(day)) {
      if (oneOff != null && _sameDay(oneOff.readyAt, day)) {
        result.add(EffectiveTarget(
          targetPercent: oneOff.targetPercent,
          readyAt: oneOff.readyAt,
          isOneOff: true,
          climate: oneOff.climate,
          climateTemperature: oneOff.climateTemperature,
        ));
        continue;
      }
      final recurring = agenda?.targets[day.weekday];
      if (recurring != null) {
        result.add(EffectiveTarget(
          targetPercent: recurring.targetPercent,
          readyAt: recurring.readyAt.onDay(day),
          isOneOff: false,
          climate: recurring.climate,
          climateTemperature: recurring.climateTemperature,
        ));
      }
    }
    return result.where((t) => t.readyAt.isAfter(from) && !t.readyAt.isAfter(to)).toList();
  }

  // --- Commandes -----------------------------------------------------------------

  /// Commande en vigueur a [now] : la derniere dont l'heure d'envoi est
  /// passee et qui n'a pas encore ete relayee par la suivante. C'est celle
  /// que la tache d'arriere-plan doit avoir envoyee (et envoie si ce n'est
  /// pas encore fait). Null si le calendrier est vide.
  ///
  /// [socPercent] (niveau de batterie actuel) sert uniquement au test de
  /// suffisance : sans lui (ou sans capacite/puissance), pas d'elargissement.
  ChargeCommand? commandInForce(DateTime now, {int? socPercent}) {
    for (final command in commands(now, socPercent: socPercent)) {
      if (!command.pushAt.isAfter(now) && command.validUntil.isAfter(now)) return command;
    }
    return null;
  }

  /// Prochaine commande a envoyer apres [now].
  ChargeCommand? upcomingCommand(DateTime now, {int? socPercent}) {
    for (final command in commands(now, socPercent: socPercent)) {
      if (command.pushAt.isAfter(now)) return command;
    }
    return null;
  }

  /// Toutes les commandes de l'horizon, dans l'ordre d'envoi.
  List<ChargeCommand> commands(DateTime now, {int? socPercent}) {
    final horizonEnd = now.add(const Duration(days: _horizonDays));
    final occs = occurrences(now.subtract(const Duration(days: 2)), horizonEnd);
    final allTargets = targets(now, horizonEnd.add(const Duration(days: 2)));

    final result = <ChargeCommand>[];
    for (var i = 0; i < occs.length; i++) {
      final occ = occs[i];
      final previous = i > 0 ? occs[i - 1] : null;
      final next = i + 1 < occs.length ? occs[i + 1] : null;
      if (occ.allDay) {
        result.addAll(_allDayCommands(occ, previous, allTargets));
      } else {
        result.add(_windowCommand(occ, previous, next, occs.sublist(i), allTargets, socPercent));
      }
    }

    // Chaque commande reste en vigueur jusqu'a l'envoi de la suivante.
    for (var i = 0; i < result.length; i++) {
      final next = i + 1 < result.length ? result[i + 1] : null;
      result[i] = result[i]._copy(validUntil: next?.pushAt ?? result[i].windowEnd);
    }
    return result;
  }

  List<ChargeCommand> _allDayCommands(
    WindowOccurrence block,
    WindowOccurrence? previous,
    List<EffectiveTarget> allTargets,
  ) {
    final day = block.start;
    final morningStart = block.leadInStart ?? day;
    final morningEnd = allDayMorningEnd.onDay(day);
    final fullPushAt = allDayFullPushTime.onDay(day);

    var morningPushAt = morningStart.subtract(pushLead);
    if (previous != null && !previous.allDay && previous.end.isAfter(morningPushAt)) {
      morningPushAt = previous.end;
    }

    final morningTarget = _firstTarget(allTargets, after: morningStart, notAfter: morningEnd);
    final fullTarget = _firstTarget(allTargets, after: fullPushAt, notAfter: _nextDay(day));

    return [
      ChargeCommand(
        id: 'allday-morning-${_key(day)}',
        kind: ChargeCommandKind.allDayMorning,
        pushAt: morningPushAt,
        windowStart: morningStart,
        durationMinutes: morningEnd.difference(morningStart).inMinutes,
        readyAt: morningTarget?.readyAt ?? morningPushAt.subtract(defaultReadyBeforePush),
        target: morningTarget,
      ),
      ChargeCommand(
        id: 'allday-full-${_key(day)}',
        kind: ChargeCommandKind.allDayFull,
        pushAt: fullPushAt,
        windowStart: day,
        durationMinutes: 1440,
        readyAt: fullTarget?.readyAt ?? fullPushAt.subtract(defaultReadyBeforePush),
        target: fullTarget,
      ),
    ];
  }

  ChargeCommand _windowCommand(
    WindowOccurrence occ,
    WindowOccurrence? previous,
    WindowOccurrence? next,
    List<WindowOccurrence> fromHere,
    List<EffectiveTarget> allTargets,
    int? socPercent,
  ) {
    var pushAt = occ.start.subtract(pushLead);
    var windowStart = occ.start;
    var windowEnd = occ.end;
    // Borne basse pour avancer le debut de plage (jamais sur la plage
    // precedente, deja envoyee).
    DateTime? earliestStart;

    if (previous != null && previous.allDay) {
      // Sortie d'un bloc HC complet : la plage 24 h en place deborderait en
      // heures pleines apres minuit, donc on envoie avant la fin du bloc, et
      // la plage demarre des l'envoi (on est encore en HC) pour ne pas
      // couper la charge.
      final latest = previous.end.subtract(allDayExitMargin);
      if (latest.isBefore(pushAt)) pushAt = latest;
      final floor = allDayFullPushTime.onDay(previous.start).add(const Duration(minutes: _roundingMinutes));
      if (pushAt.isBefore(floor)) pushAt = floor;
      windowStart = _floorTo(pushAt, _roundingMinutes);
      earliestStart = windowStart;
    } else if (previous != null && previous.end.isAfter(pushAt)) {
      // Ne pas remplacer une plage encore en cours.
      pushAt = previous.end;
      earliestStart = previous.end;
    } else {
      earliestStart = previous?.end;
    }

    final target = _firstTarget(allTargets, after: windowStart);
    var extendedMinutes = 0;
    String? note;

    if (target != null) {
      final needed = _neededMinutes(target.targetPercent, socPercent);
      if (needed == null) {
        note = 'Capacité, puissance ou niveau de batterie inconnu : plage non vérifiée pour l\'objectif.';
      } else {
        final available = _availableMinutes(fromHere, windowStart, target.readyAt);
        var deficit = needed - available;
        if (deficit > 0) {
          deficit = _roundUp(deficit, _roundingMinutes);

          // 1) Prolonger la fin, sans depasser l'echeance ni empieter sur la
          //    plage suivante (deja comptee comme disponible).
          var endCap = target.readyAt;
          if (next != null && next.start.isBefore(endCap)) endCap = next.start;
          if (windowEnd.isBefore(endCap)) {
            final extension = _minDuration(Duration(minutes: deficit), endCap.difference(windowEnd));
            windowEnd = windowEnd.add(extension);
            extendedMinutes += extension.inMinutes;
            deficit -= extension.inMinutes;
          }

          // 2) Avancer le debut (l'envoi suit, pour rester avant le debut).
          if (deficit > 0) {
            var newStart = windowStart.subtract(Duration(minutes: deficit));
            if (earliestStart != null && newStart.isBefore(earliestStart)) newStart = earliestStart;
            final gained = windowStart.difference(newStart).inMinutes;
            windowStart = newStart;
            extendedMinutes += gained;
            deficit -= gained;
            if (windowStart.isBefore(pushAt)) pushAt = windowStart;
          }

          if (deficit > 0) {
            note = 'Objectif ${target.targetPercent} % inatteignable à l\'heure : il manque environ $deficit min de charge.';
          }
        }
      }
    }

    var duration = windowEnd.difference(windowStart).inMinutes;
    if (duration > 1440) duration = 1440;

    // L'objectif ne pilote l'heure "pret a" que si aucune autre plage ne le
    // precede ; sinon c'est une plage ulterieure qui le servira.
    final servesTarget = target != null && (next == null || !next.start.isBefore(target.readyAt));
    final readyAt = servesTarget ? target.readyAt : pushAt.subtract(defaultReadyBeforePush);

    return ChargeCommand(
      id: 'window-${_key(occ.start)}',
      kind: ChargeCommandKind.window,
      pushAt: pushAt,
      windowStart: windowStart,
      durationMinutes: duration,
      readyAt: readyAt,
      target: servesTarget ? target : null,
      extendedMinutes: extendedMinutes,
      note: note,
    );
  }

  /// Minutes de charge necessaires pour passer de [socPercent] a
  /// [targetPercent], ou null si une donnee manque.
  int? _neededMinutes(int targetPercent, int? socPercent) {
    final capacity = config.batteryCapacityKwh;
    final power = config.chargePowerKw;
    if (socPercent == null || capacity == null || power == null || capacity <= 0 || power <= 0) return null;
    if (socPercent >= targetPercent) return 0;
    // Fin de charge ralentie (equilibrage des cellules) : au-dela de
    // [slowChargeFromPercent], la puissance est divisee par
    // [slowChargePowerDivisor].
    final fastPart = (targetPercent < slowChargeFromPercent ? targetPercent : slowChargeFromPercent) - socPercent;
    final slowPart = targetPercent - (socPercent > slowChargeFromPercent ? socPercent : slowChargeFromPercent);
    final hours = (fastPart > 0 ? fastPart : 0) / 100 * capacity / power +
        (slowPart > 0 ? slowPart : 0) / 100 * capacity / (power / slowChargePowerDivisor);
    return (hours * 60).ceil();
  }

  /// Minutes de plage HC disponibles entre [from] et [until].
  int _availableMinutes(List<WindowOccurrence> occs, DateTime from, DateTime until) {
    var total = 0;
    for (final occ in occs) {
      final start = _maxDate(occ.leadInStart ?? occ.start, from);
      final end = occ.end.isBefore(until) ? occ.end : until;
      if (end.isAfter(start)) total += end.difference(start).inMinutes;
    }
    return total;
  }

  EffectiveTarget? _firstTarget(List<EffectiveTarget> all, {required DateTime after, DateTime? notAfter}) {
    for (final target in all) {
      if (!target.readyAt.isAfter(after)) continue;
      if (notAfter != null && target.readyAt.isAfter(notAfter)) return null;
      return target;
    }
    return null;
  }

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _nextDay(DateTime d) => DateTime(d.year, d.month, d.day + 1);
  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  static DateTime _maxDate(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
  static Duration _minDuration(Duration a, Duration b) => a < b ? a : b;
  static int _roundUp(int value, int step) => ((value + step - 1) ~/ step) * step;
  static DateTime _floorTo(DateTime d, int stepMinutes) =>
      DateTime(d.year, d.month, d.day, d.hour, d.minute - d.minute % stepMinutes);
  static String _key(DateTime d) =>
      '${d.year}${_two(d.month)}${_two(d.day)}T${_two(d.hour)}${_two(d.minute)}';
  static String _two(int v) => v.toString().padLeft(2, '0');
}
