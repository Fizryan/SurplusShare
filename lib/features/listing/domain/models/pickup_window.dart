import 'package:flutter/foundation.dart';

enum PickupPhase { upcoming, open, expired }

enum PickupUrgency { normal, closingSoon, critical, expired }

@immutable
class PickupWindow {
  const new({required this.start, required this.end});

  factory fromJson(Map<String, dynamic> json) {
    return PickupWindow(
      start: DateTime.parse(json['start'] as String).toUtc(),
      end: DateTime.parse(json['end'] as String).toUtc(),
    );
  }

  static const Duration minDuration = Duration(minutes: 15);
  static const Duration maxDuration = Duration(hours: 24);
  static const Duration closingSoonThreshold = Duration(minutes: 60);
  static const Duration criticalThreshold = Duration(minutes: 15);

  final DateTime start;
  final DateTime end;

  Duration get duration => end.toUtc().difference(start.toUtc());

  PickupPhase phase({DateTime? now}) {
    final reference = (now ?? DateTime.now()).toUtc();
    if (!reference.isBefore(end.toUtc())) return PickupPhase.expired;
    if (reference.isBefore(start.toUtc())) return PickupPhase.upcoming;
    return PickupPhase.open;
  }

  /// Remaining duration until [end] (clamped at [Duration.zero]).
  Duration remaining({DateTime? now}) {
    final diff = end.toUtc().difference((now ?? DateTime.now()).toUtc());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Duration until pickup [start] (clamped at [Duration.zero]).
  Duration timeUntilStart({DateTime? now}) {
    final diff = start.toUtc().difference((now ?? DateTime.now()).toUtc());
    return diff.isNegative ? Duration.zero : diff;
  }

  bool isExpired({DateTime? now}) => phase(now: now) == PickupPhase.expired;

  bool isOpen({DateTime? now}) => phase(now: now) == PickupPhase.open;

  PickupUrgency urgency({DateTime? now}) {
    final currentPhase = phase(now: now);
    if (currentPhase == PickupPhase.expired) return PickupUrgency.expired;
    if (currentPhase == PickupPhase.upcoming) return PickupUrgency.normal;

    final left = remaining(now: now);
    if (left <= criticalThreshold) return PickupUrgency.critical;
    if (left <= closingSoonThreshold) return PickupUrgency.closingSoon;
    return PickupUrgency.normal;
  }

  /// Validates pickup window bounds and food-safety duration limits.
  /// Returns an error message or `null` if valid.
  String? validate({DateTime? now}) {
    final reference = (now ?? DateTime.now()).toUtc();
    final startUtc = start.toUtc();
    final endUtc = end.toUtc();

    if (!endUtc.isAfter(startUtc)) {
      return 'Waktu selesai pengambilan harus setelah waktu mulai.';
    }
    if (!endUtc.isAfter(reference)) {
      return 'Batas waktu pengambilan tidak boleh berada di masa lalu.';
    }

    final span = endUtc.difference(startUtc);
    if (span < minDuration) {
      return 'Durasi pengambilan minimal ${minDuration.inMinutes} menit.';
    }
    if (span > maxDuration) {
      return 'Durasi pengambilan maksimal ${maxDuration.inHours} jam '
          'demi keamanan pangan.';
    }
    return null;
  }

  /// Formats the pickup window range, e.g. `21:00 - 22:00` or
  /// `23:00 - 00:30 (+1 hari)` when crossing midnight.
  String formatWindowRange({bool useLocalTime = true}) {
    final s = useLocalTime ? start.toLocal() : start.toUtc();
    final e = useLocalTime ? end.toLocal() : end.toUtc();
    final crossesDay = s.year != e.year || s.month != e.month || s.day != e.day;
    final range = '${_hhmm(s)} - ${_hhmm(e)}';
    return crossesDay ? '$range (+1 hari)' : range;
  }

  PickupCountdownSnapshot snapshot({DateTime? now, bool useLocalTime = true}) {
    final currentPhase = phase(now: now);
    final currentUrgency = urgency(now: now);
    final left = remaining(now: now);
    final untilStart = timeUntilStart(now: now);

    final activeDuration = switch (currentPhase) {
      PickupPhase.upcoming => untilStart,
      PickupPhase.open => left,
      PickupPhase.expired => Duration.zero,
    };

    return PickupCountdownSnapshot(
      phase: currentPhase,
      urgency: currentUrgency,
      remaining: left,
      timeUntilStart: untilStart,
      formattedCountdown: formatCountdown(activeDuration),
      formattedWindow: formatWindowRange(useLocalTime: useLocalTime),
    );
  }

  /// Formats [duration] as `HH:mm:ss` when >= 1 hour, or `mm:ss` otherwise.
  /// Rounds partial seconds up so `00:00` is shown only when fully expired.
  static String formatCountdown(Duration duration) {
    if (duration <= Duration.zero) return '00:00';
    final totalSeconds = (duration.inMilliseconds / 1000).ceil();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${_pad2(hours)}:${_pad2(minutes)}:${_pad2(seconds)}';
    }
    return '${_pad2(minutes)}:${_pad2(seconds)}';
  }

  static String _hhmm(DateTime dt) => '${_pad2(dt.hour)}:${_pad2(dt.minute)}';

  static String _pad2(int value) => value.toString().padLeft(2, '0');

  Map<String, dynamic> toJson() => {
    'start': start.toUtc().toIso8601String(),
    'end': end.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PickupWindow &&
        other.start.toUtc() == start.toUtc() &&
        other.end.toUtc() == end.toUtc();
  }

  @override
  int get hashCode => Object.hash(start.toUtc(), end.toUtc());
}

@immutable
class PickupCountdownSnapshot {
  const new({
    required this.phase,
    required this.urgency,
    required this.remaining,
    required this.timeUntilStart,
    required this.formattedCountdown,
    required this.formattedWindow,
  });

  final PickupPhase phase;
  final PickupUrgency urgency;
  final Duration remaining;
  final Duration timeUntilStart;
  final String formattedCountdown;
  final String formattedWindow;

  bool get isExpired => phase == PickupPhase.expired;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PickupCountdownSnapshot &&
        other.phase == phase &&
        other.urgency == urgency &&
        other.remaining == remaining &&
        other.timeUntilStart == timeUntilStart &&
        other.formattedCountdown == formattedCountdown &&
        other.formattedWindow == formattedWindow;
  }

  @override
  int get hashCode => Object.hash(
    phase,
    urgency,
    remaining,
    timeUntilStart,
    formattedCountdown,
    formattedWindow,
  );
}
