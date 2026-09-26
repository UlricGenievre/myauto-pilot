import 'package:flutter_test/flutter_test.dart';
import 'package:myauto_pilot/core/charge_plan/charge_pilot.dart';
import 'package:myauto_pilot/core/charge_plan/charge_planner.dart';
import 'package:myauto_pilot/core/charge_plan/pilot_state.dart';
import 'package:myauto_pilot/core/models/charge_plan_config.dart';
import 'package:myauto_pilot/core/models/vehicle_schedule.dart';
import 'package:myauto_pilot/core/models/vehicle_support.dart';

import 'vehicle_schedule_test.dart' show realResponse;

// Mardi 2026-09-22, plages 01:15-06:15 et 14:05-17:05 du mardi au vendredi.
DateTime at(int day, int hour, [int minute = 0]) => DateTime(2026, 9, day, hour, minute);

ChargePlanConfig pilotConfig({bool safeMode = true, bool enabled = true}) {
  final windows = DaySchedule(windows: [
    ChargeWindow(start: ClockTime.hm(1, 15), end: ClockTime.hm(6, 15)),
    ChargeWindow(start: ClockTime.hm(14, 5), end: ClockTime.hm(17, 5)),
  ]);
  return ChargePlanConfig(
    calendar: ChargeCalendar(days: {for (final d in [2, 3, 4, 5]) d: windows}),
    dedicatedProgramIndex: 0,
    enabled: enabled,
    safeMode: safeMode,
    vehicleVin: 'VIN',
    vehicleModelCode: 'XHN1CP',
  );
}

class MemoryStore implements PilotStore {
  MemoryStore(this.config);

  ChargePlanConfig config;
  PilotState state = const PilotState();

  @override
  Future<ChargePlanConfig> load() async => config;
  @override
  Future<PilotState> loadState() async => state;
  @override
  Future<void> saveState(PilotState value) async => state = value;
}

class FakePlatform implements PilotPlatform {
  final wakes = <PilotWake, DateTime>{};
  final confirmations = <String>[];
  final results = <String>[];
  var dismissed = 0;

  @override
  Future<void> scheduleWake(PilotWake wake, DateTime at) async => wakes[wake] = at;
  @override
  Future<void> cancelWake(PilotWake wake) async => wakes.remove(wake);
  @override
  Future<void> showConfirmation(ChargeCommand command, String body) async => confirmations.add(command.id);
  @override
  Future<void> dismissConfirmation() async => dismissed++;
  @override
  Future<void> showResult(String title, String body) async => results.add(title);
  @override
  Future<void> showReminder(String body) async {}
}

/// Voiture simulee : applique l'ecriture au bout de [applyAfterReads]
/// relectures (ecriture asynchrone cote Renault).
class FakeVehicle implements PilotVehicleGateway {
  FakeVehicle({this.applyAfterReads = 1, this.failWrite = false, this.soc = 50});

  final int applyAfterReads;
  final bool failWrite;
  int soc;
  Map<String, dynamic> _settings = realResponse();
  Map<String, dynamic>? _pending;
  var _readsSinceWrite = 0;
  final writes = <Map<String, dynamic>>[];

  @override
  Future<int?> fetchSoc(String vin) async => soc;

  @override
  Future<VehicleSchedule> fetchSchedule(String vin) async {
    if (_pending != null && ++_readsSinceWrite > applyAfterReads) {
      _settings = {..._pending!, 'lastSettingsUpdateTimestamp': 'apres-${writes.length}'};
      _pending = null;
    }
    return VehicleSchedule.fromJson(_settings);
  }

  @override
  Future<void> updateSchedule(String vin, Map<String, dynamic> settings) async {
    if (failWrite) throw Exception('403');
    writes.add(settings);
    _pending = settings;
    _readsSinceWrite = 0;
  }
}

ChargePilot pilot(MemoryStore store, FakePlatform platform, FakeVehicle? vehicle, DateTime now) => ChargePilot(
      store: store,
      platform: platform,
      gateway: () async => vehicle,
      clock: () => now,
      pollInterval: Duration.zero,
    );

