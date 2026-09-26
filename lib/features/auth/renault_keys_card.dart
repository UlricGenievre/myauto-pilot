import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_config.dart';
import '../../core/api/renault_api_settings.dart';
import '../../core/debug/dev_log.dart';
import '../../core/debug/dev_tools.dart';
import '../../core/storage/secure_token_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_formatting.dart';
import '../../core/widgets/dashboard_card.dart';
import '../charge_plan/charge_plan_pickers.dart';
import 'auth_controller.dart';
import 'auth_repository.dart';

final _apiSettingsProvider = FutureProvider.autoDispose<RenaultApiSettings?>((ref) => SecureTokenStorage().apiSettings);

/// Reglages : pays du compte, date de chargement des cles Renault et
/// verification manuelle. En mode developpement, simulation d'une cle
/// perimee pour valider la mise a jour automatique.
class RenaultKeysCard extends ConsumerStatefulWidget {
  const RenaultKeysCard({super.key});

  @override
  ConsumerState<RenaultKeysCard> createState() => _RenaultKeysCardState();
}

class _RenaultKeysCardState extends ConsumerState<RenaultKeysCard> {
  bool _busy = false;

  Future<void> _check() async {
    setState(() => _busy = true);
    final result = await ref.read(authRepositoryProvider).recoverFromKeyRejection(force: true);
    if (!mounted) return;
    setState(() => _busy = false);
    ref.invalidate(_apiSettingsProvider);
    final message = switch (result) {
      KeysUpdateResult.updated => 'Nouvelles clés récupérées et testées : elles sont maintenant utilisées.',
      KeysUpdateResult.unchanged => 'Clés à jour : identiques à celles de renault-api.',
      KeysUpdateResult.tooSoon => 'Vérification déjà faite récemment.',
      KeysUpdateResult.failed => 'Vérification impossible (renault-api injoignable, ou nouvelles clés refusées).',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Outil de dev : altere une cle (en memoire et en stockage) pour
  /// provoquer un refus de Renault au prochain appel, et reautorise une
  /// recherche immediate de nouvelles cles.
  Future<void> _simulateStaleKey({required bool gigya}) async {
    final storage = SecureTokenStorage();
    final current = ApiConfig.settings ?? await storage.apiSettings;
    if (current == null) return;
    final stale = gigya
        ? current.copyWith(gigyaKey: '${current.gigyaKey}X')
        : current.copyWith(kamereonKey: '${current.kamereonKey}X');
    ApiConfig.use(stale);
    await storage.saveApiSettings(stale);
    await storage.saveLastKeyCheck(null);
    final reread = await storage.apiSettings;
    DevLog.send('simulate', {
      'gigya': gigya,
      'storedGigyaKeyEnd': reread?.gigyaKey.substring(reread.gigyaKey.length - 4),
      'storedKamereonKeyEnd': reread?.kamereonKey.substring(reread.kamereonKey.length - 4),
    });
    if (!mounted) return;
    ref.invalidate(_apiSettingsProvider);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Clé ${gigya ? 'Gigya' : 'Kamereon'} altérée : le prochain appel à Renault doit la refuser.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(_apiSettingsProvider).valueOrNull;
    return DashboardCard(
      title: 'Clés Renault',
      icon: Icons.key_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            settings == null ? 'Aucune clé chargée.' : renaultLocaleName(settings.locale),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            settings?.fetchedAt != null
                ? 'Clés récupérées depuis renault-api ${formatDayTime(settings!.fetchedAt!)}.'
                : 'Clés récupérées depuis renault-api à la connexion.',
            style: hintStyle,
          ),
          const SizedBox(height: 2),
          const Text(
            'Si Renault les change, l\'app récupère les nouvelles d\'elle-même. Pour changer de pays : se déconnecter.',
            style: hintStyle,
          ),
          const SizedBox(height: 8),
          if (_busy)
            const LinearProgressIndicator()
          else
            TextButton.icon(
              icon: const Icon(Icons.refresh, color: AppColors.accent),
              label: const Text('Vérifier les clés'),
              onPressed: settings == null ? null : _check,
            ),
          if (devToolsEnabled && settings != null) ...[
            const Divider(),
            const Text('Développement : simuler une clé périmée', style: hintStyle),
            Wrap(
              spacing: 8,
              children: [
                TextButton(onPressed: () => _simulateStaleKey(gigya: true), child: const Text('Altérer Gigya')),
                TextButton(onPressed: () => _simulateStaleKey(gigya: false), child: const Text('Altérer Kamereon')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
