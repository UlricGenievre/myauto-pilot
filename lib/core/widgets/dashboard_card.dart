import 'package:flutter/material.dart';

/// Conteneur standard des ecrans dashboard : reprend le CardTheme (fond
/// anthracite, coins arrondis, liseret) avec un padding et un titre
/// optionnels pour eviter de repeter cette structure sur chaque ecran.
class DashboardCard extends StatelessWidget {
  const DashboardCard({super.key, this.title, this.icon, required this.child, this.padding, this.trailing});

  final String? title;
  final IconData? icon;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// Action a droite du titre (ex. bouton de personnalisation).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    title!.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: Color(0xFF9A9A9E),
                    ),
                  ),
                  if (trailing != null) ...[const Spacer(), trailing!],
                ],
              ),
              SizedBox(height: trailing != null ? 8 : 16),
            ],
            child,
          ],
        ),
      ),
    );
  }
}
