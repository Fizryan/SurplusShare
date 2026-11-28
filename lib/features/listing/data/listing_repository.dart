import 'package:fpdart/fpdart.dart';
import 'package:surplus_share/core/auth/dummy/dummy_auth_repository.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/features/listing/domain/models/create_listing_input.dart';
import 'package:surplus_share/features/listing/domain/models/food_safety_declaration.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/listing/domain/models/listing_failure.dart';
import 'package:surplus_share/features/listing/domain/models/pickup_window.dart';
import 'package:surplus_share/features/listing/domain/models/surplus_listing.dart';
import 'package:surplus_share/features/location/domain/models/geo_point.dart';
import 'package:uuid/uuid.dart';

abstract interface class ListingRepository {
  Future<Either<ListingFailure, List<SurplusListing>>> getListings({
    ListingChannel? channel,
  });

  Future<Either<ListingFailure, SurplusListing>> createListing(
    CreateListingInput input,
  );

  Future<Either<ListingFailure, SurplusListing>> convertToDonation({
    required String listingId,
  });

  Future<Either<ListingFailure, SurplusListing>> claimStock({
    required String listingId,
    required int quantity,
  });

  Future<Either<ListingFailure, SurplusListing>> releaseStock({
    required String listingId,
    required int quantity,
  });

  Future<Either<ListingFailure, SurplusListing>> closeListing({
    required String listingId,
  });

  Future<Either<ListingFailure, SurplusListing>> allocateVolunteerPortions({
    required String listingId,
    required int portions,
  });
}

class InMemoryListingRepository implements ListingRepository {
  new({List<SurplusListing>? seed, Uuid? uuid, Clock? clock})
    : _clock = clock ?? DateTime.now,
      _uuid = uuid ?? const Uuid(),
      _items = List<SurplusListing>.of(
        seed ?? _defaultSeed((clock ?? DateTime.now)()),
      );

  final List<SurplusListing> _items;
  final Uuid _uuid;
  final Clock _clock;

  @override
  Future<Either<ListingFailure, List<SurplusListing>>> getListings({
    ListingChannel? channel,
  }) async {
    _expireStaleListings();
    final result = channel == null
        ? List<SurplusListing>.unmodifiable(_items)
        : List<SurplusListing>.unmodifiable(
            _items.where((item) => item.channel == channel),
          );
    return right(result);
  }

  @override
  Future<Either<ListingFailure, SurplusListing>> createListing(
    CreateListingInput input,
  ) async {
    final now = _clock().toUtc();
    final error = input.validate(now: now);
    if (error != null) {
      return left(ListingValidationFailure(error));
    }

    final publicRemaining = input.quantity - input.volunteerAllocatedPortions;
    final listing = SurplusListing(
      id: _uuid.v4(),
      partnerId: input.partnerId.trim(),
      partnerName: input.partnerName.trim(),
      title: input.title.trim(),
      description: input.description.trim(),
      channel: input.channel,
      discountFormat: input.discountFormat,
      originalPrice: input.originalPrice,
      discountedPrice: input.discountedPrice,
      totalQuantity: input.quantity,
      remainingQuantity: publicRemaining,
      volunteerAllocatedPortions: input.volunteerAllocatedPortions,
      pickupWindow: input.pickupWindow,
      status: publicRemaining == 0
          ? ListingStatus.soldOut
          : ListingStatus.active,
      createdAt: now,
      location: input.location,
      address: input.address?.trim(),
      foodSafety: input.foodSafety,
    );

    _items.insert(0, listing);
    return right(listing);
  }

  @override
  Future<Either<ListingFailure, SurplusListing>> convertToDonation({
    required String listingId,
  }) async {
    _expireStaleListings();
    final index = _items.indexWhere((item) => item.id == listingId);
    if (index == -1) {
      return left(const ListingNotFoundFailure());
    }

    final current = _items[index];
    final now = _clock().toUtc();
    if (!current.canConvertToDonation(now: now)) {
      return left(
        const InvalidChannelTransitionFailure(
          'Hanya listing mode diskon yang aktif dan masih memiliki stok '
          'yang dapat dialihkan ke Donasi Gratis.',
        ),
      );
    }

    final converted = current.copyWith(
      channel: ListingChannel.donation,
      clearDiscountFormat: true,
      discountedPrice: 0,
      convertedToDonationAt: now,
    );
    _items[index] = converted;
    return right(converted);
  }

