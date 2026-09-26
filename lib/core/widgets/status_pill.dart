import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Petite pastille "Actif/Inactif" (ou tout autre libelle a deux etats),
/// utilisee partout ou l'app affiche un etat marche/arret compact.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.isActive, this.activeLabel = 'Actif', this.inactiveLabel = 'Inactif'});

  final bool isActive;
  final String activeLabel;
  final String inactiveLabel;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.success : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isActive ? activeLabel : inactiveLabel,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}
