import 'package:flutter_test/flutter_test.dart';
import 'package:myauto_pilot/core/models/vehicle_schedule.dart';

/// Reponse reelle de `ev/settings` (plage 00:00 -> 00:00 active).
Map<String, dynamic> realResponse() => {
      'lastSettingsUpdateTimestamp': '2026-09-22T21:26:52.956178Z',
      'delegatedActivated': false,
      'chargeModeRq': 'SCHEDULED',
      'chargeTimeStart': '00:00',
      'chargeDuration': 1440,
      'preconditioningTemperature': 21,
      'preconditioningHeatedStrgWheel': false,
      'preconditioningHeatedRightSeat': false,
      'preconditioningHeatedLeftSeat': false,
      'programs': [
        for (final (active, time) in [(true, '09:00:00'), (false, '07:45:00'), (false, '07:10:00')])
          {
            'programActivationStatus': active,
            'programType': 'CHARGE',
            'programDepartureTime': time,
            for (final day in ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'])
              'programActivation$day': true,
          },
      ],
    };

void main() {
  test('parse la reponse reelle', () {
    final schedule = VehicleSchedule.fromJson(realResponse());
    expect(schedule.chargeWindowStart, '00:00');
    expect(schedule.chargeWindowDurationMinutes, 1440);
    expect(schedule.programs, hasLength(3));
    expect(schedule.programs.first.isActive, isTrue);
    expect(schedule.programs.first.activeDays, {1, 2, 3, 4, 5, 6, 7});
  });

  test('toUpdatedJson sans modification = objet identique', () {
    final schedule = VehicleSchedule.fromJson(realResponse());
    expect(schedule.toUpdatedJson(), realResponse());
  });

  test('toUpdatedJson modifie plage + programme, conserve le reste, sans muter raw', () {
    final schedule = VehicleSchedule.fromJson(realResponse());
    final updated = schedule.toUpdatedJson(
      chargeTimeStart: '01:00',
      chargeDurationMinutes: 360,
      programIndex: 1,
      departureTime: '07:30',
      programActive: true,
    );

    expect(updated['chargeTimeStart'], '01:00');
    expect(updated['chargeDuration'], 360);
    expect(updated['preconditioningTemperature'], 21);
    final program = (updated['programs'] as List)[1] as Map<String, dynamic>;
    expect(program['programDepartureTime'], '07:30:00');
    expect(program['programActivationStatus'], isTrue);
    expect(program['programActivationSunday'], isTrue);
    // Autres programmes et objet d'origine intacts.
    expect((updated['programs'] as List)[0], (realResponse()['programs'] as List)[0]);
    expect(schedule.raw, realResponse());
  });

  test('toUpdatedJson refuse un index de programme hors limites', () {
    final schedule = VehicleSchedule.fromJson(realResponse());
    expect(() => schedule.toUpdatedJson(programIndex: 3), throwsRangeError);
  });
}
