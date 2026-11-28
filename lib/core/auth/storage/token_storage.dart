import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';

abstract interface class TokenStorage {
  Future<void> saveTokens(AuthTokens tokens);

  Future<AuthTokens?> getTokens();

  Future<String?> getAccessToken();

  Future<void> clearTokens();
}

class SecureTokenStorage implements TokenStorage {
  new(this._storage);

  static const accessTokenKey = 'auth_access_token';
  static const _legacyRefreshTokenKey = 'auth_refresh_token';

  final FlutterSecureStorage _storage;

  String? _cachedAccessToken;
  bool _accessCached = false;

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    await _storage.write(key: accessTokenKey, value: tokens.accessToken);
    _cachedAccessToken = tokens.accessToken;
    _accessCached = true;
  }

  @override
  Future<AuthTokens?> getTokens() async {
    final accessToken = await getAccessToken();
    if (accessToken == null) return null;
    return AuthTokens(accessToken: accessToken);
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
  Future<void> clearTokens() async {
    await Future.wait([
      _storage.delete(key: accessTokenKey),
      _storage.delete(key: _legacyRefreshTokenKey),
    ]);
    _cachedAccessToken = null;
    _accessCached = true;
  }
}
