import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../../background/pilot_runtime.dart';
import '../../core/charge_plan/pilot_state.dart';
import '../../core/models/charge_plan_config.dart';
import '../../core/storage/charge_plan_storage.dart';
import '../auth/auth_controller.dart';
import '../demo/demo_data.dart';

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
  Future<void> edit(ChargePlanConfig Function(ChargePlanConfig current) change) async {
    final current = state.value ?? const ChargePlanConfig();
    final updated = change(current);
    state = AsyncData(updated);
    await ref.read(chargePlanStorageProvider).save(updated);
    _tickDebounce?.cancel();
    if (ref.read(demoModeProvider)) return;
    _tickDebounce = Timer(const Duration(seconds: 2), () => refreshPilot(ref.invalidate));
  }
}

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

/// Passage du pilote depuis l'app, puis relecture de son etat.
/// [invalidate] : `ref.invalidate` d'un `Ref` ou d'un `WidgetRef`.
Future<void> refreshPilot(void Function(ProviderOrFamily provider, {bool asReload}) invalidate) async {
  try {
    await runPilotTick();
  } catch (error) {
    debugPrint('runPilotTick: $error');
  }
  invalidate(pilotStateProvider);
}
