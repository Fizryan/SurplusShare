import 'package:flutter/foundation.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation_status.dart';

@immutable
class PaymentSession {
  const new({
    required this.sessionId,
    required this.checkoutUrl,
    required this.method,
    required this.amount,
    required this.expiresAt,
  });

  factory fromJson(Map<String, dynamic> json) {
    final rawMethod = json['method'] as String? ?? '';
    return PaymentSession(
      sessionId:
          json['session_id'] as String? ?? json['sessionId'] as String? ?? '',
      checkoutUrl: Uri.parse(
        (json['checkout_url'] ?? json['checkoutUrl']) as String,
      ),
      method: PaymentMethod.values.firstWhere(
        (e) => e.name == rawMethod,
        orElse: () => PaymentMethod.qris,
      ),
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      expiresAt: DateTime.parse(
        (json['expires_at'] ?? json['expiresAt']) as String,
      ).toUtc(),
    );
  }

  final String sessionId;
  final Uri checkoutUrl;
  final PaymentMethod method;
  final int amount;
  final DateTime expiresAt;

  bool get isSecureUrl =>
      checkoutUrl.scheme == 'https' && checkoutUrl.host.isNotEmpty;

  bool isExpired({DateTime? now}) {
    final reference = (now ?? DateTime.now()).toUtc();
    return !reference.isBefore(expiresAt.toUtc());
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PaymentSession &&
        other.sessionId == sessionId &&
        other.checkoutUrl == checkoutUrl &&
        other.method == method &&
        other.amount == amount &&
        other.expiresAt == expiresAt;
  }

  @override
  int get hashCode =>
      Object.hash(sessionId, checkoutUrl, method, amount, expiresAt);
}
