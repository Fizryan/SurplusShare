import 'package:flutter/foundation.dart';

/// Single session token issued by backend after Google OAuth sign-in.
@immutable
class AuthTokens {
  const new({required this.accessToken});

  factory fromJson(Map<String, dynamic> json) {
    final payload = _extractPayload(json);
    final rawAccess =
        payload['session_token'] ??
        payload['access_token'] ??
        payload['accessToken'] ??
        payload['token'];

    if (rawAccess is! String || rawAccess.trim().isEmpty) {
      throw const FormatException(
        'Missing or invalid session token in auth response.',
      );
    }

    return AuthTokens(accessToken: rawAccess.trim());
  }

  final String accessToken;

  static Map<String, dynamic> _extractPayload(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return json;
  }

  Map<String, dynamic> toJson() => {'access_token': accessToken};

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuthTokens && other.accessToken == accessToken;
  }

  @override
  int get hashCode => accessToken.hashCode;

  @override
  String toString() => 'AuthTokens(accessToken: [REDACTED])';
}
