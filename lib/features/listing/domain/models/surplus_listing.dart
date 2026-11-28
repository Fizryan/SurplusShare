import 'package:flutter/foundation.dart';
import 'package:surplus_share/features/listing/domain/models/food_safety_declaration.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/listing/domain/models/pickup_window.dart';
import 'package:surplus_share/features/location/domain/models/geo_point.dart';

@immutable
class SurplusListing {
  const new({
    required this.id,
    required this.partnerId,
    required this.partnerName,
    required this.title,
    required this.description,
    required this.channel,
    required this.originalPrice,
    required this.discountedPrice,
    required this.totalQuantity,
    required this.remainingQuantity,
    required this.pickupWindow,
    required this.status,
    required this.createdAt,
    this.discountFormat,
    this.convertedToDonationAt,
    this.location,
    this.address,
    this.foodSafety,
  });

  factory fromJson(Map<String, dynamic> json) {
    final channelName = json['channel'] as String?;
    final formatName = json['discount_format'] as String?;
    final statusName = json['status'] as String?;
    final rawLocation = json['location'];
    final rawSafety = json['food_safety'];
    final rawConverted = json['converted_to_donation_at'] as String?;

    return SurplusListing(
      id: json['id'] as String,
      partnerId: json['partner_id'] as String,
      partnerName: json['partner_name'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      channel: ListingChannel.values.firstWhere(
        (v) => v.name == channelName,
        orElse: () => ListingChannel.discount,
      ),
      discountFormat: formatName == null
          ? null
          : DiscountFormat.values.firstWhere(
              (v) => v.name == formatName,
              orElse: () => DiscountFormat.flashSale,
            ),
      originalPrice: (json['original_price'] as num).toInt(),
      discountedPrice: (json['discounted_price'] as num).toInt(),
      totalQuantity: (json['total_quantity'] as num).toInt(),
      remainingQuantity: (json['remaining_quantity'] as num).toInt(),
      pickupWindow: PickupWindow.fromJson(
        Map<String, dynamic>.from(json['pickup_window'] as Map),
      ),
      status: ListingStatus.values.firstWhere(
        (v) => v.name == statusName,
        orElse: () => ListingStatus.active,
      ),
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      convertedToDonationAt: rawConverted == null
          ? null
          : DateTime.parse(rawConverted).toUtc(),
      location: rawLocation is Map
          ? GeoPoint.fromJson(Map<String, dynamic>.from(rawLocation))
          : null,
      address: json['address'] as String?,
      foodSafety: rawSafety is Map
          ? FoodSafetyDeclaration.fromJson(Map<String, dynamic>.from(rawSafety))
          : null,
    );
  }

  final String id;
  final String partnerId;
  final String partnerName;
  final String title;
  final String description;
  final ListingChannel channel;
  final DiscountFormat? discountFormat;
  final int originalPrice;
  final int discountedPrice;
  final int totalQuantity;
  final int remainingQuantity;
  final PickupWindow pickupWindow;
  final ListingStatus status;
  final DateTime createdAt;
  final DateTime? convertedToDonationAt;
  final GeoPoint? location;
  final String? address;
  final FoodSafetyDeclaration? foodSafety;

  DateTime get pickupStart => pickupWindow.start;
  DateTime get pickupEnd => pickupWindow.end;

  /// Single source of truth for discount percentage calculation.
  static int calculateDiscountPercent({
    required int originalPrice,
    required int discountedPrice,
  }) {
    if (originalPrice <= 0) return 0;
    return (((originalPrice - discountedPrice) * 100) / originalPrice).round();
  }

  /// Effective discount percentage (`100` for donation channel).
  int get discountPercent {
    if (channel == ListingChannel.donation) return 100;
    return calculateDiscountPercent(
      originalPrice: originalPrice,
      discountedPrice: discountedPrice,
    );
  }

  /// Automatically resolves to [ListingStatus.expired] once [pickupWindow]
  /// has passed, even before persisted status is reconciled.
  ListingStatus effectiveStatus({DateTime? now}) {
    if (status == ListingStatus.active && pickupWindow.isExpired(now: now)) {
      return ListingStatus.expired;
    }
    return status;
  }

  bool isAvailable({DateTime? now}) {
    return effectiveStatus(now: now) == ListingStatus.active &&
        remainingQuantity > 0;
  }

  bool canConvertToDonation({DateTime? now}) {
    return channel == ListingChannel.discount && isAvailable(now: now);
  }

  PickupCountdownSnapshot countdownSnapshot({
    DateTime? now,
    bool useLocalTime = true,
  }) {
    return pickupWindow.snapshot(now: now, useLocalTime: useLocalTime);
  }

  SurplusListing copyWith({
    ListingChannel? channel,
    DiscountFormat? discountFormat,
    bool clearDiscountFormat = false,
    int? discountedPrice,
    int? remainingQuantity,
    PickupWindow? pickupWindow,
    ListingStatus? status,
    DateTime? convertedToDonationAt,
  }) {
    return SurplusListing(
      id: id,
      partnerId: partnerId,
      partnerName: partnerName,
      title: title,
      description: description,
      channel: channel ?? this.channel,
      discountFormat: clearDiscountFormat
          ? null
          : (discountFormat ?? this.discountFormat),
      originalPrice: originalPrice,
      discountedPrice: discountedPrice ?? this.discountedPrice,
      totalQuantity: totalQuantity,
      remainingQuantity: remainingQuantity ?? this.remainingQuantity,
      pickupWindow: pickupWindow ?? this.pickupWindow,
      status: status ?? this.status,
      createdAt: createdAt,
      convertedToDonationAt:
          convertedToDonationAt ?? this.convertedToDonationAt,
      location: location,
      address: address,
      foodSafety: foodSafety,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'partner_id': partnerId,
    'partner_name': partnerName,
    'title': title,
    'description': description,
    'channel': channel.name,
    'discount_format': discountFormat?.name,
    'original_price': originalPrice,
    'discounted_price': discountedPrice,
    'total_quantity': totalQuantity,
    'remaining_quantity': remainingQuantity,
    'pickup_window': pickupWindow.toJson(),
    'status': status.name,
    'created_at': createdAt.toUtc().toIso8601String(),
    'converted_to_donation_at': convertedToDonationAt
        ?.toUtc()
        .toIso8601String(),
    'location': location?.toJson(),
    'address': address,
    'food_safety': foodSafety?.toJson(),
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SurplusListing &&
        other.id == id &&
        other.partnerId == partnerId &&
        other.partnerName == partnerName &&
        other.title == title &&
        other.description == description &&
        other.channel == channel &&
        other.discountFormat == discountFormat &&
        other.originalPrice == originalPrice &&
        other.discountedPrice == discountedPrice &&
        other.totalQuantity == totalQuantity &&
        other.remainingQuantity == remainingQuantity &&
        other.pickupWindow == pickupWindow &&
        other.status == status &&
        other.createdAt == createdAt &&
        other.convertedToDonationAt == convertedToDonationAt &&
        other.location == location &&
        other.address == address &&
        other.foodSafety == foodSafety;
  }

  @override
  int get hashCode => Object.hash(
    id,
    partnerId,
    partnerName,
    title,
    description,
    channel,
    discountFormat,
    originalPrice,
    discountedPrice,
    totalQuantity,
    remainingQuantity,
    pickupWindow,
    status,
    createdAt,
    convertedToDonationAt,
    location,
    address,
    foodSafety,
  );
}
