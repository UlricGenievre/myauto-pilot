import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myauto_pilot/core/api/gigya_client.dart';
import 'package:myauto_pilot/core/api/kamereon_client.dart';

DioException error(int status, Object? body) {
  final options = RequestOptions(path: '/commerce/v1/accounts/x/kamereon/kca/car-adapter/v1/cars/y/cockpit');
  return DioException(
    requestOptions: options,
    response: Response(requestOptions: options, statusCode: status, data: body),
  );
}

void main() {
  test('403 au corps vide : cle refusee (constate sur le vrai serveur)', () {
    expect(KamereonClient.isKeyRejection(error(403, '')), isTrue);
    expect(KamereonClient.isKeyRejection(error(403, null)), isTrue);
  });

  test('403 d\'endpoint non supporte : pas un refus de cle', () {
    final body = {
      'errors': [
        {'errorCode': 'err.func.wired.forbidden', 'errorMessage': 'forbidden'},
      ],
    };
    expect(KamereonClient.isKeyRejection(error(403, body)), isFalse);
  });

  test('401 de JWT expire : pas un refus de cle', () {
    expect(KamereonClient.isKeyRejection(error(401, {'message': 'Invalid JWT'})), isFalse);
  });

  test('corps qui nomme la cle : refus de cle', () {
    expect(KamereonClient.isKeyRejection(error(403, {'message': 'Invalid apikey'})), isTrue);
  });

  test('Gigya : cle inconnue (HTTP 500, code 400093), en JSON ou en texte brut', () {
    const body = {'errorCode': 400093, 'errorMessage': 'Invalid ApiKey parameter', 'statusCode': 400};
    expect(GigyaClient.isKeyRejection(body), isTrue);
    expect(GigyaClient.isKeyRejection('{"errorCode":400093,"errorMessage":"Invalid ApiKey parameter"}'), isTrue);
  });

  test('Gigya : jeton invalide (403005) ou corps illisible : pas un refus de cle', () {
    expect(GigyaClient.isKeyRejection({'errorCode': 403005, 'errorMessage': 'Unauthorized user'}), isFalse);
    expect(GigyaClient.isKeyRejection('<html>erreur</html>'), isFalse);
    expect(GigyaClient.isKeyRejection(null), isFalse);
  });
}
