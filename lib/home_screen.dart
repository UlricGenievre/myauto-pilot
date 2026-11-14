import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/models/vehicle.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/status_pill.dart';
import 'features/auth/auth_controller.dart';
import 'features/charge_plan/charge_plan_providers.dart';
import 'features/charge_plan/charge_plan_settings_screen.dart';
import 'features/charge_plan/pilot_screen.dart';
import 'features/location/location_screen.dart';
import 'features/remote_actions/remote_actions_screen.dart';
import 'features/vehicle/vehicle_providers.dart';
import 'features/vehicle_status/vehicle_status_screen.dart';
import 'home_tab.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Bandeau de demonstration masque par l'utilisateur (jusqu'a la sortie).
  bool _demoBannerHidden = false;

  @override
  void initState() {
    super.initState();
    // A l'ouverture : rattrape un envoi manque (reveil perdu, telephone
    // eteint) et reprogramme les reveils du pilotage de charge (jamais en
    // demonstration : le pilote travaille sur le parametrage reel).
    if (!ref.read(demoModeProvider)) refreshPilot(ref.invalidate);
  }

  static const _tabs = [
    VehicleStatusScreen(),
    LocationScreen(),
    PilotScreen(),
    RemoteActionsScreen(),
  ];

  /// Tient a jour le code modele du vehicule pilote (il determine ce que
  /// l'app peut y ecrire) et son compte (utilise par les reveils), y compris
  /// pour un parametrage enregistre sans.
  void _syncPilotedModelCode(List<Vehicle> vehicles) {
    final config = ref.read(chargePlanConfigProvider).value;
    final vin = config?.vehicleVin;
    if (config == null || vin == null) return;
    for (final vehicle in vehicles) {
      if (vehicle.vin != vin) continue;
      final modelChanged = vehicle.modelCode != null && vehicle.modelCode != config.vehicleModelCode;
      final accountChanged = vehicle.accountId != null && vehicle.accountId != config.vehicleAccountId;
      if (modelChanged || accountChanged) {
        ref.read(chargePlanConfigProvider.notifier).edit((c) => c.copyWith(
            vehicleModelCode: vehicle.modelCode ?? c.vehicleModelCode, vehicleAccountId: vehicle.accountId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehiclesAsync = ref.watch(vehiclesProvider);
    final tabIndex = ref.watch(homeTabProvider);
    final demo = ref.watch(demoModeProvider);

    ref.listen(vehiclesProvider, (previous, next) {
      next.whenData((vehicles) {
        final selected = ref.read(selectedVehicleProvider);
        if (selected == null && vehicles.isNotEmpty) {
          // Le vehicule pilote d'abord, s'il est dans la liste.
          final vin = ref.read(chargePlanConfigProvider).value?.vehicleVin;
          final piloted = vehicles.where((v) => v.vin == vin);
          ref.read(selectedVehicleProvider.notifier).select(piloted.isEmpty ? vehicles.first : piloted.first);
        }
        _syncPilotedModelCode(vehicles);
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: vehiclesAsync.when(
          data: (vehicles) {
            final selected = ref.watch(selectedVehicleProvider);
            return _VehiclePicker(
              vehicles: vehicles,
              selected: selected,
              onSelected: (vehicle) => ref.read(selectedVehicleProvider.notifier).select(vehicle),
            );
          },
          loading: () => const Text('MyAuto Pilot'),
          error: (_, _) => const Text('MyAuto Pilot'),
        ),
        actions: [
          IconButton(
            tooltip: 'Réglages',
            icon: const Icon(Icons.settings_outlined, color: AppColors.textSecondary),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ChargePlanSettingsScreen()),
            ),
          ),
          IconButton(
            tooltip: demo ? 'Quitter la démonstration' : 'Se déconnecter',
            icon: const Icon(Icons.logout, color: AppColors.textSecondary),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (demo && !_demoBannerHidden) _DemoBanner(onClose: () => setState(() => _demoBannerHidden = true)),
          // Pas de titre d'ecran : la barre d'onglets indique deja l'onglet
          // actif (libelle + surbrillance).
          const SizedBox(height: 12),
          Expanded(child: _tabs[tabIndex]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabIndex,
        onDestinationSelected: (index) => ref.read(homeTabProvider.notifier).select(index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.speed_outlined), selectedIcon: Icon(Icons.speed), label: 'État'),
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Localisation'),
          NavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            selectedIcon: Icon(Icons.bolt),
            label: 'Pilotage',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_remote_outlined),
            selectedIcon: Icon(Icons.settings_remote),
            label: 'Actions',
          ),
        ],
      ),
    );
  }
}

/// Rappel du mode demonstration, masquable (croix) pour juger du rendu.
class _DemoBanner extends StatelessWidget {
  const _DemoBanner({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent),
      ),
      child: Row(
        children: [
          const Icon(Icons.science_outlined, size: 18, color: AppColors.accent),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Démonstration : véhicules et données fictifs, rien n\'est envoyé.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: 'Masquer',
            icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// Titre de l'en-tete : nom du vehicule affiche. Avec plusieurs vehicules,
/// un chevron et, au toucher, la liste des vehicules ([_VehicleSheet]) ;
/// sinon un simple titre, pour ne pas laisser croire qu'on peut en changer.
class _VehiclePicker extends StatelessWidget {
  const _VehiclePicker({required this.vehicles, required this.selected, required this.onSelected});

  final List<Vehicle> vehicles;
  final Vehicle? selected;
  final ValueChanged<Vehicle> onSelected;

  static const _style = TextStyle(fontSize: 20, fontWeight: FontWeight.w800);

  @override
  Widget build(BuildContext context) {
    final name = selected?.displayName ?? 'MyAuto Pilot';
    if (vehicles.length <= 1) return Text(name, style: _style);

    return Semantics(
      button: true,
      label: 'Changer de véhicule',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          final chosen = await showModalBottomSheet<Vehicle>(
            context: context,
            backgroundColor: AppColors.surface,
            builder: (_) => _VehicleSheet(vehicles: vehicles, selected: selected),
          );
          if (chosen != null) onSelected(chosen);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(name, style: _style, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 2),
              const Icon(Icons.expand_more_rounded, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Liste des vehicules du compte : celui affiche coche, celui que le
/// pilotage de charge pilote signale.
class _VehicleSheet extends ConsumerWidget {
  const _VehicleSheet({required this.vehicles, required this.selected});

  final List<Vehicle> vehicles;
  final Vehicle? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pilotedVin = ref.watch(chargePlanConfigProvider).value?.vehicleVin;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('Véhicules', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            for (final vehicle in vehicles)
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Icon(
                  Icons.directions_car_outlined,
                  color: vehicle.vin == selected?.vin ? AppColors.accent : AppColors.textSecondary,
                ),
                title: Text(vehicle.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  [
                    if (vehicle.nickname?.isNotEmpty == true) '${vehicle.brand} ${vehicle.model}',
                    'VIN …${vehicle.vin.substring(vehicle.vin.length > 6 ? vehicle.vin.length - 6 : 0)}',
                  ].join(' · '),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (vehicle.vin == pilotedVin) const StatusPill(isActive: true, activeLabel: 'Piloté'),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 24,
                      child: vehicle.vin == selected?.vin
                          ? const Icon(Icons.check_rounded, color: AppColors.accent)
                          : null,
                    ),
                  ],
                ),
                onTap: () => Navigator.pop(context, vehicle),
              ),
          ],
        ),
      ),
    );
  }
}
