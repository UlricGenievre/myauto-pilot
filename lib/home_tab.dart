import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Onglet affiche : partage pour permettre a un ecran d'en ouvrir un autre
/// (ex. le resume de pilotage de l'onglet Etat ouvre l'onglet Pilotage).
final homeTabProvider = StateProvider<int>((ref) => 0);

/// Index des onglets, dans l'ordre de la barre de navigation.
abstract final class HomeTab {
  static const status = 0;
  static const location = 1;
  static const pilot = 2;
  static const actions = 3;
}
