/// Parametrage du pilotage de charge, entierement stocke cote app (la voiture
/// n'en voit que ce que l'app lui envoie : sa plage de charge unique + le
/// programme dedie). Voir `.claude/plans/charge-heures-creuses.md`.
///
/// Classes Dart pures (pas de dependance Flutter/Riverpod) : reutilisees
/// telles quelles par les reveils en arriere-plan.
library;

import 'dart:convert';

import 'vehicle_support.dart';

/// Heure de la journee en minutes depuis minuit (0..1440 ; 1440 = "24:00",
/// utile pour une fin de plage a minuit).
class ClockTime implements Comparable<ClockTime> {
  const ClockTime(this.minutes) : assert(minutes >= 0 && minutes <= 1440);

  ClockTime.hm(int hour, int minute) : this(hour * 60 + minute);

  final int minutes;

  int get hour => minutes ~/ 60;
  int get minute => minutes % 60;

  /// Accepte "HH:MM" et "HH:MM:SS" (secondes ignorees), comme renvoye par
  /// `ev/settings`. Null si le format est inattendu.
  static ClockTime? tryParse(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'^(\d{2}):(\d{2})(?::\d{2})?$').firstMatch(raw);
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 24 || minute > 59 || (hour == 24 && minute > 0)) return null;
    return ClockTime.hm(hour, minute);
  }

  /// "HH:MM".
  String format() => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// Cette heure le jour de [day] (seule la date de [day] est utilisee).
  /// Construit par composantes (et non `+ Duration`) pour rester juste les
  /// jours de changement d'heure.
  DateTime onDay(DateTime day) => DateTime(day.year, day.month, day.day, hour, minute);

  @override
  int compareTo(ClockTime other) => minutes.compareTo(other.minutes);

  @override
  bool operator ==(Object other) => other is ClockTime && other.minutes == minutes;

  @override
  int get hashCode => minutes.hashCode;

  @override
  String toString() => format();
}

/// Plage de charge d'un jour. [end] <= [start] signifie que la plage passe
/// minuit (ex. 22:00-06:00) : elle est rattachee au jour ou elle commence.
class ChargeWindow {
  const ChargeWindow({required this.start, required this.end});

  final ClockTime start;
  final ClockTime end;

  int get durationMinutes {
    final raw = end.minutes - start.minutes;
    return raw > 0 ? raw : raw + 1440;
  }

  Map<String, dynamic> toJson() => {'start': start.format(), 'end': end.format()};

  factory ChargeWindow.fromJson(Map<String, dynamic> json) => ChargeWindow(
        start: ClockTime.tryParse(json['start'] as String?) ?? const ClockTime(0),
        end: ClockTime.tryParse(json['end'] as String?) ?? const ClockTime(0),
      );
}

/// Plages de charge d'un jour de semaine : soit la journee entiere, soit une
/// liste de plages (vide = aucune charge ce jour-la).
class DaySchedule {
  const DaySchedule({this.allDay = false, this.windows = const []});

  final bool allDay;
  final List<ChargeWindow> windows;

  DaySchedule copyWith({bool? allDay, List<ChargeWindow>? windows}) =>
      DaySchedule(allDay: allDay ?? this.allDay, windows: windows ?? this.windows);

  Map<String, dynamic> toJson() => {
        'allDay': allDay,
        'windows': windows.map((w) => w.toJson()).toList(),
      };

