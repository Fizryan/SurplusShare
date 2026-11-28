import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:surplus_share/core/config/api_config.dart';
import 'package:surplus_share/core/network/api_endpoints.dart';
import 'package:surplus_share/features/kyc/data/remote_kyc_repository.dart';
import 'package:surplus_share/features/kyc/domain/models/kyc_failure.dart';
import 'package:surplus_share/features/listing/data/remote_listing_repository.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/listing/domain/models/listing_failure.dart';
import 'package:surplus_share/features/reservation/data/remote_reservation_repository.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation_failure.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation_status.dart';

class _MockDio extends Mock implements Dio;

void main() {
  late _MockDio dio;

  setUp(() {
    dio = _MockDio();
  });

  group('ApiConfig.isDemoMode', () {
    test('is true in debug when API_BASE_URL is empty, false when set', () {
      expect(const ApiConfig(baseUrl: '').isDemoMode, isTrue);
      expect(
        const ApiConfig(baseUrl: 'https://api.surplusshare.id').isDemoMode,
        isFalse,
      );
    });
  });

  group('RemoteListingRepository', () {
    test('parses GET /listings envelope and maps 409 stock conflict', () async {
      final repo = RemoteListingRepository(dio: dio);
      when(() => dio.get<dynamic>(ApiEndpoints.listings)).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: ApiEndpoints.listings),
          statusCode: 200,
          data: {
            'data': [
              {
                'id': 'lst-1',
                'partner_id': 'p-1',
                'partner_name': 'Resto A',
                'title': 'Nasi Box',
                'description': 'Segar',
                'channel': 'discount',
                'discount_format': 'flashSale',
                'original_price': 40000,
                'discounted_price': 20000,
                'total_quantity': 5,
                'remaining_quantity': 3,
                'pickup_window': {
                  'start': '2026-11-28T11:00:00Z',
                  'end': '2026-11-28T13:00:00Z',
                },
                'status': 'active',
                'created_at': '2026-11-28T10:00:00Z',
              },
            ],
          },
        ),
      );

      final res = await repo.getListings();
      expect(res.isRight(), isTrue);
      final items = res.getOrElse((_) => []);
      expect(items.length, 1);
      expect(items.first.id, 'lst-1');
      expect(items.first.channel, ListingChannel.discount);

      when(
        () => dio.post<dynamic>(
          ApiEndpoints.claimListingStock('lst-1'),
          data: {'quantity': 10},
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(
            path: ApiEndpoints.claimListingStock('lst-1'),
          ),
          response: Response<dynamic>(
            requestOptions: RequestOptions(
              path: ApiEndpoints.claimListingStock('lst-1'),
            ),
            statusCode: 409,
            data: {'code': 'INSUFFICIENT_STOCK', 'message': 'Stok habis'},
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final conflict = await repo.claimStock(listingId: 'lst-1', quantity: 10);
      expect(conflict.isLeft(), isTrue);
      conflict.fold(
        (f) => expect(f, isA<InsufficientStockFailure>()),
        (_) => fail('Expected Left'),
      );
    });
  });

  group('RemoteKycRepository', () {
    test('parses GET /kyc/quota/me and returns null on 404 /kyc/me', () async {
      final repo = RemoteKycRepository(dio: dio);
      when(() => dio.get<dynamic>(ApiEndpoints.myKyc)).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: ApiEndpoints.myKyc),
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: ApiEndpoints.myKyc),
            statusCode: 404,
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final myKyc = await repo.getApplicationForUser('u-1');
      expect(myKyc.isRight(), isTrue);
      expect(myKyc.getOrElse((_) => throw StateError('')), isNull);

      when(() => dio.get<dynamic>(ApiEndpoints.myDailyQuota)).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: ApiEndpoints.myDailyQuota),
          statusCode: 200,
          data: {
            'data': {
              'user_id': 'u-1',
              'date_key': '2026-11-28',
              'daily_limit': 30,
              'used_today': 5,
            },
          },
        ),
      );

      final quota = await repo.getDailyQuota('u-1');
      expect(quota.isRight(), isTrue);
      expect(quota.getOrElse((_) => throw StateError('')).remaining, 25);

      when(() => dio.get<dynamic>(ApiEndpoints.pendingKycApplications))
          .thenThrow(
            DioException(
              requestOptions: RequestOptions(
                path: ApiEndpoints.pendingKycApplications,
              ),
              response: Response<dynamic>(
                requestOptions: RequestOptions(
                  path: ApiEndpoints.pendingKycApplications,
                ),
                statusCode: 403,
              ),
              type: DioExceptionType.badResponse,
            ),
          );
      final denied = await repo.getPendingApplications();
      denied.fold(
        (f) => expect(f, isA<KycPermissionDeniedFailure>()),
        (_) => fail('Expected Left'),
      );
    });
  });

  group('RemoteReservationRepository', () {
    test('parses reservation list and maps 423 PIN_LOCKED', () async {
      final repo = RemoteReservationRepository(dio: dio);
      when(() => dio.get<dynamic>(ApiEndpoints.myReservations)).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: ApiEndpoints.myReservations),
          statusCode: 200,
          data: {
            'data': [
              {
                'id': 'res-1',
                'listing_id': 'lst-1',
                'listing_title': 'Nasi Box',
                'partner_id': 'p-1',
                'customer_id': 'u-1',
                'channel': 'discount',
                'quantity': 1,
                'total_amount': 20000,
                'pickup_window': {
                  'start': '2026-11-28T11:00:00Z',
                  'end': '2026-11-28T13:00:00Z',
                },
                'status': 'confirmed',
                'created_at': '2026-11-28T10:00:00Z',
                'pickup_pin': '123456',
              },
            ],
          },
        ),
      );

      final listRes = await repo.getReservationsForUser('u-1');
      expect(listRes.isRight(), isTrue);
      final items = listRes.getOrElse((_) => []);
      expect(items.single.status, ReservationStatus.confirmed);
      expect(items.single.pickupPin, '123456');

      when(
        () => dio.post<dynamic>(
          ApiEndpoints.validateReservationPin('res-1'),
          data: {'pin': '000000'},
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(
            path: ApiEndpoints.validateReservationPin('res-1'),
          ),
          response: Response<dynamic>(
            requestOptions: RequestOptions(
              path: ApiEndpoints.validateReservationPin('res-1'),
            ),
            statusCode: 423,
            data: {'code': 'PIN_LOCKED', 'message': 'PIN terkunci'},
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final locked = await repo.validatePickupPin(
        reservationId: 'res-1',
        pin: '000000',
        staffId: 'st-1',
      );
      locked.fold(
        (f) => expect(f, isA<PinLockedFailure>()),
        (_) => fail('Expected Left'),
      );
    });
  });
}
