import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/debug/dev_tools.dart';
import '../../core/theme/app_theme.dart';
import '../about/about_card.dart';
import '../auth/auth_controller.dart';
import '../auth/renault_keys_card.dart';
import 'cards/agendas_card.dart';
import 'cards/battery_card.dart';
import 'cards/calendar_card.dart';
import 'cards/dedicated_program_card.dart';
import 'cards/push_settings_card.dart';
import 'charge_plan_providers.dart';
import 'write_test_card.dart';

/// Reglages (roue dentee) : le parametrage de fond du pilotage, qu'on ne
/// touche qu'occasionnellement. L'usage quotidien est dans l'onglet
/// Pilotage.
class ChargePlanSettingsScreen extends ConsumerWidget {
  const ChargePlanSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncConfig = ref.watch(chargePlanConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages', style: TextStyle(fontWeight: FontWeight.w700))),
      body: asyncConfig.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error', style: const TextStyle(color: AppColors.error))),
        data: (config) {
          final controller = ref.read(chargePlanConfigProvider.notifier);
          return ListView(
            // Marge de la barre de navigation Android : l'app s'affiche dessous
            // (plein ecran impose depuis Android 15).
            padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + MediaQuery.paddingOf(context).bottom),
            children: [
              CalendarCard(config: config, controller: controller),
              const SizedBox(height: 16),
              PushSettingsCard(config: config, controller: controller),
              const SizedBox(height: 16),
              AgendasCard(config: config, controller: controller),
              const SizedBox(height: 16),
              BatteryCard(config: config, controller: controller),
              const SizedBox(height: 16),
              DedicatedProgramCard(config: config, controller: controller),
              const SizedBox(height: 16),
              if (!ref.watch(demoModeProvider)) ...[
                const RenaultKeysCard(),
                const SizedBox(height: 16),
              ],
              const AboutCard(),
              if (devToolsEnabled) ...[
                const SizedBox(height: 16),
                WriteTestCard(config: config),
              ],
            ],
          );
        },
      ),
    );
  }
}
