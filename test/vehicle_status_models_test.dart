import 'package:flutter_test/flutter_test.dart';
import 'package:myauto_pilot/core/models/battery_status.dart';
import 'package:myauto_pilot/core/models/cockpit.dart';
import 'package:myauto_pilot/core/models/hvac_status.dart';

/// Reponses reprises des fixtures de `renault-api` (tests/fixtures/kamereon).
void main() {
  test('battery-status : branchee, en attente de la plage de charge', () {
    final battery = BatteryStatus.fromJson({
      'attributes': {'batteryLevel': 49, 'plugStatus': 1, 'chargingStatus': 0.1},
    });
    expect(battery.plugState, PlugState.plugged);
    expect(battery.chargeState, ChargeState.waitingPlanned);
    expect(battery.isCharging, isFalse);
  });

  test('battery-status : en charge, puissance en kW ou en W', () {
    final kw = BatteryStatus.fromJson({
      'attributes': {'plugStatus': 1, 'chargingStatus': 1.0, 'chargingInstantaneousPower': 7.2, 'batteryTemperature': 20},
    });
    expect(kw.isCharging, isTrue);
    expect(kw.chargingPowerKw, 7.2);
    expect(kw.batteryTemperature, 20);
    final watts = BatteryStatus.fromJson({'attributes': {'chargingInstantaneousPower': 7400}});
    expect(watts.chargingPowerKw, 7.4);
  });

  test('battery-status : debranchee, etats inconnus ignores', () {
    final battery = BatteryStatus.fromJson({
      'attributes': {'plugStatus': 0, 'chargingStatus': -1.1},
    });
    expect(battery.plugState, PlugState.unplugged);
    expect(battery.chargeState, ChargeState.unavailable);
    expect(BatteryStatus.fromJson({'attributes': {'plugStatus': -2147483648}}).plugState, isNull);
  });

  test('cockpit : carburant en litres et autonomie (hybride), rien pour un electrique', () {
    final hybrid = Cockpit.fromJson({
      'attributes': {'fuelAutonomy': 348, 'fuelQuantity': 18, 'totalMileage': 2698},
    });
    expect(hybrid.hasFuel, isTrue);
    expect(hybrid.fuelQuantityLiters, 18);
    expect(hybrid.fuelAutonomyKm, 348);
    expect(Cockpit.fromJson({'attributes': {'fuelQuantity': 0.0, 'totalMileage': 559}}).hasFuel, isFalse);
    expect(Cockpit.fromJson({'attributes': {'totalMileage': 559}}).hasFuel, isFalse);
    expect(Cockpit.fromJson({'attributes': {'fuelQuantity': 12}}).hasFuel, isTrue);
  });

  test('hvac-status', () {
    final hvac = HvacStatus.fromJson({
      'attributes': {'internalTemperature': 15.0, 'hvacStatus': 'off', 'socThreshold': 15.0},
    });
    expect(hvac.isOn, isFalse);
    expect(hvac.internalTemperature, 15);
    expect(hvac.socThreshold, 15);
    expect(HvacStatus.fromJson({'attributes': {'hvacStatus': 'on'}}).isOn, isTrue);
  });

  test('hvac-status : mesure ancienne signalee', () {
    final hvac = HvacStatus.fromJson({
      'attributes': {'internalTemperature': 33.0, 'lastUpdateTime': '2026-09-26T14:11:33Z'},
    });
    expect(hvac.isStale(now: DateTime.utc(2026, 9, 26, 14, 30)), isFalse);
    expect(hvac.isStale(now: DateTime.utc(2026, 9, 26, 23, 30)), isTrue);
  });
}
