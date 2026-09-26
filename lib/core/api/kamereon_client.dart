import 'dart:convert';

import 'package:dio/dio.dart';

import '../debug/dev_log.dart';
import 'api_config.dart';
import 'api_exception.dart';
import '../models/battery_status.dart';
import '../models/cockpit.dart';
import '../models/hvac_status.dart';
import '../models/vehicle.dart';
import '../models/vehicle_location.dart';
import '../models/vehicle_schedule.dart';

/// Actions a distance supportees (toutes ne sont pas disponibles sur tous
/// les vehicules : ca depend du modele/motorisation).
///
/// Pas de verrouillage/deverrouillage a distance : cette action n'existe
/// dans l'API Kamereon pour aucun modele Renault (confirme par le projet
/// `renault-api`, ou l'endpoint `lock-status` est systematiquement absent
/// ou non supporte selon les vehicules). MyRenault ne l'expose pas non
/// plus dans son app.
enum VehicleAction { hvacStart, hvacStop, chargeStart, chargePause, horn, lights }

/// Client pour l'API Kamereon (donnees + actions vehicule), authentifie via
/// le JWT Gigya passe en header `x-gigya-id_token`.
///
/// Chemins/versions verifies contre le projet `renault-api`
/// (hacf-fr/renault-api, fichier `kamereon/models.py`) : seul
/// `battery-status` est en v2, tout le reste (`cockpit`, `location`,
/// actions hvac/charge) est en v1. Si un appel renvoie 404/410, Renault a
/// pu faire evoluer ces chemins : revrifie cote `renault-api`.
class KamereonClient {
  /// [onUnauthorized] est appele quand un appel renvoie 401 : doit rafraichir
  /// le JWT et renvoyer le nouveau (ou null si le refresh echoue, auquel cas
  /// l'erreur d'origine est propagee normalement). Branche par
  /// [VehicleRepository]/`vehicleRepositoryProvider` sur
  /// `AuthController.refreshSession`.
  ///
  /// [onKeyRejected] est appele quand la cle d'API elle-meme est refusee :
  /// doit chercher et adopter de nouvelles cles (cf.
  /// `AuthRepository.recoverFromKeyRejection`) et renvoyer true si c'est
  /// fait, auquel cas l'appel est rejoue une fois avec la nouvelle cle.
  ///
  /// Ce sont des intercepteurs Dio (pas un wrapper a appeler cote appelant) :
  /// ca couvre par construction tous les appels de ce client, presents et
  /// futurs, sans dependre de ce que chaque appelant pense a faire.
  KamereonClient({Dio? dio, this._onUnauthorized, this._onKeyRejected}) : _dio = dio ?? Dio() {
    _dio.interceptors.add(InterceptorsWrapper(onRequest: _useCurrentServerAndKey, onError: _retryOnError));
  }

  final Dio _dio;
  final Future<String?> Function()? _onUnauthorized;
  final Future<bool> Function()? _onKeyRejected;

  /// Les chemins sont relatifs ("/commerce/...") : serveur et cle sont lus a
  /// chaque requete (y compris un rejeu), pour suivre une mise a jour des
  /// cles sans recreer le client.
  void _useCurrentServerAndKey(RequestOptions options, RequestInterceptorHandler handler) {
    try {
      final relative = options.extra['relPath'] as String? ?? options.path;
      options
        ..extra['relPath'] = relative
        ..path = '${ApiConfig.kamereonBaseUrl}$relative'
        ..headers['apikey'] = ApiConfig.kamereonApiKey;
      handler.next(options);
    } on ApiException catch (e) {
      handler.reject(DioException(requestOptions: options, error: e, message: e.message));
    }
  }

