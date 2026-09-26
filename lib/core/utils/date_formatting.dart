import 'dart:ui' show PlatformDispatcher;

import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

/// Formatte une date pour affichage utilisateur (ex: derniere position
/// connue), adapte a la locale de l'appareil plutot qu'au francais en dur :
/// c'est le point le plus couteux a corriger plus tard si l'app devient
/// internationale, donc autant le faire correctement des maintenant meme si
/// le reste des textes de l'UI reste en francais pour l'instant.
///
/// - Moins de 24h : relatif ("il y a 5 min" / "5 minutes ago"...).
/// - Au-dela : date+heure absolues, dans l'ordre/format de la locale.
String formatRelativeDateTime(DateTime dateTime) {
  final locale = _deviceLocale();
  final age = DateTime.now().difference(dateTime);

  if (age >= Duration.zero && age < const Duration(hours: 24)) {
    // timeago ne connait que les locales explicitement enregistrees (cf.
    // setLocaleMessages dans main.dart) ; pour toute autre langue il
    // retombe silencieusement sur l'anglais, donc pas besoin de le
    // verifier nous-memes ici.
    final language = locale.split(RegExp('[-_]')).first.toLowerCase();
    return timeago.format(dateTime, locale: language);
  }
  return DateFormat.yMMMd(locale).add_Hm().format(dateTime);
}

/// La locale reelle de l'appareil/navigateur, PAS `Localizations.localeOf`
/// (qui depend de `supportedLocales` cote `MaterialApp` : sans l'avoir
/// explicitement configure, Flutter retombe silencieusement sur `en_US` quel
/// que soit le systeme). `PlatformDispatcher` remonte directement ce que
/// rapporte l'OS/le navigateur, sans cette couche de resolution.
String _deviceLocale() => PlatformDispatcher.instance.locale.toLanguageTag();

/// Formatte une heure (sans date) en "HH:mm" selon la locale de l'appareil.
String formatTimeOfDay(DateTime dateTime) => DateFormat.Hm(_deviceLocale()).format(dateTime);

/// Parse une heure au format "HH:MM" ou "HH:MM:SS" (`ev/settings` renvoie
/// `chargeTimeStart` en "HH:MM" mais `programDepartureTime` en "HH:MM:SS" ;
/// deja en heure locale/vehicule, pas de conversion UTC a faire ici). Les
/// secondes sont ignorees. Retourne null si le format est inattendu.
DateTime? parseTimeOfDay(String? raw) {
  if (raw == null) return null;
  final match = RegExp(r'^(\d{2}):(\d{2})(?::\d{2})?$').firstMatch(raw);
  if (match == null) return null;
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, int.parse(match.group(1)!), int.parse(match.group(2)!));
}

/// Comme [parseTimeOfDay], mais ajoute une duree (en minutes) : utile pour
/// calculer l'heure de fin d'une plage de charge ("debut + duree").
DateTime? addMinutesToTimeOfDay(String? raw, int? minutes) {
  final start = parseTimeOfDay(raw);
  if (start == null || minutes == null) return null;
  return start.add(Duration(minutes: minutes));
}

/// Jour + heure courts pour une echeance proche : "aujourd'hui 13:00",
/// "demain 07:30", sinon "mer. 24 07:30" (jour selon la locale de
/// l'appareil).
String formatDayTime(DateTime dateTime) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dateTime.year, dateTime.month, dateTime.day);
  final time = formatTimeOfDay(dateTime);
  final days = (day.difference(today).inHours / 24).round(); // robuste aux jours de 23/25 h
  if (days == 0) return 'aujourd\'hui $time';
  if (days == 1) return 'demain $time';
  if (days == -1) return 'hier $time';
  return '${DateFormat('EEE d', _deviceLocale()).format(dateTime)} $time';
}
