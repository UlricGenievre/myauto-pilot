import 'package:flutter/material.dart';

import '../models/battery_health.dart';
import '../theme/app_theme.dart';

/// Couleur de l'appreciation de la sante (icone et libelle).
Color batteryHealthColor(BatteryHealthLevel level) => switch (level) {
  BatteryHealthLevel.good => AppColors.success,
  BatteryHealthLevel.worn => AppColors.accent,
  BatteryHealthLevel.check => AppColors.error,
};

String batteryHealthLabel(BatteryHealthLevel level) => switch (level) {
  BatteryHealthLevel.good => 'Bon état',
  BatteryHealthLevel.worn => 'Usure normale',
  BatteryHealthLevel.check => 'À faire contrôler',
};

/// Sante de la batterie, empilee et centree : "Sante" (+ bouton d'aide),
/// pourcentage, coeur colore selon l'appreciation, appreciation.
class BatteryHealthIndicator extends StatelessWidget {
  const BatteryHealthIndicator({super.key, required this.health, this.helpShown = false, this.onHelp});

  final BatteryHealth health;
  final bool helpShown;

  /// Bouton d'aide a cote de "Sante" ; sans (null), pas de bouton
  /// (illustration du tutoriel).
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context) {
    final color = batteryHealthColor(health.level);
    // Reduit l'ensemble plutot que de deborder sur un ecran tres etroit.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Meme hauteur avec ou sans bouton d'aide.
          SizedBox(
            height: 28,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Compense le bouton d'aide pour garder "Sante" centre.
                if (onHelp != null) const SizedBox(width: 24),
                const Text('Santé', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                if (onHelp != null)
                  IconButton(
                    icon: Icon(
                      helpShown ? Icons.help_rounded : Icons.help_outline_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    tooltip: helpShown ? 'Masquer l\'aide' : 'Qu\'est-ce que la santé de la batterie ?',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 28),
                    onPressed: onHelp,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text('${health.percent} %', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1)),
          const SizedBox(height: 8),
          Icon(Icons.favorite_rounded, color: color, size: 36, semanticLabel: batteryHealthLabel(health.level)),
          const SizedBox(height: 6),
          Text(
            batteryHealthLabel(health.level),
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
