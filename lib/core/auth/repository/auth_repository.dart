import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:fpdart/fpdart.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:surplus_share/core/auth/google/google_auth_client.dart';
import 'package:surplus_share/core/auth/models/auth_failure.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/auth/storage/token_storage.dart';
import 'package:surplus_share/core/network/api_endpoints.dart';
import 'package:surplus_share/core/network/api_response_parser.dart';

abstract interface class AuthRepository {
  /// Signs in (or registers on first login) via Google OAuth and exchanges
  /// the Google ID token for an application session token.
  ///
  /// [debugAccountId] is only honored by `DummyAuthRepository` in debug mode.
  Future<Either<AuthFailure, AuthTokens>> signInWithGoogle({
    String? debugAccountId,
  });

  Future<Either<AuthFailure, Unit>> logout();

  Future<Either<AuthFailure, AuthTokens?>> restoreSession();
}

class AuthRepositoryImpl implements AuthRepository {
  const new({
    required this._dio,
    required this._tokenStorage,
    required this._googleAuthClient,
  });

  final Dio _dio;
  final TokenStorage _tokenStorage;
  final GoogleAuthClient _googleAuthClient;

  @override
  Future<Either<AuthFailure, AuthTokens>> signInWithGoogle({
    String? debugAccountId,
  }) async {
    try {
      final credential = await _googleAuthClient.signIn();
      final response = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.googleAuth,
        data: <String, dynamic>{
          'id_token': credential.idToken,
          if (credential.googleId != null) 'google_id': credential.googleId,
          'email': credential.email,
          if (credential.displayName != null) 'name': credential.displayName,
          if (credential.photoUrl != null) 'picture': credential.photoUrl,
        },
      );

      final data = response.data;
      if (data == null) {
        return left(
          const ServerFailure('Respons autentikasi kosong dari server.'),
        );
      }

      final tokens = AuthTokens.fromJson(data);
      await _tokenStorage.saveTokens(tokens);
      return right(tokens);
    } on GoogleAuthCancelledException {
      return left(const AuthCancelledFailure());
    } on GoogleSignInException catch (e) {
      return left(UnknownFailure(e.description ?? 'Autentikasi Google gagal.'));
    } on DioException catch (e) {
      return left(_mapDioException(e));
    } on FormatException catch (e) {
      return left(ServerFailure(e.message));
    } on PlatformException catch (e) {
      return left(StorageFailure(e.message ?? 'Gagal menyimpan token aman.'));
    } on Object catch (e) {
      return left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<AuthFailure, Unit>> logout() async {
    try {
      final accessToken = await _tokenStorage.getAccessToken();
      if (accessToken != null && accessToken.isNotEmpty) {
        try {
          await _dio.post<dynamic>(
            ApiEndpoints.logout,
            options: Options(
              headers: <String, dynamic>{
                'Authorization': 'Bearer $accessToken',
              },
            ),
          );
        } on DioException {
          // Best-effort server revocation; local token cleanup still runs.
        }
      }
      await _googleAuthClient.signOut();
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

  AuthFailure _mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
        return const NetworkFailure();
      case DioExceptionType.badCertificate:
        return const NetworkFailure('Sertifikat keamanan server tidak valid.');
      case DioExceptionType.cancel:
        return const UnknownFailure('Permintaan dibatalkan.');
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        final fallback = statusCode == 401
            ? 'Kredensial tidak valid atau sesi telah berakhir.'
            : 'Terjadi kesalahan pada server.';
        final serverMessage = ApiResponseParser.extractErrorMessage(
          e,
          fallback,
        );
        if (statusCode == 401) {
          return UnauthorizedFailure(serverMessage);
        }
        return ServerFailure(serverMessage, statusCode: statusCode);
      case DioExceptionType.unknown:
        return UnknownFailure(e.message ?? 'Terjadi kesalahan jaringan.');
    }
  }
}
