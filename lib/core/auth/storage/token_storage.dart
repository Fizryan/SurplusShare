import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';

abstract interface class TokenStorage {
  Future<void> saveTokens(AuthTokens tokens);

  Future<AuthTokens?> getTokens();

  Future<String?> getAccessToken();

  Future<String?> getRefreshToken();

  Future<void> clearTokens();
}

class SecureTokenStorage implements TokenStorage {
  new(this._storage);

  static const accessTokenKey = 'auth_access_token';
  static const refreshTokenKey = 'auth_refresh_token';

  final FlutterSecureStorage _storage;

  String? _cachedAccessToken;
  String? _cachedRefreshToken;
  bool _accessCached = false;
  bool _refreshCached = false;

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    await Future.wait([
      _storage.write(key: accessTokenKey, value: tokens.accessToken),
      _storage.write(key: refreshTokenKey, value: tokens.refreshToken),
    ]);
    _cachedAccessToken = tokens.accessToken;
    _cachedRefreshToken = tokens.refreshToken;
    _accessCached = true;
    _refreshCached = true;
  }

  @override
  Future<AuthTokens?> getTokens() async {
    final results = await Future.wait([getAccessToken(), getRefreshToken()]);
    final accessToken = results[0];
    final refreshToken = results[1];

    if (accessToken == null || refreshToken == null) {
      return null;
    }

    return AuthTokens(accessToken: accessToken, refreshToken: refreshToken);
  }

  @override
  Future<String?> getAccessToken() async {
    if (_accessCached) return _cachedAccessToken;
    final raw = (await _storage.read(key: accessTokenKey))?.trim();
    final token = (raw == null || raw.isEmpty) ? null : raw;
    _cachedAccessToken = token;
    _accessCached = true;
    return token;
  }

  @override
  Future<String?> getRefreshToken() async {
    if (_refreshCached) return _cachedRefreshToken;
    final raw = (await _storage.read(key: refreshTokenKey))?.trim();
    final token = (raw == null || raw.isEmpty) ? null : raw;
    _cachedRefreshToken = token;
    _refreshCached = true;
    return token;
  }

  @override
  Future<void> clearTokens() async {
    await Future.wait([
      _storage.delete(key: accessTokenKey),
      _storage.delete(key: refreshTokenKey),
    ]);
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    _accessCached = true;
    _refreshCached = true;
  }
}