  /// Refus de la cle d'API (et non du JWT, du compte ou de l'endpoint).
  ///
  /// Kamereon repond alors **403 avec un corps vide** (observe sur le vrai
  /// serveur avec une cle alteree). Les autres 403 connus ont un corps
  /// (ex. `err.func.wired.forbidden` pour un endpoint non supporte) et ne
  /// sont donc pas pris pour un refus de cle. Un corps qui nomme la cle
  /// est aussi accepte. Au pire (403 vide d'une autre origine), l'app
  /// verifie `renault-api` pour rien : elle n'adopte que des cles testees.
  static bool isKeyRejection(DioException e) {
    final status = e.response?.statusCode;
    if (status != 401 && status != 403) return false;
    final data = e.response?.data;
    final body = data == null ? '' : (data is String ? data : jsonEncode(data)).trim().toLowerCase();
    if (status == 403 && (body.isEmpty || body == 'null' || body == '{}')) return true;
    return body.contains('apikey') || body.contains('api key') || body.contains('api-key');
  }

  Future<void> _retryOnError(DioException err, ErrorInterceptorHandler handler) async {
    final extra = err.requestOptions.extra;

    if (_onKeyRejected != null && extra['retriedKey'] != true && isKeyRejection(err)) {
      var recovered = false;
      try {
        recovered = await _onKeyRejected();
      } catch (_) {
        recovered = false;
      }
      if (!recovered) return handler.next(err);
      return _replay(err, handler, {'retriedKey': true});
    }

    if (_onUnauthorized != null && err.response?.statusCode == 401 && extra['retriedAuth'] != true) {
      String? newJwt;
      try {
        newJwt = await _onUnauthorized();
      } catch (_) {
        newJwt = null;
      }
      if (newJwt == null) return handler.next(err);
      err.requestOptions.headers['x-gigya-id_token'] = newJwt;
      return _replay(err, handler, {'retriedAuth': true});
    }

    handler.next(err);
  }

