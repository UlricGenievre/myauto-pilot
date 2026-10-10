import '../models/vehicle_schedule.dart';
import 'charge_planner.dart';

/// Trace d'une commande envoyee, ignoree ou proposee : de quelle plage il
/// s'agit ([id]), son contenu ([signature] : horaires + heure "pret a") et
/// le parametrage d'alors ([configFingerprint]).
class CommandMark {
  const CommandMark({
    required this.id,
    required this.signature,
    required this.configFingerprint,
    this.windowStart,
    this.durationMinutes,
    this.readyAt,
    this.defaultReadyAt = false,
    this.climate = false,
    this.climateTemperature,
    this.sentAt,
  });

  CommandMark.of(ChargeCommand command, String configFingerprint, {DateTime? sentAt})
      : this(
          id: command.id,
          signature: command.signature,
          configFingerprint: configFingerprint,
          windowStart: command.windowStart,
          durationMinutes: command.durationMinutes,
          readyAt: command.readyAt,
          defaultReadyAt: command.defaultReadyAt,
          climate: command.climate,
          climateTemperature: command.climateTemperature,
          sentAt: sentAt,
        );

  final String id;
  final String signature;
  final String configFingerprint;

  /// Contenu exact de la commande (pour une proposition confirmee : c'est
  /// ce contenu-la qui est envoye, sans recalcul).
  final DateTime? windowStart;
  final int? durationMinutes;
  final DateTime? readyAt;
  final bool defaultReadyAt;
  final bool climate;
  final int? climateTemperature;

  /// Heure reelle de l'envoi, pour une commande envoyee (null : commande
  /// non envoyee, ou envoyee par une version anterieure).
  final DateTime? sentAt;

  bool get hasContent => windowStart != null && durationMinutes != null && readyAt != null;

  /// La commande telle qu'elle a ete proposee (null sans contenu).
  ChargeCommand? toCommand(DateTime now) => hasContent
      ? ChargeCommand(
          id: id,
          kind: ChargeCommandKind.window,
          pushAt: now,
          windowStart: windowStart!,
          durationMinutes: durationMinutes!,
          readyAt: readyAt!,
          defaultReadyAt: defaultReadyAt,
          climate: climate,
          climateTemperature: climateTemperature,
        )
      : null;

  /// Cette trace vaut-elle encore pour [command] ? Oui pour la meme plage,
  /// sauf si le parametrage a change depuis ET que le calcul donne un
  /// contenu different (ex. objectif ajoute ou supprime apres l'envoi). Une
  /// simple variation du niveau de batterie (qui peut modifier
  /// l'elargissement) ne suffit pas : pas de renvoi en pleine charge.
  bool covers(ChargeCommand command, String currentConfigFingerprint) =>
      command.id == id && (currentConfigFingerprint == configFingerprint || command.signature == signature);

  Map<String, dynamic> toJson() => {
        'id': id,
        'signature': signature,
        'configFingerprint': configFingerprint,
        'windowStart': windowStart?.toIso8601String(),
        'durationMinutes': durationMinutes,
        'readyAt': readyAt?.toIso8601String(),
        if (defaultReadyAt) 'defaultReadyAt': true,
        if (climate) 'climate': true,
        if (climateTemperature != null) 'climateTemperature': climateTemperature,
        if (sentAt != null) 'sentAt': sentAt!.toIso8601String(),
      };

  static CommandMark? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'] as String?;
    if (id == null) return null;
    return CommandMark(
      id: id,
      signature: json['signature'] as String? ?? '',
      configFingerprint: json['configFingerprint'] as String? ?? '',
      windowStart: DateTime.tryParse(json['windowStart'] as String? ?? ''),
      durationMinutes: json['durationMinutes'] as int?,
      readyAt: DateTime.tryParse(json['readyAt'] as String? ?? ''),
      defaultReadyAt: json['defaultReadyAt'] as bool? ?? false,
      climate: json['climate'] as bool? ?? false,
      climateTemperature: json['climateTemperature'] as int?,
      sentAt: DateTime.tryParse(json['sentAt'] as String? ?? ''),
    );
  }
}

