import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/charge_plan_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../vehicle_status/vehicle_status_providers.dart';
import '../charge_plan_pickers.dart';
import '../charge_plan_providers.dart';

class BatteryCard extends ConsumerStatefulWidget {
  const BatteryCard({super.key, required this.config, required this.controller});

  final ChargePlanConfig config;
  final ChargePlanConfigController controller;

  @override
  ConsumerState<BatteryCard> createState() => _BatteryCardState();
}

class _BatteryCardState extends ConsumerState<BatteryCard> {
  late final _capacity = TextEditingController(text: _format(widget.config.batteryCapacityKwh));
  late final _power = TextEditingController(text: _format(widget.config.chargePowerKw));

  @override
  void dispose() {
    _capacity.dispose();
    _power.dispose();
    super.dispose();
  }

  static String _format(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();
  }

  static double? _parse(String text) => double.tryParse(text.trim().replaceAll(',', '.'));

  void _save() {
    final capacity = _parse(_capacity.text);
    final power = _parse(_power.text);
    widget.controller.edit((c) => c.copyWith(batteryCapacityKwh: capacity, chargePowerKw: power));
  }

  Future<void> _prefill() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final battery = await ref.refresh(batteryStatusProvider.future);
      final messages = <String>[];
      if (battery?.batteryCapacityKwh case final capacity? when capacity > 0) {
        _capacity.text = _format(capacity);
        messages.add('capacité $capacity kWh');
      }
      if (battery?.chargingPowerKw case final kw?) {
        // Unite non confirmee (kW le plus souvent, W sur certaines
        // passerelles) : cf. BatteryStatus.chargingPowerKw.
        _power.text = _format(double.parse(kw.toStringAsFixed(1)));
        messages.add('puissance ${battery!.chargingInstantaneousPower} brute → ${_power.text} kW');
      }
      _save();
      messenger.showSnackBar(SnackBar(
        content: Text(messages.isEmpty
            ? 'Le véhicule ne remonte ni capacité ni puissance (la puissance n\'est connue qu\'en cours de charge).'
            : 'Prérempli : ${messages.join(', ')}. Vérifiez ces valeurs.'),
      ));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Lecture impossible : $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatters = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return DashboardCard(
      title: 'Batterie et charge',
      icon: Icons.battery_charging_full_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Sert à vérifier si une plage suffit pour atteindre l\'objectif.', style: hintStyle),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _capacity,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: formatters,
                  decoration: const InputDecoration(labelText: 'Capacité utile', suffixText: 'kWh'),
                  onChanged: (_) => _save(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _power,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: formatters,
                  decoration: const InputDecoration(labelText: 'Puissance', suffixText: 'kW'),
                  onChanged: (_) => _save(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.download_outlined, color: AppColors.accent),
            label: const Text('Préremplir depuis les données véhicule'),
            onPressed: _prefill,
          ),
        ],
      ),
    );
  }
}
