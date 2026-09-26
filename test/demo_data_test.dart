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
    final before = await repository.fetchVehicleSchedule(demoVehicle.vin);
    expect(before.programs, hasLength(3));

    final updated = before.toUpdatedJson(
      chargeTimeStart: '12:30',
      chargeDurationMinutes: 120,
      programIndex: 2,
      departureTime: '07:30',
      programActive: true,
    );
    await repository.updateVehicleSchedule(demoVehicle.vin, updated);

    final after = await repository.fetchVehicleSchedule(demoVehicle.vin);
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
}
