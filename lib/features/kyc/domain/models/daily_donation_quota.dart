import 'package:flutter/foundation.dart';

@immutable
class DailyDonationQuota {
  const new({
    required this.userId,
    required this.dateKey,
    required this.dailyLimit,
    required this.usedToday,
  });

  factory fromJson(Map<String, dynamic> json) {
    return DailyDonationQuota(
      userId: json['user_id'] as String? ?? json['userId'] as String? ?? '',
      dateKey: json['date_key'] as String? ?? json['dateKey'] as String? ?? '',
      dailyLimit:
          (json['daily_limit'] as num? ?? json['dailyLimit'] as num?)
              ?.toInt() ??
          0,
      usedToday:
          (json['used_today'] as num? ?? json['usedToday'] as num?)?.toInt() ??
          0,
    );
  }

  final String userId;
  final String dateKey;
  final int dailyLimit;
  final int usedToday;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'user_id': userId,
    'date_key': dateKey,
    'daily_limit': dailyLimit,
    'used_today': usedToday,
  };

  int get remaining => (dailyLimit - usedToday).clamp(0, dailyLimit);
  bool get isExhausted => remaining == 0;

  bool canClaim(int quantity) => quantity > 0 && quantity <= remaining;

  DailyDonationQuota copyWith({int? dailyLimit, int? usedToday}) {
    return DailyDonationQuota(
      userId: userId,
      dateKey: dateKey,
      dailyLimit: dailyLimit ?? this.dailyLimit,
      usedToday: usedToday ?? this.usedToday,
    );
  }

  /// Returns a canonical UTC date key (`YYYY-MM-DD`) used for daily resets.
  static String dateKeyFor(DateTime dateTime) {
    final utc = dateTime.toUtc();
    final y = utc.year.toString().padLeft(4, '0');
    final m = utc.month.toString().padLeft(2, '0');
    final d = utc.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DailyDonationQuota &&
        other.userId == userId &&
        other.dateKey == dateKey &&
        other.dailyLimit == dailyLimit &&
        other.usedToday == usedToday;
  }

  @override
  int get hashCode => Object.hash(userId, dateKey, dailyLimit, usedToday);
}
