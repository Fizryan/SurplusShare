import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/app/shell/app_shell.dart';
import 'package:surplus_share/core/auth/dummy/dummy_auth_repository.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/auth/storage/token_storage.dart';
import 'package:surplus_share/core/cache/local_cache_service.dart';
import 'package:surplus_share/core/di/global_provider.dart';
import 'package:surplus_share/core/shared/service/snackbar_service.dart';
import 'package:surplus_share/core/theme/green/green_theme.dart';
import 'package:surplus_share/core/theme/theme_notifier.dart';
import 'package:surplus_share/core/theme/theme_state.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/features/impact/presentation/provider/impact_provider.dart';
import 'package:surplus_share/features/impact/presentation/screens/impact_profile_screen.dart';
import 'package:surplus_share/features/kyc/presentation/provider/kyc_provider.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/listing/presentation/provider/listing_provider.dart';
import 'package:surplus_share/features/listing/presentation/screens/feed_screen.dart';
import 'package:surplus_share/features/listing/presentation/widgets/create_listing_sheet.dart';
import 'package:surplus_share/features/location/data/location_service.dart';
import 'package:surplus_share/features/location/domain/models/geo_point.dart';
import 'package:surplus_share/features/location/domain/models/location_failure.dart';
import 'package:surplus_share/features/location/presentation/provider/location_provider.dart';
import 'package:surplus_share/features/location/presentation/screens/explore_screen.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation_status.dart';
import 'package:surplus_share/features/reservation/presentation/provider/reservation_provider.dart';
import 'package:surplus_share/features/reservation/presentation/screens/reservations_screen.dart';
import 'package:surplus_share/features/reservation/presentation/widgets/book_listing_sheet.dart';

class _InMemoryTokenStorage implements TokenStorage {
  AuthTokens? _tokens;

  @override
  Future<void> clearTokens() async => _tokens = null;

  @override
  Future<String?> getAccessToken() async => _tokens?.accessToken;

  @override
  Future<AuthTokens?> getTokens() async => _tokens;

  @override
  Future<void> saveTokens(AuthTokens tokens) async => _tokens = tokens;
}

class _StubLocationService implements LocationService {
  const new(this._point);
  final GeoPoint _point;

  @override
  Future<Either<LocationFailure, GeoPoint>> getCurrentLocation() async {
    return right(_point);
  }

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

class _StubThemeNotifier extends ThemeNotifier {
  @override
  ThemeState build() =>
      const ThemeState(mode: ThemeMode.light, color: AppThemeColor.green);

  @override
  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(mode: mode);
  }
}

ProviderContainer _makeContainer(DateTime now) {
  final tokenStorage = _InMemoryTokenStorage();
  final cache = InMemoryCacheStore(clock: () => now);
  return ProviderContainer(
    overrides: [
      clockProvider.overrideWithValue(() => now),
      cacheStoreProvider.overrideWithValue(cache),
      tokenStorageProvider.overrideWithValue(tokenStorage),
      authRepositoryProvider.overrideWithValue(
        DummyAuthRepository(tokenStorage: tokenStorage),
      ),
      locationServiceProvider.overrideWithValue(
        const _StubLocationService(
          GeoPoint(latitude: -6.2088, longitude: 106.8456),
        ),
      ),
      themeNotifierProvider.overrideWith(_StubThemeNotifier.new),
      snackbarServiceProvider.overrideWithValue(SnackbarService()),
    ],
  );
}

Widget _wrapScreen(ProviderContainer container, Widget child) {
  final green = GreenTheme(ThemeData.light().textTheme);
  final snackbar = container.read(snackbarServiceProvider);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      scaffoldMessengerKey: snackbar.scaffoldKey,
      theme: green.light(),
      darkTheme: green.dark(),
      home: child,
    ),
  );
}