  factory DaySchedule.fromJson(Map<String, dynamic> json) => DaySchedule(
        allDay: json['allDay'] as bool? ?? false,
        windows: (json['windows'] as List<dynamic>? ?? const [])
            .map((e) => ChargeWindow.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Calendrier hebdomadaire des plages de charge (contrat heures creuses),
/// jours ISO 1 (lundi) .. 7 (dimanche). Jour absent = aucune plage.
class ChargeCalendar {
  const ChargeCalendar({this.days = const {}});

  final Map<int, DaySchedule> days;

  DaySchedule dayOf(int weekday) => days[weekday] ?? const DaySchedule();

  ChargeCalendar withDay(int weekday, DaySchedule schedule) =>
      ChargeCalendar(days: {...days, weekday: schedule});

  Map<String, dynamic> toJson() => {
        for (final entry in days.entries) '${entry.key}': entry.value.toJson(),
      };

  factory ChargeCalendar.fromJson(Map<String, dynamic> json) => ChargeCalendar(
        days: {
          for (final entry in json.entries)
            int.parse(entry.key): DaySchedule.fromJson(entry.value as Map<String, dynamic>),
        },
      );
}

/// Temperature d'habitacle d'un objectif climatise (°C) : plage proposee
/// et valeur par defaut (celle de MyRenault).
const minClimateTemperature = 16;
const maxClimateTemperature = 26;
const defaultClimateTemperature = 21;

/// Objectif recurrent : "pret a [targetPercent] % a [readyAt]", habitacle
/// climatise a [climateTemperature] °C a cette heure si [climate].
///
/// La climatisation n'apparait dans le JSON que si elle est active :
/// l'empreinte des parametrages sans climatisation reste celle d'avant
/// l'option.
class ReadyTarget {
  const ReadyTarget({
    required this.targetPercent,
    required this.readyAt,
    this.climate = false,
    this.climateTemperature = defaultClimateTemperature,
  });

  final int targetPercent;
  final ClockTime readyAt;
  final bool climate;

  /// Ecrite dans la voiture avec la plage qui sert cet objectif (reglage
  /// unique de la voiture, reecrit a chaque envoi).
  final int climateTemperature;

  ReadyTarget copyWith({int? targetPercent, ClockTime? readyAt, bool? climate, int? climateTemperature}) =>
      ReadyTarget(
        targetPercent: targetPercent ?? this.targetPercent,
        readyAt: readyAt ?? this.readyAt,
        climate: climate ?? this.climate,
        climateTemperature: climateTemperature ?? this.climateTemperature,
      );

  Map<String, dynamic> toJson() => {
        'targetPercent': targetPercent,
        'readyAt': readyAt.format(),
        if (climate) ...{'climate': true, 'climateTemperature': climateTemperature},
      };

  factory ReadyTarget.fromJson(Map<String, dynamic> json) => ReadyTarget(
        targetPercent: json['targetPercent'] as int? ?? 80,
        readyAt: ClockTime.tryParse(json['readyAt'] as String?) ?? ClockTime.hm(7, 0),
        climate: json['climate'] as bool? ?? false,
        climateTemperature: json['climateTemperature'] as int? ?? defaultClimateTemperature,
      );
}

/// Agenda nomme d'objectifs par jour de semaine (ex. "Habituel",
/// "Vacances"). Au plus un objectif par jour ; jour absent = pas d'objectif.
class TargetAgenda {
  const TargetAgenda({required this.id, required this.name, this.targets = const {}});

  final String id;
  final String name;
  final Map<int, ReadyTarget> targets;

  TargetAgenda copyWith({String? name, Map<int, ReadyTarget>? targets}) =>
      TargetAgenda(id: id, name: name ?? this.name, targets: targets ?? this.targets);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'targets': {for (final entry in targets.entries) '${entry.key}': entry.value.toJson()},
      };

  factory TargetAgenda.fromJson(Map<String, dynamic> json) => TargetAgenda(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        targets: {
          for (final entry in (json['targets'] as Map<String, dynamic>? ?? const {}).entries)
            int.parse(entry.key): ReadyTarget.fromJson(entry.value as Map<String, dynamic>),
        },
      );
}

/// Objectif exceptionnel ("demain 7h a 100 %") : prioritaire sur l'agenda
/// ce jour-la, ignore une fois l'echeance passee.
class OneOffTarget {
  const OneOffTarget({
    required this.targetPercent,
    required this.readyAt,
    this.climate = false,
    this.climateTemperature = defaultClimateTemperature,
  });

  final int targetPercent;
  final DateTime readyAt;

  /// Habitacle climatise a [readyAt] (cf. [ReadyTarget.climate]).
  final bool climate;
  final int climateTemperature;

  Map<String, dynamic> toJson() => {
        'targetPercent': targetPercent,
        'readyAt': readyAt.toIso8601String(),
        if (climate) ...{'climate': true, 'climateTemperature': climateTemperature},
      };

  factory OneOffTarget.fromJson(Map<String, dynamic> json) => OneOffTarget(
        targetPercent: json['targetPercent'] as int? ?? 100,
        readyAt: DateTime.parse(json['readyAt'] as String),
        climate: json['climate'] as bool? ?? false,
        climateTemperature: json['climateTemperature'] as int? ?? defaultClimateTemperature,
      );
}

class ChargePlanConfig {
  const ChargePlanConfig({
    this.batteryCapacityKwh,
    this.chargePowerKw,
    this.calendar = const ChargeCalendar(),
    this.agendas = const [],
    this.activeAgendaId,
    this.oneOffTarget,
    this.dedicatedProgramIndex,
    this.enabled = false,
    this.safeMode = true,
    this.vehicleVin,
    this.vehicleModelCode,
    this.pushLeadMinutes = defaultPushLeadMinutes,
  });

  static const defaultPushLeadMinutes = 240;


  final double? batteryCapacityKwh;
  final double? chargePowerKw;
  final ChargeCalendar calendar;
  final List<TargetAgenda> agendas;

  /// Un seul agenda actif a la fois, ou aucun (null).
  final String? activeAgendaId;
  final OneOffTarget? oneOffTarget;

  /// Position dans `programs[]` de `ev/settings` du programme que l'app a le
  /// droit de modifier : les programmes Kamereon n'ont pas d'identifiant.
  final int? dedicatedProgramIndex;

  /// Interrupteur maitre du pilotage automatique.
  final bool enabled;

  /// Mode securise : chaque envoi est propose par notification et n'est
  /// fait qu'apres confirmation de l'utilisateur.
  final bool safeMode;

  /// Vehicule pilote : les reveils tournent sans interface, donc sans
  /// "vehicule selectionne".
  final String? vehicleVin;

  /// Code modele du vehicule pilote : determine ce que l'app peut y ecrire.
  final String? vehicleModelCode;

  VehicleSupport get vehicleSupport => VehicleSupport.of(vehicleModelCode);

  /// Mode securise effectif : choisi par l'utilisateur, ou impose tant que
  /// le modele n'est pas verifie.
  bool get effectiveSafeMode => safeMode || vehicleSupport.forcesSafeMode;

  /// Delai entre l'envoi d'une plage a la voiture et son debut.
  final int pushLeadMinutes;


  /// Empreinte du parametrage (FNV-1a 32 bits de sa forme JSON) : sert a
  /// savoir s'il a change depuis un envoi. Stable d'une execution a
  /// l'autre, contrairement a `String.hashCode`.
  String get fingerprint {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(jsonEncode(toJson()))) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  TargetAgenda? get activeAgenda {
    for (final agenda in agendas) {
      if (agenda.id == activeAgendaId) return agenda;
    }
    return null;
  }

  // Les champs nullables se remettent a null via les `clear*` explicites
  // (un simple `copyWith(x: null)` ne permet pas de distinguer "inchange").
  ChargePlanConfig copyWith({
    double? batteryCapacityKwh,
    double? chargePowerKw,
    ChargeCalendar? calendar,
    List<TargetAgenda>? agendas,
    String? activeAgendaId,
    bool clearActiveAgenda = false,
    OneOffTarget? oneOffTarget,
    bool clearOneOffTarget = false,
    int? dedicatedProgramIndex,
    bool? enabled,
    bool? safeMode,
    String? vehicleVin,
    String? vehicleModelCode,
    int? pushLeadMinutes,
  }) =>
      ChargePlanConfig(
        batteryCapacityKwh: batteryCapacityKwh ?? this.batteryCapacityKwh,
        chargePowerKw: chargePowerKw ?? this.chargePowerKw,
        calendar: calendar ?? this.calendar,
        agendas: agendas ?? this.agendas,
        activeAgendaId: clearActiveAgenda ? null : (activeAgendaId ?? this.activeAgendaId),
        oneOffTarget: clearOneOffTarget ? null : (oneOffTarget ?? this.oneOffTarget),
        dedicatedProgramIndex: dedicatedProgramIndex ?? this.dedicatedProgramIndex,
        enabled: enabled ?? this.enabled,
        safeMode: safeMode ?? this.safeMode,
        vehicleVin: vehicleVin ?? this.vehicleVin,
        vehicleModelCode: vehicleModelCode ?? this.vehicleModelCode,
        pushLeadMinutes: pushLeadMinutes ?? this.pushLeadMinutes,
      );

  Map<String, dynamic> toJson() => {
        'batteryCapacityKwh': batteryCapacityKwh,
        'chargePowerKw': chargePowerKw,
        'calendar': calendar.toJson(),
        'agendas': agendas.map((a) => a.toJson()).toList(),
        'activeAgendaId': activeAgendaId,
        'oneOffTarget': oneOffTarget?.toJson(),
        'dedicatedProgramIndex': dedicatedProgramIndex,
        'enabled': enabled,
        'safeMode': safeMode,
        'vehicleVin': vehicleVin,
        'vehicleModelCode': vehicleModelCode,
        'pushLeadMinutes': pushLeadMinutes,
      };

  factory ChargePlanConfig.fromJson(Map<String, dynamic> json) => ChargePlanConfig(
        batteryCapacityKwh: (json['batteryCapacityKwh'] as num?)?.toDouble(),
        chargePowerKw: (json['chargePowerKw'] as num?)?.toDouble(),
        calendar: ChargeCalendar.fromJson(json['calendar'] as Map<String, dynamic>? ?? const {}),
        agendas: (json['agendas'] as List<dynamic>? ?? const [])
            .map((e) => TargetAgenda.fromJson(e as Map<String, dynamic>))
            .toList(),
        activeAgendaId: json['activeAgendaId'] as String?,
        oneOffTarget: json['oneOffTarget'] != null
            ? OneOffTarget.fromJson(json['oneOffTarget'] as Map<String, dynamic>)
            : null,
        dedicatedProgramIndex: json['dedicatedProgramIndex'] as int?,
        enabled: json['enabled'] as bool? ?? false,
        safeMode: json['safeMode'] as bool? ?? true,
        vehicleVin: json['vehicleVin'] as String?,
        vehicleModelCode: json['vehicleModelCode'] as String?,
        pushLeadMinutes: json['pushLeadMinutes'] as int? ?? defaultPushLeadMinutes,
      );
}
