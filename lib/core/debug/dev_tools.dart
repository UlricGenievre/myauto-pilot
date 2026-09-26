import 'package:flutter/foundation.dart';

/// Outils de developpement visibles (ex. tests d'ecriture sur le vehicule) :
/// en mode debug (`flutter run`, apercu web) ou dans un build construit avec
/// `--dart-define=DEV_TOOLS=true`. Masques dans un build release normal.
const bool devToolsEnabled = kDebugMode || bool.fromEnvironment('DEV_TOOLS');
