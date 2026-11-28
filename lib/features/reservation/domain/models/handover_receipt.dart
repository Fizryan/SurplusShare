import 'package:flutter/foundation.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';

/// Immutable digital proof of on-site food handover after PIN verification.
@immutable
class HandoverReceipt {
  const new({
    required this.receiptId,
    required this.reservationId,
    required this.listingId,
    required this.listingTitle,
    required this.partnerId,
    required this.customerId,
    required this.verifiedByStaffId,
    required this.channel,
    required this.quantity,
    required this.totalAmount,
    required this.handedOverAt,
  });

  factory fromJson(Map<String, dynamic> json) {
    final rawChannel = json['channel'] as String? ?? '';
    return HandoverReceipt(
      receiptId:
          json['receipt_id'] as String? ?? json['receiptId'] as String? ?? '',
      reservationId:
          json['reservation_id'] as String? ??
          json['reservationId'] as String? ??
          '',
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
      verifiedByStaffId:
          json['verified_by_staff_id'] as String? ??
          json['verifiedByStaffId'] as String? ??
          '',
      channel: ListingChannel.values.firstWhere(
        (e) => e.name == rawChannel,
        orElse: () => ListingChannel.discount,
      ),
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      totalAmount:
          (json['total_amount'] as num? ?? json['totalAmount'] as num?)
              ?.toInt() ??
          0,
      handedOverAt: DateTime.parse(
        (json['handed_over_at'] ?? json['handedOverAt']) as String,
      ).toUtc(),
    );
  }

  final String receiptId;
  final String reservationId;
  final String listingId;
  final String listingTitle;
  final String partnerId;
  final String customerId;
  final String verifiedByStaffId;
  final ListingChannel channel;
  final int quantity;
  final int totalAmount;
  final DateTime handedOverAt;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HandoverReceipt &&
        other.receiptId == receiptId &&
        other.reservationId == reservationId &&
        other.listingId == listingId &&
        other.listingTitle == listingTitle &&
        other.partnerId == partnerId &&
        other.customerId == customerId &&
        other.verifiedByStaffId == verifiedByStaffId &&
        other.channel == channel &&
        other.quantity == quantity &&
        other.totalAmount == totalAmount &&
        other.handedOverAt == handedOverAt;
  }

  @override
  int get hashCode => Object.hash(
    receiptId,
    reservationId,
    listingId,
    listingTitle,
    partnerId,
    customerId,
    verifiedByStaffId,
    channel,
    quantity,
    totalAmount,
    handedOverAt,
  );
}
