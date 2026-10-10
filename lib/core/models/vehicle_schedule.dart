import 'dart:convert';

/// Type d'un programme : uniquement charge, uniquement preclimatisation, ou
/// les deux combines (c'est ce champ qui indique si le vehicule doit etre
/// climatise, pas un booleen dedie).
enum ProgramKind { charge, preconditioning, chargeAndPreconditioning, unknown }

extension ProgramKindX on ProgramKind {
  bool get includesClimate =>
      this == ProgramKind.preconditioning || this == ProgramKind.chargeAndPreconditioning;
}

ProgramKind _parseProgramKind(String? raw) {
  switch (raw) {
    case 'CHARGE':
      return ProgramKind.charge;
    case 'PRECONDITIONING':
      return ProgramKind.preconditioning;
    case 'CHARGE_AND_PRECONDITIONING':
      return ProgramKind.chargeAndPreconditioning;
    default:
      return ProgramKind.unknown;
  }
}

const Map<int, String> _dayFields = {
  1: 'programActivationMonday',
  2: 'programActivationTuesday',
  3: 'programActivationWednesday',
  4: 'programActivationThursday',
  5: 'programActivationFriday',
  6: 'programActivationSaturday',
  7: 'programActivationSunday',
};

/// Un "programme" : jour(s) + heure a laquelle le vehicule doit etre pret,
/// et si la climatisation doit tourner. Endpoint Kamereon
/// `kcm/v1/vehicles/{vin}/ev/settings` (cf. commentaire dans
/// `KamereonClient.fetchVehicleSchedule` pour pourquoi cet endpoint plutot
/// que `hvac-settings`).
class VehicleProgram {
  const VehicleProgram({
    required this.isActive,
    required this.kind,
    required this.departureTime,
    required this.activeDays,
  });

  final bool isActive;
  final ProgramKind kind;

  /// Heure "HH:MM:SS", deja en heure locale/vehicule (pas de suffixe UTC/Z,
  /// contrairement au format de `hvac-settings`).
  final String? departureTime;

  /// Jours ISO (1=lundi..7=dimanche) ou ce programme s'applique.
  final Set<int> activeDays;

  factory VehicleProgram.fromJson(Map<String, dynamic> json) {
    final days = <int>{
      for (final entry in _dayFields.entries)
        if (json[entry.value] == true) entry.key,
    };
    return VehicleProgram(
      isActive: json['programActivationStatus'] as bool? ?? false,
      kind: _parseProgramKind(json['programType'] as String?),
      departureTime: json['programDepartureTime'] as String?,
      activeDays: days,
    );
  }
}

/// Reglages de charge/preclimatisation du vehicule, endpoint Kamereon
/// `kcm/v1/vehicles/{vin}/ev/settings`. La plage de charge
/// (`chargeWindowStart`/`chargeWindowDurationMinutes`) est unique et globale
/// au vehicule (pas par programme) : c'est elle qui determine quand la
/// charge a effectivement lieu, les programmes ne pilotant que
/// l'heure-cible de disponibilite et la preclimatisation.
class VehicleSchedule {
  const VehicleSchedule({
    required this.chargeMode,
    required this.chargeWindowStart,
    required this.chargeWindowDurationMinutes,
    required this.programs,
    this.raw = const {},
  });

  /// Ex: "SCHEDULED" (seule valeur observee a ce jour, y compris avec une
  /// plage de 24 h).
  final String? chargeMode;

  /// Heure "HH:MM", deja en heure locale/vehicule.
  final String? chargeWindowStart;
  final int? chargeWindowDurationMinutes;
  final List<VehicleProgram> programs;

  /// JSON tel que recu : l'ecriture repose l'objet **complet** (pattern
  /// GET -> mutation -> POST de `renault-api`), y compris les champs que
  /// l'app ne parse pas (preclimatisation, sieges chauffants...).
  final Map<String, dynamic> raw;

