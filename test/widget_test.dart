import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myauto_pilot/app.dart';
import 'package:myauto_pilot/features/about/disclaimer.dart';
import 'package:myauto_pilot/core/api/renault_api_settings.dart';
import 'package:myauto_pilot/features/auth/auth_controller.dart';
import 'package:myauto_pilot/features/auth/auth_repository.dart';

/// Repository de test : pas de session a restaurer, sans toucher au vrai
/// stockage securise (qui depend d'un service systeme absent en test).
class _NoSessionAuthRepository implements AuthRepository {
  @override
  Future<AuthSession?> restoreSession() async => null;

  @override
  Future<AuthSession> login({required String email, required String password, required RenaultApiSettings settings}) =>
      throw UnimplementedError();

  @override
  Future<KeysUpdateResult> recoverFromKeyRejection({bool force = false}) => throw UnimplementedError();

  @override
  void Function(String title, String body)? get onKeysEvent => null;

  @override
  Future<AuthSession?> refreshJwt() => throw UnimplementedError();

  @override
  Future<void> logout() => throw UnimplementedError();
}

final _fakeLocales = renaultLocalesProvider.overrideWith(
  (ref) async => const [
    RenaultApiSettings(
      locale: 'fr_FR',
      gigyaUrl: 'https://accounts.eu1.gigya.com',
      gigyaKey: '3_FakeGigyaKey0123456789',
      kamereonUrl: 'https://api.wrd-aws.com',
      kamereonKey: 'FakeKamereonKey0123456789',
    ),
  ],
);

void main() {
  testWidgets('affiche l\'ecran de login quand aucune session n\'est active', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          disclaimerAcceptedProvider.overrideWith((ref) async => true),
          authRepositoryProvider.overrideWithValue(_NoSessionAuthRepository()),
          // Pas de reseau en test : liste de pays factice.
          _fakeLocales,
        ],
        child: const MyAutoPilotApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MyAuto Pilot'), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
    expect(find.text('France'), findsOneWidget);
  });

  testWidgets('premier lancement : avertissement avant la connexion', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          disclaimerAcceptedProvider.overrideWith((ref) async => false),
          authRepositoryProvider.overrideWithValue(_NoSessionAuthRepository()),
        ],
        child: const MyAutoPilotApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Avant de commencer'), findsOneWidget);
    expect(find.text('J\'ai compris'), findsOneWidget);
    expect(find.text('Se connecter'), findsNothing);
  });

  testWidgets('demonstration : vehicule fictif sans pilotage, puis retour a la connexion', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          disclaimerAcceptedProvider.overrideWith((ref) async => true),
          authRepositoryProvider.overrideWithValue(_NoSessionAuthRepository()),
          _fakeLocales,
        ],
        child: const MyAutoPilotApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Découvrir sans compte (démonstration)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Démonstration'), findsOneWidget);
    expect(find.text('Renault Rafale'), findsOneWidget);

    await tester.tap(find.text('Pilotage'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('Non disponible en démonstration'), 200);
    expect(find.textContaining('Non disponible en démonstration'), findsOneWidget);

    // Sortie : pas d'appel au logout du repository (il leverait ici).
    await tester.tap(find.byTooltip('Quitter la démonstration'));
    await tester.pumpAndSettle();
    expect(find.text('Se connecter'), findsOneWidget);
  });
}