  @override
  Future<Either<ListingFailure, SurplusListing>> claimStock({
    required String listingId,
    required int quantity,
  }) async {
    if (quantity <= 0) {
      return left(
        const ListingValidationFailure('Jumlah klaim harus lebih dari 0.'),
      );
    }

    _expireStaleListings();
    final index = _items.indexWhere((item) => item.id == listingId);
    if (index == -1) {
      return left(const ListingNotFoundFailure());
    }

    final current = _items[index];
    final now = _clock().toUtc();
    if (current.effectiveStatus(now: now) == ListingStatus.expired) {
      return left(const ListingExpiredFailure());
    }
    if (!current.isAvailable(now: now)) {
      return left(
        const InsufficientStockFailure('Listing sudah tidak tersedia.'),
      );
    }
    if (quantity > current.remainingQuantity) {
      return left(
        InsufficientStockFailure(
          'Stok tersisa hanya ${current.remainingQuantity}.',
        ),
      );
    }

    final remaining = current.remainingQuantity - quantity;
    final updated = current.copyWith(
      remainingQuantity: remaining,
      status: remaining == 0 ? ListingStatus.soldOut : ListingStatus.active,
    );
    _items[index] = updated;
    return right(updated);
  }

  @override
  Future<Either<ListingFailure, SurplusListing>> releaseStock({
    required String listingId,
    required int quantity,
  }) async {
    if (quantity <= 0) {
      return left(
        const ListingValidationFailure('Jumlah rilis stok harus lebih dari 0.'),
      );
    }

    _expireStaleListings();
    final index = _items.indexWhere((item) => item.id == listingId);
    if (index == -1) {
      return left(const ListingNotFoundFailure());
    }

    final current = _items[index];
    final restored = (current.remainingQuantity + quantity).clamp(
      0,
      current.totalQuantity,
    );
    final now = _clock().toUtc();
    final nextStatus =
        current.status == ListingStatus.soldOut &&
            !current.pickupWindow.isExpired(now: now)
        ? ListingStatus.active
        : current.status;

    final updated = current.copyWith(
      remainingQuantity: restored,
      status: nextStatus,
    );
    _items[index] = updated;
    return right(updated);
  }

  @override
  Future<Either<ListingFailure, SurplusListing>> closeListing({
    required String listingId,
  }) async {
    _expireStaleListings();
    final index = _items.indexWhere((item) => item.id == listingId);
    if (index == -1) {
      return left(const ListingNotFoundFailure());
    }

    final updated = _items[index].copyWith(status: ListingStatus.closed);
    _items[index] = updated;
    return right(updated);
  }

  @override
  Future<Either<ListingFailure, SurplusListing>> allocateVolunteerPortions({
    required String listingId,
    required int portions,
  }) async {
    if (portions <= 0) {
      return left(
        const ListingValidationFailure(
          'Jumlah alokasi porsi relawan harus lebih dari 0.',
        ),
      );
    }

    _expireStaleListings();
    final index = _items.indexWhere((item) => item.id == listingId);
    if (index == -1) {
      return left(const ListingNotFoundFailure());
    }

    final current = _items[index];
    final now = _clock().toUtc();
    if (current.effectiveStatus(now: now) == ListingStatus.expired) {
      return left(const ListingExpiredFailure());
    }
    if (!current.isAvailable(now: now)) {
      return left(
        const InsufficientStockFailure('Listing sudah tidak tersedia.'),
      );
    }
    if (portions > current.remainingQuantity) {
      return left(
        InsufficientStockFailure(
          'Stok tersisa hanya ${current.remainingQuantity} porsi.',
        ),
      );
    }

    final remaining = current.remainingQuantity - portions;
    final updated = current.copyWith(
      remainingQuantity: remaining,
      volunteerAllocatedPortions: current.volunteerAllocatedPortions + portions,
      status: remaining == 0 ? ListingStatus.soldOut : ListingStatus.active,
    );
    _items[index] = updated;
    return right(updated);
  }

