import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:surplus_share/core/permission/app_role.dart';
import 'package:surplus_share/core/permission/permission.dart';

@immutable
class JwtClaims {
  const new({
    this.subject,
    this.displayName,
    this.email,
    this.photoUrl,
    this.role = AppRole.consumer,
    this.kycStatus = KycStatus.unverified,
    this.grantedPermissions = const <Permission>{},
    this.revokedPermissions = const <Permission>{},
    this.expiresAt,
  });

  final String? subject;
  final String? displayName;
  final String? email;
  final String? photoUrl;
  final AppRole role;
  final KycStatus kycStatus;
  final Set<Permission> grantedPermissions;
  final Set<Permission> revokedPermissions;
  final DateTime? expiresAt;

  bool get isExpired => isExpiringSoon(buffer: Duration.zero);

  /// Returns `true` if [expiresAt] is within [buffer] from [now] (or passed).
  bool isExpiringSoon({
    Duration buffer = const Duration(seconds: 30),
    DateTime? now,
  }) {
    final exp = expiresAt;
    if (exp == null) return false;
    final reference = (now ?? DateTime.now()).toUtc();
    return !reference.add(buffer).isBefore(exp);
  }

  /// Decodes the payload segment of a JWT without verifying its signature.
  /// Returns `null` if the token is not a valid 3-part base64url JSON JWT.
  static JwtClaims? tryParse(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;

    try {
      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final dynamic raw = jsonDecode(decoded);
      if (raw is! Map) return null;

      final payload = Map<String, dynamic>.from(raw);
      final rawSub = payload['sub'];
      final rawName = payload['name'];
      final rawEmail = payload['email'];
      final rawPicture = payload['picture'];
      final rawRole = payload['role'];
      final rawKyc = payload['kyc_status'] ?? payload['kycStatus'];
      final rawGranted =
          payload['granted_permissions'] ??
          payload['grantedPermissions'] ??
          payload['permissions'];
      final rawRevoked =
          payload['revoked_permissions'] ?? payload['revokedPermissions'];
      final rawExp = payload['exp'];

      return JwtClaims(
        subject: rawSub is String ? rawSub : null,
        displayName: rawName is String && rawName.trim().isNotEmpty
            ? rawName.trim()
            : null,
        email: rawEmail is String && rawEmail.trim().isNotEmpty
            ? rawEmail.trim()
            : null,
        photoUrl: rawPicture is String && rawPicture.trim().isNotEmpty
            ? rawPicture.trim()
            : null,
        role: _parseRole(rawRole),
        kycStatus: _parseKycStatus(rawKyc),
        grantedPermissions: Set<Permission>.unmodifiable(
          _parsePermissions(rawGranted),
        ),
        revokedPermissions: Set<Permission>.unmodifiable(
          _parsePermissions(rawRevoked),
        ),
        expiresAt: rawExp is num
            ? DateTime.fromMillisecondsSinceEpoch(
                rawExp.toInt() * 1000,
                isUtc: true,
              )
            : null,
      );
    } on FormatException {
      return null;
    }
  }

  static AppRole _parseRole(Object? value) {
    if (value is! String) return AppRole.consumer;
    final normalized = _normalizeKey(value);
    for (final role in AppRole.values) {
      if (_normalizeKey(role.name) == normalized) return role;
    }
    return AppRole.consumer;
  }

  static KycStatus _parseKycStatus(Object? value) {
    if (value is! String) return KycStatus.unverified;
    final normalized = _normalizeKey(value);
    for (final status in KycStatus.values) {
      if (_normalizeKey(status.name) == normalized) return status;
    }
    return KycStatus.unverified;
  }

  static Set<Permission> _parsePermissions(Object? value) {
    if (value is! Iterable) return const <Permission>{};
    final result = <Permission>{};
    for (final entry in value) {
      if (entry is! String) continue;
      final normalized = _normalizeKey(entry);
      for (final permission in Permission.values) {
        if (_normalizeKey(permission.name) == normalized) {
          result.add(permission);
          break;
        }
      }
    }
    return result;
  }

  static String _normalizeKey(String input) =>
      input.replaceAll('_', '').toLowerCase();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is JwtClaims &&
        other.subject == subject &&
        other.displayName == displayName &&
        other.email == email &&
        other.photoUrl == photoUrl &&
        other.role == role &&
        other.kycStatus == kycStatus &&
        setEquals(other.grantedPermissions, grantedPermissions) &&
        setEquals(other.revokedPermissions, revokedPermissions) &&
        other.expiresAt == expiresAt;
  }

  @override
  int get hashCode => Object.hash(
    subject,
    displayName,
    email,
    photoUrl,
    role,
    kycStatus,
    Object.hashAllUnordered(grantedPermissions),
    Object.hashAllUnordered(revokedPermissions),
    expiresAt,
  );
}
