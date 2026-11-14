import 'package:flutter_test/flutter_test.dart';
import 'package:myauto_pilot/core/models/vehicle_support.dart';
import 'package:myauto_pilot/features/demo/demo_data.dart';

void main() {
  test('vehicule de demonstration pilotable et parametrage coherent', () {
    final config = demoChargePlanConfig();
    expect(VehicleSupport.of(demoVehicle.modelCode).canWrite, isTrue);
    expect(config.vehicleVin, demoVehicle.vin);
    expect(config.activeAgenda?.name, 'Habituel');
    expect(config.enabled, isFalse);
  });

  test('ecriture simulee : relue ensuite, sans modifier le reste', () async {
    final repository = DemoVehicleRepository();
    final before = await repository.fetchVehicleSchedule(demoVehicle);
    expect(before.programs, hasLength(3));

    final updated = before.toUpdatedJson(
      chargeTimeStart: '12:30',
      chargeDurationMinutes: 120,
      programIndex: 2,
      departureTime: '07:30',
      programActive: true,
    );
    await repository.updateVehicleSchedule(demoVehicle, updated);

    final after = await repository.fetchVehicleSchedule(demoVehicle);
    expect(after.chargeWindowStart, '12:30');
    expect(after.chargeWindowDurationMinutes, 120);
    expect(after.programs[2].isActive, isTrue);
    expect(after.programs[0].isActive, isTrue);
    expect(after.lastUpdate, isNot(before.lastUpdate));
  });

  test('stockage de demonstration en memoire, neuf a chaque instance', () async {
    final storage = DemoChargePlanStorage();
    final config = await storage.load();
    await storage.save(config.copyWith(pushLeadMinutes: 60));
    expect((await storage.load()).pushLeadMinutes, 60);
    expect((await DemoChargePlanStorage().load()).pushLeadMinutes, isNot(60));
  });

  test('deux vehicules, sur deux comptes, chacun avec ses donnees', () async {
    final repository = DemoVehicleRepository();
    final vehicles = await repository.fetchVehicles();
    expect(vehicles.map((v) => v.vin), [demoVehicle.vin, demoSecondVehicle.vin]);
    expect(vehicles.map((v) => v.accountId).toSet(), hasLength(2));
    expect(VehicleSupport.of(demoSecondVehicle.modelCode), VehicleSupport.compatible);
    expect((await repository.fetchBatteryStatus(demoSecondVehicle)).batteryLevel,
        isNot((await repository.fetchBatteryStatus(demoVehicle)).batteryLevel));

    // Ecriture sur l'un sans effet sur l'autre.
    final first = await repository.fetchVehicleSchedule(demoVehicle);
    await repository.updateVehicleSchedule(
        demoSecondVehicle, first.toUpdatedJson(chargeTimeStart: '12:30', chargeDurationMinutes: 120));
    expect((await repository.fetchVehicleSchedule(demoSecondVehicle)).chargeWindowStart, '12:30');
    expect((await repository.fetchVehicleSchedule(demoVehicle)).chargeWindowStart, first.chargeWindowStart);
  });
}
