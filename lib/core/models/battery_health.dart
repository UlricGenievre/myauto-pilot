/// Appreciation de la sante, d'apres des seuils propres a l'app (Renault
/// n'en fournit pas).
enum BatteryHealthLevel { good, worn, check }

/// Sante de la batterie de traction (SoH), bloc `sohBlms` de la reponse a
/// `POST .../vehicles/{vin}/state` sur la passerelle "myr" de Renault
/// (`apis.renault.com`, cf. `KamereonClient.fetchBatteryHealth`).
///
/// Constate sur le Rafale reel (XHN1CP, hybride rechargeable) le 2026-11-12 :
/// `{"sohCheck": false, "sohStatus": 5, "soheRef": 96}`. `soheRef` est la
/// capacite actuelle en % de la capacite neuve ; la signification de
/// `sohStatus` et `sohCheck` n'est pas etablie : gardes bruts, non affiches.
class BatteryHealth {
  const BatteryHealth({required this.percent, this.status, this.check});

  /// Capacite actuelle en % de la capacite neuve (0-100).
  final int percent;
  final int? status;
  final bool? check;

  BatteryHealthLevel get level => switch (percent) {
        >= 85 => BatteryHealthLevel.good,
        >= 70 => BatteryHealthLevel.worn,
        _ => BatteryHealthLevel.check,
      };

  /// Null si la reponse ne contient pas de sante exploitable (vehicule qui
  /// ne la fournit pas : la passerelle repond alors sans bloc `sohBlms`).
  static BatteryHealth? fromStateJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final block = json['sohBlms'];
    if (block is! Map<String, dynamic>) return null;
    final percent = (block['soheRef'] as num?)?.round();
    if (percent == null || percent <= 0 || percent > 100) return null;
    return BatteryHealth(
      percent: percent,
      status: (block['sohStatus'] as num?)?.toInt(),
      check: block['sohCheck'] as bool?,
    );
  }
}
