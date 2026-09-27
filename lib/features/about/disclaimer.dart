import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_prefs.dart';
import '../../core/theme/app_theme.dart';

final appPrefsProvider = Provider<AppPrefs>((ref) => AppPrefs());

/// Avertissement accepte (affiche au premier lancement, avant la connexion).
final disclaimerAcceptedProvider = FutureProvider<bool>((ref) => ref.read(appPrefsProvider).disclaimerAccepted);

/// Tutoriel a afficher apres l'avertissement (premier lancement uniquement).
final tutorialPendingProvider = FutureProvider<bool>((ref) => ref.read(appPrefsProvider).tutorialPending);

/// Points de l'avertissement, repris dans "A propos".
const disclaimerPoints = [
  'MyAuto Pilot est une application indépendante, ni affiliée à Renault ni approuvée par Renault.',
  'Elle utilise l\'accès non documenté de l\'application MyRenault : Renault peut le modifier ou le couper '
      'à tout moment.',
  'Elle modifie les réglages de charge de votre véhicule (plage de charge, programme « prête à »). Le mode '
      'sécurisé, activé par défaut, vous demande de confirmer chaque envoi.',
  'Vos identifiants MyRenault ne sont jamais enregistrés, et vos réglages restent sur votre téléphone.',
  'Logiciel libre fourni sans aucune garantie (licence GPL-3.0) : vous l\'utilisez à vos risques.',
];

/// Liste a puces des points de l'avertissement.
class DisclaimerPoints extends StatelessWidget {
  const DisclaimerPoints({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final point in disclaimerPoints)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.info_outline, size: 18, color: AppColors.accent),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(point, style: const TextStyle(height: 1.35))),
              ],
            ),
          ),
      ],
    );
  }
}

/// Premier lancement : avertissement a accepter avant la connexion.
class DisclaimerScreen extends ConsumerWidget {
  const DisclaimerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          children: [
            const Icon(Icons.bolt_rounded, size: 40, color: AppColors.accent),
            const SizedBox(height: 16),
            const Text('Avant de commencer', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 24),
            const DisclaimerPoints(),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                await ref.read(appPrefsProvider).acceptDisclaimer();
                ref.invalidate(tutorialPendingProvider);
                ref.invalidate(disclaimerAcceptedProvider);
              },
              child: const Text('J\'ai compris'),
            ),
          ],
        ),
      ),
    );
  }
}
