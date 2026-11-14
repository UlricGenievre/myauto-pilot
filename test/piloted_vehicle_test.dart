import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myauto_pilot/core/charge_plan/pilot_state.dart';
import 'package:myauto_pilot/core/models/charge_plan_config.dart';
import 'package:myauto_pilot/core/models/vehicle.dart';
import 'package:myauto_pilot/core/storage/charge_plan_storage.dart';
import 'package:myauto_pilot/features/auth/auth_controller.dart';
import 'package:myauto_pilot/features/charge_plan/charge_plan_providers.dart';
import 'package:myauto_pilot/features/demo/demo_data.dart';
import 'package:myauto_pilot/features/vehicle/vehicle_providers.dart';

const other = Vehicle(vin: 'VF1AUTRE', brand: 'Renault', model: 'R5', modelCode: 'R5E1VE', accountId: 'compte2');

/// Conteneur sans reseau ni reveils (mode demonstration), sur [storage].
ProviderContainer container(ChargePlanStorage storage) {
  final c = ProviderContainer(overrides: [
    demoModeProvider.overrideWithValue(true),
    chargePlanStorageProvider.overrideWithValue(storage),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('forVehicle : envoi auto coupe, reglages du vehicule oublies, le reste garde', () {
    final config = demoChargePlanConfig().copyWith(enabled: true, maxChargePercent: 80, pushLeadMinutes: 120);
    final next = config.forVehicle(vin: other.vin, modelCode: other.modelCode, accountId: other.accountId);
    expect(next.vehicleVin, other.vin);
    expect(next.vehicleAccountId, 'compte2');
    expect(next.vehicleModelCode, other.modelCode);
    expect(next.enabled, isFalse);
    expect(next.dedicatedProgramIndex, isNull);
    expect(next.batteryCapacityKwh, isNull);
    expect(next.chargePowerKw, isNull);
    expect(next.oneOffTarget, isNull);
    expect(next.calendar.toJson(), config.calendar.toJson());
    expect(next.agendas.length, config.agendas.length);
    expect(next.maxChargePercent, 80);
    expect(next.pushLeadMinutes, 120);
    expect(next.safeMode, config.safeMode);
  });

  test('changement de vehicule pilote : parametrage et etat remis a zero', () async {
    final storage = DemoChargePlanStorage();
    await storage.saveState(const PilotState(lastResult: 'ancien', lastResultOk: true));
    final c = container(storage);
    await c.read(chargePlanConfigProvider.future);
    c.read(selectedVehicleProvider.notifier).select(other);
    expect(c.read(showsOtherThanPilotedProvider), isTrue);

    expect(await c.read(chargePlanConfigProvider.notifier).switchVehicle(other), isNull);
    expect((await storage.load()).vehicleVin, other.vin);
    expect((await storage.load()).vehicleAccountId, 'compte2');
    expect((await storage.loadState()).lastResult, isNull);
    expect(c.read(showsOtherThanPilotedProvider), isFalse);
  });

  test('changement refuse pendant une charge immediate ou un envoi', () async {
    final now = DateTime.now();
    for (final state in [
      PilotState(boost: ImmediateCharge(sentAt: now, end: now.add(const Duration(hours: 1)))),
      const PilotState(manualChargeTarget: 80),
      PilotState(sendingSince: now),
    ]) {
      final storage = DemoChargePlanStorage();
      await storage.saveState(state);
      final c = container(storage);
      final before = await c.read(chargePlanConfigProvider.future);
      expect(await c.read(chargePlanConfigProvider.notifier).switchVehicle(other), isNotNull);
      expect((await storage.load()).vehicleVin, before.vehicleVin);
    }
  });

  test('sans vehicule pilote, un reglage lie le vehicule affiche', () async {
    final storage = DemoChargePlanStorage();
    await storage.save(const ChargePlanConfig());
    final c = container(storage);
    await c.read(chargePlanConfigProvider.future);
    c.read(selectedVehicleProvider.notifier).select(other);
    expect(c.read(showsOtherThanPilotedProvider), isFalse);

    await c.read(chargePlanConfigProvider.notifier).edit((cfg) => cfg.copyWith(dedicatedProgramIndex: 2));
    final saved = await storage.load();
    expect(saved.vehicleVin, other.vin);
    expect(saved.vehicleModelCode, other.modelCode);
    expect(saved.vehicleAccountId, 'compte2');
  });

  test('compte du vehicule pilote : hors empreinte du parametrage', () {
    final config = demoChargePlanConfig();
    expect(config.copyWith(vehicleAccountId: 'compte2').fingerprint, config.fingerprint);
    expect(ChargePlanConfig.fromJson(config.copyWith(vehicleAccountId: 'compte2').toJson()).vehicleAccountId, 'compte2');
  });
}
