import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myauto_pilot/core/api/api_config.dart';
import 'package:myauto_pilot/core/api/kamereon_client.dart';
import 'package:myauto_pilot/core/api/renault_api_settings.dart';
import 'package:myauto_pilot/core/models/battery_health.dart';
import 'package:myauto_pilot/core/models/vehicle.dart';

/// Adaptateur Dio qui enregistre la requete et renvoie [body].
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.body);

  final Object body;
  RequestOptions? request;
  Object? sentData;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    request = options;
    sentData = options.data;
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('state : reponse reelle du Rafale (2026-11-12)', () {
    final health = BatteryHealth.fromStateJson({
      'mileage': {'mileage': 20872},
      'sohBlms': {'vin': 'VF1XXXXXXXXXXXXXX', 'sohCheck': false, 'sohStatus': 5, 'soheRef': 96},
    });
    expect(health!.percent, 96);
    expect(health.status, 5);
    expect(health.check, isFalse);
    expect(health.level, BatteryHealthLevel.good);
  });

  test('state : sans bloc sohBlms ou valeur aberrante, pas de sante', () {
    expect(BatteryHealth.fromStateJson({'mileage': {'mileage': 1000}}), isNull);
    expect(BatteryHealth.fromStateJson({'sohBlms': {'soheRef': 0}}), isNull);
    expect(BatteryHealth.fromStateJson({'sohBlms': {'soheRef': 140}}), isNull);
    expect(BatteryHealth.fromStateJson(''), isNull);
    expect(BatteryHealth.fromStateJson(null), isNull);
  });

  test('appreciation : 85 % et plus bon, 70 a 84 usure, moins de 70 a controler', () {
    expect(const BatteryHealth(percent: 85).level, BatteryHealthLevel.good);
    expect(const BatteryHealth(percent: 84).level, BatteryHealthLevel.worn);
    expect(const BatteryHealth(percent: 70).level, BatteryHealthLevel.worn);
    expect(const BatteryHealth(percent: 69).level, BatteryHealthLevel.check);
  });

  test('vehicule : date de livraison lue dans vehicleDetails', () {
    final vehicle = Vehicle.fromJson({
      'vin': 'VF1XXXXXXXXXXXXXX',
      'deliveryDate': '2025-09-10',
      'model': {'code': 'XHN1CP', 'label': 'RAFALE'},
    });
    expect(vehicle.deliveryDate, '2025-09-10');
  });

  test('requete : POST state sur apis.renault.com, cle Kamereon et JWT', () async {
    ApiConfig.use(const RenaultApiSettings(
      locale: 'fr_FR',
      gigyaUrl: 'https://accounts.eu1.gigya.com',
      gigyaKey: '3_xxxxxxxxxxxxxxxx',
      kamereonUrl: 'https://api-wired-prod-1-euw1.wrd-aws.com',
      kamereonKey: 'abcdefghijklmnopqrstuvwxyz012345',
    ));
    final adapter = _RecordingAdapter({
      'sohBlms': {'soheRef': 96},
    });
    final client = KamereonClient(dio: Dio()..httpClientAdapter = adapter);

    final health = await client.fetchBatteryHealth(
      jwt: 'jwt',
      accountId: 'acc',
      vin: 'VIN1',
      deliveryDate: '2025-09-10',
    );

    expect(health!.percent, 96);
    final request = adapter.request!;
    expect(request.method, 'POST');
    expect(request.uri.toString(), 'https://apis.renault.com/myr/api/v1/accounts/acc/vehicles/VIN1/state?country=FR');
    expect(request.headers['apikey'], 'abcdefghijklmnopqrstuvwxyz012345');
    expect(request.headers['x-gigya-id_token'], 'jwt');
    expect(adapter.sentData, {
      'uidveh': [202, 345],
      'deliveryDate': '2025-09-10',
    });
  });
}