  /// Horodatage de derniere modification cote serveur. L'ecriture est
  /// asynchrone (un GET juste apres le POST renvoie encore l'etat
  /// precedent) : c'est ce champ qui permet de savoir quand elle a ete
  /// appliquee.
  String? get lastUpdate => raw['lastSettingsUpdateTimestamp'] as String?;

  /// [now] tombe-t-il dans la plage de charge (quotidienne, commencee
  /// aujourd'hui ou la veille) ? Null si la plage est illisible.
  bool? chargeWindowContains(DateTime now) {
    final parts = chargeWindowStart?.split(':');
    final duration = chargeWindowDurationMinutes;
    if (parts == null || parts.length < 2 || duration == null) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (duration >= 1440) return true;
    for (final dayOffset in [0, -1]) {
      final start = DateTime(now.year, now.month, now.day + dayOffset, hour, minute);
      if (!now.isBefore(start) && now.isBefore(start.add(Duration(minutes: duration)))) return true;
    }
    return false;
  }

  /// Temperature de preclimatisation (°C), commune a tous les programmes.
  num? get preconditioningTemperature => raw['preconditioningTemperature'] as num?;

  factory VehicleSchedule.fromJson(Map<String, dynamic> json) {
    final programs = json['programs'] as List<dynamic>? ?? const [];
    return VehicleSchedule(
      chargeMode: json['chargeModeRq'] as String?,
      chargeWindowStart: json['chargeTimeStart'] as String?,
      chargeWindowDurationMinutes: json['chargeDuration'] as int?,
      programs: programs.map((e) => VehicleProgram.fromJson(e as Map<String, dynamic>)).toList(),
      raw: json,
    );
  }

  /// Copie profonde de [raw] avec les modifications demandees, prete a etre
  /// postee. Seuls les champs passes sont modifies.
  ///
  /// - [chargeTimeStart] : "HH:MM" (format de `chargeTimeStart`).
  /// - [chargeDurationMinutes] : 1440 pour une plage 00:00 -> 00:00.
  /// - [preconditioningTemperature] : temperature d'habitacle (°C), commune
  ///   a tous les programmes.
  /// - [programIndex] + [departureTime] ("HH:MM", converti en "HH:MM:SS"
  ///   comme renvoye par l'API) / [programActive] / [programDays] /
  ///   [programKind] (charge seule ou avec preclimatisation) : programme a
  ///   modifier (index dans `programs[]`, pas d'identifiant cote API).
  Map<String, dynamic> toUpdatedJson({
    String? chargeTimeStart,
    int? chargeDurationMinutes,
    num? preconditioningTemperature,
    int? programIndex,
    String? departureTime,
    bool? programActive,
    Set<int>? programDays,
    ProgramKind? programKind,
  }) {
    final json = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
    if (chargeTimeStart != null) json['chargeTimeStart'] = chargeTimeStart;
    if (chargeDurationMinutes != null) json['chargeDuration'] = chargeDurationMinutes;
    if (preconditioningTemperature != null) json['preconditioningTemperature'] = preconditioningTemperature;

    if (programIndex != null) {
      final programs = json['programs'] as List<dynamic>? ?? const [];
      if (programIndex < 0 || programIndex >= programs.length) {
        throw RangeError.index(programIndex, programs, 'programIndex');
      }
      final program = programs[programIndex] as Map<String, dynamic>;
      if (departureTime != null) {
        program['programDepartureTime'] = departureTime.length == 5 ? '$departureTime:00' : departureTime;
      }
      if (programActive != null) program['programActivationStatus'] = programActive;
      if (programKind != null && programKind != ProgramKind.unknown) {
        program['programType'] = switch (programKind) {
          ProgramKind.charge || ProgramKind.unknown => 'CHARGE',
          ProgramKind.preconditioning => 'PRECONDITIONING',
          ProgramKind.chargeAndPreconditioning => 'CHARGE_AND_PRECONDITIONING',
        };
      }
      if (programDays != null) {
        for (final entry in _dayFields.entries) {
          program[entry.value] = programDays.contains(entry.key);
        }
      }
    }
    return json;
  }
}