void main() {
  final now = DateTime.utc(2026, 11, 27, 18);

  group('All 7 Features Modular Material 3 UI', () {
    testWidgets(
      'FeedScreen displays Dual-Channel listings, countdown, safety filter, '
      'and Partner upload FAB',
      (tester) async {
        final container = _makeContainer(now);
        addTearDown(container.dispose);

        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(
              debugAccountId: DummyAuthAccounts.donorPartner.id,
            );
        await container.read(listingNotifierProvider.notifier).loadListings();

        await tester.pumpWidget(_wrapScreen(container, const FeedScreen()));
        await tester.pump();

        expect(find.text('Paket Nasi Campur Nusantara'), findsOneWidget);
        expect(
          find.byKey(const Key('feed_create_listing_fab')),
          findsOneWidget,
        );

        // Open Halal & Allergen filter sheet and exclude peanuts.
        await tester.tap(find.byKey(const Key('feed_safety_filter_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kacang'));
        await tester.pump();
        await tester.tap(find.text('Terapkan Filter'));
        await tester.pumpAndSettle();

        expect(find.text('Paket Nasi Campur Nusantara'), findsNothing);
        expect(find.text('Surprise Bag Bakery Sore'), findsOneWidget);
      },
    );

    testWidgets(
      'ExploreScreen renders map card, radius slider, and nearest listings',
      (tester) async {
        final container = _makeContainer(now);
        addTearDown(container.dispose);

        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(debugAccountId: DummyAuthAccounts.consumer.id);
        await container.read(listingNotifierProvider.notifier).loadListings();
        await container
            .read(locationNotifierProvider.notifier)
            .refreshLocation();

        await tester.pumpWidget(
          _wrapScreen(
            container,
            const ExploreScreen(enableNetworkTiles: false),
          ),
        );
        await tester.pump();

        expect(find.byKey(const Key('explore_radius_slider')), findsOneWidget);
        expect(find.text('0 m'), findsOneWidget);
        expect(find.text('Paket Nasi Campur Nusantara'), findsOneWidget);
      },
    );

    testWidgets(
      'ExploreScreen allows picking manual area when GPS is unavailable',
      (tester) async {
        final container = _makeContainer(now);
        addTearDown(container.dispose);

        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(debugAccountId: DummyAuthAccounts.consumer.id);
        await container.read(listingNotifierProvider.notifier).loadListings();

        await tester.pumpWidget(
          _wrapScreen(
            container,
            const ExploreScreen(enableNetworkTiles: false),
          ),
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('explore_pick_area_cta')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('area_preset_jakarta_pusat')));
        await tester.pumpAndSettle();

        expect(find.text('Paket Nasi Campur Nusantara'), findsOneWidget);
      },
    );

    testWidgets(
      'ReservationsScreen confirms payment, displays 6-digit PIN, and '
      'completes staff PIN handover',
      (tester) async {
        final container = _makeContainer(now);
        addTearDown(container.dispose);

        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(
              debugAccountId: DummyAuthAccounts.donorPartner.id,
            );
        await container.read(listingNotifierProvider.notifier).loadListings();
        final listing = container
            .read(listingNotifierProvider)
            .items
            .firstWhere((e) => e.id == 'lst-flash-1');

        await container
            .read(reservationNotifierProvider.notifier)
            .bookDiscount(
              listing: listing,
              quantity: 1,
              paymentMethod: PaymentMethod.qris,
            );

        await tester.pumpWidget(
          _wrapScreen(container, const ReservationsScreen()),
        );
        await tester.pump();

        expect(find.text('Konfirmasi Bayar'), findsOneWidget);
        await tester.tap(find.text('Konfirmasi Bayar'));
        await tester.pumpAndSettle();

        final pin = container
            .read(reservationNotifierProvider)
            .items
            .first
            .pickupPin!;
        expect(find.text(pin), findsOneWidget);

        await tester.tap(find.text('Validasi PIN'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('pin_validation_input')),
          pin,
        );
        await tester.tap(find.byKey(const Key('pin_validation_submit')));
        await tester.pumpAndSettle();

        expect(find.textContaining('Bukti:'), findsOneWidget);
      },
    );

    testWidgets(
      'ImpactProfileScreen displays Impact dashboard, CSR PDF export, and KYC',
      (tester) async {
        final container = _makeContainer(now);
        addTearDown(container.dispose);

        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(
              debugAccountId: DummyAuthAccounts.donorPartner.id,
            );

        await tester.pumpWidget(
          _wrapScreen(container, const ImpactProfileScreen()),
        );
        await tester.pump();

        expect(find.text('Food Saver Pemula'), findsOneWidget);
        expect(
          find.byKey(const Key('impact_export_csr_button')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('impact_export_csr_button')));
        await tester.pumpAndSettle();

        expect(
          container.read(csrReportNotifierProvider).lastPdfBytes,
          isNotNull,
        );
      },
    );

    testWidgets(
      'CreateListingSheet rejects discountedPrice >= originalPrice inline',
      (tester) async {
        final container = _makeContainer(now);
        addTearDown(container.dispose);

        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(
              debugAccountId: DummyAuthAccounts.donorPartner.id,
            );

        await tester.pumpWidget(
          _wrapScreen(container, const Scaffold(body: CreateListingSheet())),
        );
        await tester.pump();

        await tester.enterText(
          find.byKey(const Key('create_listing_orig_price')),
          '30000',
        );
        await tester.enterText(
          find.byKey(const Key('create_listing_disc_price')),
          '35000',
        );
        await tester.pump();

        expect(find.text('Harus < harga asli'), findsOneWidget);
        expect(
          find.byKey(const Key('bottom_sheet_close_button')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'FeedScreen resets channel filter on Beranda tab re-tap and closes '
      'CreateListingSheet via close button',
      (tester) async {
        final container = _makeContainer(now);
        addTearDown(container.dispose);

        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(
              debugAccountId: DummyAuthAccounts.donorPartner.id,
            );
        await container.read(listingNotifierProvider.notifier).loadListings();

        await tester.pumpWidget(_wrapScreen(container, const FeedScreen()));
        await tester.pump();

        container.read(listingChannelFilterProvider.notifier).filter =
            ListingChannel.discount;
        container.read(tabReselectProvider.notifier).reselect(0);
        await tester.pump();
        expect(container.read(listingChannelFilterProvider), isNull);

        await tester.tap(find.byKey(const Key('feed_create_listing_fab')));
        await tester.pumpAndSettle();
        expect(find.byType(CreateListingSheet), findsOneWidget);

        await tester.tap(find.byKey(const Key('bottom_sheet_close_button')));
        await tester.pumpAndSettle();
        expect(find.byType(CreateListingSheet), findsNothing);
      },
    );

    testWidgets(
      'BookListingSheet lets verifiedRecipient claim multiple donation '
      'portions via quick-pick chip',
      (tester) async {
        final container = _makeContainer(now);
        addTearDown(container.dispose);

        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(
              debugAccountId: DummyAuthAccounts.verifiedRecipient.id,
            );
        await container.read(listingNotifierProvider.notifier).loadListings();
        await container.read(kycNotifierProvider.notifier).loadMyKyc();

        final donation = container
            .read(listingNotifierProvider)
            .items
            .firstWhere((e) => e.id == 'lst-donation-1');

        await tester.pumpWidget(
          _wrapScreen(
            container,
            Scaffold(body: BookListingSheet(listing: donation)),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('book_qty_chip_10')), findsOneWidget);
        await tester.tap(find.byKey(const Key('book_qty_chip_10')));
        await tester.pump();
        expect(find.text('Klaim 10 Porsi Gratis'), findsOneWidget);

        await tester.tap(find.byKey(const Key('book_listing_confirm_button')));
        await tester.pumpAndSettle();

        final updated = container
            .read(listingNotifierProvider)
            .items
            .firstWhere((e) => e.id == 'lst-donation-1');
        expect(updated.remainingQuantity, donation.remainingQuantity - 10);
      },
    );
  });
}
