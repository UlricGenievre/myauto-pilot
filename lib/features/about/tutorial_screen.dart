import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../background/pilot_runtime.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/battery_gauge.dart';
import '../../core/widgets/dashboard_card.dart';
import '../../core/widgets/status_pill.dart';
import '../charge_plan/charge_plan_pickers.dart';
import '../charge_plan/charge_plan_providers.dart';

/// Tutoriel en quelques pages : affiche apres l'avertissement au premier
/// lancement (avant la connexion, donc sans donnees du vehicule : les
/// illustrations reprennent les widgets de l'app avec des valeurs fictives),
/// et a revoir depuis "A propos".
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key, required this.onFinished});

  /// Appele par "Passer" comme par le bouton de la derniere page.
  final VoidCallback onFinished;

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _TutorialPage(
      illustration: BatteryGauge(level: 78, rangeKm: 320, size: 150),
      title: 'Votre voiture en un coup d\'œil',
      details: _TabList(),
    ),
    _TutorialPage(
      illustration: _OffPeakIllustration(),
      title: 'Vos vraies heures creuses',
      body: 'Le système embarqué de la voiture ne retient qu\'une seule plage de charge, identique tous les jours. '
          'Saisissez vos heures creuses jour par jour : avant chaque plage, MyAuto Pilot envoie à la voiture celle '
          'qui convient.',
    ),
    _TutorialPage(
      illustration: _TargetIllustration(),
      title: 'Prête à l\'heure du départ',
      body: 'Fixez des objectifs « prête à 80 % de charge à 7 h 30 » : agendas récurrents (« Habituel », '
          '« Vacances »…) ou objectif exceptionnel.\nSi une plage ne suffit pas, elle est élargie juste ce qu\'il '
          'faut pour atteindre l\'objectif de charge. L\'habitacle peut en outre être préconditionné pour le départ.',
    ),
    _TutorialPage(
      illustration: _SafeModeIllustration(),
      title: 'Rien n\'est envoyé sans vous',
      body: 'Le mode sécurisé, activé par défaut, vous propose chaque envoi par notification et ne le fait '
          'qu\'après votre confirmation.\nVous êtes satisfait des envois et du fonctionnement ? Désactivez le mode '
          'sécurisé dans l\'onglet Pilotage : tout se fera en arrière-plan, sans confirmation à donner, et vous '
          'serez simplement informé du résultat des envois.',
    ),
    _TutorialPage(
      illustration: _PermissionsIllustration(),
      title: 'Deux autorisations',
      body: 'Elles permettent au pilotage de fonctionner même application fermée. Vous pourrez aussi les donner '
          'plus tard, en activant le pilotage automatique.',
    ),
    _TutorialPage(
      illustration: _StepsIllustration(),
      title: 'Pour commencer',
      body: 'Pas encore prêt ? Le mode démonstration, sur l\'écran de connexion, fait tout découvrir avec un '
          'véhicule fictif, sans rien envoyer.',
    ),
  ];

  bool get _isLast => _page == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Visibility(
                  visible: !_isLast,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: TextButton(onPressed: widget.onFinished, child: const Text('Passer')),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (page) => setState(() => _page = page),
                children: _pages,
              ),
            ),
            _PageDots(count: _pages.length, current: _page),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isLast
                      ? widget.onFinished
                      : () => _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
                  child: Text(_isLast ? 'Commencer' : 'Suivant'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorialPage extends StatelessWidget {
  const _TutorialPage({required this.illustration, required this.title, this.body, this.details});

  final Widget illustration;
  final String title;
  final String? body;

  /// Contenu sous le titre a la place (ou a la suite) du texte.
  final Widget? details;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: double.infinity, child: illustration),
          const SizedBox(height: 32),
          Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          if (body != null) ...[
            const SizedBox(height: 12),
            Text(body!, style: const TextStyle(color: AppColors.textSecondary, height: 1.4)),
          ],
          if (details != null) ...[
            const SizedBox(height: 16),
            details!,
          ],
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == current ? 20 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == current ? AppColors.accent : AppColors.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

// --- Illustrations (valeurs fictives) ----------------------------------------

/// Contenu des onglets, avec les icones de la barre de navigation (et la
/// roue dentee des reglages) en guise de puces.
class _TabList extends StatelessWidget {
  const _TabList();

  static const _tabs = [
    (Icons.speed_outlined, 'État', 'batterie, autonomie, branchement et charge'),
    (Icons.map_outlined, 'Localisation', 'position du véhicule sur la carte'),
    (Icons.bolt_outlined, 'Pilotage', 'charge en heures creuses et objectifs'),
    (Icons.settings_remote_outlined, 'Actions', 'climatisation, charge, klaxon et phares à distance'),
    (Icons.settings_outlined, 'Réglages', 'heures creuses, agendas et envoi à la voiture'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (icon, name, content) in _tabs)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 22, color: AppColors.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(text: ' : $content', style: const TextStyle(color: AppColors.textSecondary)),
                      ],
                    ),
                    style: const TextStyle(height: 1.35),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Contrat heures creuses courant : deux plages en semaine, week-end
/// entierement en heures creuses.
class _OffPeakIllustration extends StatelessWidget {
  const _OffPeakIllustration();

  static const _days = [
    ('Lundi à vendredi', '2 h – 7 h et 13 h – 16 h', [(2, 7), (13, 16)]),
    ('Samedi et dimanche', 'toute la journée', [(0, 24)]),
  ];

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      title: 'Heures creuses',
      icon: Icons.schedule_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (days, hours, ranges) in _days)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(days, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text(hours, style: hintStyle),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _DayBar(ranges: ranges),
                ],
              ),
            ),
          const Row(
            children: [
              Text('0 h', style: hintStyle),
              Spacer(),
              Text('12 h', style: hintStyle),
              Spacer(),
              Text('24 h', style: hintStyle),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({required this.ranges});

  /// Plages (heure de debut, heure de fin), triees et disjointes.
  final List<(int, int)> ranges;

  @override
  Widget build(BuildContext context) {
    final segments = <Widget>[];
    var hour = 0;
    for (final (start, end) in ranges) {
      if (start > hour) segments.add(Expanded(flex: start - hour, child: const SizedBox()));
      segments.add(Expanded(flex: end - start, child: Container(color: AppColors.accent)));
      hour = end;
    }
    if (hour < 24) segments.add(Expanded(flex: 24 - hour, child: const SizedBox()));
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(height: 14, color: AppColors.surfaceHigh, child: Row(children: segments)),
    );
  }
}

