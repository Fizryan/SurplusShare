import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:surplus_share/core/network/api_endpoints.dart';
import 'package:surplus_share/core/network/api_response_parser.dart';
import 'package:surplus_share/features/listing/data/listing_repository.dart';
import 'package:surplus_share/features/listing/domain/models/create_listing_input.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/listing/domain/models/listing_failure.dart';
import 'package:surplus_share/features/listing/domain/models/surplus_listing.dart';

class RemoteListingRepository implements ListingRepository {
  const new({required this._dio});

  final Dio _dio;

  @override
  Future<Either<ListingFailure, List<SurplusListing>>> getListings({
    ListingChannel? channel,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        ApiEndpoints.listings,
        queryParameters: channel == null
            ? null
            : <String, dynamic>{'channel': channel.name},
      );
      final rawList = ApiResponseParser.unwrapList(response.data);
      return right(
        List<SurplusListing>.unmodifiable([
          for (final json in rawList) SurplusListing.fromJson(json),
        ]),
      );
    } on DioException catch (e) {
      return left(_mapError(e));
    } on Object catch (e) {
      return left(ListingValidationFailure(e.toString()));
    }
  }

  @override
  Future<Either<ListingFailure, SurplusListing>> createListing(
    CreateListingInput input,
  ) async {
    try {
      final response = await _dio.post<dynamic>(
        ApiEndpoints.listings,
        data: <String, dynamic>{
          'partner_id': input.partnerId,
          'partner_name': input.partnerName,
          'title': input.title,
          'description': input.description,
          'channel': input.channel.name,
          if (input.discountFormat != null)
            'discount_format': input.discountFormat!.name,
          'original_price': input.originalPrice,
          'discounted_price': input.discountedPrice,
          'quantity': input.quantity,
          'pickup_start': input.pickupStart.toUtc().toIso8601String(),
          'pickup_end': input.pickupEnd.toUtc().toIso8601String(),
          if (input.address != null && input.address!.trim().isNotEmpty)
            'address': input.address!.trim(),
          if (input.location != null) 'location': input.location!.toJson(),
          if (input.foodSafety != null)
            'food_safety': input.foodSafety!.toJson(),
        },
      );
      return right(
        SurplusListing.fromJson(ApiResponseParser.unwrapMap(response.data)),
      );
    } on DioException catch (e) {
      return left(_mapError(e));
    } on Object catch (e) {
      return left(ListingValidationFailure(e.toString()));
    }
  }

  @override
  Future<Either<ListingFailure, SurplusListing>> convertToDonation({
    required String listingId,
  }) {
    return _postSingle(ApiEndpoints.convertListingToDonation(listingId));
  }

  @override
  Future<Either<ListingFailure, SurplusListing>> claimStock({
    required String listingId,
    required int quantity,
  }) {
    return _postSingle(
      ApiEndpoints.claimListingStock(listingId),
      data: <String, dynamic>{'quantity': quantity},
    );
  }

  @override
  Future<Either<ListingFailure, SurplusListing>> releaseStock({
    required String listingId,
    required int quantity,
  }) {
    return _postSingle(
      ApiEndpoints.releaseListingStock(listingId),
      data: <String, dynamic>{'quantity': quantity},
    );
  }

  @override
  Future<Either<ListingFailure, SurplusListing>> closeListing({
    required String listingId,
  }) {
    return _postSingle(ApiEndpoints.closeListing(listingId));
  }

  Future<Either<ListingFailure, SurplusListing>> _postSingle(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await _dio.post<dynamic>(path, data: data);
      return right(
        SurplusListing.fromJson(ApiResponseParser.unwrapMap(response.data)),
      );
    } on DioException catch (e) {
      return left(_mapError(e));
    } on Object catch (e) {
      return left(ListingValidationFailure(e.toString()));
    }
  }

  ListingFailure _mapError(DioException e) {
    final status = e.response?.statusCode;
    final code = ApiResponseParser.extractErrorCode(e);
    final message = ApiResponseParser.extractErrorMessage(
      e,
      'Gagal memproses permintaan listing.',
    );

    if (status == 401 || status == 403) {
      return ListingPermissionDeniedFailure(message);
    }
    if (status == 404) return ListingNotFoundFailure(message);
    if (code == 'LISTING_EXPIRED') return ListingExpiredFailure(message);
    if (status == 409 || code == 'INSUFFICIENT_STOCK') {
      return InsufficientStockFailure(message);
    }
    return ListingValidationFailure(message);
  }
}
