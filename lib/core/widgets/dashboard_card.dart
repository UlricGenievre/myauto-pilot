import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Conteneur standard des ecrans dashboard : reprend le CardTheme (fond
/// anthracite, coins arrondis, liseret) avec un padding et un titre
/// optionnels pour eviter de repeter cette structure sur chaque ecran.
///
/// [help] : explication de la carte, masquee par defaut et affichee sous le
/// titre par le bouton "?" (necessite [title]). Les informations d'etat
/// (valeurs, alertes, erreurs) restent dans [child].
class DashboardCard extends StatefulWidget {
  const DashboardCard({
    super.key,
    this.title,
    this.icon,
    required this.child,
    this.padding,
    this.trailing,
    this.help,
  });

  final String? title;
  final IconData? icon;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// Action a droite du titre (ex. bouton de personnalisation).
  final Widget? trailing;

  /// Paragraphes separes par une ligne vide.
  final String? help;

  @override
  State<DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<DashboardCard> {
  var _showHelp = false;

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final help = widget.help;
    final hasActions = widget.trailing != null || help != null;
    return Card(
      child: Padding(
        padding: widget.padding ?? const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 18, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  if (widget.trailing != null) widget.trailing!,
                  if (help != null)
                    IconButton(
                      icon: Icon(
                        _showHelp ? Icons.help_rounded : Icons.help_outline_rounded,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                      tooltip: _showHelp ? 'Masquer l\'aide' : 'Aide',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _showHelp = !_showHelp),
                    ),
                ],
              ),
              SizedBox(height: hasActions ? 8 : 16),
              if (help != null && _showHelp) ...[
                for (final paragraph in help.split('\n\n')) ...[
                  Text(
                    paragraph,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 6),
                ],
                const SizedBox(height: 8),
              ],
            ],
            widget.child,
          ],
        ),
      ),
    );
  }
}
