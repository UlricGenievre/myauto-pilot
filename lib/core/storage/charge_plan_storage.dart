import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../charge_plan/charge_pilot.dart';
import '../charge_plan/pilot_state.dart';
import '../models/charge_plan_config.dart';
import 'secure_storage.dart';

/// Persistance du parametrage de charge (une cle JSON), meme mecanisme que
/// `SecureTokenStorage`. Classe Dart pure (pas de Riverpod) : reutilisee
/// telle quelle par les reveils en arriere-plan.
class ChargePlanStorage implements PilotStore {
  ChargePlanStorage({FlutterSecureStorage? storage}) : _storage = storage ?? appSecureStorage;

  final FlutterSecureStorage _storage;

  static const _configKey = 'charge_plan_config';
  static const _stateKey = 'charge_pilot_state';

  /// Config enregistree, ou config vide si rien n'est stocke / illisible.
  @override
  Future<ChargePlanConfig> load() async {
    final raw = await _storage.read(key: _configKey);
    if (raw == null) return const ChargePlanConfig();
    try {
      return ChargePlanConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return const ChargePlanConfig();
    }
  }

  Future<void> save(ChargePlanConfig config) =>
      _storage.write(key: _configKey, value: jsonEncode(config.toJson()));

  /// Etat d'execution du pilotage (cle separee : ecrit par les reveils,
  /// alors que la config n'est ecrite que par l'interface).
  @override
  Future<PilotState> loadState() async {
    final raw = await _storage.read(key: _stateKey);
    if (raw == null) return const PilotState();
    try {
      return PilotState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return const PilotState();
    }
  }

  @override
  Future<void> saveState(PilotState state) =>
      _storage.write(key: _stateKey, value: jsonEncode(state.toJson()));
}
