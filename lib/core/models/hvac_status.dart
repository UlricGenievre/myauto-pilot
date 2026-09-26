/// Etat de la climatisation, endpoint Kamereon `hvac-status`. Champs
/// d'apres `KamereonVehicleHvacStatusData` de `renault-api`, tous
/// optionnels selon le modele.
class HvacStatus {
  const HvacStatus({
    this.isOn,
    this.internalTemperature,
    this.externalTemperature,
    this.socThreshold,
    this.lastUpdated,
  });

  final bool? isOn;
  final double? internalTemperature;
  final double? externalTemperature;

  /// Batterie minimale (%) pour que la voiture accepte de climatiser.
  final int? socThreshold;
  /// Heure de la mesure : la voiture ne la rafraichit qu'eveillee, une
  /// voiture garee depuis des heures renvoie sa derniere valeur (ex. 33 °C
  /// au soleil l'apres-midi, relus en pleine nuit).
  final DateTime? lastUpdated;

  /// Mesure datant de plus de [after] (a signaler a l'affichage).
  bool isStale({Duration after = const Duration(minutes: 30), DateTime? now}) =>
      lastUpdated != null && (now ?? DateTime.now()).difference(lastUpdated!) > after;

  factory HvacStatus.fromJson(Map<String, dynamic> json) {
    final attributes = json['attributes'] as Map<String, dynamic>? ?? json;
    final status = attributes['hvacStatus'] as String?;
    final updated = attributes['lastUpdateTime'] as String?;
    return HvacStatus(
      isOn: status == null ? null : status.toLowerCase() == 'on',
      internalTemperature: (attributes['internalTemperature'] as num?)?.toDouble(),
      externalTemperature: (attributes['externalTemperature'] as num?)?.toDouble(),
      socThreshold: (attributes['socThreshold'] as num?)?.round(),
      lastUpdated: updated != null ? DateTime.tryParse(updated) : null,
    );
  }
}
