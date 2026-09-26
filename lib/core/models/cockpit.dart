/// Etat "cockpit" du vehicule (kilometrage, niveau de carburant), endpoint
/// Kamereon `cockpit`.
class Cockpit {
  const Cockpit({this.totalMileageKm, this.fuelLevelPercent, this.fuelAutonomyKm});

  final double? totalMileageKm;
  final int? fuelLevelPercent;
  final int? fuelAutonomyKm;

  factory Cockpit.fromJson(Map<String, dynamic> json) {
    final attributes = json['attributes'] as Map<String, dynamic>? ?? json;
    return Cockpit(
      totalMileageKm: (attributes['totalMileage'] as num?)?.toDouble(),
      fuelLevelPercent: attributes['fuelLevel'] as int?,
      fuelAutonomyKm: attributes['fuelAutonomy'] as int?,
    );
  }
}
