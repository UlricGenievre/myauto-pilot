import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/about/disclaimer.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'home_screen.dart';

class MyAutoPilotApp extends ConsumerWidget {
  const MyAutoPilotApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final disclaimerAccepted = ref.watch(disclaimerAcceptedProvider);

    return MaterialApp(
      title: 'MyAuto Pilot',
      // Sombre uniquement, assume : coller au look "cockpit" premium plutot
      // que suivre le theme clair/sombre du systeme (cf. AppTheme).
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      // Interface en francais uniquement (textes de l'app en dur) : les
      // composants Material suivent. Le formatage des dates/heures, lui,
      // reste cale sur la locale de l'appareil (cf. date_formatting.dart).
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // AuthLoading n'intervient que pendant une tentative de connexion
      // depuis LoginScreen (cf. _tryRestoreSession dans AuthController, qui
      // ne passe jamais par cet etat) : on garde donc l'ecran de login
      // affiche, avec son propre indicateur de chargement sur le bouton.
      home: switch (disclaimerAccepted) {
        AsyncData(value: false) => const DisclaimerScreen(),
        AsyncData() => switch (authState) {
            AuthAuthenticated() => const HomeScreen(),
            AuthInitial() => const _SplashScreen(),
            AuthLoading() || AuthUnauthenticated() => const LoginScreen(),
          },
        _ => const _SplashScreen(),
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
