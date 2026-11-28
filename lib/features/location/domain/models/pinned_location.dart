import 'package:flutter/foundation.dart';
import 'package:surplus_share/core/permission/app_role.dart';
import 'package:surplus_share/features/location/domain/models/geo_point.dart';

/// Fixed map pin for a `donorPartner` store (pickup point) or a
/// `verifiedRecipient` organization (drop-off point).
@immutable
class PinnedLocation {
  const new({
    required this.ownerId,
    required this.ownerRole,
    required this.placeName,
    required this.address,
    required this.point,
    required this.updatedAt,
  });

  factory fromJson(Map<String, dynamic> json) {
    final roleName = json['owner_role'] as String?;
    return PinnedLocation(
      ownerId: json['owner_id'] as String,
      ownerRole: AppRole.values.firstWhere(
        (r) => r.name == roleName,
        orElse: () => AppRole.donorPartner,
      ),
      placeName: json['place_name'] as String,
      address: json['address'] as String,
      point: GeoPoint.fromJson(Map<String, dynamic>.from(json['point'] as Map)),
      updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
    );
  }

  final String ownerId;
  final AppRole ownerRole;
  final String placeName;
  final String address;
  final GeoPoint point;
  final DateTime updatedAt;

  String? validate() {
    if (ownerId.trim().isEmpty) {
      return 'Identitas pemilik lokasi tidak valid.';
    }
    if (placeName.trim().length < 3) {
      return 'Nama lokasi minimal 3 karakter.';
    }
    if (address.trim().length < 10) {
      return 'Alamat lengkap minimal 10 karakter.';
    }
    if (!point.isValid) {
      return 'Koordinat titik peta tidak valid.';
    }
    return null;
  }

  PinnedLocation copyWith({
    String? placeName,
    String? address,
    GeoPoint? point,
    DateTime? updatedAt,
  }) {
    return PinnedLocation(
      ownerId: ownerId,
      ownerRole: ownerRole,
      placeName: placeName ?? this.placeName,
      address: address ?? this.address,
      point: point ?? this.point,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'owner_id': ownerId,
    'owner_role': ownerRole.name,
    'place_name': placeName,
    'address': address,
    'point': point.toJson(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PinnedLocation &&
        other.ownerId == ownerId &&
        other.ownerRole == ownerRole &&
        other.placeName == placeName &&
        other.address == address &&
        other.point == point &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode =>
      Object.hash(ownerId, ownerRole, placeName, address, point, updatedAt);
}
