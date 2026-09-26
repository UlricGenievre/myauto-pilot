import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/charge_plan/charge_planner.dart';
import '../../core/debug/dev_log.dart';
import '../../core/models/charge_plan_config.dart';
import '../../core/models/vehicle_schedule.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/dashboard_card.dart';
import '../schedule/schedule_providers.dart';
import '../vehicle/vehicle_providers.dart';
import '../vehicle_status/vehicle_status_providers.dart';
import 'charge_plan_pickers.dart';

/// Outil de developpement : ecritures manuelles de `ev/settings` pour
/// verifier sur le vrai vehicule ce que Kamereon accepte (plage, heure du
/// programme, plage 24 h, plage calculee). Chaque envoi est confirme, puis
/// les reglages sont relus et compares a ce qui etait attendu.
class WriteTestCard extends ConsumerStatefulWidget {
  const WriteTestCard({super.key, required this.config});

  final ChargePlanConfig config;

  @override
  ConsumerState<WriteTestCard> createState() => _WriteTestCardState();
}

class _WriteTestCardState extends ConsumerState<WriteTestCard> {
  bool _busy = false;
  String? _status;

  /// L'ecriture est asynchrone cote Renault : on relit jusqu'a voir changer
  /// `lastSettingsUpdateTimestamp`, dans cette limite.
  static const _pollInterval = Duration(seconds: 5);
  static const _pollTimeout = Duration(seconds: 90);
  final _results = <_WriteResult>[];

  int? get _programIndex => widget.config.dedicatedProgramIndex;

