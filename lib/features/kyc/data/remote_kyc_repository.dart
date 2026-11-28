import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:surplus_share/core/network/api_endpoints.dart';
import 'package:surplus_share/core/network/api_response_parser.dart';
import 'package:surplus_share/features/kyc/data/kyc_repository.dart';
import 'package:surplus_share/features/kyc/domain/models/daily_donation_quota.dart';
import 'package:surplus_share/features/kyc/domain/models/kyc_application.dart';
import 'package:surplus_share/features/kyc/domain/models/kyc_failure.dart';
import 'package:surplus_share/features/kyc/domain/models/submit_kyc_input.dart';

class RemoteKycRepository implements KycRepository {
  const new({required this._dio});

  final Dio _dio;

  @override
  Future<Either<KycFailure, KycApplication?>> getApplicationForUser(
    String userId,
  ) async {
    try {
      final response = await _dio.get<dynamic>(ApiEndpoints.myKyc);
      final map = ApiResponseParser.unwrapNullableMap(response.data);
      return right(map == null ? null : KycApplication.fromJson(map));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return right(null);
      return left(_mapError(e));
    } on Object catch (e) {
      return left(KycValidationFailure(e.toString()));
    }
  }

  @override
  Future<Either<KycFailure, List<KycApplication>>>
  getPendingApplications() async {
    try {
      final response = await _dio.get<dynamic>(
        ApiEndpoints.pendingKycApplications,
      );
      final rawList = ApiResponseParser.unwrapList(response.data);
      return right(
        List<KycApplication>.unmodifiable([
          for (final json in rawList) KycApplication.fromJson(json),
        ]),
      );
    } on DioException catch (e) {
      return left(_mapError(e));
    } on Object catch (e) {
      return left(KycValidationFailure(e.toString()));
    }
  }

  @override
  Future<Either<KycFailure, KycApplication>> submitApplication(
    SubmitKycInput input,
  ) async {
    try {
      final response = await _dio.post<dynamic>(
        ApiEndpoints.kycApplications,
        data: <String, dynamic>{
          'organization_name': input.organizationName,
          'category': input.category.name,
          if (input.registrationNumber != null)
            'registration_number': input.registrationNumber,
          'address': input.address,
          'contact_phone': input.contactPhone,
          'beneficiary_count': input.beneficiaryCount,
          'documents': [for (final doc in input.documents) doc.toJson()],
        },
      );
      return right(
        KycApplication.fromJson(ApiResponseParser.unwrapMap(response.data)),
      );
    } on DioException catch (e) {
      return left(_mapError(e));
    } on Object catch (e) {
      return left(KycValidationFailure(e.toString()));
    }
  }

  @override
  Future<Either<KycFailure, KycApplication>> approveApplication({
    required String applicationId,
    required String reviewerId,
    required int dailyQuota,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        ApiEndpoints.approveKyc(applicationId),
        data: <String, dynamic>{'daily_quota': dailyQuota},
      );
      return right(
        KycApplication.fromJson(ApiResponseParser.unwrapMap(response.data)),
      );
    } on DioException catch (e) {
      return left(_mapError(e));
    } on Object catch (e) {
      return left(KycValidationFailure(e.toString()));
    }
  }

  @override
  Future<Either<KycFailure, KycApplication>> rejectApplication({
    required String applicationId,
    required String reviewerId,
    required String reason,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        ApiEndpoints.rejectKyc(applicationId),
        data: <String, dynamic>{'reason': reason},
      );
      return right(
        KycApplication.fromJson(ApiResponseParser.unwrapMap(response.data)),
      );
    } on DioException catch (e) {
      return left(_mapError(e));
    } on Object catch (e) {
      return left(KycValidationFailure(e.toString()));
    }
  }

  @override
  Future<Either<KycFailure, DailyDonationQuota>> getDailyQuota(
    String userId,
  ) async {
    try {
      final response = await _dio.get<dynamic>(ApiEndpoints.myDailyQuota);
      return right(
        DailyDonationQuota.fromJson(ApiResponseParser.unwrapMap(response.data)),
      );
    } on DioException catch (e) {
      return left(_mapError(e));
    } on Object catch (e) {
      return left(KycValidationFailure(e.toString()));
    }
  }

  @override
  Future<Either<KycFailure, DailyDonationQuota>> consumeDailyQuota({
    required String userId,
    required int quantity,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        ApiEndpoints.consumeDailyQuota,
        data: <String, dynamic>{'quantity': quantity},
      );
      return right(
        DailyDonationQuota.fromJson(ApiResponseParser.unwrapMap(response.data)),
      );
    } on DioException catch (e) {
      return left(_mapError(e));
    } on Object catch (e) {
      return left(KycValidationFailure(e.toString()));
    }
  }

  @override
  Future<Either<KycFailure, DailyDonationQuota>> refundDailyQuota({
    required String userId,
    required int quantity,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        ApiEndpoints.refundDailyQuota,
        data: <String, dynamic>{'quantity': quantity},
      );
      return right(
        DailyDonationQuota.fromJson(ApiResponseParser.unwrapMap(response.data)),
      );
    } on DioException catch (e) {
      return left(_mapError(e));
    } on Object catch (e) {
      return left(KycValidationFailure(e.toString()));
    }
  }

  KycFailure _mapError(DioException e) {
    final status = e.response?.statusCode;
    final code = ApiResponseParser.extractErrorCode(e);
    final message = ApiResponseParser.extractErrorMessage(
      e,
      'Gagal memproses permintaan KYC.',
    );

    if (status == 401 || status == 403) {
      return KycPermissionDeniedFailure(message);
    }
    if (status == 404) return KycNotFoundFailure(message);
    if (status == 409 || code == 'KYC_ALREADY_SUBMITTED') {
      return KycAlreadySubmittedFailure(message);
    }
    return KycValidationFailure(message);
  }
}
