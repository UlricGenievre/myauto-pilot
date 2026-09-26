/// Derniere position connue du vehicule, endpoint Kamereon `location`.
class VehicleLocation {
  const VehicleLocation({required this.latitude, required this.longitude, this.lastUpdated});

  final double latitude;
  final double longitude;
  final DateTime? lastUpdated;

  factory VehicleLocation.fromJson(Map<String, dynamic> json) {
    final attributes = json['attributes'] as Map<String, dynamic>? ?? json;
    return VehicleLocation(
      latitude: (attributes['gpsLatitude'] as num).toDouble(),
      longitude: (attributes['gpsLongitude'] as num).toDouble(),
      lastUpdated: attributes['lastUpdateTime'] != null
          ? DateTime.tryParse(attributes['lastUpdateTime'] as String)
          : null,
    );
  }
}
