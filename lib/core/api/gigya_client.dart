import 'dart:convert';

import 'package:dio/dio.dart';

import '../debug/dev_log.dart';
import 'api_config.dart';
import 'api_exception.dart';

/// Resultat d'une authentification Gigya reussie.
class GigyaSession {
  const GigyaSession({required this.loginToken, required this.personId});

  final String loginToken;
  final String personId;
}

/// Client pour le service d'identite Gigya (`accounts.{dc}.gigya.com`), utilise
/// par MyRenault pour authentifier le compte avant d'appeler Kamereon.
///
/// Flow : accounts.login -> accounts.getAccountInfo -> accounts.getJWT
class GigyaClient {
  GigyaClient({Dio? dio}) : _dio = dio ?? Dio();

  /// Code d'erreur Gigya "Invalid ApiKey parameter".
  static const invalidApiKeyErrorCode = 400093;

  final Dio _dio;

  Future<GigyaSession> login({required String email, required String password}) async {
    final loginToken = await _login(email: email, password: password);
    final personId = await _getPersonId(loginToken);
    return GigyaSession(loginToken: loginToken, personId: personId);
  }

  Future<String> _login({required String email, required String password}) async {
    final data = await _post('/accounts.login', {
      'loginID': email,
      'password': password,
      'apiKey': ApiConfig.gigyaApiKey,
    });

    final sessionInfo = data['sessionInfo'] as Map<String, dynamic>?;
    final loginToken = sessionInfo?['cookieValue'] as String?;
    if (loginToken == null) {
      throw const ApiException('Réponse Gigya inattendue : loginToken manquant.');
    }
    return loginToken;
  }

  Future<String> _getPersonId(String loginToken) async {
    final data = await _post('/accounts.getAccountInfo', {
      'apiKey': ApiConfig.gigyaApiKey,
      'login_token': loginToken,
    });

    final personId = (data['data'] as Map<String, dynamic>?)?['personId'] as String?;
    if (personId == null) {
      throw const ApiException('Réponse Gigya inattendue : personId manquant.');
    }
    return personId;
  }

  /// Echange le login token contre un JWT signe, utilise ensuite comme
  /// header `x-gigya-id_token` sur les appels Kamereon.
  Future<String> getJwt(String loginToken) async {
    final data = await _post('/accounts.getJWT', {
      'apiKey': ApiConfig.gigyaApiKey,
      'login_token': loginToken,
      'fields': 'data.personId,data.gigyaDataCenter',
      'expiration': '900',
    });

    final jwt = data['id_token'] as String?;
    if (jwt == null) {
      throw const ApiException('Réponse Gigya inattendue : id_token manquant.');
    }
    return jwt;
  }

  /// Poste sur l'API Gigya et renvoie le corps JSON decode en Map.
  ///
  /// On decode en `dynamic` plutot que de forcer `Map<String, dynamic>` au
  /// niveau de Dio : Gigya repond souvent avec un Content-Type que Dio ne
  /// reconnait pas comme JSON (ex: `text/javascript`, un heritage de son
  /// ancien support JSONP), auquel cas Dio laisse le corps sous forme de
  /// String brute au lieu de le decoder automatiquement. On le decode alors
  /// nous-memes.
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> data) async {
    try {
      // Adresse lue a chaque appel : suit une mise a jour des cles/serveurs.
      final response = await _dio.post<dynamic>('${ApiConfig.gigyaBaseUrl}$path', data: FormData.fromMap(data));
      var body = response.data;

      if (body is String) {
        try {
          body = jsonDecode(body);
        } on FormatException {
          // Laisse tomber dans la verification de type ci-dessous, qui logue
          // et remonte une erreur exploitable.
        }
      }

      if (body is! Map<String, dynamic>) {
        _logError('Réponse Gigya inattendue sur $path (type ${body.runtimeType}): $body');
        throw ApiException(
          'Réponse Gigya inattendue sur $path (type ${body.runtimeType}).',
          statusCode: response.statusCode,
        );
      }

      final errorCode = body['errorCode'] as int?;
      if (errorCode != null && errorCode != 0) {
        final message = body['errorMessage'] as String? ?? 'Erreur Gigya inconnue';
        _logError('Erreur Gigya sur $path (code $errorCode): $message');
        throw ApiException(message, statusCode: errorCode, keyRejected: isKeyRejection(body));
      }
      return body;
    } on DioException catch (e) {
      final message = e.message ?? e.error?.toString() ?? e.type.name;
      _logError('Appel Gigya $path échoué: $message');
      throw ApiException(
        'Appel Gigya $path échoué: $message',
        statusCode: e.response?.statusCode,
        keyRejected: isKeyRejection(e.response?.data),
      );
    }
  }

  /// Le corps d'une reponse Gigya signale-t-il une cle d'API refusee ?
  ///
  /// Gigya signale une cle inconnue par le corps
  /// `{"errorCode": 400093, "errorMessage": "Invalid ApiKey parameter"}`,
  /// selon le format de la requete dans une reponse 200 ou dans une erreur
  /// **HTTP 500** : les deux sont lues. Dans un navigateur, la reponse 500
  /// n'a pas d'en-tete CORS et reste illisible (erreur de connexion) :
  /// detection impossible dans l'apercu web, sans effet sur l'app Android.
  static bool isKeyRejection(Object? data) {
    Object? body = data;
    if (body is String) {
      try {
        body = jsonDecode(body);
      } on FormatException {
        return false;
      }
    }
    if (body is! Map) return false;
    final code = body['errorCode'];
    final message = (body['errorMessage'] ?? '').toString().toLowerCase();
    return code == invalidApiKeyErrorCode || message.contains('apikey');
  }

  void _logError(String message) {
    // print() plutot que dart:developer.log() : remonte dans `adb logcat`
    // (tag "flutter"), pratique pour deboguer sans devtools branches.
    // ignore: avoid_print
    print('[GigyaClient] $message');
    DevLog.send('gigya_error', {'message': message});
  }
}
