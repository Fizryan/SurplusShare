import 'package:flutter/foundation.dart';

@immutable
class AuthTokens {
  const new({required this.accessToken, required this.refreshToken});

  factory fromJson(Map<String, dynamic> json) {
    final payload = _extractPayload(json);
    final rawAccess = payload['access_token'] ?? payload['accessToken'];
    final rawRefresh = payload['refresh_token'] ?? payload['refreshToken'];

    if (rawAccess is! String || rawAccess.trim().isEmpty) {
      throw const FormatException(
        'Missing or invalid accessToken in auth response.',
      );
    }
    if (rawRefresh is! String || rawRefresh.trim().isEmpty) {
      throw const FormatException(
        'Missing or invalid refreshToken in auth response.',
      );
    }

    return AuthTokens(
      accessToken: rawAccess.trim(),
      refreshToken: rawRefresh.trim(),
    );
  }

  final String accessToken;
  final String refreshToken;

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

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuthTokens &&
        other.accessToken == accessToken &&
        other.refreshToken == refreshToken;
  }

  @override
  int get hashCode => Object.hash(accessToken, refreshToken);

  @override
  String toString() =>
      'AuthTokens(accessToken: [REDACTED], refreshToken: [REDACTED])';
}
