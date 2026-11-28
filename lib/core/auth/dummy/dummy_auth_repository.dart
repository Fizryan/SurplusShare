import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fpdart/fpdart.dart';
import 'package:surplus_share/core/auth/models/auth_failure.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/auth/repository/auth_repository.dart';
import 'package:surplus_share/core/auth/storage/token_storage.dart';
import 'package:surplus_share/core/permission/app_role.dart';

@immutable
class DummyAuthAccount {
  const new({
    required this.id,
    required this.email,
    required this.role,
    required this.kycStatus,
    required this.displayName,
  });

  final String id;
  final String email;
  final AppRole role;
  final KycStatus kycStatus;
  final String displayName;
}

/// One debug-only demo Google account for each [AppRole].
abstract final class DummyAuthAccounts {
  static const consumer = DummyAuthAccount(
    id: 'usr-consumer-1',
    email: 'consumer@surplusshare.id',
    role: AppRole.consumer,
    kycStatus: KycStatus.unverified,
    displayName: 'Budi Konsumen',
  );

  static const verifiedRecipient = DummyAuthAccount(
    id: 'usr-recipient-1',
    email: 'recipient@surplusshare.id',
    role: AppRole.verifiedRecipient,
    kycStatus: KycStatus.approved,
    displayName: 'Panti Asuhan Harapan',
  );

  static const donorPartner = DummyAuthAccount(
    id: 'usr-partner-1',
    email: 'partner@surplusshare.id',
    role: AppRole.donorPartner,
    kycStatus: KycStatus.approved,
    displayName: 'Resto Nusantara',
  );

  static const volunteer = DummyAuthAccount(
    id: 'usr-volunteer-1',
    email: 'volunteer@surplusshare.id',
    role: AppRole.volunteer,
    kycStatus: KycStatus.approved,
    displayName: 'Relawan Distribusi',
  );

  static const admin = DummyAuthAccount(
    id: 'usr-admin-1',
    email: 'admin@surplusshare.id',
    role: AppRole.admin,
    kycStatus: KycStatus.approved,
    displayName: 'Admin Surplus Share',
  );

  static const List<DummyAuthAccount> all = [
    consumer,
    verifiedRecipient,
    donorPartner,
    volunteer,
    admin,
  ];
}

/// Debug-only in-memory [AuthRepository] used when `API_BASE_URL` is not set.
class DummyAuthRepository implements AuthRepository {
  new({required this._tokenStorage})
    : _accounts = List<DummyAuthAccount>.of(DummyAuthAccounts.all);

  final TokenStorage _tokenStorage;
  final List<DummyAuthAccount> _accounts;

  @override
  Future<Either<AuthFailure, AuthTokens>> signInWithGoogle({
    String? debugAccountId,
  }) async {
    final account = debugAccountId == null
        ? DummyAuthAccounts.consumer
        : _findById(debugAccountId);
    if (account == null) {
      return left(const UnauthorizedFailure('Akun demo tidak ditemukan.'));
    }

    return await _issueAndStoreTokens(account);
  }

  @override
  Future<Either<AuthFailure, Unit>> logout() async {
    try {
      await _tokenStorage.clearTokens();
      return right(unit);
    } on PlatformException catch (e) {
      return left(StorageFailure(e.message ?? 'Gagal menghapus token aman.'));
    } on Object catch (e) {
      return left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<AuthFailure, AuthTokens?>> restoreSession() async {
    try {
      final tokens = await _tokenStorage.getTokens();
      return right(tokens);
    } on PlatformException catch (e) {
      return left(StorageFailure(e.message ?? 'Gagal membaca sesi tersimpan.'));
    } on Object catch (e) {
      return left(UnknownFailure(e.toString()));
    }
  }

  Future<Either<AuthFailure, AuthTokens>> _issueAndStoreTokens(
    DummyAuthAccount account,
  ) async {
    try {
      final tokens = _buildTokens(account);
      await _tokenStorage.saveTokens(tokens);
      return right(tokens);
    } on PlatformException catch (e) {
      return left(StorageFailure(e.message ?? 'Gagal menyimpan token aman.'));
    } on Object catch (e) {
      return left(UnknownFailure(e.toString()));
    }
  }

  AuthTokens _buildTokens(DummyAuthAccount account) {
    final now = DateTime.now().toUtc();
    final exp = now.add(const Duration(hours: 2));
    final accessToken = _encodeJwt({
      'sub': account.id,
      'email': account.email,
      'name': account.displayName,
      'role': account.role.name,
      'kyc_status': account.kycStatus.name,
      'exp': exp.millisecondsSinceEpoch ~/ 1000,
    });

    return AuthTokens(accessToken: accessToken);
  }

  DummyAuthAccount? _findById(String id) {
    for (final account in _accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  static String _encodeJwt(Map<String, dynamic> payload) {
    final header = base64Url
        .encode(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})))
        .replaceAll('=', '');
    final body = base64Url
        .encode(utf8.encode(jsonEncode(payload)))
        .replaceAll('=', '');
    return '$header.$body.dummy-signature';
  }
}