void main() {
  test('mode securise : propose la plage en vigueur une seule fois, sans envoyer', () async {
    final store = MemoryStore(pilotConfig());
    final platform = FakePlatform();
    final vehicle = FakeVehicle();
    final now = at(22, 10, 30); // apres l'envoi de 10:05 pour 14:05

    await pilot(store, platform, vehicle, now).tick();
    await pilot(store, platform, vehicle, now).tick();

    expect(platform.confirmations, ['window-20260922T1405']);
    expect(vehicle.writes, isEmpty);
    expect(store.state.pendingId, 'window-20260922T1405');
    // Prochain reveil : 01:15 - 4 h = 21:15.
    expect(platform.wakes[PilotWake.next], at(22, 21, 15));
    expect(platform.wakes[PilotWake.evening], at(22, 20));
  });

  test('confirmation puis reveil execution : envoi, attente de prise en compte, resultat', () async {
    final store = MemoryStore(pilotConfig());
    final platform = FakePlatform();
    final vehicle = FakeVehicle(applyAfterReads: 2);
    final now = at(22, 10, 30);

    await pilot(store, platform, vehicle, now).tick();
    await pilot(store, platform, vehicle, now).confirm('window-20260922T1405');
    expect(platform.wakes[PilotWake.execute], isNotNull);

    await pilot(store, platform, vehicle, now).executeConfirmed();

    final sent = vehicle.writes.single;
    expect(sent['chargeTimeStart'], '14:05');
    expect(sent['chargeDuration'], 180);
    final program = (sent['programs'] as List).first as Map<String, dynamic>;
    // Sans objectif : 1 h avant l'envoi de cette plage (mardi 10:05).
    expect(program['programDepartureTime'], '09:05:00');
    expect(program['programActivationStatus'], isTrue);
    // Programme actif le seul jour de l'heure "pret a" (mardi).
    expect(program['programActivationTuesday'], isTrue);
    for (final day in ['Monday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']) {
      expect(program['programActivation$day'], isFalse, reason: day);
    }
    expect(store.state.sentId, 'window-20260922T1405');
    expect(store.state.lastResultOk, isTrue);
    expect(platform.results, ['Plage envoyée']);

    // Deja envoyee : un nouveau passage ne repropose rien.
    await pilot(store, platform, vehicle, now).tick();
    expect(platform.confirmations, hasLength(1));
  });

  test('ignorer : la commande n\'est plus proposee', () async {
    final store = MemoryStore(pilotConfig());
    final platform = FakePlatform();
    final now = at(22, 10, 30);

    await pilot(store, platform, FakeVehicle(), now).tick();
    await pilot(store, platform, FakeVehicle(), now).ignore('window-20260922T1405');
    await pilot(store, platform, FakeVehicle(), now).tick();

    expect(platform.confirmations, hasLength(1));
    expect(store.state.pendingId, isNull);
  });

  test('confirmation tardive d\'une plage depassee : expiree, rien n\'est envoye', () async {
    final store = MemoryStore(pilotConfig());
    final platform = FakePlatform();
    final vehicle = FakeVehicle();

    await pilot(store, platform, vehicle, at(22, 10, 30)).confirm('window-20260922T1405');
    // Apres 21:15, la commande en vigueur est celle de la nuit.
    await pilot(store, platform, vehicle, at(22, 21, 30)).executeConfirmed();

    expect(vehicle.writes, isEmpty);
    expect(platform.results, ['Plage expirée']);
    expect(store.state.confirmedId, isNull);
  });

  test('mode automatique : envoi direct au passage (rattrapage inclus)', () async {
    final store = MemoryStore(pilotConfig(safeMode: false));
    final platform = FakePlatform();
    final vehicle = FakeVehicle();

    await pilot(store, platform, vehicle, at(22, 12)).tick();

    expect(vehicle.writes, hasLength(1));
    expect(platform.confirmations, isEmpty);
    expect(store.state.sentId, 'window-20260922T1405');
  });

  test('echec d\'ecriture : resultat en erreur, commande reproposee au passage suivant', () async {
    final store = MemoryStore(pilotConfig());
    final platform = FakePlatform();
    final now = at(22, 10, 30);

    await pilot(store, platform, FakeVehicle(), now).tick();
    await pilot(store, platform, FakeVehicle(), now).confirm('window-20260922T1405');
    await pilot(store, platform, FakeVehicle(failWrite: true), now).executeConfirmed();

    expect(store.state.lastResultOk, isFalse);
    expect(store.state.sentId, isNull);
    await pilot(store, platform, FakeVehicle(), now).tick();
    expect(platform.confirmations, hasLength(2));
  });

  test('ecriture jamais appliquee : echec apres le delai d\'attente', () async {
    final store = MemoryStore(pilotConfig(safeMode: false));
    final platform = FakePlatform();
    final vehicle = FakeVehicle(applyAfterReads: 1 << 30);
    var now = at(22, 12);
    // Horloge qui avance a chaque lecture pour depasser le delai.
    final p = ChargePilot(
      store: store,
      platform: platform,
      gateway: () async => vehicle,
      clock: () => now = now.add(const Duration(seconds: 30)),
      pollInterval: Duration.zero,
    );

    await p.tick();

    expect(store.state.lastResultOk, isFalse);
    expect(store.state.sentId, isNull);
  });

  test('desactive : reveils annules', () async {
    final store = MemoryStore(pilotConfig(enabled: false));
    final platform = FakePlatform()..wakes[PilotWake.next] = at(22, 21);

    await pilot(store, platform, FakeVehicle(), at(22, 12)).tick();

    expect(platform.wakes, isEmpty);
  });

  test('session absente : pas d\'envoi, resultat explicite', () async {
    final store = MemoryStore(pilotConfig(safeMode: false));
    final platform = FakePlatform();

    await pilot(store, platform, null, at(22, 12)).tick();

    expect(store.state.lastResultOk, isFalse);
    expect(store.state.lastResult, contains('Session expirée'));
  });

  group('parametrage modifie apres un envoi', () {
    // Scenario reel : objectif exceptionnel mercredi 07:15 a 100 % ajoute le
    // soir (plage de nuit elargie), puis supprime.
    ChargePlanConfig withTarget({required bool safeMode, bool target = true}) {
      final base = pilotConfig(safeMode: safeMode).copyWith(batteryCapacityKwh: 52, chargePowerKw: 7.4);
      return target
          ? base.copyWith(oneOffTarget: OneOffTarget(targetPercent: 100, readyAt: at(23, 7, 15)))
          : base.copyWith(clearOneOffTarget: true);
    }

    test('mode automatique : objectif supprime -> plage normale renvoyee', () async {
      final store = MemoryStore(withTarget(safeMode: false));
      final platform = FakePlatform();
      final vehicle = FakeVehicle(soc: 10);
      final now = at(22, 22); // mardi 22:00, plage de nuit en vigueur

      await pilot(store, platform, vehicle, now).tick();
      expect(vehicle.writes.single['chargeTimeStart'], '00:30'); // elargie pour l'objectif

      store.config = withTarget(safeMode: false, target: false);
      await pilot(store, platform, vehicle, now).tick();

      expect(vehicle.writes, hasLength(2));
      expect(vehicle.writes.last['chargeTimeStart'], '01:15');
      expect(vehicle.writes.last['chargeDuration'], 300);
    });

    test('mode securise : objectif supprime -> nouvelle confirmation proposee', () async {
      final store = MemoryStore(withTarget(safeMode: true));
      final platform = FakePlatform();
      final vehicle = FakeVehicle(soc: 10);
      final now = at(22, 22);

      await pilot(store, platform, vehicle, now).tick();
      await pilot(store, platform, vehicle, now).confirm('window-20260923T0115');
      await pilot(store, platform, vehicle, now).executeConfirmed();
      expect(vehicle.writes, hasLength(1));

      store.config = withTarget(safeMode: true, target: false);
      await pilot(store, platform, vehicle, now).tick();

      expect(platform.confirmations, ['window-20260923T0115', 'window-20260923T0115']);
      expect(vehicle.writes, hasLength(1)); // rien d'envoye sans confirmation
    });

    test('variation de batterie seule : pas de renvoi en pleine charge', () async {
      final store = MemoryStore(withTarget(safeMode: false));
      final platform = FakePlatform();
      final vehicle = FakeVehicle(soc: 10);

      await pilot(store, platform, vehicle, at(22, 22)).tick();
      vehicle.soc = 40; // l'elargissement calcule changerait
      await pilot(store, platform, vehicle, at(23, 2)).tick();

      expect(vehicle.writes, hasLength(1));
    });

    test('proposition en attente mise a jour si le parametrage change avant confirmation', () async {
      final store = MemoryStore(withTarget(safeMode: true));
      final platform = FakePlatform();
      final vehicle = FakeVehicle(soc: 10);
      final now = at(22, 22);

      await pilot(store, platform, vehicle, now).tick();
      await pilot(store, platform, vehicle, now).tick(); // inchange : pas de doublon
      expect(platform.confirmations, hasLength(1));

      store.config = withTarget(safeMode: true, target: false);
      await pilot(store, platform, vehicle, now).tick();
      expect(platform.confirmations, hasLength(2));
    });

    test('plage ignoree reproposee si le parametrage la modifie', () async {
      final store = MemoryStore(withTarget(safeMode: true));
      final platform = FakePlatform();
      final vehicle = FakeVehicle(soc: 10);
      final now = at(22, 22);

      await pilot(store, platform, vehicle, now).tick();
      await pilot(store, platform, vehicle, now).ignore('window-20260923T0115');
      await pilot(store, platform, vehicle, now).tick();
      expect(platform.confirmations, hasLength(1));

      store.config = withTarget(safeMode: true, target: false);
      await pilot(store, platform, vehicle, now).tick();
      expect(platform.confirmations, hasLength(2));
    });
  });

  group('un seul envoi a la fois', () {
    test('"Recalculer" pendant un envoi confirme : pas de double ecriture', () async {
      final store = MemoryStore(pilotConfig());
      final platform = FakePlatform();
      final vehicle = FakeVehicle();
      final now = at(22, 10, 30);

      await pilot(store, platform, vehicle, now).tick();
      await pilot(store, platform, vehicle, now).confirm('window-20260922T1405');
      await pilot(store, platform, vehicle, now).tick(); // "Recalculer" avant le reveil d'envoi
      expect(vehicle.writes, isEmpty);

      await pilot(store, platform, vehicle, now).executeConfirmed();
      expect(vehicle.writes, hasLength(1));
      expect(store.state.sendingSince, isNull); // verrou libere
    });

    test('envoi en cours ailleurs : pas d\'envoi, verrou conserve', () async {
      final store = MemoryStore(pilotConfig(safeMode: false))
        ..state = PilotState(sendingSince: at(22, 11, 59));
      final vehicle = FakeVehicle();

      await pilot(store, FakePlatform(), vehicle, at(22, 12)).tick();

      expect(vehicle.writes, isEmpty);
      expect(store.state.sendingSince, at(22, 11, 59));
    });

    test('verrou orphelin (plus de 3 min) : ignore, envoi fait', () async {
      final store = MemoryStore(pilotConfig(safeMode: false))
        ..state = PilotState(sendingSince: at(22, 11, 50));
      final vehicle = FakeVehicle();

      await pilot(store, FakePlatform(), vehicle, at(22, 12)).tick();

      expect(vehicle.writes, hasLength(1));
      expect(store.state.sendingSince, isNull);
    });

    test('reveil d\'envoi pendant un autre envoi : reprogramme, confirmation gardee', () async {
      final store = MemoryStore(pilotConfig())
        ..state = PilotState(
          confirmed: const CommandMark(id: 'window-20260922T1405', signature: '', configFingerprint: ''),
          sendingSince: at(22, 10, 29),
        );
      final platform = FakePlatform();
      final vehicle = FakeVehicle();

      await pilot(store, platform, vehicle, at(22, 10, 30)).executeConfirmed();

      expect(vehicle.writes, isEmpty);
      expect(platform.wakes[PilotWake.execute], at(22, 10, 31));
      expect(store.state.confirmedId, 'window-20260922T1405');
    });
  });

  group('ce qui est confirme est exactement ce qui est envoye', () {
    ChargePlanConfig withTarget({bool target = true}) {
      final base = pilotConfig().copyWith(batteryCapacityKwh: 52, chargePowerKw: 7.4);
      return target
          ? base.copyWith(oneOffTarget: OneOffTarget(targetPercent: 100, readyAt: at(23, 7, 15)))
          : base.copyWith(clearOneOffTarget: true);
    }

    test('batterie differente a l\'envoi : le contenu confirme est envoye tel quel', () async {
      final store = MemoryStore(withTarget());
      final platform = FakePlatform();
      final vehicle = FakeVehicle(soc: 10);
      final now = at(22, 22);

      await pilot(store, platform, vehicle, now).tick(); // proposition elargie (00:30)
      await pilot(store, platform, vehicle, now).confirm('window-20260923T0115');
      vehicle.soc = 60; // un recalcul ne donnerait plus d'elargissement
      await pilot(store, platform, vehicle, now).executeConfirmed();

      expect(vehicle.writes.single['chargeTimeStart'], '00:30');
    });

    test('parametrage modifie apres confirmation : rien d\'envoye, nouvelle proposition', () async {
      final store = MemoryStore(withTarget());
      final platform = FakePlatform();
      final vehicle = FakeVehicle(soc: 10);
      final now = at(22, 22);

      await pilot(store, platform, vehicle, now).tick();
      await pilot(store, platform, vehicle, now).confirm('window-20260923T0115');
      store.config = withTarget(target: false);
      await pilot(store, platform, vehicle, now).executeConfirmed();
      expect(vehicle.writes, isEmpty);
      expect(store.state.confirmedId, isNull);

      await pilot(store, platform, vehicle, now).tick(); // (suit toujours le reveil d'envoi)
      expect(platform.confirmations, hasLength(2));
      expect(vehicle.writes, isEmpty);
    });

    test('mode securise : aucun passage n\'ecrit sans confirmation', () async {
      final store = MemoryStore(withTarget());
      final platform = FakePlatform();
      final vehicle = FakeVehicle(soc: 10);

      for (final now in [at(22, 10, 30), at(22, 21, 30), at(23, 2), at(23, 12)]) {
        await pilot(store, platform, vehicle, now).tick();
        await pilot(store, platform, vehicle, now).executeConfirmed();
      }
      store.config = withTarget(target: false);
      await pilot(store, platform, vehicle, at(23, 12, 5)).tick();

      expect(vehicle.writes, isEmpty);
      expect(platform.confirmations, isNotEmpty);
    });
  });

  group('modeles de vehicule', () {
    test('niveaux : verifie, compatible (renault-api), non pris en charge', () {
      expect(VehicleSupport.of('XHN1CP'), VehicleSupport.verified);
      expect(VehicleSupport.of('R5E1VE'), VehicleSupport.compatible);
      expect(VehicleSupport.of('X102VE'), VehicleSupport.unsupported); // Zoe phase 2
      expect(VehicleSupport.of(null), VehicleSupport.unsupported);
    });

    test('modele non pris en charge : aucune ecriture, reveils annules', () async {
      final store = MemoryStore(pilotConfig(safeMode: false).copyWith(vehicleModelCode: 'X102VE'));
      final platform = FakePlatform()..wakes[PilotWake.next] = at(22, 21);
      final vehicle = FakeVehicle();

      await pilot(store, platform, vehicle, at(22, 12)).tick();

      expect(vehicle.writes, isEmpty);
      expect(platform.confirmations, isEmpty);
      expect(platform.wakes, isEmpty);
    });

    test('modele compatible non verifie : mode securise impose', () async {
      final store = MemoryStore(pilotConfig(safeMode: false).copyWith(vehicleModelCode: 'R5E1VE'));
      final platform = FakePlatform();
      final vehicle = FakeVehicle();

      await pilot(store, platform, vehicle, at(22, 12)).tick();

      expect(vehicle.writes, isEmpty);
      expect(platform.confirmations, hasLength(1));
    });
  });
}