  void _expireStaleListings() {
    final now = _clock().toUtc();
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (item.status == ListingStatus.active &&
          item.pickupWindow.isExpired(now: now)) {
        _items[i] = item.copyWith(status: ListingStatus.expired);
      }
    }
  }

  static List<SurplusListing> _defaultSeed(DateTime referenceTime) {
    final now = referenceTime.toUtc();
    final window = PickupWindow(
      start: now.add(const Duration(hours: 1)),
      end: now.add(const Duration(hours: 4)),
    );

    return [
      SurplusListing(
        id: 'lst-flash-1',
        partnerId: DummyAuthAccounts.donorPartner.id,
        partnerName: DummyAuthAccounts.donorPartner.displayName,
        title: 'Paket Nasi Campur Nusantara',
        description: 'Sisa porsi makan siang layak konsumsi, dikemas rapi.',
        channel: ListingChannel.discount,
        discountFormat: DiscountFormat.flashSale,
        originalPrice: 50000,
        discountedPrice: 20000,
        totalQuantity: 10,
        remainingQuantity: 6,
        pickupWindow: window,
        status: ListingStatus.active,
        createdAt: now,
        location: const GeoPoint(latitude: -6.2088, longitude: 106.8456),
        address: 'Jl. Sudirman No. 10, Jakarta Pusat',
        foodSafety: FoodSafetyDeclaration(
          halalStatus: HalalStatus.halalCertified,
          category: FoodCategory.readyToEat,
          allergens: const {FoodAllergen.peanuts},
          safeUntil: window.end.add(const Duration(hours: 4)),
          hygieneConfirmed: true,
          storageNote: 'Hangatkan sebelum dikonsumsi.',
        ),
      ),
      SurplusListing(
        id: 'lst-bag-1',
        partnerId: DummyAuthAccounts.donorPartner.id,
        partnerName: DummyAuthAccounts.donorPartner.displayName,
        title: 'Surprise Bag Bakery Sore',
        description: 'Aneka roti dan pastry pilihan harian menjelang tutup.',
        channel: ListingChannel.discount,
        discountFormat: DiscountFormat.surpriseBag,
        originalPrice: 60000,
        discountedPrice: 24000,
        totalQuantity: 8,
        remainingQuantity: 5,
        pickupWindow: window,
        status: ListingStatus.active,
        createdAt: now,
        location: const GeoPoint(latitude: -6.2150, longitude: 106.8456),
        address: 'Jl. Thamrin No. 22, Jakarta Pusat',
        foodSafety: FoodSafetyDeclaration(
          halalStatus: HalalStatus.halalFriendly,
          category: FoodCategory.bakery,
          allergens: const {FoodAllergen.gluten, FoodAllergen.dairy},
          safeUntil: window.end.add(const Duration(hours: 18)),
          hygieneConfirmed: true,
          storageNote: 'Simpan di wadah tertutup pada suhu ruang.',
        ),
      ),
      SurplusListing(
        id: 'lst-donation-1',
        partnerId: DummyAuthAccounts.donorPartner.id,
        partnerName: DummyAuthAccounts.donorPartner.displayName,
        title: 'Donasi Kotak Makan Malam',
        description: 'Khusus panti asuhan dan komunitas terverifikasi.',
        channel: ListingChannel.donation,
        originalPrice: 40000,
        discountedPrice: 0,
        totalQuantity: 20,
        remainingQuantity: 15,
        volunteerAllocatedPortions: 5,
        pickupWindow: window,
        status: ListingStatus.active,
        createdAt: now,
        location: const GeoPoint(latitude: -6.2200, longitude: 106.8456),
        address: 'Jl. Gatot Subroto No. 5, Jakarta Selatan',
        foodSafety: FoodSafetyDeclaration(
          halalStatus: HalalStatus.halalCertified,
          category: FoodCategory.readyToEat,
          safeUntil: window.end.add(const Duration(hours: 4)),
          hygieneConfirmed: true,
          storageNote: 'Konsumsi dalam 4 jam setelah diambil.',
        ),
      ),
    ];
  }
}
