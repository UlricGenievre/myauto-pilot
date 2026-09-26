import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/models/vehicle.dart';
import 'core/theme/app_theme.dart';
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

  static const _titles = ['État', 'Localisation', 'Pilotage', 'Actions'];

  /// Tient a jour le code modele du vehicule pilote (il determine ce que
  /// l'app peut y ecrire), y compris pour un parametrage enregistre sans.
  void _syncPilotedModelCode(List<Vehicle> vehicles) {
    final config = ref.read(chargePlanConfigProvider).valueOrNull;
    final vin = config?.vehicleVin;
    if (config == null || vin == null) return;
    for (final vehicle in vehicles) {
      if (vehicle.vin == vin && vehicle.modelCode != null && vehicle.modelCode != config.vehicleModelCode) {
        ref.read(chargePlanConfigProvider.notifier).edit((c) => c.copyWith(vehicleModelCode: vehicle.modelCode));
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
          ref.read(selectedVehicleProvider.notifier).state = vehicles.first;
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
              onSelected: (vehicle) => ref.read(selectedVehicleProvider.notifier).state = vehicle,
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
          if (demo) const _DemoBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _titles[tabIndex],
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          Expanded(child: _tabs[tabIndex]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabIndex,
        onDestinationSelected: (index) => ref.read(homeTabProvider.notifier).state = index,
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

/// Rappel permanent du mode demonstration.
class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent),
      ),
      child: const Row(
        children: [
          Icon(Icons.science_outlined, size: 18, color: AppColors.accent),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Démonstration : véhicule et données fictifs, rien n\'est envoyé.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Selecteur de vehicule stylise en pilule, dans l'AppBar. Reste un simple
/// libelle (pas de chevron/menu) quand il n'y a qu'un seul vehicule, pour ne
/// pas laisser croire qu'on peut en changer.
class _VehiclePicker extends StatelessWidget {
  const _VehiclePicker({required this.vehicles, required this.selected, required this.onSelected});

  final List<Vehicle> vehicles;
  final Vehicle? selected;
  final ValueChanged<Vehicle> onSelected;

  @override
  Widget build(BuildContext context) {
    final name = selected?.displayName ?? 'MyAuto Pilot';

    if (vehicles.length <= 1) {
      return Text(name, style: const TextStyle(fontWeight: FontWeight.w700));
    }

    return PopupMenuButton<String>(
      color: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (vin) => onSelected(vehicles.firstWhere((v) => v.vin == vin)),
      itemBuilder: (context) => vehicles
          .map<PopupMenuEntry<String>>(
            (v) => PopupMenuItem(value: v.vin, child: Text(v.displayName)),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
