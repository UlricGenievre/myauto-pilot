/// Etat de la batterie / charge, endpoint Kamereon `battery-status`.
///
/// Champs `null` pour les vehicules thermiques (pas de batterie de traction).
class BatteryStatus {
  const BatteryStatus({
    this.batteryLevel,
    this.rangeKm,
    this.isCharging,
    this.plugStatus,
    this.chargingRemainingMinutes,
    this.lastUpdated,
    this.batteryCapacityKwh,
    this.availableEnergyKwh,
    this.chargingInstantaneousPower,
  });

  final int? batteryLevel;
  final int? rangeKm;
  final bool? isCharging;
  final String? plugStatus;
  final int? chargingRemainingMinutes;
  final DateTime? lastUpdated;

  /// Capacite et energie disponible (kWh), quand le vehicule les remonte.
  final double? batteryCapacityKwh;
  final double? availableEnergyKwh;

  /// Puissance de charge instantanee, **unite non confirmee** (kW sur la
  /// plupart des modeles, W sur certaines passerelles d'apres `renault-api`) :
  /// valeur brute, a interpreter avec prudence (cf. prefill du parametrage).
  final double? chargingInstantaneousPower;

  factory BatteryStatus.fromJson(Map<String, dynamic> json) {
    final attributes = json['attributes'] as Map<String, dynamic>? ?? json;
    return BatteryStatus(
      batteryLevel: attributes['batteryLevel'] as int?,
      rangeKm: attributes['batteryAutonomy'] as int?,
      isCharging: (attributes['chargingStatus'] as num?) == 1,
      plugStatus: attributes['plugStatus']?.toString(),
      chargingRemainingMinutes: attributes['chargingRemainingTime'] as int?,
      lastUpdated: attributes['timestamp'] != null
          ? DateTime.tryParse(attributes['timestamp'] as String)
          : null,
      batteryCapacityKwh: (attributes['batteryCapacity'] as num?)?.toDouble(),
      availableEnergyKwh: (attributes['batteryAvailableEnergy'] as num?)?.toDouble(),
      chargingInstantaneousPower: (attributes['chargingInstantaneousPower'] as num?)?.toDouble(),
    );
  }
}
