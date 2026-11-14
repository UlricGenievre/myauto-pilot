import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../../background/pilot_runtime.dart';
import '../../core/charge_plan/charge_pilot.dart';
import '../../core/charge_plan/pilot_state.dart';
import '../../core/models/charge_plan_config.dart';
import '../../core/models/vehicle.dart';
import '../../core/storage/charge_plan_storage.dart';
import '../auth/auth_controller.dart';
import '../demo/demo_data.dart';
import '../schedule/schedule_providers.dart';
import '../vehicle/vehicle_providers.dart';

/// En demonstration : stockage en memoire, neuf a chaque entree.
final chargePlanStorageProvider = Provider<ChargePlanStorage>(
  (ref) => ref.watch(demoModeProvider) ? DemoChargePlanStorage() : ChargePlanStorage(),
);

/// Parametrage de charge, charge depuis le stockage au premier acces et
/// sauvegarde a chaque modification.
final chargePlanConfigProvider =
    AsyncNotifierProvider<ChargePlanConfigController, ChargePlanConfig>(ChargePlanConfigController.new);

class ChargePlanConfigController extends AsyncNotifier<ChargePlanConfig> {
  @override
  Future<ChargePlanConfig> build() => ref.watch(chargePlanStorageProvider).load();

  Timer? _tickDebounce;

  /// Applique [change] a la config courante et la sauvegarde, puis relance
  /// le pilote (reprogrammation des reveils) apres un court delai, pour ne
  /// pas le faire a chaque cran d'un curseur.
  ///
  /// Sans vehicule pilote, le vehicule affiche le devient : ce qui est regle
  /// (programme dedie, batterie...) vaut pour lui.
  Future<void> edit(ChargePlanConfig Function(ChargePlanConfig current) change) async {
    final current = state.value ?? const ChargePlanConfig();
    var updated = change(current);
    final selected = ref.read(selectedVehicleProvider);
    if (updated.vehicleVin == null && selected != null) {
      updated = updated.copyWith(
          vehicleVin: selected.vin, vehicleModelCode: selected.modelCode, vehicleAccountId: selected.accountId);
    }
    state = AsyncData(updated);
    await ref.read(chargePlanStorageProvider).save(updated);
    _tickDebounce?.cancel();
    if (ref.read(demoModeProvider)) return;
    _tickDebounce = Timer(const Duration(seconds: 2), () => refreshPilot(ref.invalidate));
  }

  /// Pilotage reporte sur [vehicle] (cf. [ChargePlanConfig.forVehicle]),
  /// etat d'execution remis a zero. Renvoie la raison d'un refus, ou null :
  /// pas de changement pendant un envoi ou une charge immediate (ce qu'elle
  /// a remplace doit etre remis dans l'ancien vehicule).
  Future<String?> switchVehicle(Vehicle vehicle) async {
    final storage = ref.read(chargePlanStorageProvider);
    final pilotState = await storage.loadState();
    if (pilotState.boost != null || pilotState.manualChargeTarget != null) {
      return 'Charge immédiate en cours : arrêtez-la ou attendez sa fin avant de changer de véhicule.';
    }
    final since = pilotState.sendingSince;
    if (since != null && DateTime.now().difference(since) < ChargePilot.sendLockTimeout) {
      return 'Envoi en cours à la voiture : réessayez dans un instant.';
    }
    final current = state.value ?? const ChargePlanConfig();
    final updated = current.forVehicle(vin: vehicle.vin, modelCode: vehicle.modelCode, accountId: vehicle.accountId);
    state = AsyncData(updated);
    await storage.save(updated);
    await storage.saveState(const PilotState());
    _tickDebounce?.cancel();
    if (!ref.read(demoModeProvider)) await refreshPilot(ref.invalidate);
    return null;
  }
}

/// Vehicule affiche autre que le vehicule pilote : le pilotage et les
/// reglages propres au vehicule ne s'y appliquent pas.
final showsOtherThanPilotedProvider = Provider<bool>((ref) {
  final selected = ref.watch(selectedVehicleProvider);
  final vin = ref.watch(chargePlanConfigProvider).value?.vehicleVin;
  return selected != null && vin != null && selected.vin != vin;
});

/// Etat d'execution du pilotage (dernier envoi, confirmation en attente,
/// prochain reveil), ecrit par les reveils en arriere-plan.
final pilotStateProvider = FutureProvider.autoDispose<PilotState>(
  (ref) => ref.watch(chargePlanStorageProvider).loadState(),
);

/// Autorisations Android dont depend le pilotage : notifications
/// (confirmations du mode securise, resultats) et "Alarmes et rappels"
/// (reveils a l'heure exacte).
final notificationsAllowedProvider = FutureProvider.autoDispose<bool>((ref) => notificationsAllowed());
final exactAlarmsAllowedProvider = FutureProvider.autoDispose<bool>((ref) => exactAlarmsAllowed());

/// Passage du pilote depuis l'app, puis relecture de son etat et des
/// reglages de la voiture (un envoi a pu les modifier).
/// [invalidate] : `ref.invalidate` d'un `Ref` ou d'un `WidgetRef`.
Future<void> refreshPilot(void Function(ProviderOrFamily provider, {bool asReload}) invalidate) async {
  try {
    await runPilotTick();
  } catch (error) {
    debugPrint('runPilotTick: $error');
  }
  invalidate(pilotStateProvider);
  invalidate(vehicleScheduleProvider);
}