  Future<void> _replay(DioException err, ErrorInterceptorHandler handler, Map<String, dynamic> mark) async {
    try {
      final retryOptions = err.requestOptions..extra = {...err.requestOptions.extra, ...mark};
      final response = await _dio.fetch<dynamic>(retryOptions);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  /// La cle d'API est posee par [_useCurrentServerAndKey].
  Options _authHeaders(String jwt) => Options(headers: {'x-gigya-id_token': jwt});

  /// Recupere le/les comptes Kamereon lies a la personne authentifiee.
  Future<String> fetchAccountId({required String jwt, required String personId}) async {
    final data = await _get(
      '/commerce/v1/persons/$personId',
      jwt: jwt,
      query: {'country': ApiConfig.country},
    );

    final accounts = data['accounts'] as List<dynamic>?;
    final accountId = accounts?.isNotEmpty == true
        ? accounts!.first['accountId'] as String?
        : null;
    if (accountId == null) {
      throw const ApiException('Aucun compte Kamereon trouvé pour ce profil.');
    }
    return accountId;
  }

  Future<List<Vehicle>> fetchVehicles({required String jwt, required String accountId}) async {
    final data = await _get(
      '/commerce/v1/accounts/$accountId/vehicles',
      jwt: jwt,
      query: {'country': ApiConfig.country},
    );

    final items = data['vehicleLinks'] as List<dynamic>? ?? const [];
    return items
        .map((e) => Vehicle.fromJson((e as Map<String, dynamic>)['vehicleDetails'] as Map<String, dynamic>? ?? e))
        .toList();
  }

  Future<BatteryStatus> fetchBatteryStatus({
    required String jwt,
    required String accountId,
    required String vin,
  }) async {
    final data = await _get(_carAdapterPath(accountId, vin, 'battery-status', version: 2), jwt: jwt);
    return BatteryStatus.fromJson(data['data'] as Map<String, dynamic>? ?? const {});
  }

  Future<Cockpit> fetchCockpit({
    required String jwt,
    required String accountId,
    required String vin,
  }) async {
    final data = await _get(_carAdapterPath(accountId, vin, 'cockpit'), jwt: jwt);
    return Cockpit.fromJson(data['data'] as Map<String, dynamic>? ?? const {});
  }

  Future<HvacStatus> fetchHvacStatus({
    required String jwt,
    required String accountId,
    required String vin,
  }) async {
    final data = await _get(_carAdapterPath(accountId, vin, 'hvac-status'), jwt: jwt);
    return HvacStatus.fromJson(data['data'] as Map<String, dynamic>? ?? const {});
  }

  Future<VehicleLocation> fetchLocation({
    required String jwt,
    required String accountId,
    required String vin,
  }) async {
    final data = await _get(_carAdapterPath(accountId, vin, 'location'), jwt: jwt);
    return VehicleLocation.fromJson(data['data'] as Map<String, dynamic>? ?? const {});
  }

  /// Programmes (charge/preclimatisation) + plage de charge globale.
  ///
  /// PAS le chemin `kca/car-adapter` habituel : sur les vehicules recents,
  /// les endpoints `hvac-settings`/`charging-settings` classiques renvoient
  /// respectivement 502 (`err.tech.vcps.ev.hvac-settings.error`) et 403
  /// (`err.func.wired.forbidden`) -- constate en pratique sur un vrai
  /// vehicule, et confirme par le registre par modele de `renault-api`
  /// (`kamereon/models.py`, `_VEHICLE_ENDPOINTS`, mode `kcm-settings` :
  /// `charge-schedule` -> `/kcm/v1/vehicles/{vin}/ev/settings`). Contrairement
  /// aux autres endpoints, la reponse n'est pas enveloppee dans
  /// `{"data": {"attributes": ...}}`, c'est du JSON plat.
  Future<VehicleSchedule> fetchVehicleSchedule({
    required String jwt,
    required String accountId,
    required String vin,
  }) async {
    final data = await _get(
      '/commerce/v1/accounts/$accountId/kamereon/kcm/v1/vehicles/$vin/ev/settings',
      jwt: jwt,
    );
    return VehicleSchedule.fromJson(data);
  }

  /// Ecrit les reglages `ev/settings` : POST de l'objet **complet** (pas un
  /// diff), JSON plat, meme URL que le GET -- pattern de `renault-api`
  /// (`set_charge_start`, seule ecriture prouvee a ce jour : bascule de
  /// `programActivationStatus`). La modification des horaires eux-memes est a
  /// valider sur le vrai vehicule (cf. `.claude/plans/charge-heures-creuses.md`).
  ///
  /// [settings] : typiquement `VehicleSchedule.toUpdatedJson(...)` sur la
  /// derniere lecture. Renvoie les reglages tels que relus juste apres, pour
  /// que l'appelant constate ce que le vehicule a reellement retenu.
  Future<VehicleSchedule> updateVehicleSchedule({
    required String jwt,
    required String accountId,
    required String vin,
    required Map<String, dynamic> settings,
  }) async {
    final path = '/commerce/v1/accounts/$accountId/kamereon/kcm/v1/vehicles/$vin/ev/settings';
    try {
      await _dio.post<dynamic>(path, data: settings, options: _authHeaders(jwt));
    } on DioException catch (e) {
      final message = _describeDioError(e);
      _logError('Écriture ev/settings échouée sur $path: $message');
      throw ApiException('Écriture des réglages échouée: $message',
          statusCode: e.response?.statusCode, keyRejected: isKeyRejection(e));
    }
    return fetchVehicleSchedule(jwt: jwt, accountId: accountId, vin: vin);
  }

  Future<void> sendAction({
    required String jwt,
    required String accountId,
    required String vin,
    required VehicleAction action,
  }) async {
    final (endpoint, type, attributes) = _actionPayload(action);
    final path = _carAdapterPath(accountId, vin, 'actions/$endpoint');
    try {
      await _dio.post<dynamic>(
        path,
        data: {
          'data': {'type': type, 'attributes': attributes},
        },
        options: _authHeaders(jwt),
      );
    } on DioException catch (e) {
      final message = _describeDioError(e);
      _logError('Action ${action.name} échouée sur $path: $message');
      throw ApiException('Action ${action.name} échouée: $message',
          statusCode: e.response?.statusCode, keyRejected: isKeyRejection(e));
    }
  }

  String _carAdapterPath(String accountId, String vin, String suffix, {int version = 1}) =>
      '/commerce/v1/accounts/$accountId/kamereon/kca/car-adapter/v$version/cars/$vin/$suffix';

  /// Chemin (sous `actions/`), type et attributs de chaque action, d'apres
  /// `renault_vehicle.py` de `renault-api`.
  (String, String, Map<String, String>) _actionPayload(VehicleAction action) => switch (action) {
        VehicleAction.hvacStart => ('hvac-start', 'HvacStart', {'action': 'start'}),
        VehicleAction.hvacStop => ('hvac-start', 'HvacStart', {'action': 'stop'}),
        VehicleAction.chargeStart => ('charging-start', 'ChargingStart', {'action': 'start'}),
        VehicleAction.chargePause => ('charging-start', 'ChargingStart', {'action': 'stop'}),
        VehicleAction.horn => ('horn-lights', 'HornLights', {'action': 'start', 'target': 'horn'}),
        VehicleAction.lights => ('horn-lights', 'HornLights', {'action': 'start', 'target': 'lights'}),
      };

  /// GET sur l'API Kamereon, renvoie le corps JSON decode en Map.
  ///
  /// Comme pour Gigya, on decode en `dynamic` et on gere nous-memes le cas
  /// ou le corps arrive sous forme de String brute (Content-Type non
  /// reconnu par Dio comme JSON) plutot que de laisser Dio planter sur un
  /// cast implicite.
  Future<Map<String, dynamic>> _get(
    String path, {
    required String jwt,
    Map<String, dynamic>? query,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        path,
        queryParameters: query,
        options: _authHeaders(jwt),
      );
      var body = response.data;

      if (body is String) {
        try {
          body = jsonDecode(body);
        } on FormatException {
          // Laisse tomber dans la verification de type ci-dessous.
        }
      }

      if (body is! Map<String, dynamic>) {
        _logError('Réponse Kamereon inattendue sur $path (type ${body.runtimeType}): $body');
        throw ApiException(
          'Réponse Kamereon inattendue sur $path (type ${body.runtimeType}).',
          statusCode: response.statusCode,
        );
      }

      return body;
    } on DioException catch (e) {
      final message = _describeDioError(e);
      _logError('Appel Kamereon $path échoué: $message');
      DevLog.send('kamereon_error_detail', {
        'status': e.response?.statusCode,
        'keyRejected': isKeyRejection(e),
        'headers': e.response?.headers.map,
      });
      throw ApiException('Appel Kamereon $path échoué: $message',
          statusCode: e.response?.statusCode, keyRejected: isKeyRejection(e));
    }
  }

  /// Dio ne met par defaut que son propre message generique (ex: "Http
  /// status error [403]") dans `e.message`, sans le corps de la reponse —
  /// qui contient pourtant souvent le detail utile cote Kamereon (code
  /// d'erreur, endpoint non supporte pour ce vehicule...). On l'ajoute donc
  /// explicitement, essentiel pour diagnostiquer sans DevTools branches
  /// (cf. cible web, qui n'a pas acces aux `print()` sans l'extension Chrome
  /// de debug).
  String _describeDioError(DioException e) {
    final base = e.message ?? e.error?.toString() ?? e.type.name;
    final body = e.response?.data;
    if (body == null) return base;
    final bodyText = body is String ? body : jsonEncode(body);
    if (bodyText.isEmpty) return base;
    return '$base — réponse: $bodyText';
  }

  void _logError(String message) {
    // print() plutot que dart:developer.log() : remonte dans `adb logcat`
    // (tag "flutter"), pratique pour deboguer sans devtools branches.
    // ignore: avoid_print
    print('[KamereonClient] $message');
    DevLog.send('kamereon_error', {'message': message});
  }
}
