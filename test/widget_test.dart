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

void main() {
  testWidgets('affiche l\'ecran de login quand aucune session n\'est active', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          disclaimerAcceptedProvider.overrideWith((ref) async => true),
          authRepositoryProvider.overrideWithValue(_NoSessionAuthRepository()),
          // Pas de reseau en test : liste de pays factice.
          renaultLocalesProvider.overrideWith(
            (ref) async => const [
              RenaultApiSettings(
                locale: 'fr_FR',
                gigyaUrl: 'https://accounts.eu1.gigya.com',
                gigyaKey: '3_FakeGigyaKey0123456789',
                kamereonUrl: 'https://api.wrd-aws.com',
                kamereonKey: 'FakeKamereonKey0123456789',
              ),
            ],
          ),
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
}
