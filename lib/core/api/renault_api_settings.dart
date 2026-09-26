/// Cles et serveurs Renault d'un pays (locale `renault-api`, ex. "fr_FR"),
/// charges par l'app depuis `renault-api` (cf. `renault_keys_source.dart`).
class RenaultApiSettings {
  const RenaultApiSettings({
    required this.locale,
    required this.gigyaUrl,
    required this.gigyaKey,
    required this.kamereonUrl,
    required this.kamereonKey,
    this.fetchedAt,
  });

  /// Ex. "fr_FR" : langue (Gigya) + pays (parametre `country` de Kamereon).
  final String locale;
  final String gigyaUrl;
  final String gigyaKey;
  final String kamereonUrl;
  final String kamereonKey;

  /// Date du chargement depuis `renault-api` (affichee dans les reglages).
  final DateTime? fetchedAt;

  /// Ex. "FR".
  String get country => locale.split('_').last;

  /// Memes cles et serveurs (hors date de chargement).
  bool sameValuesAs(RenaultApiSettings other) =>
      locale == other.locale &&
      gigyaUrl == other.gigyaUrl &&
      gigyaKey == other.gigyaKey &&
      kamereonUrl == other.kamereonUrl &&
      kamereonKey == other.kamereonKey;

  RenaultApiSettings copyWith({String? gigyaKey, String? kamereonKey, DateTime? fetchedAt}) => RenaultApiSettings(
        locale: locale,
        gigyaUrl: gigyaUrl,
        gigyaKey: gigyaKey ?? this.gigyaKey,
        kamereonUrl: kamereonUrl,
        kamereonKey: kamereonKey ?? this.kamereonKey,
        fetchedAt: fetchedAt ?? this.fetchedAt,
      );

  Map<String, dynamic> toJson() => {
        'locale': locale,
        'gigyaUrl': gigyaUrl,
        'gigyaKey': gigyaKey,
        'kamereonUrl': kamereonUrl,
        'kamereonKey': kamereonKey,
        'fetchedAt': fetchedAt?.toIso8601String(),
      };

  factory RenaultApiSettings.fromJson(Map<String, dynamic> json) => RenaultApiSettings(
        locale: json['locale'] as String,
        gigyaUrl: json['gigyaUrl'] as String,
        gigyaKey: json['gigyaKey'] as String,
        kamereonUrl: json['kamereonUrl'] as String,
        kamereonKey: json['kamereonKey'] as String,
        fetchedAt: DateTime.tryParse(json['fetchedAt'] as String? ?? ''),
      );
}

/// Noms des pays en francais pour les locales de `renault-api`. Une locale
/// absente de cette table s'affiche avec son code.
const renaultLocaleNames = <String, String>{
  'bg_BG': 'Bulgarie',
  'cs_CZ': 'Tchéquie',
  'da_DK': 'Danemark',
  'de_DE': 'Allemagne',
  'de_AT': 'Autriche',
  'de_CH': 'Suisse (allemand)',
  'en_GB': 'Royaume-Uni',
  'en_IE': 'Irlande',
  'es_ES': 'Espagne',
  'es_MX': 'Mexique',
  'fi_FI': 'Finlande',
  'fr_FR': 'France',
  'fr_BE': 'Belgique (français)',
  'fr_CH': 'Suisse (français)',
  'fr_LU': 'Luxembourg',
  'hr_HR': 'Croatie',
  'hu_HU': 'Hongrie',
  'it_IT': 'Italie',
  'it_CH': 'Suisse (italien)',
  'nl_NL': 'Pays-Bas',
  'nl_BE': 'Belgique (néerlandais)',
  'no_NO': 'Norvège',
  'pl_PL': 'Pologne',
  'pt_PT': 'Portugal',
  'ro_RO': 'Roumanie',
  'ru_RU': 'Russie',
  'sk_SK': 'Slovaquie',
  'sl_SI': 'Slovénie',
  'sv_SE': 'Suède',
};

String renaultLocaleName(String locale) => renaultLocaleNames[locale] ?? locale;

/// Pays propose par defaut a la connexion.
const defaultRenaultLocale = 'fr_FR';
