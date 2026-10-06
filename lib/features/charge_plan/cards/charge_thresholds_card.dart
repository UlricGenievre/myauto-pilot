import 'package:flutter/material.dart';

import '../../../core/models/charge_plan_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../charge_plan_pickers.dart';
import '../charge_plan_providers.dart';

/// Charge maximale (plages raccourcies) et minimale (charge immediate
/// proposee), reglees dans l'app : la voiture n'applique pas ses propres
/// seuils.
class ChargeThresholdsCard extends StatelessWidget {
  const ChargeThresholdsCard({super.key, required this.config, required this.controller});

  final ChargePlanConfig config;
  final ChargePlanConfigController controller;

  static const _maxRange = (50, 95);
  static const _minRange = (10, 50);
  static const _defaultMax = 80;
  static const _defaultMin = 20;

  /// Ecart minimal entre les deux seuils.
  static const _gap = 5;

  @override
  Widget build(BuildContext context) {
    final max = config.maxChargePercent;
    final min = config.minChargePercent;
    final minCeiling = max == null ? _minRange.$2 : (max - _gap).clamp(_minRange.$1, _minRange.$2);

    return DashboardCard(
      title: 'Seuils de charge',
      icon: Icons.battery_5_bar_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Nécessitent la capacité et la puissance de charge (carte « Batterie et charge »).',
              style: hintStyle),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: max != null,
            activeTrackColor: AppColors.accent,
            onChanged: (on) => controller.edit((c) => on
                ? c.copyWith(
                    maxChargePercent: _defaultMax,
                    minChargePercent: min != null && min > _defaultMax - _gap ? _defaultMax - _gap : null,
                  )
                : c.copyWith(clearMaxCharge: true)),
            title: const Text('Charge maximale'),
            subtitle: const Text(
              'Les plages sont raccourcies pour s\'arrêter vers ce niveau, d\'après la batterie au moment de '
              'l\'envoi. Un objectif plus haut passe outre.',
              style: hintStyle,
            ),
          ),
          if (max != null)
            PercentSlider(
              value: max.clamp(_maxRange.$1, _maxRange.$2),
              min: _maxRange.$1,
              max: _maxRange.$2,
              onChanged: (v) => controller.edit((c) => c.copyWith(
                    maxChargePercent: v,
                    minChargePercent: min != null && min > v - _gap ? (v - _gap).clamp(_minRange.$1, _minRange.$2) : null,
                  )),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: min != null,
            activeTrackColor: AppColors.accent,
            onChanged: (on) => controller.edit((c) => on
                ? c.copyWith(minChargePercent: _defaultMin.clamp(_minRange.$1, minCeiling))
                : c.copyWith(clearMinCharge: true)),
            title: const Text('Charge minimale'),
            subtitle: const Text(
              'Batterie en dessous et voiture branchée : le pilotage automatique propose une charge immédiate '
              'jusqu\'à ce niveau, même en heures pleines. Rien n\'est lancé sans votre accord.',
              style: hintStyle,
            ),
          ),
          if (min != null)
            PercentSlider(
              value: min.clamp(_minRange.$1, minCeiling),
              min: _minRange.$1,
              max: minCeiling,
              onChanged: (v) => controller.edit((c) => c.copyWith(minChargePercent: v)),
            ),
        ],
      ),
    );
  }
}
