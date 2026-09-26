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
    this.climate = false,
    this.climateTemperature,
  });

  CommandMark.of(ChargeCommand command, String configFingerprint)
      : this(
          id: command.id,
          signature: command.signature,
          configFingerprint: configFingerprint,
          windowStart: command.windowStart,
          durationMinutes: command.durationMinutes,
          readyAt: command.readyAt,
          climate: command.climate,
          climateTemperature: command.climateTemperature,
        );

  final String id;
  final String signature;
  final String configFingerprint;

  /// Contenu exact de la commande (pour une proposition confirmee : c'est
  /// ce contenu-la qui est envoye, sans recalcul).
  final DateTime? windowStart;
  final int? durationMinutes;
  final DateTime? readyAt;
  final bool climate;
  final int? climateTemperature;

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
        if (climate) 'climate': true,
        if (climateTemperature != null) 'climateTemperature': climateTemperature,
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
      climate: json['climate'] as bool? ?? false,
      climateTemperature: json['climateTemperature'] as int?,
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
      );
}
