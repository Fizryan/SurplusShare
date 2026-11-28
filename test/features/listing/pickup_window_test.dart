import 'package:flutter_test/flutter_test.dart';
import 'package:surplus_share/features/listing/domain/models/pickup_window.dart';

void main() {
  group('PickupWindow validation', () {
    final now = DateTime.utc(2026, 11, 27, 20);

    test('accepts arbitrary custom window including cross-midnight', () {
      final standard = PickupWindow(
        start: DateTime.utc(2026, 11, 27, 21),
        end: DateTime.utc(2026, 11, 27, 22),
      );
      final crossMidnight = PickupWindow(
        start: DateTime.utc(2026, 11, 27, 23),
        end: DateTime.utc(2026, 11, 28, 0, 30),
      );

      expect(standard.validate(now: now), isNull);
      expect(crossMidnight.validate(now: now), isNull);
      expect(standard.formatWindowRange(useLocalTime: false), '21:00 - 22:00');
      expect(
        crossMidnight.formatWindowRange(useLocalTime: false),
        '23:00 - 00:30 (+1 hari)',
      );
    });

    test('rejects invalid bounds, past end, < 15 min, and > 24 hours', () {
      final reversed = PickupWindow(
        start: DateTime.utc(2026, 11, 27, 22),
        end: DateTime.utc(2026, 11, 27, 21),
      );
      final inPast = PickupWindow(
        start: DateTime.utc(2026, 11, 27, 18),
        end: DateTime.utc(2026, 11, 27, 19),
      );
      final tooShort = PickupWindow(
        start: DateTime.utc(2026, 11, 27, 21),
        end: DateTime.utc(2026, 11, 27, 21, 10),
      );
      final tooLong = PickupWindow(
        start: DateTime.utc(2026, 11, 27, 21),
        end: DateTime.utc(2026, 11, 28, 22),
      );

      expect(reversed.validate(now: now), isNotNull);
      expect(inPast.validate(now: now), isNotNull);
      expect(tooShort.validate(now: now), isNotNull);
      expect(tooLong.validate(now: now), isNotNull);
    });
  });

  group('PickupWindow phase, urgency & countdown formatting', () {
    final window = PickupWindow(
      start: DateTime.utc(2026, 11, 27, 20),
      end: DateTime.utc(2026, 11, 27, 22),
    );

    test('resolves upcoming phase and countdown until start', () {
      final snap = window.snapshot(
        now: DateTime.utc(2026, 11, 27, 19, 30, 15),
        useLocalTime: false,
      );

      expect(snap.phase, PickupPhase.upcoming);
      expect(snap.urgency, PickupUrgency.normal);
      expect(snap.isExpired, isFalse);
      expect(snap.formattedCountdown, '29:45');
    });

    test(
      'resolves open phase with normal, closingSoon, and critical urgency',
      () {
        // 1h 30m left -> normal
        final normal = window.snapshot(
          now: DateTime.utc(2026, 11, 27, 20, 30),
          useLocalTime: false,
        );
        expect(normal.phase, PickupPhase.open);
        expect(normal.urgency, PickupUrgency.normal);
        expect(normal.formattedCountdown, '01:30:00');

        // 45m left -> closingSoon (<= 60m)
        final closingSoon = window.snapshot(
          now: DateTime.utc(2026, 11, 27, 21, 15),
          useLocalTime: false,
        );
        expect(closingSoon.phase, PickupPhase.open);
        expect(closingSoon.urgency, PickupUrgency.closingSoon);
        expect(closingSoon.formattedCountdown, '45:00');

        // 10m 5s left -> critical (<= 15m)
        final critical = window.snapshot(
          now: DateTime.utc(2026, 11, 27, 21, 49, 55),
          useLocalTime: false,
        );
        expect(critical.phase, PickupPhase.open);
        expect(critical.urgency, PickupUrgency.critical);
        expect(critical.formattedCountdown, '10:05');
        // 500ms left -> rounds up to 00:01 (never shows 00:00 before expiry)
        final subSecond = window.snapshot(
          now: DateTime.utc(2026, 11, 27, 21, 59, 59, 500),
          useLocalTime: false,
        );
        expect(subSecond.isExpired, isFalse);
        expect(subSecond.formattedCountdown, '00:01');
      },
    );

    test('resolves expired phase at or after end time with 00:00', () {
      final atEnd = window.snapshot(
        now: DateTime.utc(2026, 11, 27, 22),
        useLocalTime: false,
      );
      final afterEnd = window.snapshot(
        now: DateTime.utc(2026, 11, 27, 22, 5),
        useLocalTime: false,
      );

      for (final snap in [atEnd, afterEnd]) {
        expect(snap.phase, PickupPhase.expired);
        expect(snap.urgency, PickupUrgency.expired);
        expect(snap.isExpired, isTrue);
        expect(snap.remaining, Duration.zero);
        expect(snap.formattedCountdown, '00:00');
      }
    });
  });
}
