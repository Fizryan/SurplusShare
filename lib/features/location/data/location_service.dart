import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fpdart/fpdart.dart';
import 'package:geolocator/geolocator.dart';
import 'package:surplus_share/features/location/domain/models/geo_point.dart';
import 'package:surplus_share/features/location/domain/models/location_failure.dart';

abstract interface class LocationService {
  Future<Either<LocationFailure, GeoPoint>> getCurrentLocation();

  Future<bool> openLocationSettings();

  Future<bool> openAppSettings();
}

typedef PositionFetcher = Future<GeoPoint> Function({
  required LocationAccuracy accuracy,
  required Duration timeLimit,
  required bool forceAndroidLocationManager,
});

typedef LastKnownPositionFetcher = Future<GeoPoint?> Function({
  required bool forceAndroidLocationManager,
});

/// Resilient multi-tier GPS service:
/// 1. Active fix via FusedLocationProvider (medium accuracy, 8s)
/// 2. Android fallback via legacy LocationManager (low accuracy, 6s)
/// 3. OS-cached `getLastKnownPosition()` (Fused + LocationManager)
class GeolocatorLocationService implements LocationService {
  const new({
    this._timeout = const Duration(seconds: 8),
    this._fallbackTimeout = const Duration(seconds: 6),
    this._isAndroidOverride,
    this._isServiceEnabled,
    this._checkPermission,
    this._requestPermission,
    this._fetchPosition,
    this._fetchLastKnown,
  });

  final Duration _timeout;
  final Duration _fallbackTimeout;
  final bool? _isAndroidOverride;
  final Future<bool> Function()? _isServiceEnabled;
  final Future<LocationPermission> Function()? _checkPermission;
  final Future<LocationPermission> Function()? _requestPermission;
  final PositionFetcher? _fetchPosition;
  final LastKnownPositionFetcher? _fetchLastKnown;

  bool get _isAndroid =>
      _isAndroidOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  @override
  Future<Either<LocationFailure, GeoPoint>> getCurrentLocation() async {
    try {
      final serviceEnabled = await (_isServiceEnabled != null
          ? _isServiceEnabled()
          : Geolocator.isLocationServiceEnabled());
      if (!serviceEnabled) {
        return left(const LocationServiceDisabledFailure());
      }

      var permission = await (_checkPermission != null
          ? _checkPermission()
          : Geolocator.checkPermission());
      if (permission == LocationPermission.denied) {
        permission = await (_requestPermission != null
            ? _requestPermission()
            : Geolocator.requestPermission());
      }

      if (permission == LocationPermission.denied) {
        return left(const LocationPermissionDeniedFailure());
      }
      if (permission == LocationPermission.deniedForever) {
        return left(const LocationPermissionDeniedForeverFailure());
      }

      // Tier 1: Primary active fix (FusedLocationProvider on Android).
      try {
        final primary = await _getPosition(
          accuracy: LocationAccuracy.medium,
          timeLimit: _timeout,
          forceAndroidLocationManager: false,
        );
        return right(primary);
      } on TimeoutException {
        // Fall through to Tier 2 / Tier 3.
      } on PlatformException {
        // Devices/emulators without Google Play Services fall through to Tier 2.
      }

      // Tier 2 (Android): Legacy LocationManager often succeeds on emulators
      // and devices where FusedLocationProvider hangs without fresh push.
      if (_isAndroid) {
        try {
          final legacy = await _getPosition(
            accuracy: LocationAccuracy.low,
            timeLimit: _fallbackTimeout,
            forceAndroidLocationManager: true,
          );
          return right(legacy);
        } on Object {
          // Proceed to Tier 3 last-known position fallback.
        }
      }

      // Tier 3: OS-cached last known position (instant, avoids indoor timeout).
      final lastKnown = await _getLastKnownWithFallback();
      if (lastKnown != null && lastKnown.isValid) {
        return right(lastKnown);
      }

      return left(
        const LocationTimeoutFailure(
          'Sinyal GPS timeout. Gunakan "Pilih Area" untuk memilih lokasi '
          'secara manual.',
        ),
      );
    } on TimeoutException {
      return left(
        const LocationTimeoutFailure(
          'Sinyal GPS timeout. Gunakan "Pilih Area" untuk memilih lokasi '
          'secara manual.',
        ),
      );
    } on Object catch (e) {
      return left(LocationUnknownFailure(e.toString()));
    }
  }

  @override
  Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } on Object {
      return false;
    }
  }

  Future<GeoPoint> _getPosition({
    required LocationAccuracy accuracy,
    required Duration timeLimit,
    required bool forceAndroidLocationManager,
  }) async {
    if (_fetchPosition != null) {
      return await _fetchPosition(
        accuracy: accuracy,
        timeLimit: timeLimit,
        forceAndroidLocationManager: forceAndroidLocationManager,
      );
    }

    final settings = _isAndroid
        ? AndroidSettings(
            accuracy: accuracy,
            timeLimit: timeLimit,
            forceLocationManager: forceAndroidLocationManager,
          )
        : LocationSettings(accuracy: accuracy, timeLimit: timeLimit);

    final position = await Geolocator.getCurrentPosition(
      locationSettings: settings,
    );
    return GeoPoint(latitude: position.latitude, longitude: position.longitude);
  }

  Future<GeoPoint?> _getLastKnownWithFallback() async {
    final primary = await _getLastKnown(forceAndroidLocationManager: false);
    if (primary != null) return primary;
    if (_isAndroid) {
      return await _getLastKnown(forceAndroidLocationManager: true);
    }
    return null;
  }

  Future<GeoPoint?> _getLastKnown({
    required bool forceAndroidLocationManager,
  }) async {
    if (_fetchLastKnown != null) {
      return await _fetchLastKnown(
        forceAndroidLocationManager: forceAndroidLocationManager,
      );
    }
    try {
      final pos = await Geolocator.getLastKnownPosition(
        forceAndroidLocationManager: forceAndroidLocationManager,
      );
      if (pos == null) return null;
      return GeoPoint(latitude: pos.latitude, longitude: pos.longitude);
    } on Object {
      return null;
    }
  }
}
