import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Tuile de controle a distance : grande icone, label, etat eventuel, et un
/// segment demarrer/arreter en bas (un seul bouton [startLabel] sans
/// [onStop]). `isPending` remplace le segment par un spinner le temps que
/// l'action reponde.
class ActionControl extends StatelessWidget {
  const ActionControl({
    super.key,
    required this.icon,
    required this.label,
    required this.isPending,
    required this.onStart,
    this.onStop,
    this.startLabel = 'Démarrer',
    this.status,
  });

  final IconData icon;
  final String label;
  final bool isPending;
  final VoidCallback onStart;
  final VoidCallback? onStop;
  final String startLabel;

  /// Etat actuel (ex. "En marche · 20 °C"), sous le label.
  final String? status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28, color: AppColors.accent),
          const SizedBox(height: 16),
          Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (status != null) ...[
            const SizedBox(height: 4),
            Text(status!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
          const Spacer(),
          const SizedBox(height: 16),
          if (isPending)
            const SizedBox(
              height: 36,
              child: Center(
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                ),
              ),
            )
          else
            Row(
              children: [
                if (onStop case final stop?) ...[
                  Expanded(child: _SegmentButton(label: 'Arrêter', onTap: stop, filled: false)),
                  const SizedBox(width: 8),
                ],
                Expanded(child: _SegmentButton(label: startLabel, onTap: onStart, filled: true)),
              ],
            ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({required this.label, required this.onTap, required this.filled});

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? AppColors.accent : AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: filled ? AppColors.onAccent : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
