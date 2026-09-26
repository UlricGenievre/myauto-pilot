import 'dart:convert';

import 'package:dio/dio.dart';

/// Envoi d'evenements de diagnostic vers `scripts/dev_log_server.py`, pour
/// l'apercu web en developpement (le navigateur ne peut pas ecrire de
/// fichier local, et ses `print()` restent dans sa console).
///
/// Inactif par defaut : ne fait rien tant que l'app n'est pas lancee avec
/// `--dart-define=DEV_LOG_URL=http://localhost:8091/log` (jamais dans
/// `.env`, qui sert aussi aux builds du telephone). Envoi "au mieux" : une
/// erreur d'envoi est ignoree, elle ne doit jamais gener l'app.
abstract final class DevLog {
  static const _url = String.fromEnvironment('DEV_LOG_URL');

  static bool get isEnabled => _url.isNotEmpty;

  static final _dio = Dio();

  /// [event] : nom court ; [data] : details serialisables en JSON.
  static void send(String event, [Map<String, Object?> data = const {}]) {
    if (!isEnabled) return;
    // text/plain : requete "simple" cote navigateur, sans pre-verification
    // CORS supplementaire.
    _dio
        .post<void>(
          _url,
          data: jsonEncode({'event': event, ...data}),
          options: Options(contentType: 'text/plain'),
        )
        .ignore();
  }
}
