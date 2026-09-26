import 'package:flutter_test/flutter_test.dart';
import 'package:myauto_pilot/core/api/renault_api_settings.dart';
import 'package:myauto_pilot/core/api/renault_keys_source.dart';

/// Extrait synthetique de `renault-api/const.py` : memes formes que le vrai
/// fichier (constantes CONF_*, references par nom, litteral inline avec
/// commentaire, parentheses multi-lignes), mais avec de FAUSSES cles.
const fixture = '''
"""Constants for Renault API."""

CONF_COUNTRY = "country"
CONF_LOCALE = "locale"
CONF_GIGYA_APIKEY = "gigya-api-key"
CONF_GIGYA_URL = "gigya-root-url"
CONF_KAMEREON_APIKEY = "kamereon-api-key"
CONF_KAMEREON_URL = "kamereon-root-url"

GIGYA_KEY_EU = "3_FakeEuropeGigyaKey0123456789"
GIGYA_URL_EU = "https://accounts.eu1.gigya.com"
GIGYA_URL_US = "https://accounts.us1.gigya.com"
KAMEREON_APIKEY = "FakeKamereonKey0123456789abcdef"
KAMEREON_URL_EU = "https://api-wired-prod-1-euw1.wrd-aws.com"
KAMEREON_URL_US = "https://api-wired-prod-1-usw2.wrd-aws.com"

LOCALE_BASE_URL = (
    "https://example.s3-eu-west-1.amazonaws.com"
)

AVAILABLE_LOCALES = {
    "fr_FR": {
        CONF_GIGYA_URL: GIGYA_URL_EU,
        CONF_GIGYA_APIKEY: GIGYA_KEY_EU,
        CONF_KAMEREON_URL: KAMEREON_URL_EU,
        CONF_KAMEREON_APIKEY: KAMEREON_APIKEY,
    },
    "es_MX": {
        CONF_GIGYA_URL: GIGYA_URL_US,
        CONF_GIGYA_APIKEY: "4_FakeMexicoKey01234",  # noqa
        CONF_KAMEREON_URL: KAMEREON_URL_US,
        CONF_KAMEREON_APIKEY: KAMEREON_APIKEY,
    },
    "xx_XX": {
        CONF_GIGYA_URL: "https://evil.example.com",
        CONF_GIGYA_APIKEY: GIGYA_KEY_EU,
        CONF_KAMEREON_URL: KAMEREON_URL_EU,
        CONF_KAMEREON_APIKEY: KAMEREON_APIKEY,
    },
}

MIN_SOC_MIN = 15
''';

RenaultApiSettings settings({String? gigyaUrl, String? gigyaKey, String? kamereonUrl, String? kamereonKey}) =>
    RenaultApiSettings(
      locale: 'fr_FR',
      gigyaUrl: gigyaUrl ?? 'https://accounts.eu1.gigya.com',
      gigyaKey: gigyaKey ?? '3_FakeEuropeGigyaKey0123456789',
      kamereonUrl: kamereonUrl ?? 'https://api-wired-prod-1-euw1.wrd-aws.com',
      kamereonKey: kamereonKey ?? 'FakeKamereonKey0123456789abcdef',
    );

void main() {
  group('parseRenaultConst', () {
    final parsed = {for (final s in parseRenaultConst(fixture)) s.locale: s};

    test('resout les references par nom (pas les constantes CONF_*)', () {
      final fr = parsed['fr_FR']!;
      expect(fr.gigyaKey, '3_FakeEuropeGigyaKey0123456789');
      expect(fr.kamereonKey, 'FakeKamereonKey0123456789abcdef');
      expect(fr.gigyaUrl, 'https://accounts.eu1.gigya.com');
      expect(fr.kamereonUrl, 'https://api-wired-prod-1-euw1.wrd-aws.com');
      expect(fr.country, 'FR');
    });

    test('lit un litteral inline (avec commentaire en fin de ligne)', () {
      final mx = parsed['es_MX']!;
      expect(mx.gigyaKey, '4_FakeMexicoKey01234');
      expect(mx.gigyaUrl, 'https://accounts.us1.gigya.com');
    });

    test('ecarte une locale dont le serveur n\'est pas autorise', () {
      expect(parsed.containsKey('xx_XX'), isFalse);
    });

    test('structure introuvable : FormatException', () {
      expect(() => parseRenaultConst('GIGYA_KEY_EU = "3_x"'), throwsFormatException);
    });
  });

  group('validateRenaultSettings', () {
    test('valeurs actuelles acceptees', () {
      expect(validateRenaultSettings(settings()), isNull);
    });

    test('serveurs hors liste refuses', () {
      expect(validateRenaultSettings(settings(gigyaUrl: 'https://accounts.eu1.gigya.com.evil.io')), isNotNull);
      expect(validateRenaultSettings(settings(gigyaUrl: 'http://accounts.eu1.gigya.com')), isNotNull);
      expect(validateRenaultSettings(settings(kamereonUrl: 'https://wrd-aws.com.evil.io')), isNotNull);
      expect(validateRenaultSettings(settings(kamereonUrl: 'https://user@api.wrd-aws.com')), isNotNull);
      expect(validateRenaultSettings(settings(kamereonUrl: 'https://api.wrd-aws.com/proxy')), isNotNull);
      expect(validateRenaultSettings(settings(kamereonUrl: 'https://api-wired.kamereon.com')), isNull);
    });

    test('cles au format inattendu refusees', () {
      expect(validateRenaultSettings(settings(gigyaKey: 'abc')), isNotNull);
      expect(validateRenaultSettings(settings(kamereonKey: 'with space 0123456789')), isNotNull);
    });
  });
}
