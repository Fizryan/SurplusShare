import 'package:surplus_share/features/reservation/domain/models/payment_session.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation_status.dart';
import 'package:uuid/uuid.dart';

/// Abstraction for generating hosted WebView checkout sessions (QRIS/e-Wallet).
abstract interface class PaymentGatewayService {
  Future<PaymentSession> createCheckoutSession({
    required String reservationId,
    required PaymentMethod method,
    required int amount,
    required DateTime expiresAt,
  });
}

/// Local/debug stub producing valid HTTPS checkout URLs for WebView testing.
class StubPaymentGatewayService implements PaymentGatewayService {
  const new({
    this._checkoutHost = 'pay.surplusshare.id',
    this._uuid = const Uuid(),
  });

  final String _checkoutHost;
  final Uuid _uuid;

  @override
  Future<PaymentSession> createCheckoutSession({
    required String reservationId,
    required PaymentMethod method,
    required int amount,
    required DateTime expiresAt,
  }) async {
    final sessionId = 'pay-${_uuid.v4()}';
    final checkoutUrl = Uri.https(
      _checkoutHost,
      '/checkout/$sessionId',
      <String, String>{
        'reservation_id': reservationId,
        'method': method.name,
        'amount': '$amount',
      },
    );

    return PaymentSession(
      sessionId: sessionId,
      checkoutUrl: checkoutUrl,
      method: method,
      amount: amount,
      expiresAt: expiresAt.toUtc(),
    );
  }
}
