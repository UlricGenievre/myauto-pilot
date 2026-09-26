/// Erreur levee par la couche API (Gigya ou Kamereon).
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.keyRejected = false});

  final String message;
  final int? statusCode;

  /// La cle d'API elle-meme a ete refusee (et non la session, le compte ou
  /// l'endpoint) : declenche la recherche de nouvelles cles.
  final bool keyRejected;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
