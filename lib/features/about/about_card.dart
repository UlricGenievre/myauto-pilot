import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/dashboard_card.dart';
import '../charge_plan/charge_plan_pickers.dart';
import 'disclaimer.dart';
import 'tutorial_screen.dart';

final _packageInfoProvider = FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());

/// Reglages : version, licence, code source, credits et avertissement.
class AboutCard extends ConsumerWidget {
  const AboutCard({super.key});

  static const sourceUrl = 'https://github.com/UlricGenievre/myauto-pilot';
  static const privacyUrl = '$sourceUrl/blob/main/PRIVACY.md';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(_packageInfoProvider).value?.version;
    return DashboardCard(
      title: 'À propos',
      icon: Icons.info_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MyAuto Pilot${version != null ? ' $version' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Logiciel libre sous licence GPL-3.0. Code source :', style: hintStyle),
          const SelectableText(sourceUrl, style: hintStyle),
          const SizedBox(height: 4),
          const Text(
            'Accès aux services Renault d\'après le projet communautaire renault-api (hacf-fr/renault-api).',
            style: hintStyle,
          ),
          const SizedBox(height: 4),
          const Text('Politique de confidentialité :', style: hintStyle),
          const SelectableText(privacyUrl, style: hintStyle),
          TextButton.icon(
            icon: const Icon(Icons.description_outlined, color: AppColors.accent),
            label: const Text('Licences des composants'),
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'MyAuto Pilot',
              applicationVersion: version,
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.school_outlined, color: AppColors.accent),
            label: const Text('Revoir le tutoriel'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (route) => TutorialScreen(onFinished: () => Navigator.of(route).pop()),
            )),
          ),
          const SizedBox(height: 8),
          const DisclaimerPoints(),
        ],
      ),
    );
  }
}