/// Reglages de la voiture remplaces par une charge immediate : plage et
/// programme dedie, remis a sa fin quand le pilotage est coupe (sinon, la
/// plage de la charge immediate se repeterait chaque jour).
class CarSettingsSnapshot {
  const CarSettingsSnapshot({
    required this.chargeTimeStart,
    required this.durationMinutes,
    required this.programIndex,
    this.departureTime,
    this.programActive,
    this.programDays,
    this.programKind = ProgramKind.unknown,
  });

  /// Null si la voiture n'a pas de plage lisible, ou sans [programIndex]
  /// dans [schedule].
  static CarSettingsSnapshot? of(VehicleSchedule schedule, int programIndex) {
    final start = schedule.chargeWindowStart;
    final duration = schedule.chargeWindowDurationMinutes;
    if (start == null || duration == null || programIndex < 0 || programIndex >= schedule.programs.length) return null;
    final program = schedule.programs[programIndex];
    return CarSettingsSnapshot(
      chargeTimeStart: start,
      durationMinutes: duration,
      programIndex: programIndex,
      departureTime: program.departureTime,
      programActive: program.isActive,
      programDays: program.activeDays,
      programKind: program.kind,
    );
  }

  /// "HH:MM", tel que lu dans `ev/settings`.
  final String chargeTimeStart;
  final int durationMinutes;
  final int programIndex;
  final String? departureTime;
  final bool? programActive;
  final Set<int>? programDays;
  final ProgramKind programKind;

  /// [current] avec ces reglages remis, pret a etre poste.
  Map<String, dynamic> applyTo(VehicleSchedule current) => current.toUpdatedJson(
        chargeTimeStart: chargeTimeStart,
        chargeDurationMinutes: durationMinutes,
        programIndex: programIndex,
        departureTime: departureTime,
        programActive: programActive,
        programDays: programDays,
        programKind: programKind,
      );

  Map<String, dynamic> toJson() => {
        'chargeTimeStart': chargeTimeStart,
        'durationMinutes': durationMinutes,
        'programIndex': programIndex,
        'departureTime': departureTime,
        'programActive': programActive,
        'programDays': programDays?.toList(),
        'programKind': programKind.name,
      };

  static CarSettingsSnapshot? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final start = json['chargeTimeStart'] as String?;
    final duration = json['durationMinutes'] as int?;
    final index = json['programIndex'] as int?;
    if (start == null || duration == null || index == null) return null;
    final kind = json['programKind'] as String?;
    return CarSettingsSnapshot(
      chargeTimeStart: start,
      durationMinutes: duration,
      programIndex: index,
      departureTime: json['departureTime'] as String?,
      programActive: json['programActive'] as bool?,
      programDays: (json['programDays'] as List<dynamic>?)?.cast<int>().toSet(),
      programKind: ProgramKind.values.asNameMap()[kind] ?? ProgramKind.unknown,
    );
  }
}

/// Charge immediate envoyee a la voiture a la place de la plage en vigueur :
/// jusqu'a la charge minimale (proposee par le pilotage) ou jusqu'a la cible
/// demandee depuis l'app ([manual]).
class ImmediateCharge {
  const ImmediateCharge({
    required this.sentAt,
    required this.end,
    this.windowStart,
    this.durationMinutes,
    this.targetPercent,
    this.manual = false,
    this.displaced,
    this.merged = false,
    this.previous,
  });

  final DateTime sentAt;

  /// Fin de la charge (fin de la plage d'heures creuses si [merged]).
  final DateTime end;

  /// Plage envoyee a la voiture (null : charge envoyee par une version
  /// anterieure). Distincte de [end] une fois la charge arretee.
  final DateTime? windowStart;
  final int? durationMinutes;

  /// La voiture a-t-elle encore cette plage ? Non si elle a ete modifiee
  /// hors app (ex. depuis MyRenault) ; null si on ne peut pas le dire.
  bool? inCar(VehicleSchedule car) {
    final start = windowStart;
    final duration = durationMinutes;
    return start == null || duration == null ? null : car.hasChargeWindow(start, duration);
  }

