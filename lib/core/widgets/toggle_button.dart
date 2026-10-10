import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Bouton a deux etats au libelle court, qui porte l'etat d'une
/// fonctionnalite : jaune avec une coche si active, gris avec un cercle
/// vide sinon (l'icone double la couleur). Un appui inverse l'etat.
///
/// [onChanged] null : bouton desactive (grise) ; [locked] : etat impose,
/// avec un cadenas.
class ToggleButton extends StatelessWidget {
  const ToggleButton({super.key, required this.label, required this.value, this.onChanged, this.locked = false});

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null && !locked;
    final foreground = value ? AppColors.onAccent : AppColors.textSecondary;
    final icon = locked
        ? Icons.lock_outline_rounded
        : value
            ? Icons.check_circle_rounded
            : Icons.radio_button_unchecked_rounded;
    return Opacity(
      opacity: enabled || locked ? 1 : 0.45,
      child: Material(
        color: value ? AppColors.accent : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? () => onChanged!(!value) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
