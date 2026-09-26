import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myauto_pilot/core/api/api_config.dart';
import 'package:myauto_pilot/core/api/api_exception.dart';
import 'package:myauto_pilot/core/api/gigya_client.dart';
import 'package:myauto_pilot/core/api/kamereon_client.dart';
import 'package:myauto_pilot/core/api/renault_api_settings.dart';
import 'package:myauto_pilot/core/api/renault_keys_source.dart';
import 'package:myauto_pilot/core/storage/secure_token_storage.dart';
import 'package:myauto_pilot/features/auth/auth_repository.dart';

RenaultApiSettings keys(String gigyaKey) => RenaultApiSettings(
      locale: 'fr_FR',
      gigyaUrl: 'https://accounts.eu1.gigya.com',
      gigyaKey: gigyaKey,
      kamereonUrl: 'https://api-wired-prod-1-euw1.wrd-aws.com',
      kamereonKey: 'FakeKamereonKey0123456789abcdef',
    );

final oldKeys = keys('3_OldFakeGigyaKey0123456789');
final newKeys = keys('3_NewFakeGigyaKey0123456789');

/// Gigya simule : n'accepte que la cle [validKey].
class FakeGigya extends GigyaClient {
  FakeGigya(this.validKey);

  String validKey;
  var jwtCalls = 0;

  @override
  Future<String> getJwt(String loginToken) async {
    jwtCalls++;
    if (ApiConfig.gigyaApiKey != validKey) {
      throw const ApiException('Invalid ApiKey parameter', statusCode: 400093, keyRejected: true);
    }
    return 'jwt-with-${ApiConfig.gigyaApiKey}';
  }
}

class FakeKamereon extends KamereonClient {
  @override
  Future<String> fetchAccountId({required String jwt, required String personId}) async => 'account';
}

class FakeSource extends RenaultKeysSource {
  FakeSource(this.result);

  RenaultApiSettings? result;
  var fetches = 0;

  @override
  Future<RenaultApiSettings?> fetch(String locale) async {
    fetches++;
    return result;
  }
}

void main() {
  late SecureTokenStorage storage;
  late FakeGigya gigya;
  late FakeSource source;
  late List<String> events;

  AuthRepository repo() => AuthRepository(
        gigyaClient: gigya,
        kamereonClient: FakeKamereon(),
        storage: storage,
        keysSource: source,
        onKeysEvent: (title, body) => events.add(title),
      );

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    storage = SecureTokenStorage();
    await storage.saveSession(gigyaLoginToken: 'token', kamereonJwt: 'old-jwt', personId: 'person', accountId: 'account');
    await storage.saveApiSettings(oldKeys);
    gigya = FakeGigya(newKeys.gigyaKey); // Renault a change sa cle.
    source = FakeSource(newKeys);
    events = [];
  });

  test('cle refusee au demarrage : nouvelles cles recuperees, testees, adoptees', () async {
    final session = await repo().restoreSession();

    expect(session!.jwt, 'jwt-with-${newKeys.gigyaKey}');
    expect(ApiConfig.settings!.gigyaKey, newKeys.gigyaKey);
    expect((await storage.apiSettings)!.gigyaKey, newKeys.gigyaKey);
    expect(events, ['Clés Renault mises à jour']);
  });

  test('renault-api pas encore a jour : erreur remontee, cles inchangees, notification', () async {
    source.result = oldKeys;

    await expectLater(repo().restoreSession(), throwsA(isA<ApiException>()));

    expect(ApiConfig.settings!.gigyaKey, oldKeys.gigyaKey);
    expect(events, ['Clés Renault refusées']);
  });

  test('nouvelles cles refusees elles aussi : retour aux anciennes', () async {
    gigya.validKey = '3_YetAnotherFakeKey0123456';

    await expectLater(repo().restoreSession(), throwsA(isA<ApiException>()));

    expect(ApiConfig.settings!.gigyaKey, oldKeys.gigyaKey);
    expect((await storage.apiSettings)!.gigyaKey, oldKeys.gigyaKey);
  });

  test('au plus une recherche automatique par periode, sauf verification manuelle', () async {
    source.result = oldKeys;
    final r = repo();
    ApiConfig.use(oldKeys);

    expect(await r.recoverFromKeyRejection(), KeysUpdateResult.unchanged);
    expect(await r.recoverFromKeyRejection(), KeysUpdateResult.tooSoon);
    expect(source.fetches, 1);
    expect(await r.recoverFromKeyRejection(force: true), KeysUpdateResult.unchanged);
    expect(source.fetches, 2);
  });

  test('verification manuelle : pas de notification (resultat affiche par l\'ecran)', () async {
    ApiConfig.use(oldKeys);

    expect(await repo().recoverFromKeyRejection(force: true), KeysUpdateResult.updated);
    expect(events, isEmpty);
  });

  test('deconnexion : cles effacees avec la session (pays a rechoisir)', () async {
    await repo().logout();

    expect(await storage.apiSettings, isNull);
    expect(await storage.gigyaLoginToken, isNull);
  });
}