  /// Niveau vise (charge minimale, ou cible demandee).
  final int? targetPercent;

  /// Demandee depuis l'app, pilotage actif ou non.
  final bool manual;

  /// Commande en place dans la voiture avant la charge immediate, renvoyee
  /// a sa fin (sans confirmation : le telephone peut etre en mode nuit).
  final CommandMark? displaced;

  /// Prolongee jusqu'a la fin de la plage d'heures creuses suivante, qui
  /// compte alors comme envoyee : rien a renvoyer a la fin.
  final bool merged;

  /// Reglages de la voiture juste avant : remis a la fin si le pilotage
  /// est coupe (ou s'il n'a rien a renvoyer).
  final CarSettingsSnapshot? previous;

  bool activeAt(DateTime now) => end.isAfter(now);

  ImmediateCharge copyWith({DateTime? end, CommandMark? displaced, bool? merged}) => ImmediateCharge(
        sentAt: sentAt,
        end: end ?? this.end,
        windowStart: windowStart,
        durationMinutes: durationMinutes,
        targetPercent: targetPercent,
        manual: manual,
        displaced: displaced ?? this.displaced,
        merged: merged ?? this.merged,
        previous: previous,
      );

  Map<String, dynamic> toJson() => {
        'sentAt': sentAt.toIso8601String(),
        'end': end.toIso8601String(),
        if (windowStart != null) 'windowStart': windowStart!.toIso8601String(),
        if (durationMinutes != null) 'durationMinutes': durationMinutes,
        if (targetPercent != null) 'targetPercent': targetPercent,
        if (manual) 'manual': true,
        'displaced': displaced?.toJson(),
        if (merged) 'merged': true,
        if (previous != null) 'previous': previous!.toJson(),
      };

  static ImmediateCharge? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final sentAt = DateTime.tryParse(json['sentAt'] as String? ?? '');
    final end = DateTime.tryParse(json['end'] as String? ?? '');
    if (sentAt == null || end == null) return null;
    return ImmediateCharge(
      sentAt: sentAt,
      end: end,
      windowStart: DateTime.tryParse(json['windowStart'] as String? ?? ''),
      durationMinutes: json['durationMinutes'] as int?,
      targetPercent: json['targetPercent'] as int?,
      manual: json['manual'] as bool? ?? false,
      displaced: CommandMark.fromJson(json['displaced']),
      merged: json['merged'] as bool? ?? false,
      previous: CarSettingsSnapshot.fromJson(json['previous']),
    );
  }
}

/// Etat d'execution du pilotage automatique, persiste entre les reveils
/// (chaque reveil tourne dans un isolate neuf, sans memoire).
class PilotState {
  const PilotState({
    this.sent,
    this.ignored,
    this.pending,
    this.confirmed,
    this.lastResult,
    this.lastResultOk,
    this.lastResultAt,
    this.nextWakeAt,
    this.sendingSince,
    this.boost,
    this.boostProposed = false,
    this.boostConfirmed = false,
    this.boostDismissed = false,
    this.manualChargeTarget,
  });

  /// Derniere commande envoyee avec succes.
  final CommandMark? sent;

  /// Commande que l'utilisateur a choisi d'ignorer (mode securise).
  final CommandMark? ignored;

  /// Commande proposee par notification, en attente de confirmation.
  final CommandMark? pending;

  String? get sentId => sent?.id;
  String? get ignoredId => ignored?.id;
  String? get pendingId => pending?.id;

  /// Proposition confirmee par l'utilisateur, a envoyer telle quelle par le
  /// prochain reveil "execution".
  final CommandMark? confirmed;

  String? get confirmedId => confirmed?.id;

  /// Dernier resultat, affiche dans l'ecran de pilotage.
  final String? lastResult;
  final bool? lastResultOk;
  final DateTime? lastResultAt;

  /// Prochain reveil programme (envoi suivant).
  final DateTime? nextWakeAt;

  /// Verrou d'envoi : un envoi est en cours depuis cette date (partage entre
  /// l'app et les reveils, cf. `ChargePilot.sendLockTimeout`).
  final DateTime? sendingSince;

