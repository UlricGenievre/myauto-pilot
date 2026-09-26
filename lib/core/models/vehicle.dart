/// Un vehicule rattache au compte MyRenault.
class Vehicle {
  const Vehicle({
    required this.vin,
    required this.brand,
    required this.model,
    this.modelCode,
    this.nickname,
  });

  final String vin;
  final String brand;
  final String model;

  /// Code modele Renault (ex. "R5E1VE") : determine ce que l'app peut
  /// ecrire sur ce vehicule (cf. `vehicle_support.dart`).
  final String? modelCode;
  final String? nickname;

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      vin: json['vin'] as String,
      brand: (json['brand'] as Map<String, dynamic>?)?['label'] as String? ?? '',
      model: (json['model'] as Map<String, dynamic>?)?['label'] as String? ?? '',
      modelCode: (json['model'] as Map<String, dynamic>?)?['code'] as String?,
      nickname: json['nickname'] as String?,
    );
  }

  String get displayName => nickname?.isNotEmpty == true ? nickname! : '$brand $model';
}
