import 'package:flutter_test/flutter_test.dart';
import 'package:myauto_pilot/core/utils/date_formatting.dart';

void main() {
  group('parseTimeOfDay', () {
    test('accepte "HH:MM" (chargeTimeStart)', () {
      final t = parseTimeOfDay('23:30')!;
      expect((t.hour, t.minute), (23, 30));
    });

    test('accepte "HH:MM:SS" (programDepartureTime), secondes ignorees', () {
      final t = parseTimeOfDay('07:45:00')!;
      expect((t.hour, t.minute, t.second), (7, 45, 0));
    });

    test('retourne null sur un format inattendu', () {
      expect(parseTimeOfDay(null), isNull);
      expect(parseTimeOfDay('T07:45Z'), isNull);
      expect(parseTimeOfDay('7:45'), isNull);
    });
  });
}
