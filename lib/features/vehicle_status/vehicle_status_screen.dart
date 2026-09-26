import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/battery_status.dart';
import '../../core/models/cockpit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/battery_gauge.dart';
import '../../core/widgets/dashboard_card.dart';
import '../../core/widgets/stat_tile.dart';
import '../charge_plan/cards/pilot_summary_card.dart';
import 'vehicle_status_providers.dart';

class VehicleStatusScreen extends ConsumerWidget {
  const VehicleStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battery = ref.watch(batteryStatusProvider);
    final cockpit = ref.watch(cockpitProvider);

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surfaceHigh,
      onRefresh: () async {
        ref.invalidate(batteryStatusProvider);
        ref.invalidate(cockpitProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          _BatterySection(asyncBattery: battery),
          const SizedBox(height: 16),
          const PilotSummaryCard(),
          const SizedBox(height: 16),
          _CockpitSection(asyncCockpit: cockpit),
        ],
      ),
    );
  }
}

class _BatterySection extends StatelessWidget {
  const _BatterySection({required this.asyncBattery});

  final AsyncValue<BatteryStatus?> asyncBattery;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: asyncBattery.when(
        data: (battery) {
          if (battery == null) {
            return const Center(child: Text('Aucun véhicule sélectionné.'));
          }
          // Toute la largeur de la carte, pour centrer la jauge.
          return SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                BatteryGauge(
                  level: battery.batteryLevel,
                  rangeKm: battery.rangeKm,
                  isCharging: battery.isCharging ?? false,
                ),
                if (battery.isCharging == true) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      battery.chargingRemainingMinutes != null
                          ? 'En charge · ${battery.chargingRemainingMinutes} min restantes'
                          : 'En charge',
                      style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
        loading: () => const SizedBox(height: 220, child: Center(child: CircularProgressIndicator())),
        error: (error, _) => SizedBox(
          height: 120,
          child: Center(
            child: Text('Erreur : $error', style: const TextStyle(color: AppColors.error)),
          ),
        ),
      ),
    );
  }
}

class _CockpitSection extends StatelessWidget {
  const _CockpitSection({required this.asyncCockpit});

  final AsyncValue<Cockpit?> asyncCockpit;

  @override
  Widget build(BuildContext context) {
    return asyncCockpit.when(
      data: (cockpit) {
        if (cockpit == null) return const SizedBox.shrink();
        return DashboardCard(
          title: 'Véhicule',
          icon: Icons.directions_car_outlined,
          child: Row(
            children: [
              StatTile(
                icon: Icons.speed_outlined,
                value: cockpit.totalMileageKm != null ? '${cockpit.totalMileageKm!.toStringAsFixed(0)} km' : '-',
                label: 'Kilométrage',
              ),
              if (cockpit.fuelLevelPercent != null) ...[
                const SizedBox(width: 12),
                StatTile(
                  icon: Icons.local_gas_station_outlined,
                  value: '${cockpit.fuelLevelPercent}%',
                  label: cockpit.fuelAutonomyKm != null ? '${cockpit.fuelAutonomyKm} km' : 'Carburant',
                ),
              ],
            ],
          ),
        );
      },
      loading: () => const DashboardCard(
        title: 'Véhicule',
        child: SizedBox(height: 60, child: Center(child: CircularProgressIndicator())),
      ),
      error: (error, _) => DashboardCard(
        title: 'Véhicule',
        child: Text('Erreur : $error', style: const TextStyle(color: AppColors.error)),
      ),
    );
  }
}
