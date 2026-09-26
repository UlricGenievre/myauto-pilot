/// Prise de charge (`plugStatus`, cf. `PlugState` de `renault-api`).
enum PlugState { unplugged, plugged, error }

/// Etat de charge detaille (`chargingStatus`, cf. `ChargeState` de
/// `renault-api`). [waitingPlanned] : branchee, attend sa plage de charge.
enum ChargeState { notCharging, waitingPlanned, ended, waitingCurrent, flapOpen, charging, error, unavailable }

PlugState? _parsePlug(Object? raw) => switch (raw is num ? raw.toInt() : null) {
      0 => PlugState.unplugged,
      1 => PlugState.plugged,
      -1 => PlugState.error,
      _ => null,
    };

ChargeState? _parseCharge(Object? raw) {
  if (raw is! num) return null;
  // Valeurs decimales (0.1, 0.2...) : comparaison au dixieme.
  return switch ((raw * 10).round()) {
    0 => ChargeState.notCharging,
    1 => ChargeState.waitingPlanned,
    2 => ChargeState.ended,
    3 => ChargeState.waitingCurrent,
    4 => ChargeState.flapOpen,
    10 => ChargeState.charging,
    -10 => ChargeState.error,
    -11 => ChargeState.unavailable,
    _ => null,
  };
}

/// Etat de la batterie / charge, endpoint Kamereon `battery-status`.
///
/// Champs `null` pour les vehicules thermiques (pas de batterie de traction).
class BatteryStatus {
  const BatteryStatus({
    this.batteryLevel,
    this.rangeKm,
    this.plugState,
    this.chargeState,
    this.batteryTemperature,
    this.chargingRemainingMinutes,
    this.lastUpdated,
    this.batteryCapacityKwh,
    this.availableEnergyKwh,
    this.chargingInstantaneousPower,
  });

  final int? batteryLevel;
  final int? rangeKm;
  final PlugState? plugState;
  final ChargeState? chargeState;

  /// Temperature de la batterie (°C), quand le vehicule la remonte.
  final int? batteryTemperature;

  bool? get isCharging => chargeState == null ? null : chargeState == ChargeState.charging;
  final int? chargingRemainingMinutes;
  final DateTime? lastUpdated;

  /// Capacite et energie disponible (kWh), quand le vehicule les remonte.
  final double? batteryCapacityKwh;
  final double? availableEnergyKwh;

  /// Puissance de charge instantanee, **unite non confirmee** (kW sur la
  /// plupart des modeles, W sur certaines passerelles d'apres `renault-api`) :
  /// valeur brute, a interpreter avec prudence (cf. prefill du parametrage).
  final double? chargingInstantaneousPower;

  /// [chargingInstantaneousPower] en kW : au-dela de 100, la valeur ne peut
  /// etre que des W.
  double? get chargingPowerKw => switch (chargingInstantaneousPower) {
        final raw? when raw > 0 => raw > 100 ? raw / 1000 : raw,
        _ => null,
      };

  factory BatteryStatus.fromJson(Map<String, dynamic> json) {
    final attributes = json['attributes'] as Map<String, dynamic>? ?? json;
    return BatteryStatus(
      batteryLevel: attributes['batteryLevel'] as int?,
      rangeKm: attributes['batteryAutonomy'] as int?,
      plugState: _parsePlug(attributes['plugStatus']),
      chargeState: _parseCharge(attributes['chargingStatus']),
      batteryTemperature: (attributes['batteryTemperature'] as num?)?.toInt(),
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
