import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:surplus_share/core/network/api_endpoints.dart';
import 'package:surplus_share/core/network/api_response_parser.dart';
import 'package:surplus_share/features/distribution/data/distribution_repository.dart';
import 'package:surplus_share/features/distribution/domain/models/distribution_failure.dart';
import 'package:surplus_share/features/distribution/domain/models/distribution_task.dart';

class RemoteDistributionRepository implements DistributionRepository {
  const new({required this._dio});

  final Dio _dio;

  @override
  Future<Either<DistributionFailure, List<DistributionTask>>> getTasks() async {
    try {
      final response = await _dio.get<dynamic>(ApiEndpoints.distributions);
      final rawList = ApiResponseParser.unwrapList(response.data);
      return right(
        List<DistributionTask>.unmodifiable([
          for (final item in rawList) DistributionTask.fromJson(item),
        ]),
      );
    } on DioException catch (e) {
      return left(_mapError(e));
    } on Object catch (e) {
      return left(DistributionValidationFailure(e.toString()));
    }
  }

  @override
  Future<Either<DistributionFailure, DistributionTask>> createTask(
    CreateDistributionInput input,
  ) {
    return _postSingle(
      ApiEndpoints.distributions,
      data: <String, dynamic>{
        'listing_id': input.listingId,
        'listing_title': input.listingTitle,
        'partner_id': input.partnerId,
        'partner_name': input.partnerName,
        'store_address': input.storeAddress,
        'store_location': input.storeLocation.toJson(),
        'recipient_id': input.recipientId,
        'recipient_name': input.recipientName,
        'recipient_address': input.recipientAddress,
        'recipient_location': input.recipientLocation.toJson(),
        'portions': input.portions,
      },
    );
  }

  @override
  Future<Either<DistributionFailure, DistributionTask>> acceptTask({
    required String taskId,
    required String volunteerId,
    required String volunteerName,
  }) {
    return _postSingle(ApiEndpoints.acceptDistribution(taskId));
  }

  @override
  Future<Either<DistributionFailure, DistributionTask>> markPickedUp({
    required String taskId,
    required String volunteerId,
    required String pin,
  }) {
    return _postSingle(
      ApiEndpoints.pickupDistribution(taskId),
      data: <String, dynamic>{'pin': pin.trim()},
    );
  }

  @override
  Future<Either<DistributionFailure, DistributionTask>> markDelivered({
    required String taskId,
    required String volunteerId,
    required String pin,
  }) {
    return _postSingle(
      ApiEndpoints.deliverDistribution(taskId),
      data: <String, dynamic>{'pin': pin.trim()},
    );
  }

  @override
  Future<Either<DistributionFailure, DistributionTask>> cancelTask({
    required String taskId,
  }) {
    return _postSingle(ApiEndpoints.cancelDistribution(taskId));
  }

  Future<Either<DistributionFailure, DistributionTask>> _postSingle(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await _dio.post<dynamic>(path, data: data);
      return right(
        DistributionTask.fromJson(ApiResponseParser.unwrapMap(response.data)),
      );
    } on DioException catch (e) {
      return left(_mapError(e));
    } on Object catch (e) {
      return left(DistributionValidationFailure(e.toString()));
    }
  }

  DistributionFailure _mapError(DioException e) {
    final status = e.response?.statusCode;
    final code = ApiResponseParser.extractErrorCode(e);
    final message = ApiResponseParser.extractErrorMessage(
      e,
      'Gagal memproses permintaan distribusi.',
    );

    if (status == 401 || status == 403) {
      return DistributionPermissionDeniedFailure(message);
    }
    if (status == 404 || code == 'DISTRIBUTION_NOT_FOUND') {
      return DistributionNotFoundFailure(message);
    }
    if (status == 423 || code == 'PIN_LOCKED') {
      return DistributionPinLockedFailure(message);
    }
    if (code == 'INVALID_PIN') {
      final raw = e.response?.data;
      final remaining = raw is Map && raw['remaining_attempts'] is num
          ? (raw['remaining_attempts'] as num).toInt()
          : 0;
      return InvalidDistributionPinFailure(
        remainingAttempts: remaining,
        message: message,
      );
    }
    if (status == 409 || code == 'INVALID_DISTRIBUTION_TRANSITION') {
      return InvalidDistributionTransitionFailure(message);
    }
    return DistributionValidationFailure(message);
  }
}
