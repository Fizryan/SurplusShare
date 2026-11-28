import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:surplus_share/core/auth/dummy/dummy_auth_repository.dart';
import 'package:surplus_share/core/network/api_endpoints.dart';
import 'package:surplus_share/core/network/api_response_parser.dart';
import 'package:surplus_share/core/permission/app_role.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/features/location/domain/models/geo_point.dart';
import 'package:surplus_share/features/location/domain/models/location_failure.dart';
import 'package:surplus_share/features/location/domain/models/pinned_location.dart';

abstract interface class PinnedLocationRepository {
  Future<Either<LocationFailure, PinnedLocation?>> getPinnedLocation(
    String ownerId,
  );

  Future<Either<LocationFailure, PinnedLocation>> savePinnedLocation(
    PinnedLocation location,
  );

  Future<Either<LocationFailure, List<PinnedLocation>>>
  getVerifiedRecipientLocations();
}

class InMemoryPinnedLocationRepository implements PinnedLocationRepository {
  new({Map<String, PinnedLocation>? seed, Clock? clock})
    : _clock = clock ?? DateTime.now,
      _items = Map<String, PinnedLocation>.of(
        seed ?? _defaultSeed((clock ?? DateTime.now)()),
      );

  final Clock _clock;
  final Map<String, PinnedLocation> _items;

  @override
  Future<Either<LocationFailure, PinnedLocation?>> getPinnedLocation(
    String ownerId,
  ) async {
    return right(_items[ownerId]);
  }

  @override
  Future<Either<LocationFailure, PinnedLocation>> savePinnedLocation(
    PinnedLocation location,
  ) async {
    final error = location.validate();
    if (error != null) {
      return left(LocationUnknownFailure(error));
    }

    final saved = location.copyWith(
      placeName: location.placeName.trim(),
      address: location.address.trim(),
      updatedAt: _clock().toUtc(),
    );
    _items[saved.ownerId] = saved;
    return right(saved);
  }

  @override
  Future<Either<LocationFailure, List<PinnedLocation>>>
  getVerifiedRecipientLocations() async {
    final recipients = _items.values
        .where((loc) => loc.ownerRole == AppRole.verifiedRecipient)
        .toList(growable: false);
    return right(List<PinnedLocation>.unmodifiable(recipients));
  }

  static Map<String, PinnedLocation> _defaultSeed(DateTime referenceTime) {
    final now = referenceTime.toUtc();
    return {
      DummyAuthAccounts.donorPartner.id: PinnedLocation(
        ownerId: DummyAuthAccounts.donorPartner.id,
        ownerRole: AppRole.donorPartner,
        placeName: DummyAuthAccounts.donorPartner.displayName,
        address: 'Jl. Sudirman No. 10, Jakarta Pusat',
        point: const GeoPoint(latitude: -6.2088, longitude: 106.8456),
        updatedAt: now,
      ),
      DummyAuthAccounts.verifiedRecipient.id: PinnedLocation(
        ownerId: DummyAuthAccounts.verifiedRecipient.id,
        ownerRole: AppRole.verifiedRecipient,
        placeName: DummyAuthAccounts.verifiedRecipient.displayName,
        address: 'Jl. Tebet Timur Dalam No. 18, Jakarta Selatan',
        point: const GeoPoint(latitude: -6.2297, longitude: 106.8570),
        updatedAt: now,
      ),
    };
  }
}

class RemotePinnedLocationRepository implements PinnedLocationRepository {
  const new({required this._dio});

  final Dio _dio;

  @override
  Future<Either<LocationFailure, PinnedLocation?>> getPinnedLocation(
    String ownerId,
  ) async {
    try {
      final response = await _dio.get<dynamic>(ApiEndpoints.myPinnedLocation);
      final raw = response.data;
      if (raw == null) return right(null);
      if (raw is Map && raw['data'] == null) return right(null);
      return right(PinnedLocation.fromJson(ApiResponseParser.unwrapMap(raw)));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return right(null);
      return left(
        LocationUnknownFailure(
          ApiResponseParser.extractErrorMessage(
            e,
            'Gagal memuat titik lokasi tetap.',
          ),
        ),
      );
    } on Object catch (e) {
      return left(LocationUnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<LocationFailure, PinnedLocation>> savePinnedLocation(
    PinnedLocation location,
  ) async {
    final error = location.validate();
    if (error != null) {
      return left(LocationUnknownFailure(error));
    }

    try {
      final response = await _dio.put<dynamic>(
        ApiEndpoints.myPinnedLocation,
        data: <String, dynamic>{
          'place_name': location.placeName.trim(),
          'address': location.address.trim(),
          'point': location.point.toJson(),
        },
      );
      return right(
        PinnedLocation.fromJson(ApiResponseParser.unwrapMap(response.data)),
      );
    } on DioException catch (e) {
      return left(
        LocationUnknownFailure(
          ApiResponseParser.extractErrorMessage(
            e,
            'Gagal menyimpan titik lokasi tetap.',
          ),
        ),
      );
    } on Object catch (e) {
      return left(LocationUnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<LocationFailure, List<PinnedLocation>>>
  getVerifiedRecipientLocations() async {
    try {
      final response = await _dio.get<dynamic>(
        ApiEndpoints.verifiedRecipientLocations,
      );
      final rawList = ApiResponseParser.unwrapList(response.data);
      return right(
        List<PinnedLocation>.unmodifiable([
          for (final item in rawList) PinnedLocation.fromJson(item),
        ]),
      );
    } on DioException catch (e) {
      return left(
        LocationUnknownFailure(
          ApiResponseParser.extractErrorMessage(
            e,
            'Gagal memuat daftar lokasi penerima terverifikasi.',
          ),
        ),
      );
    } on Object catch (e) {
      return left(LocationUnknownFailure(e.toString()));
    }
  }
}