  @override
  Widget build(BuildContext context) {
    final hasProgram = _programIndex != null;
    return DashboardCard(
      title: 'Tests d\'écriture',
      icon: Icons.science_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Validation sur le véhicule avant l\'automatisation. Chaque envoi modifie réellement les réglages '
            'de la voiture, puis les relit pour vérifier qu\'ils ont été pris en compte.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          _TestButton(label: '0. Relire les réglages (sans envoi)', busy: _busy, onPressed: _reread),
          _TestButton(label: '1. Renvoyer les réglages tels quels', busy: _busy, onPressed: _resendAsIs),
          _TestButton(label: '2. Envoyer une plage...', busy: _busy, onPressed: _sendWindow),
          _TestButton(
            label: '3. Programme dédié : prête à...',
            busy: _busy || !hasProgram,
            onPressed: _sendDeparture,
          ),
          _TestButton(label: '4. Plage 24 h (00:00 → 00:00)', busy: _busy, onPressed: _sendFullDay),
          _TestButton(
            label: '5. Appliquer la plage calculée',
            busy: _busy || !hasProgram,
            onPressed: _sendComputed,
          ),
          if (!hasProgram)
            const Text('Choisissez d\'abord le programme dédié (tests 3 et 5).',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          if (_busy) ...[
            const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_status!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ),
          ],
          for (final result in _results.reversed) _ResultTile(result: result),
        ],
      ),
    );
  }

  // --- Scenarios -------------------------------------------------------------

  Future<void> _reread() async {
    final repository = ref.read(vehicleRepositoryProvider);
    final vehicle = ref.read(selectedVehicleProvider);
    if (repository == null || vehicle == null) return;
    setState(() => _busy = true);
    try {
      final schedule = await repository.fetchVehicleSchedule(vehicle.vin);
      DevLog.send('read', {'schedule': schedule.raw});
      if (!mounted) return;
      setState(() => _results.add(_WriteResult(
            description: 'Relecture',
            ok: true,
            detail: '${_Expectation.fromSchedule(schedule, _programIndex).describe()} · modifié le ${schedule.lastUpdate}',
          )));
    } catch (error) {
      if (!mounted) return;
      setState(() => _results.add(_WriteResult(description: 'Relecture', ok: false, detail: '$error')));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        ref.invalidate(vehicleScheduleProvider);
      }
    }
  }

  Future<void> _resendAsIs() => _write(
        description: 'Renvoi sans modification',
        change: (schedule) => schedule.toUpdatedJson(),
        expected: (schedule) => _Expectation.fromSchedule(schedule, _programIndex),
      );

  Future<void> _sendWindow() async {
    final window = await pickChargeWindow(context);
    if (window == null || !mounted) return;
    await _write(
      description: 'Plage ${window.start.format()} → ${window.end.format()}',
      change: (schedule) => schedule.toUpdatedJson(
        chargeTimeStart: window.start.format(),
        chargeDurationMinutes: window.durationMinutes,
      ),
      expected: (_) => _Expectation(chargeTimeStart: window.start.format(), durationMinutes: window.durationMinutes),
    );
  }

  Future<void> _sendDeparture() async {
    final index = _programIndex!;
    final time = await pickClockTime(context, initial: ClockTime.hm(7, 30), title: 'Prête à');
    if (time == null || !mounted) return;
    await _write(
      description: 'Programme ${index + 1} actif, prête à ${time.format()}',
      change: (schedule) => schedule.toUpdatedJson(
        programIndex: index,
        departureTime: time.format(),
        programActive: true,
      ),
      expected: (_) => _Expectation(programIndex: index, departureTime: time.format(), programActive: true),
    );
  }

  Future<void> _sendFullDay() => _write(
        description: 'Plage 00:00 → 00:00 (1440 min)',
        change: (schedule) => schedule.toUpdatedJson(chargeTimeStart: '00:00', chargeDurationMinutes: 1440),
        expected: (_) => const _Expectation(chargeTimeStart: '00:00', durationMinutes: 1440),
      );

  Future<void> _sendComputed() async {
    final index = _programIndex!;
    final soc = ref.read(batteryStatusProvider).valueOrNull?.batteryLevel;
    final planner = ChargePlanner(widget.config);
    final now = DateTime.now();
    final command = planner.commandInForce(now, socPercent: soc) ?? planner.upcomingCommand(now, socPercent: soc);
    if (command == null) {
      _showMessage('Aucune plage calculée : définissez d\'abord vos plages de charge.');
      return;
    }
    final start = command.chargeTimeStart.format();
    final departure = ClockTime.hm(command.readyAt.hour, command.readyAt.minute).format();
    await _write(
      description: 'Plage calculée $start +${command.durationMinutes} min, programme ${index + 1} prête à $departure',
      change: (schedule) => schedule.toUpdatedJson(
        chargeTimeStart: start,
        chargeDurationMinutes: command.durationMinutes,
        programIndex: index,
        departureTime: departure,
        programActive: true,
        programDays: {command.readyDay},
      ),
      expected: (_) => _Expectation(
        chargeTimeStart: start,
        durationMinutes: command.durationMinutes,
        programIndex: index,
        departureTime: departure,
        programActive: true,
      ),
    );
  }

  // --- Mecanique commune -------------------------------------------------------

  Future<void> _write({
    required String description,
    required Map<String, dynamic> Function(VehicleSchedule current) change,
    required _Expectation Function(VehicleSchedule current) expected,
  }) async {
    final repository = ref.read(vehicleRepositoryProvider);
    final vehicle = ref.read(selectedVehicleProvider);
    if (repository == null || vehicle == null) {
      _showMessage('Aucun véhicule sélectionné.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Envoyer au véhicule ?'),
        content: Text('$description.\n\nLes réglages actuels sont relus juste avant l\'envoi, '
            'seuls les champs indiqués sont modifiés.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Envoyer')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      // Toujours repartir d'une lecture fraiche (pattern GET -> mutation -> POST).
      final current = await repository.fetchVehicleSchedule(vehicle.vin);
      final sent = change(current);
      final stopwatch = Stopwatch()..start();
      var reread = await repository.updateVehicleSchedule(vehicle.vin, sent);
      var polls = 1;
      while (reread.lastUpdate == current.lastUpdate && stopwatch.elapsed < _pollTimeout) {
        if (mounted) setState(() => _status = 'Attente de la prise en compte... ${stopwatch.elapsed.inSeconds} s');
        await Future<void>.delayed(_pollInterval);
        reread = await repository.fetchVehicleSchedule(vehicle.vin);
        polls++;
      }
      final applied = reread.lastUpdate != current.lastUpdate;
      final expectation = expected(current);
      final ok = applied && expectation.matches(reread);
      DevLog.send('write_test', {
        'description': description,
        'ok': ok,
        'applied': applied,
        'delaySeconds': stopwatch.elapsed.inSeconds,
        'polls': polls,
        'before': current.raw,
        'sent': sent,
        'reread': reread.raw,
      });
      if (!mounted) return;
      setState(() => _results.add(_WriteResult(
            description: description,
            ok: ok,
            detail: '${applied ? 'Appliqué en ~${stopwatch.elapsed.inSeconds} s' : 'Pas de changement côté serveur après ${_pollTimeout.inSeconds} s'}'
                ' · relu : ${_Expectation.fromSchedule(reread, _programIndex).describe()}',
          )));
    } catch (error) {
      DevLog.send('write_test', {'description': description, 'ok': false, 'error': '$error'});
      if (!mounted) return;
      setState(() => _results.add(_WriteResult(description: description, ok: false, detail: '$error')));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
        ref.invalidate(vehicleScheduleProvider);
      }
    }
  }

  void _showMessage(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Valeurs attendues apres ecriture (champs null = non verifies).
class _Expectation {
  const _Expectation({
    this.chargeTimeStart,
    this.durationMinutes,
    this.programIndex,
    this.departureTime,
    this.programActive,
  });

  factory _Expectation.fromSchedule(VehicleSchedule schedule, int? programIndex) {
    final program = programIndex != null && programIndex < schedule.programs.length
        ? schedule.programs[programIndex]
        : null;
    return _Expectation(
      chargeTimeStart: schedule.chargeWindowStart,
      durationMinutes: schedule.chargeWindowDurationMinutes,
      programIndex: program != null ? programIndex : null,
      departureTime: ClockTime.tryParse(program?.departureTime)?.format(),
      programActive: program?.isActive,
    );
  }

  final String? chargeTimeStart;
  final int? durationMinutes;
  final int? programIndex;
  final String? departureTime;
  final bool? programActive;

  bool matches(VehicleSchedule schedule) {
    final actual = _Expectation.fromSchedule(schedule, programIndex);
    return (chargeTimeStart == null || chargeTimeStart == actual.chargeTimeStart) &&
        (durationMinutes == null || durationMinutes == actual.durationMinutes) &&
        (departureTime == null || departureTime == actual.departureTime) &&
        (programActive == null || programActive == actual.programActive);
  }

  String describe() {
    final parts = ['plage ${chargeTimeStart ?? '?'} +${durationMinutes ?? '?'} min'];
    if (programIndex != null) {
      parts.add('programme ${programIndex! + 1} prête à ${departureTime ?? '?'} '
          '${programActive == true ? '(actif)' : '(inactif)'}');
    }
    return parts.join(' · ');
  }
}

class _WriteResult {
  const _WriteResult({required this.description, required this.ok, required this.detail});

  final String description;
  final bool ok;
  final String detail;
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result});

  final _WriteResult result;

  @override
  Widget build(BuildContext context) {
    final color = result.ok ? AppColors.success : AppColors.error;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(result.ok ? Icons.check_circle_outline : Icons.error_outline, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.description, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                SelectableText(result.detail, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TestButton extends StatelessWidget {
  const _TestButton({required this.label, required this.busy, required this.onPressed});

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: busy ? null : onPressed,
        style: TextButton.styleFrom(foregroundColor: AppColors.accent),
        child: Text(label),
      ),
    );
  }
}
