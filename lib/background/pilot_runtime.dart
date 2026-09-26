/// Execution du pilotage automatique sur la plateforme : reveils Android a
/// l'heure exacte + notifications. Sur le web (apercu de dev), une version
/// vide est utilisee : ces mecanismes n'y existent pas.
library;

export 'pilot_runtime_stub.dart' if (dart.library.io) 'pilot_runtime_android.dart';
