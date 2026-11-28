import 'package:flutter/foundation.dart';

@immutable
class ApiConfig {
  const new({
    required this.baseUrl,
    this.googleClientId = '',
    this.googleServerClientId = '',
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 15),
    this.sendTimeout = const Duration(seconds: 15),
  });

  const new fromEnvironment()
    : baseUrl = const String.fromEnvironment('API_BASE_URL'),
      googleClientId = const String.fromEnvironment('GOOGLE_CLIENT_ID'),
      googleServerClientId = const String.fromEnvironment(
        'GOOGLE_SERVER_CLIENT_ID',
      ),
      connectTimeout = const Duration(seconds: 15),
      receiveTimeout = const Duration(seconds: 15),
      sendTimeout = const Duration(seconds: 15);

  final String baseUrl;
  final String googleClientId;
  final String googleServerClientId;
  final Duration connectTimeout;
  final Duration receiveTimeout;
  final Duration sendTimeout;

  String? get effectiveGoogleClientId =>
      googleClientId.trim().isEmpty ? null : googleClientId.trim();

  String? get effectiveGoogleServerClientId =>
      googleServerClientId.trim().isEmpty ? null : googleServerClientId.trim();

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  /// Demo mode is ONLY enabled in debug builds when `API_BASE_URL` is unset.
  /// Always `false` in `--release` and `--profile` builds.
  bool get isDemoMode => kDebugMode && !isConfigured;

  bool get isSecure {
    final uri = Uri.tryParse(baseUrl.trim());
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  /// Validates that [baseUrl] is configured and uses HTTPS when required.
  void validate({bool requireHttps = kReleaseMode}) {
    if (!isConfigured) {
      throw StateError(
        'API_BASE_URL belum dikonfigurasi. '
        'Jalankan dengan --dart-define=API_BASE_URL=https://...',
      );
    }
    if (requireHttps && !isSecure) {
      throw StateError(
        'API_BASE_URL wajib menggunakan HTTPS pada environment ini.',
      );
    }
  }
}
