import 'package:flutter/foundation.dart';
import 'package:surplus_share/features/location/domain/models/geo_point.dart';

enum DistributionStatus { open, accepted, pickedUp, delivered, cancelled }

@immutable
class CreateDistributionInput {
  const new({
    required this.listingId,
    required this.listingTitle,
    required this.partnerId,
    required this.partnerName,
    required this.storeAddress,
    required this.storeLocation,
    required this.recipientId,
    required this.recipientName,
    required this.recipientAddress,
    required this.recipientLocation,
    required this.portions,
  });

  final String listingId;
  final String listingTitle;
  final String partnerId;
  final String partnerName;
  final String storeAddress;
  final GeoPoint storeLocation;
  final String recipientId;
  final String recipientName;
  final String recipientAddress;
  final GeoPoint recipientLocation;
  final int portions;

  String? validate() {
    if (listingId.trim().isEmpty || listingTitle.trim().isEmpty) {
      return 'Listing distribusi tidak valid.';
    }
    if (partnerId.trim().isEmpty || partnerName.trim().isEmpty) {
      return 'Identitas mitra tidak valid.';
    }
    if (storeAddress.trim().length < 5 || !storeLocation.isValid) {
      return 'Lokasi toko tetap belum valid.';
    }
    if (recipientId.trim().isEmpty || recipientName.trim().isEmpty) {
      return 'Penerima donasi terverifikasi wajib dipilih.';
    }
    if (recipientAddress.trim().length < 5 || !recipientLocation.isValid) {
      return 'Lokasi penerima terverifikasi belum valid.';
    }
    if (portions <= 0) {
      return 'Jumlah porsi distribusi harus lebih dari 0.';
    }
    return null;
  }
}

@immutable
class DistributionTask {
  const new({
    required this.id,
    required this.listingId,
    required this.listingTitle,
    required this.partnerId,
    required this.partnerName,
    required this.storeAddress,
    required this.storeLocation,
    required this.recipientId,
    required this.recipientName,
    required this.recipientAddress,
    required this.recipientLocation,
    required this.portions,
    required this.status,
    required this.createdAt,
    this.volunteerId,
    this.volunteerName,
    this.pickupPin,
    this.deliveryPin,
    this.failedPinAttempts = 0,
    this.acceptedAt,
    this.pickedUpAt,
    this.deliveredAt,
  });

