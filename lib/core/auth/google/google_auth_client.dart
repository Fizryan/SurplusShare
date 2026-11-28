import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

@immutable
class GoogleAuthCredential {
  const new({
    required this.idToken,
    required this.email,
    this.displayName,
    this.photoUrl,
  });

  final String idToken;
  final String email;
  final String? displayName;
  final String? photoUrl;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GoogleAuthCredential &&
        other.idToken == idToken &&
        other.email == email &&
        other.displayName == displayName &&
        other.photoUrl == photoUrl;
  }

  @override
  int get hashCode => Object.hash(idToken, email, displayName, photoUrl);
}

/// Exception thrown when the user cancels interactive Google Sign-In.
class GoogleAuthCancelledException implements Exception {
  const new();
}

/// Injectable boundary around `google_sign_in` for testability and SRP.
abstract interface class GoogleAuthClient {
  Future<GoogleAuthCredential> signIn();

  Future<void> signOut();
}

/// Production implementation backed by `google_sign_in` v7 singleton API.
class GoogleSignInClient implements GoogleAuthClient {
  new({this._clientId, this._serverClientId, GoogleSignIn? googleSignIn})
    : _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final String? _clientId;
  final String? _serverClientId;
  final GoogleSignIn _googleSignIn;

  Future<void>? _initFuture;

  Future<void> _ensureInitialized() {
    final existing = _initFuture;
    if (existing != null) return existing;
    final future = _googleSignIn.initialize(
      clientId: _clientId,
      serverClientId: _serverClientId,
    );
    _initFuture = future;
    return future.catchError((Object error, StackTrace stack) {
      if (identical(_initFuture, future)) {
        _initFuture = null;
      }
      Error.throwWithStackTrace(error, stack);
    });
  }

  @override
  Future<GoogleAuthCredential> signIn() async {
    await _ensureInitialized();

    if (!_googleSignIn.supportsAuthenticate()) {
      throw UnsupportedError(
        'Platform ini belum mendukung Google Sign-In interaktif.',
      );
    }

    try {
      final account = await _googleSignIn.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.trim().isEmpty) {
        throw const FormatException(
          'Google ID token tidak tersedia. Periksa konfigurasi OAuth client.',
        );
      }
      return GoogleAuthCredential(
        idToken: idToken,
        email: account.email,
        displayName: account.displayName,
        photoUrl: account.photoUrl,
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        throw const GoogleAuthCancelledException();
      }
      rethrow;
    }
  }

  @override
  Future<void> signOut() async {
    if (_initFuture == null) return;
    try {
      await _initFuture;
      await _googleSignIn.signOut();
    } on Object {
      // Best-effort Google sign-out; local JWT cleanup still runs.
    }
  }
}