class _TargetIllustration extends StatelessWidget {
  const _TargetIllustration();

  @override
  Widget build(BuildContext context) {
    return const DashboardCard(
      title: 'Agenda « Habituel »',
      icon: Icons.flag_outlined,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('80 %', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, height: 1)),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusPill(isActive: true, activeLabel: 'Habitacle climatisé'),
                SizedBox(height: 6),
                Text('Lundi, prête à 7:30', style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Notification de confirmation telle que le mode securise l'affiche.
class _SafeModeIllustration extends StatelessWidget {
  const _SafeModeIllustration();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, size: 18, color: AppColors.accent),
              SizedBox(width: 6),
              Text('MyAuto Pilot', style: hintStyle),
            ],
          ),
          SizedBox(height: 8),
          Text('Plage à confirmer', style: TextStyle(fontWeight: FontWeight.w700)),
          SizedBox(height: 2),
          Text('Envoyer la plage 22:00 – 6:00 à la voiture ?', style: TextStyle(color: AppColors.textSecondary)),
          SizedBox(height: 12),
          Row(
            children: [
              Text('ENVOYER', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
              SizedBox(width: 24),
              Text('IGNORER', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Autorisations Android du pilotage, a donner depuis le tutoriel. Etat
/// reverifie au retour dans l'app (reglage Android ouvert entre-temps).
class _PermissionsIllustration extends ConsumerStatefulWidget {
  const _PermissionsIllustration();

  @override
  ConsumerState<_PermissionsIllustration> createState() => _PermissionsIllustrationState();
}

class _PermissionsIllustrationState extends ConsumerState<_PermissionsIllustration> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _recheck);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _recheck() {
    ref.invalidate(notificationsAllowedProvider);
    ref.invalidate(exactAlarmsAllowedProvider);
  }

  @override
  Widget build(BuildContext context) {
    if (!pilotSupported) {
      return const DashboardCard(
        child: Text('Autorisations à donner sur le téléphone Android.', style: hintStyle),
      );
    }
    return DashboardCard(
      child: Column(
        children: [
          _PermissionRow(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            description: 'Pour vous proposer chaque envoi et vous en donner le résultat.',
            allowed: ref.watch(notificationsAllowedProvider).value,
            onRequest: () async {
              await requestNotifications();
              _recheck();
            },
          ),
          const Divider(height: 24),
          _PermissionRow(
            icon: Icons.alarm_rounded,
            title: 'Alarmes et rappels',
            description: 'Pour envoyer chaque plage à l\'heure prévue, même téléphone en veille.',
            allowed: ref.watch(exactAlarmsAllowedProvider).value,
            onRequest: () async {
              await requestExactAlarms();
              _recheck();
            },
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.allowed,
    required this.onRequest,
  });

  final IconData icon;
  final String title;
  final String description;

  /// null tant que l'etat n'est pas connu.
  final bool? allowed;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(description, style: hintStyle),
            ],
          ),
        ),
        const SizedBox(width: 8),
        switch (allowed) {
          true => const StatusPill(isActive: true, activeLabel: 'Autorisé'),
          false => TextButton(onPressed: onRequest, child: const Text('Autoriser')),
          null => const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        },
      ],
    );
  }
}

class _StepsIllustration extends StatelessWidget {
  const _StepsIllustration();

  static const _steps = [
    'Choisissez votre pays, puis connectez-vous avec votre compte MyRenault.',
    'Renseignez vos heures creuses dans Réglages (roue dentée).',
    'Activez le pilotage automatique dans l\'onglet Pilotage.',
  ];

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        children: [
          for (final (index, step) in _steps.indexed)
            Padding(
              padding: EdgeInsets.only(bottom: index < _steps.length - 1 ? 16 : 0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onAccent,
                    child: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(step, style: const TextStyle(height: 1.35))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