  factory fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String?;
    return DistributionTask(
      id: json['id'] as String,
      listingId: json['listing_id'] as String,
      listingTitle: json['listing_title'] as String,
      partnerId: json['partner_id'] as String,
      partnerName: json['partner_name'] as String,
      storeAddress: json['store_address'] as String,
      storeLocation: GeoPoint.fromJson(
        Map<String, dynamic>.from(json['store_location'] as Map),
      ),
      recipientId: json['recipient_id'] as String,
      recipientName: json['recipient_name'] as String,
      recipientAddress: json['recipient_address'] as String,
      recipientLocation: GeoPoint.fromJson(
        Map<String, dynamic>.from(json['recipient_location'] as Map),
      ),
      portions: (json['portions'] as num).toInt(),
      status: DistributionStatus.values.firstWhere(
        (s) => s.name == statusName,
        orElse: () => DistributionStatus.open,
      ),
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      volunteerId: json['volunteer_id'] as String?,
      volunteerName: json['volunteer_name'] as String?,
      pickupPin: json['pickup_pin'] as String?,
      deliveryPin: json['delivery_pin'] as String?,
      failedPinAttempts: (json['failed_pin_attempts'] as num?)?.toInt() ?? 0,
      acceptedAt: _parseOptionalDate(json['accepted_at'] as String?),
      pickedUpAt: _parseOptionalDate(json['picked_up_at'] as String?),
      deliveredAt: _parseOptionalDate(json['delivered_at'] as String?),
    );
  }

  final String id;
  final String listingId;
  final String listingTitle;
  final String partnerId;
  final String partnerName;
  final String storeAddress;
  final GeoPoint storeLocation;
  final String recipientId;
  final String recipientName;
  final String recipientAddress;
  final GeoPoint recipientLocation;
  final int portions;
  final DistributionStatus status;
  final DateTime createdAt;
  final String? volunteerId;
  final String? volunteerName;
  final String? pickupPin;
  final String? deliveryPin;
  final int failedPinAttempts;
  final DateTime? acceptedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;

  bool get canCancel =>
      status == DistributionStatus.open ||
      status == DistributionStatus.accepted;

  DistributionTask copyWith({
    DistributionStatus? status,
    String? volunteerId,
    String? volunteerName,
    String? pickupPin,
    String? deliveryPin,
    int? failedPinAttempts,
    DateTime? acceptedAt,
    DateTime? pickedUpAt,
    DateTime? deliveredAt,
  }) {
    return DistributionTask(
      id: id,
      listingId: listingId,
      listingTitle: listingTitle,
      partnerId: partnerId,
      partnerName: partnerName,
      storeAddress: storeAddress,
      storeLocation: storeLocation,
      recipientId: recipientId,
      recipientName: recipientName,
      recipientAddress: recipientAddress,
      recipientLocation: recipientLocation,
      portions: portions,
      status: status ?? this.status,
      createdAt: createdAt,
      volunteerId: volunteerId ?? this.volunteerId,
      volunteerName: volunteerName ?? this.volunteerName,
      pickupPin: pickupPin ?? this.pickupPin,
      deliveryPin: deliveryPin ?? this.deliveryPin,
      failedPinAttempts: failedPinAttempts ?? this.failedPinAttempts,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      pickedUpAt: pickedUpAt ?? this.pickedUpAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'listing_id': listingId,
    'listing_title': listingTitle,
    'partner_id': partnerId,
    'partner_name': partnerName,
    'store_address': storeAddress,
    'store_location': storeLocation.toJson(),
    'recipient_id': recipientId,
    'recipient_name': recipientName,
    'recipient_address': recipientAddress,
    'recipient_location': recipientLocation.toJson(),
    'portions': portions,
    'status': status.name,
    'created_at': createdAt.toUtc().toIso8601String(),
    'volunteer_id': volunteerId,
    'volunteer_name': volunteerName,
    'pickup_pin': pickupPin,
    'delivery_pin': deliveryPin,
    'failed_pin_attempts': failedPinAttempts,
    'accepted_at': acceptedAt?.toUtc().toIso8601String(),
    'picked_up_at': pickedUpAt?.toUtc().toIso8601String(),
    'delivered_at': deliveredAt?.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DistributionTask &&
        other.id == id &&
        other.listingId == listingId &&
        other.listingTitle == listingTitle &&
        other.partnerId == partnerId &&
        other.partnerName == partnerName &&
        other.storeAddress == storeAddress &&
        other.storeLocation == storeLocation &&
        other.recipientId == recipientId &&
        other.recipientName == recipientName &&
        other.recipientAddress == recipientAddress &&
        other.recipientLocation == recipientLocation &&
        other.portions == portions &&
        other.status == status &&
        other.createdAt == createdAt &&
        other.volunteerId == volunteerId &&
        other.volunteerName == volunteerName &&
        other.pickupPin == pickupPin &&
        other.deliveryPin == deliveryPin &&
        other.failedPinAttempts == failedPinAttempts &&
        other.acceptedAt == acceptedAt &&
        other.pickedUpAt == pickedUpAt &&
        other.deliveredAt == deliveredAt;
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    listingId,
    listingTitle,
    partnerId,
    partnerName,
    storeAddress,
    storeLocation,
    recipientId,
    recipientName,
    recipientAddress,
    recipientLocation,
    portions,
    status,
    createdAt,
    volunteerId,
    volunteerName,
    pickupPin,
    deliveryPin,
    failedPinAttempts,
    acceptedAt,
    pickedUpAt,
    deliveredAt,
  ]);
}

DateTime? _parseOptionalDate(String? raw) =>
    raw == null ? null : DateTime.parse(raw).toUtc();