  /// Charge immediate envoyee (en cours ou a solder).
  final ImmediateCharge? boost;

  /// Charge immediate proposee (notification affichee), sans reponse.
  final bool boostProposed;

  /// Charge immediate acceptee, a envoyer par le reveil "execution".
  final bool boostConfirmed;

  /// Proposition refusee : plus reproposee avant que la batterie repasse
  /// au-dessus du minimum ou que la voiture soit debranchee.
  final bool boostDismissed;

  /// Charge immediate demandee depuis l'app jusqu'a ce niveau, a envoyer
  /// par le reveil "execution".
  final int? manualChargeTarget;

  PilotState copyWith({
    CommandMark? sent,
    CommandMark? ignored,
    CommandMark? pending,
    bool clearPending = false,
    CommandMark? confirmed,
    bool clearConfirmed = false,
    String? lastResult,
    bool? lastResultOk,
    DateTime? lastResultAt,
    DateTime? nextWakeAt,
    bool clearNextWake = false,
    DateTime? sendingSince,
    bool clearSending = false,
    ImmediateCharge? boost,
    bool clearBoost = false,
    bool? boostProposed,
    bool? boostConfirmed,
    bool? boostDismissed,
    int? manualChargeTarget,
    bool clearManualChargeTarget = false,
  }) =>
      PilotState(
        sent: sent ?? this.sent,
        ignored: ignored ?? this.ignored,
        pending: clearPending ? null : (pending ?? this.pending),
        confirmed: clearConfirmed ? null : (confirmed ?? this.confirmed),
        lastResult: lastResult ?? this.lastResult,
        lastResultOk: lastResultOk ?? this.lastResultOk,
        lastResultAt: lastResultAt ?? this.lastResultAt,
        nextWakeAt: clearNextWake ? null : (nextWakeAt ?? this.nextWakeAt),
        sendingSince: clearSending ? null : (sendingSince ?? this.sendingSince),
        boost: clearBoost ? null : (boost ?? this.boost),
        boostProposed: boostProposed ?? this.boostProposed,
        boostConfirmed: boostConfirmed ?? this.boostConfirmed,
        boostDismissed: boostDismissed ?? this.boostDismissed,
        manualChargeTarget: clearManualChargeTarget ? null : (manualChargeTarget ?? this.manualChargeTarget),
      );

  Map<String, dynamic> toJson() => {
        'sent': sent?.toJson(),
        'ignored': ignored?.toJson(),
        'pending': pending?.toJson(),
        'confirmed': confirmed?.toJson(),
        'lastResult': lastResult,
        'lastResultOk': lastResultOk,
        'lastResultAt': lastResultAt?.toIso8601String(),
        'nextWakeAt': nextWakeAt?.toIso8601String(),
        'sendingSince': sendingSince?.toIso8601String(),
        'boost': boost?.toJson(),
        if (boostProposed) 'boostProposed': true,
        if (boostConfirmed) 'boostConfirmed': true,
        if (boostDismissed) 'boostDismissed': true,
        if (manualChargeTarget != null) 'manualChargeTarget': manualChargeTarget,
      };

  factory PilotState.fromJson(Map<String, dynamic> json) => PilotState(
        sent: CommandMark.fromJson(json['sent']),
        ignored: CommandMark.fromJson(json['ignored']),
        pending: CommandMark.fromJson(json['pending']),
        confirmed: CommandMark.fromJson(json['confirmed']),
        lastResult: json['lastResult'] as String?,
        lastResultOk: json['lastResultOk'] as bool?,
        lastResultAt: DateTime.tryParse(json['lastResultAt'] as String? ?? ''),
        nextWakeAt: DateTime.tryParse(json['nextWakeAt'] as String? ?? ''),
        sendingSince: DateTime.tryParse(json['sendingSince'] as String? ?? ''),
        boost: ImmediateCharge.fromJson(json['boost']),
        boostProposed: json['boostProposed'] as bool? ?? false,
        boostConfirmed: json['boostConfirmed'] as bool? ?? false,
        boostDismissed: json['boostDismissed'] as bool? ?? false,
        manualChargeTarget: json['manualChargeTarget'] as int?,
      );
}
