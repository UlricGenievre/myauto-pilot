import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myauto_pilot/core/api/api_config.dart';
import 'package:myauto_pilot/core/api/kamereon_client.dart';
import 'package:myauto_pilot/core/api/renault_api_settings.dart';

/// Client dont chaque GET recoit la reponse [routes] de son chemin (404 sinon).
KamereonClient clientWith(Map<String, Object> routes) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    final body = routes[options.path];
    if (body == null) {
      handler.reject(DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 404, data: {'message': 'not found'}),
      ));
    } else {
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: body));
    }
  }));
  return KamereonClient(dio: dio);
}

Map<String, Object> person(List<String> ids) => {
      'accounts': [for (final id in ids) {'accountId': id, 'accountType': 'X', 'accountStatus': 'ACTIVE'}],
    };

const withVehicle = {
  'vehicleLinks': [
    {'vin': 'VF1TEST', 'vehicleDetails': {'vin': 'VF1TEST'}},
  ],
};

void main() {
  setUp(() => ApiConfig.use(const RenaultApiSettings(
        locale: 'fr_FR',
        gigyaUrl: 'https://accounts.eu1.gigya.com',
        gigyaKey: '3_FakeGigyaKey0123456789',
        kamereonUrl: 'https://api-wired-prod-1-euw1.wrd-aws.com',
        kamereonKey: 'FakeKamereonKey0123456789abcdef',
      )));

  test('un seul compte : retenu sans lister ses vehicules', () async {
    final client = clientWith({'/commerce/v1/persons/p': person(['a'])});
    expect(await client.fetchAccountId(jwt: 'j', personId: 'p'), 'a');
  });

  test('plusieurs comptes : le premier qui a un vehicule', () async {
    final client = clientWith({
      '/commerce/v1/persons/p': person(['vide', 'illisible', 'bon']),
      '/commerce/v1/accounts/vide/vehicles': {'vehicleLinks': <Object>[]},
      '/commerce/v1/accounts/bon/vehicles': withVehicle,
    });
    expect(await client.fetchAccountId(jwt: 'j', personId: 'p'), 'bon');
  });

  test('plusieurs comptes sans vehicule : le premier', () async {
    final client = clientWith({
      '/commerce/v1/persons/p': person(['a', 'b']),
      '/commerce/v1/accounts/a/vehicles': {'vehicleLinks': <Object>[]},
    });
    expect(await client.fetchAccountId(jwt: 'j', personId: 'p'), 'a');
  });
}
