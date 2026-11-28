import 'package:flutter/foundation.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/listing/domain/models/pickup_window.dart';
import 'package:surplus_share/features/reservation/domain/models/handover_receipt.dart';
import 'package:surplus_share/features/reservation/domain/models/payment_session.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation_status.dart';

@immutable
class Reservation {
  const new({
    required this.id,
    required this.listingId,
    required this.listingTitle,
    required this.partnerId,
    required this.customerId,
    required this.channel,
    required this.quantity,
    required this.totalAmount,
    required this.pickupWindow,
    required this.status,
    required this.createdAt,
    this.paymentSession,
    this.pickupPin,
    this.failedPinAttempts = 0,
    this.receipt,
  });

  factory fromJson(Map<String, dynamic> json) {
    final rawChannel = json['channel'] as String? ?? '';
    final rawStatus = json['status'] as String? ?? '';
    final rawWindow = json['pickup_window'] ?? json['pickupWindow'];
    final rawPayment = json['payment_session'] ?? json['paymentSession'];
    final rawReceipt = json['receipt'];
    return Reservation(
      id: json['id'] as String? ?? '',
      listingId:
          json['listing_id'] as String? ?? json['listingId'] as String? ?? '',
      listingTitle:
          json['listing_title'] as String? ??
          json['listingTitle'] as String? ??
          '',
      partnerId:
          json['partner_id'] as String? ?? json['partnerId'] as String? ?? '',
      customerId:
          json['customer_id'] as String? ?? json['customerId'] as String? ?? '',
      channel: ListingChannel.values.firstWhere(
        (e) => e.name == rawChannel,
        orElse: () => ListingChannel.discount,
      ),
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      totalAmount:
          (json['total_amount'] as num? ?? json['totalAmount'] as num?)
              ?.toInt() ??
          0,
      pickupWindow: PickupWindow.fromJson(
        Map<String, dynamic>.from(rawWindow as Map),
      ),
      status: ReservationStatus.values.firstWhere(
        (e) => e.name == rawStatus,
        orElse: () => ReservationStatus.pendingPayment,
      ),
      createdAt: DateTime.parse(
        (json['created_at'] ?? json['createdAt']) as String,
      ).toUtc(),
      paymentSession: rawPayment is Map
          ? PaymentSession.fromJson(Map<String, dynamic>.from(rawPayment))
          : null,
      pickupPin: json['pickup_pin'] as String? ?? json['pickupPin'] as String?,
      failedPinAttempts:
          (json['failed_pin_attempts'] as num? ??
                  json['failedPinAttempts'] as num?)
              ?.toInt() ??
          0,
      receipt: rawReceipt is Map
          ? HandoverReceipt.fromJson(Map<String, dynamic>.from(rawReceipt))
          : null,
    );
  }

  final String id;
  final String listingId;
  final String listingTitle;
  final String partnerId;
  final String customerId;
  final ListingChannel channel;
  final int quantity;
  final int totalAmount;
  final PickupWindow pickupWindow;
  final ReservationStatus status;
  final DateTime createdAt;
  final PaymentSession? paymentSession;
  final String? pickupPin;
  final int failedPinAttempts;
  final HandoverReceipt? receipt;

  ReservationStatus effectiveStatus({DateTime? now}) {
    if (status == ReservationStatus.pendingPayment &&
        (paymentSession?.isExpired(now: now) ?? false)) {
      return ReservationStatus.expired;
    }
    if ((status == ReservationStatus.pendingPayment ||
            status == ReservationStatus.confirmed) &&
        pickupWindow.isExpired(now: now)) {
      return ReservationStatus.expired;
    }
    return status;
  }

  bool canCancel({DateTime? now}) {
    final current = effectiveStatus(now: now);
    return current == ReservationStatus.pendingPayment ||
        current == ReservationStatus.confirmed;
  }

  Reservation copyWith({
    ReservationStatus? status,
    String? pickupPin,
    bool clearPickupPin = false,
    int? failedPinAttempts,
    HandoverReceipt? receipt,
  }) {
    return Reservation(
      id: id,
      listingId: listingId,
      listingTitle: listingTitle,
      partnerId: partnerId,
      customerId: customerId,
      channel: channel,
      quantity: quantity,
      totalAmount: totalAmount,
      pickupWindow: pickupWindow,
      status: status ?? this.status,
      createdAt: createdAt,
      paymentSession: paymentSession,
      pickupPin: clearPickupPin ? null : (pickupPin ?? this.pickupPin),
      failedPinAttempts: failedPinAttempts ?? this.failedPinAttempts,
      receipt: receipt ?? this.receipt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Reservation &&
        other.id == id &&
        other.listingId == listingId &&
        other.listingTitle == listingTitle &&
        other.partnerId == partnerId &&
        other.customerId == customerId &&
        other.channel == channel &&
        other.quantity == quantity &&
        other.totalAmount == totalAmount &&
        other.pickupWindow == pickupWindow &&
        other.status == status &&
        other.createdAt == createdAt &&
        other.paymentSession == paymentSession &&
        other.pickupPin == pickupPin &&
        other.failedPinAttempts == failedPinAttempts &&
        other.receipt == receipt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    listingId,
    listingTitle,
    partnerId,
    customerId,
    channel,
    quantity,
    totalAmount,
    pickupWindow,
    status,
    createdAt,
    paymentSession,
    pickupPin,
    failedPinAttempts,
    receipt,
  );

  @override
  String toString() =>
      'Reservation(id: $id, status: ${status.name}, pickupPin: [REDACTED])';
}
