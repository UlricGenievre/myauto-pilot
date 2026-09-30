import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/battery_status.dart';
import '../../core/models/cockpit.dart';
import '../../core/models/hvac_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_formatting.dart';
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
        ref.invalidate(hvacStatusProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          _BatterySection(asyncBattery: battery),
          const SizedBox(height: 16),
          const PilotSummaryCard(),
          const SizedBox(height: 16),
          _CockpitSection(
            asyncCockpit: cockpit,
            battery: battery.value,
            hvac: ref.watch(hvacStatusProvider).value,
          ),
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
                if (_ChargeLine.of(battery) case final line?) ...[
                  const SizedBox(height: 20),
                  line,
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

/// Pastille sous la jauge : branchement et etat de charge detaille.
class _ChargeLine extends StatelessWidget {
  const _ChargeLine(this.text, this.color, this.icon);

  final String text;
  final Color color;
  final IconData icon;

  static _ChargeLine? of(BatteryStatus battery) {
    final plugged = switch (battery.plugState) {
      PlugState.plugged => 'Branchée',
      PlugState.unplugged => 'Débranchée',
      PlugState.error => 'Erreur de prise',
      null => null,
    };
    String join(String? a, String b) => a == null ? b : '$a · $b';
    final power = battery.chargingPowerKw;
    final remaining = battery.chargingRemainingMinutes;
    return switch (battery.chargeState) {
      ChargeState.charging => _ChargeLine(
          [
            'En charge',
            if (power != null) '${power.toStringAsFixed(1).replaceAll('.', ',')} kW',
            if (remaining != null && remaining > 0) '${_duration(remaining)} restantes',
          ].join(' · '),
          AppColors.success,
          Icons.bolt_rounded,
        ),
      ChargeState.waitingPlanned =>
        _ChargeLine(join(plugged, 'en attente de la plage de charge'), AppColors.accent, Icons.schedule_rounded),
      ChargeState.ended => _ChargeLine(join(plugged, 'charge terminée'), AppColors.success, Icons.check_rounded),
      ChargeState.waitingCurrent =>
        _ChargeLine(join(plugged, 'en attente de courant'), AppColors.accent, Icons.hourglass_empty_rounded),
      ChargeState.flapOpen => const _ChargeLine('Trappe de charge ouverte', AppColors.accent, Icons.ev_station_outlined),
      ChargeState.error => _ChargeLine(join(plugged, 'erreur de charge'), AppColors.error, Icons.error_outline),
      ChargeState.notCharging || ChargeState.unavailable || null => plugged == null
          ? null
          : _ChargeLine(
              battery.plugState == PlugState.plugged ? join(plugged, 'pas en charge') : plugged,
              battery.plugState == PlugState.error ? AppColors.error : AppColors.textSecondary,
              battery.plugState == PlugState.unplugged ? Icons.power_off_outlined : Icons.power_outlined,
            ),
    };
  }

  static String _duration(int minutes) =>
      minutes < 60 ? '$minutes min' : '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _CockpitSection extends StatelessWidget {
  const _CockpitSection({required this.asyncCockpit, required this.battery, required this.hvac});

  final AsyncValue<Cockpit?> asyncCockpit;
  final BatteryStatus? battery;
  final HvacStatus? hvac;

  static String _number(double value, {int decimals = 0}) =>
      value.toStringAsFixed(decimals).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    return asyncCockpit.when(
      data: (cockpit) {
        if (cockpit == null) return const SizedBox.shrink();
        final tiles = <Widget>[
          StatTile(
            icon: Icons.speed_outlined,
            value: cockpit.totalMileageKm != null ? '${_number(cockpit.totalMileageKm!)} km' : '-',
            label: 'Kilométrage',
          ),
          if (cockpit.hasFuel)
            // Autonomie en valeur principale, sinon la quantite seule.
            StatTile(
              icon: Icons.local_gas_station_outlined,
              value: (cockpit.fuelAutonomyKm ?? 0) > 0
                  ? '${cockpit.fuelAutonomyKm} km'
                  : '${_number(cockpit.fuelQuantityLiters!)} L',
              label: (cockpit.fuelAutonomyKm ?? 0) > 0 && (cockpit.fuelQuantityLiters ?? 0) > 0
                  ? 'Carburant · ${_number(cockpit.fuelQuantityLiters!)} L'
                  : 'Carburant',
            ),
          if (hvac?.internalTemperature case final inside?)
            StatTile(
              icon: Icons.thermostat_outlined,
              value: '${_number(inside, decimals: inside % 1 == 0 ? 0 : 1)} °C',
              label: hvac!.isStale() ? 'Habitacle, ${formatRelativeDateTime(hvac!.lastUpdated!)}' : 'Habitacle',
            )
          else if (battery?.batteryTemperature case final temperature?)
            StatTile(icon: Icons.thermostat_outlined, value: '$temperature °C', label: 'Batterie'),
        ];
        return DashboardCard(
          title: 'Véhicule',
          icon: Icons.directions_car_outlined,
          child: Row(
            children: [
              for (final (i, tile) in tiles.indexed) ...[
                if (i > 0) const SizedBox(width: 12),
                tile,
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
