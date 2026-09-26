import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'app.dart';
import 'background/pilot_runtime.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Charge les symboles de date (noms de mois/jours, ordre jour/mois...)
  // pour toutes les locales : sans ca, DateFormat leve LocaleDataException
  // des qu'on formate avec une locale autre que celle par defaut.
  await initializeDateFormatting();

  // timeago n'enregistre que l'anglais par defaut (utilise en fallback pour
  // toute locale non geree) : on ajoute le francais, langue actuelle de
  // l'UI. A completer au fur et a mesure des langues effectivement
  // supportees par l'app (cf. formatRelativeDateTime).
  timeago.setLocaleMessages('fr', timeago.FrMessages());

  // Licence de la police embarquee, affichee avec celles des paquets
  // (ecran des licences de "A propos").
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Manrope'], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });

  // Reveils + notifications du pilotage de charge. Un echec ici ne doit pas
  // empecher l'app de demarrer.
  try {
    await initPilotRuntime();
  } catch (error) {
    debugPrint('initPilotRuntime: $error');
  }

  runApp(const ProviderScope(child: MyAutoPilotApp()));
}
