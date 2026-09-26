/// Etat "cockpit" du vehicule (kilometrage, carburant des hybrides),
/// endpoint Kamereon `cockpit`. Champs d'apres `KamereonVehicleCockpitData`
/// de `renault-api` : le carburant est en litres, pas en pourcentage.
class Cockpit {
  const Cockpit({this.totalMileageKm, this.fuelQuantityLiters, this.fuelAutonomyKm});

  final double? totalMileageKm;
  final double? fuelQuantityLiters;
  final int? fuelAutonomyKm;

  /// Information carburant exploitable (vehicule avec reservoir) : les
  /// electriques renvoient 0 ou rien, la tuile est alors masquee.
  bool get hasFuel => (fuelQuantityLiters ?? 0) > 0 || (fuelAutonomyKm ?? 0) > 0;

  factory Cockpit.fromJson(Map<String, dynamic> json) {
    final attributes = json['attributes'] as Map<String, dynamic>? ?? json;
    return Cockpit(
      totalMileageKm: (attributes['totalMileage'] as num?)?.toDouble(),
      fuelQuantityLiters: (attributes['fuelQuantity'] as num?)?.toDouble(),
      fuelAutonomyKm: (attributes['fuelAutonomy'] as num?)?.round(),
    );
  }
}
