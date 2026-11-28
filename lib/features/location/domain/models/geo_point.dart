import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

@immutable
class GeoPoint {
  const new({required this.latitude, required this.longitude});

  factory fromJson(Map<String, dynamic> json) {
    final lat = json['latitude'] ?? json['lat'];
    final lng = json['longitude'] ?? json['lng'];
    if (lat is! num || lng is! num) {
      throw const FormatException('Invalid GeoPoint coordinates.');
    }
    return GeoPoint(latitude: lat.toDouble(), longitude: lng.toDouble());
  }

  static const double _earthRadiusKm = 6371;

  final double latitude;
  final double longitude;

  bool get isValid =>
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  LatLng toLatLng() => LatLng(latitude, longitude);

  /// Computes great-circle distance in kilometers using the Haversine formula.
  double distanceInKmTo(GeoPoint other) {
    final dLat = _toRadians(other.latitude - latitude);
    final dLng = _toRadians(other.longitude - longitude);
    final lat1 = _toRadians(latitude);
    final lat2 = _toRadians(other.latitude);

    final a =
        (math.pow(math.sin(dLat / 2), 2) +
                math.cos(lat1) *
                    math.cos(lat2) *
                    math.pow(math.sin(dLng / 2), 2))
            .clamp(0.0, 1.0);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _earthRadiusKm * c;
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
  };

  static double _toRadians(double degrees) => degrees * math.pi / 180;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GeoPoint &&
        other.latitude == latitude &&
        other.longitude == longitude;
  }

  @override
  int get hashCode => Object.hash(latitude, longitude);
}
