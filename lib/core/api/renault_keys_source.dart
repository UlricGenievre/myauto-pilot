import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'renault_api_settings.dart';

/// Recuperation des cles et serveurs Renault par pays depuis le projet open
/// source `renault-api` (fichier `const.py`), qui les tient a jour quand
/// Renault les change. Le fichier de configuration MyRenault publie par
/// Renault (sur S3) n'est pas utilisable : il repond 403.
class RenaultKeysSource {
  RenaultKeysSource({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const sourceUrl = 'https://raw.githubusercontent.com/hacf-fr/renault-api/main/src/renault_api/const.py';

  /// Toutes les locales valides, triees par nom de pays. Leve une
  /// [ApiException] lisible si le fichier est injoignable ou illisible.
  Future<List<RenaultApiSettings>> fetchAll() async {
    final String source;
    try {
      final response = await _dio.get<String>(
        sourceUrl,
        options: Options(responseType: ResponseType.plain, receiveTimeout: const Duration(seconds: 20)),
      );
      source = response.data ?? '';
    } on DioException catch (e) {
      throw ApiException('Impossible de récupérer les clés Renault (renault-api) : ${e.message ?? e.type.name}');
    }
    final now = DateTime.now();
    try {
      return parseRenaultConst(source).map((s) => s.copyWith(fetchedAt: now)).toList()
        ..sort((a, b) => renaultLocaleName(a.locale).compareTo(renaultLocaleName(b.locale)));
    } on FormatException catch (e) {
      throw ApiException('Fichier de clés renault-api illisible (${e.message}) : mise à jour de l\'app nécessaire.');
    }
  }

  /// Reglages d'une locale, ou null si elle n'existe plus dans le fichier.
  Future<RenaultApiSettings?> fetch(String locale) async {
    for (final settings in await fetchAll()) {
      if (settings.locale == locale) return settings;
    }
    return null;
  }
}

/// Lit `AVAILABLE_LOCALES` dans le source Python de `const.py`.
///
/// Ce n'est pas un format de donnees : les valeurs sont soit des litteraux,
/// soit des references a des constantes de haut niveau
/// (`GIGYA_KEY_EU = "..."`). Les constantes sont lues **ancrees en debut de
/// ligne** : une recherche naive de `KAMEREON_APIKEY = "..."` tombe d'abord
/// sur `CONF_KAMEREON_APIKEY = "kamereon-api-key"`.
///
/// Les locales dont une valeur ne passe pas [validateRenaultSettings] sont
/// ecartees. [FormatException] si la structure attendue est introuvable.
List<RenaultApiSettings> parseRenaultConst(String source) {
  final constants = <String, String>{
    for (final m in RegExp(r'^([A-Z][A-Z0-9_]*)\s*=\s*"([^"]*)"', multiLine: true).allMatches(source))
      m.group(1)!: m.group(2)!,
  };

  final start = RegExp(r'^AVAILABLE_LOCALES\s*=\s*\{', multiLine: true).firstMatch(source);
  if (start == null) throw const FormatException('AVAILABLE_LOCALES introuvable');
  final end = RegExp(r'^\}', multiLine: true).firstMatch(source.substring(start.end));
  if (end == null) throw const FormatException('fin de AVAILABLE_LOCALES introuvable');
  final section = source.substring(start.end, start.end + end.start);

  String? resolve(String token) {
    if (token.startsWith('"')) return token.substring(1, token.length - 1);
    return constants[token];
  }

  final result = <RenaultApiSettings>[];
  final blocks = RegExp(r'"([a-z]{2}_[A-Z]{2})"\s*:\s*\{([^}]*)\}').allMatches(section);
  for (final block in blocks) {
    final fields = <String, String>{};
    for (final entry in RegExp(r'([A-Z][A-Z0-9_]*)\s*:\s*("[^"]*"|[A-Z][A-Z0-9_]*)').allMatches(block.group(2)!)) {
      final field = constants[entry.group(1)!];
      final value = resolve(entry.group(2)!);
      if (field != null && value != null) fields[field] = value;
    }
    final settings = _settingsFrom(block.group(1)!, fields);
    if (settings != null && validateRenaultSettings(settings) == null) result.add(settings);
  }

  if (result.isEmpty) throw const FormatException('aucune locale exploitable');
  return result;
}

RenaultApiSettings? _settingsFrom(String locale, Map<String, String> fields) {
  final gigyaUrl = fields['gigya-root-url'];
  final gigyaKey = fields['gigya-api-key'];
  final kamereonUrl = fields['kamereon-root-url'];
  final kamereonKey = fields['kamereon-api-key'];
  if (gigyaUrl == null || gigyaKey == null || kamereonUrl == null || kamereonKey == null) return null;
  return RenaultApiSettings(
    locale: locale,
    gigyaUrl: gigyaUrl,
    gigyaKey: gigyaKey,
    kamereonUrl: kamereonUrl,
    kamereonKey: kamereonKey,
  );
}

/// Null si les valeurs sont acceptables, sinon la raison du refus.
///
/// Les adresses sont limitees a une liste de domaines : un depot
/// `renault-api` compromis ne doit pas pouvoir rediriger identifiants et JWT
/// vers un autre serveur. Si Renault change un jour de domaine, il faudra
/// mettre l'app a jour (rare, accepte).
String? validateRenaultSettings(RenaultApiSettings s) {
  if (!RegExp(r'^[34]_[A-Za-z0-9_-]{10,}$').hasMatch(s.gigyaKey)) return 'clé Gigya au format inattendu';
  if (!RegExp(r'^[A-Za-z0-9]{16,64}$').hasMatch(s.kamereonKey)) return 'clé Kamereon au format inattendu';
  if (!_isAllowedUrl(s.gigyaUrl, (host) => RegExp(r'^accounts\.[a-z0-9]+\.gigya\.com$').hasMatch(host))) {
    return 'serveur Gigya non autorisé : ${s.gigyaUrl}';
  }
  if (!_isAllowedUrl(s.kamereonUrl, (host) => host.endsWith('.wrd-aws.com') || host.endsWith('.kamereon.com'))) {
    return 'serveur Kamereon non autorisé : ${s.kamereonUrl}';
  }
  return null;
}

bool _isAllowedUrl(String url, bool Function(String host) allowedHost) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.hasPort) return false;
  if (uri.path.isNotEmpty && uri.path != '/') return false;
  if (uri.hasQuery || uri.hasFragment) return false;
  return allowedHost(uri.host.toLowerCase());
}
