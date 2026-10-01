import 'package:flutter_test/flutter_test.dart';
import 'package:sova/core/format.dart';

void main() {
  group('naira', () {
    test('formats whole naira with separators', () {
      expect(naira(120000), '₦120,000');
      expect(naira(500), '₦500');
    });

    test('formats receipts with kobo', () => expect(nairaExact(10000), '₦10,000.00'));
  });

  group('normalisePhone', () {
    test('accepts common Nigerian formats', () {
      for (final input in ['08031234567', '0803 123 4567', '2348031234567', '+234 803 123 4567', '8031234567']) {
        expect(normalisePhone(input), '+2348031234567', reason: input);
      }
    });

    test('accepts 070, 080, 081, 090 and 091 prefixes', () {
      for (final p in ['070', '080', '081', '090', '091']) {
        expect(normalisePhone('${p}12345678'), '+234${p.substring(1)}12345678');
      }
    });

    test('rejects landlines and wrong lengths', () {
      for (final input in ['', '12345', '0803123456', '080312345678', '01234567890', '06031234567']) {
        expect(normalisePhone(input), isNull, reason: input);
      }
    });
  });

  test('displayPhone groups digits the local way', () {
    expect(displayPhone('+2348031234567'), '0803 123 4567');
  });

  test('relativeDay', () {
    final now = DateTime(2026, 10, 1, 15);
    expect(relativeDay(DateTime(2026, 10, 1), now: now), 'today');
    expect(relativeDay(DateTime(2026, 10, 2), now: now), 'tomorrow');
    expect(relativeDay(DateTime(2026, 10, 5), now: now), 'in 4 days');
    expect(relativeDay(DateTime(2026, 9, 29), now: now), '2 days ago');
  });
}
