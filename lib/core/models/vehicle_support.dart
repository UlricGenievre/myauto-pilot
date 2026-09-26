/// Ce que l'app peut faire sur un vehicule, selon son code modele.
///
/// L'ecriture des reglages de charge (`kcm/v1/.../ev/settings`) n'existe que
/// sur certains modeles ; sur les autres, une ecriture mal adaptee pourrait
/// perturber la charge. Trois niveaux :
/// - [verified] : ecriture verifiee sur un vrai vehicule de ce modele ;
/// - [compatible] : meme acces que les modeles verifies d'apres le registre
///   par modele de `renault-api` (`kamereon/models.py`, mode
///   `kcm-settings`), mais ecriture jamais testee : pilotage autorise en
///   mode securise uniquement ;
/// - [unsupported] : lecture seule.
enum VehicleSupport {
  verified,
  compatible,
  unsupported;

  /// Pilotage (ecriture des plages) autorise.
  bool get canWrite => this != unsupported;

  /// Chaque envoi doit etre confirme par l'utilisateur.
  bool get forcesSafeMode => this == compatible;

  static VehicleSupport of(String? modelCode) {
    if (modelCode == null) return unsupported;
    if (verifiedModelCodes.contains(modelCode)) return verified;
    if (kcmSettingsModelCodes.contains(modelCode)) return compatible;
    return unsupported;
  }
}

/// Modeles dont l'ecriture des reglages de charge a ete verifiee sur un vrai
/// vehicule : Rafale (XHN1CP).
const verifiedModelCodes = {'XHN1CP'};

/// Modeles utilisant `kcm/v1/.../ev/settings` pour la charge programmee
/// d'apres `renault-api` : R4 E-Tech (A4E1VE), Alpine A290 (A5E1AE),
/// R5 E-Tech (R5E1VE), XCB1SE, Master E-Tech (XDD1VE), Rafale (XHN1CP).
const kcmSettingsModelCodes = {'A4E1VE', 'A5E1AE', 'R5E1VE', 'XCB1SE', 'XDD1VE', 'XHN1CP'};
