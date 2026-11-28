import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:surplus_share/core/network/api_endpoints.dart';
import 'package:surplus_share/core/network/api_response_parser.dart';
import 'package:surplus_share/features/listing/domain/models/surplus_listing.dart';
import 'package:surplus_share/features/reservation/data/reservation_repository.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation_failure.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation_status.dart';

class RemoteReservationRepository implements ReservationRepository {
  const new({required this._dio});

  final Dio _dio;

  @override
  Future<Either<ReservationFailure, Reservation>> createDiscountReservation({
    required SurplusListing listing,
    required String customerId,
    required int quantity,
    required PaymentMethod paymentMethod,
  }) {
    return _postSingle(
      ApiEndpoints.discountReservation,
      data: <String, dynamic>{
        'listing_id': listing.id,
        'quantity': quantity,
        'payment_method': paymentMethod.name,
      },
    );
  }

  @override
  Future<Either<ReservationFailure, Reservation>> createDonationReservation({
    required SurplusListing listing,
    required String customerId,
    required int quantity,
    bool bypassQuota = false,
  }) {
    return _postSingle(
      ApiEndpoints.donationReservation,
      data: <String, dynamic>{'listing_id': listing.id, 'quantity': quantity},
    );
  }

  @override
  Future<Either<ReservationFailure, Reservation>> confirmPayment({
    required String reservationId,
  }) {
    return _postSingle(ApiEndpoints.confirmReservationPayment(reservationId));
  }

  @override
  Future<Either<ReservationFailure, Reservation>> cancelReservation({
    required String reservationId,
  }) {
    return _postSingle(ApiEndpoints.cancelReservation(reservationId));
  }

  @override
  Future<Either<ReservationFailure, Reservation>> validatePickupPin({
    required String reservationId,
    required String pin,
    required String staffId,
  }) {
    return _postSingle(
      ApiEndpoints.validateReservationPin(reservationId),
      data: <String, dynamic>{'pin': pin},
    );
  }

  @override
  Future<Either<ReservationFailure, List<Reservation>>> getReservationsForUser(
    String userId,
  ) {
    return _getList(ApiEndpoints.myReservations);
  }

  @override
  Future<Either<ReservationFailure, List<Reservation>>>
  getReservationsForPartner(String partnerId) {
    return _getList(ApiEndpoints.partnerReservations);
  }

  @override
  Future<void> reconcileExpired() async {
    // Server-side cron / transactional checks reconcile expired reservations.
  }

  Future<Either<ReservationFailure, Reservation>> _postSingle(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await _dio.post<dynamic>(path, data: data);
      return right(
        Reservation.fromJson(ApiResponseParser.unwrapMap(response.data)),
      );
    } on DioException catch (e) {
      return left(_mapError(e));
    } on Object catch (e) {
      return left(ReservationValidationFailure(e.toString()));
    }
  }

  Future<Either<ReservationFailure, List<Reservation>>> _getList(
    String path,
  ) async {
    try {
      final response = await _dio.get<dynamic>(path);
      final rawList = ApiResponseParser.unwrapList(response.data);
      return right(
        List<Reservation>.unmodifiable([
          for (final json in rawList) Reservation.fromJson(json),
        ]),
      );
    } on DioException catch (e) {
      return left(_mapError(e));
    } on Object catch (e) {
      return left(ReservationValidationFailure(e.toString()));
    }
  }

  ReservationFailure _mapError(DioException e) {
    final status = e.response?.statusCode;
    final code = ApiResponseParser.extractErrorCode(e);
    final message = ApiResponseParser.extractErrorMessage(
      e,
      'Gagal memproses reservasi.',
    );

    if (status == 401 || status == 403) {
      return ReservationPermissionDeniedFailure(message);
    }
    if (status == 404) return ReservationNotFoundFailure(message);
    if (code == 'PIN_LOCKED' || status == 423) {
      return PinLockedFailure(message);
    }
    if (code == 'INVALID_PIN') {
      final data = e.response?.data;
      final remaining = data is Map && data['remaining_attempts'] is num
          ? (data['remaining_attempts'] as num).toInt()
          : 0;
      return InvalidPinFailure(remainingAttempts: remaining);
    }
    if (code == 'PAYMENT_EXPIRED' || code == 'RESERVATION_EXPIRED') {
      return PaymentExpiredFailure(message);
    }
    return ReservationValidationFailure(message);
  }
}
