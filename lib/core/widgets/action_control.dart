import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Tuile de controle a distance : grande icone, label, et un segment
/// demarrer/arreter en bas. `isPending` remplace le segment par un spinner
/// le temps que l'action reponde.
class ActionControl extends StatelessWidget {
  const ActionControl({
    super.key,
    required this.icon,
    required this.label,
    required this.isPending,
    required this.onStart,
    required this.onStop,
  });

  final IconData icon;
  final String label;
  final bool isPending;
  final VoidCallback onStart;
  final VoidCallback onStop;

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
                Expanded(child: _SegmentButton(label: 'Arrêter', onTap: onStop, filled: false)),
                const SizedBox(width: 8),
                Expanded(child: _SegmentButton(label: 'Démarrer', onTap: onStart, filled: true)),
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
