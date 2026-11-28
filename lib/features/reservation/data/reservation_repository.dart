import 'package:fpdart/fpdart.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/features/kyc/data/kyc_repository.dart';
import 'package:surplus_share/features/kyc/domain/models/kyc_failure.dart';
import 'package:surplus_share/features/listing/data/listing_repository.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/listing/domain/models/listing_failure.dart';
import 'package:surplus_share/features/listing/domain/models/surplus_listing.dart';
import 'package:surplus_share/features/reservation/data/payment_gateway_service.dart';
import 'package:surplus_share/features/reservation/domain/models/handover_receipt.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation_failure.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation_status.dart';
import 'package:surplus_share/features/reservation/domain/policy/reservation_policy.dart';
import 'package:uuid/uuid.dart';

abstract interface class ReservationRepository {
  Future<Either<ReservationFailure, Reservation>> createDiscountReservation({
    required SurplusListing listing,
    required String customerId,
    required int quantity,
    required PaymentMethod paymentMethod,
  });

  Future<Either<ReservationFailure, Reservation>> createDonationReservation({
    required SurplusListing listing,
    required String customerId,
    required int quantity,
    bool bypassQuota = false,
  });

  Future<Either<ReservationFailure, Reservation>> confirmPayment({
    required String reservationId,
  });

  Future<Either<ReservationFailure, Reservation>> cancelReservation({
    required String reservationId,
  });

  Future<Either<ReservationFailure, Reservation>> validatePickupPin({
    required String reservationId,
    required String pin,
    required String staffId,
  });

  Future<Either<ReservationFailure, List<Reservation>>> getReservationsForUser(
    String userId,
  );

  Future<Either<ReservationFailure, List<Reservation>>>
  getReservationsForPartner(String partnerId);

  Future<void> reconcileExpired();
}

class InMemoryReservationRepository implements ReservationRepository {
  new({
    required this._listingRepository,
    required this._kycRepository,
    required this._paymentGatewayService,
    Clock? clock,
    Uuid? uuid,
  }) : _clock = clock ?? DateTime.now,
       _uuid = uuid ?? const Uuid();

  final ListingRepository _listingRepository;
  final KycRepository _kycRepository;
  final PaymentGatewayService _paymentGatewayService;
  final Clock _clock;
  final Uuid _uuid;
  final List<Reservation> _reservations = [];

  @override
  Future<Either<ReservationFailure, Reservation>> createDiscountReservation({
    required SurplusListing listing,
    required String customerId,
    required int quantity,
    required PaymentMethod paymentMethod,
  }) async {
    await reconcileExpired();

    if (listing.channel != ListingChannel.discount) {
      return left(
        const ReservationValidationFailure(
          'Listing ini bukan paket mode diskon.',
        ),
      );
    }
    if (quantity <= 0) {
      return left(
        const ReservationValidationFailure(
          'Jumlah booking harus lebih dari 0.',
        ),
      );
    }

    final now = _clock().toUtc();
    if (listing.effectiveStatus(now: now) == ListingStatus.expired) {
      return left(const ReservationPickupExpiredFailure());
    }

    final holdResult = await _listingRepository.claimStock(
      listingId: listing.id,
      quantity: quantity,
    );
    if (holdResult.isLeft()) {
      return left(
        holdResult.fold(
          _mapListingFailure,
          (_) => const ReservationStockUnavailableFailure(),
        ),
      );
    }

    final reservationId = _uuid.v4();
    final totalAmount = listing.discountedPrice * quantity;
    final paymentExpiry = ReservationPolicy.computePaymentExpiry(
      now: now,
      pickupEnd: listing.pickupEnd,
    );

    try {
      final session = await _paymentGatewayService.createCheckoutSession(
        reservationId: reservationId,
        method: paymentMethod,
        amount: totalAmount,
        expiresAt: paymentExpiry,
      );
      if (!session.isSecureUrl) {
        await _listingRepository.releaseStock(
          listingId: listing.id,
          quantity: quantity,
        );
        return left(
          const ReservationValidationFailure(
            'URL payment gateway wajib menggunakan HTTPS.',
          ),
        );
      }

      final reservation = Reservation(
        id: reservationId,
        listingId: listing.id,
        listingTitle: listing.title,
        partnerId: listing.partnerId,
        customerId: customerId,
        channel: ListingChannel.discount,
        quantity: quantity,
        totalAmount: totalAmount,
        pickupWindow: listing.pickupWindow,
        status: ReservationStatus.pendingPayment,
        createdAt: now,
        paymentSession: session,
      );
      _reservations.insert(0, reservation);
      return right(reservation);
    } on Object {
      await _listingRepository.releaseStock(
        listingId: listing.id,
        quantity: quantity,
      );
      return left(
        const ReservationValidationFailure(
          'Gagal membuat sesi pembayaran gateway.',
        ),
      );
    }
  }

  @override
  Future<Either<ReservationFailure, Reservation>> createDonationReservation({
    required SurplusListing listing,
    required String customerId,
    required int quantity,
    bool bypassQuota = false,
  }) async {
    await reconcileExpired();

    if (listing.channel != ListingChannel.donation) {
      return left(
        const ReservationValidationFailure(
          'Listing ini bukan paket mode donasi.',
        ),
      );
    }
    if (quantity <= 0) {
      return left(
        const ReservationValidationFailure('Jumlah klaim harus lebih dari 0.'),
      );
    }

    final now = _clock().toUtc();
    if (listing.effectiveStatus(now: now) == ListingStatus.expired) {
      return left(const ReservationPickupExpiredFailure());
    }

    if (!bypassQuota) {
      final quotaResult = await _kycRepository.getDailyQuota(customerId);
      final quotaFailure = quotaResult.fold<ReservationFailure?>(
        _mapKycFailure,
        (quota) => quota.canClaim(quantity)
            ? null
            : ReservationQuotaExceededFailure(
                remaining: quota.remaining,
                dailyLimit: quota.dailyLimit,
              ),
      );
      if (quotaFailure != null) return left(quotaFailure);
    }

    final holdResult = await _listingRepository.claimStock(
      listingId: listing.id,
      quantity: quantity,
    );
    if (holdResult.isLeft()) {
      return left(
        holdResult.fold(
          _mapListingFailure,
          (_) => const ReservationStockUnavailableFailure(),
        ),
      );
    }

    if (!bypassQuota) {
      final consumeResult = await _kycRepository.consumeDailyQuota(
        userId: customerId,
        quantity: quantity,
      );
      if (consumeResult.isLeft()) {
        await _listingRepository.releaseStock(
          listingId: listing.id,
          quantity: quantity,
        );
        return left(
          consumeResult.fold(
            _mapKycFailure,
            (_) => const ReservationPermissionDeniedFailure(),
          ),
        );
      }
    }

    final pin = ReservationPolicy.generateUniquePin(
      _activePinsForPartner(listing.partnerId),
    );
    final reservation = Reservation(
      id: _uuid.v4(),
      listingId: listing.id,
      listingTitle: listing.title,
      partnerId: listing.partnerId,
      customerId: customerId,
      channel: ListingChannel.donation,
      quantity: quantity,
      totalAmount: 0,
      pickupWindow: listing.pickupWindow,
      status: ReservationStatus.confirmed,
      createdAt: now,
      pickupPin: pin,
    );
    _reservations.insert(0, reservation);
    return right(reservation);
  }

  @override
  Future<Either<ReservationFailure, Reservation>> confirmPayment({
    required String reservationId,
  }) async {
    await reconcileExpired();

    final index = _reservations.indexWhere((r) => r.id == reservationId);
    if (index == -1) return left(const ReservationNotFoundFailure());

    final current = _reservations[index];
    if (current.status == ReservationStatus.expired) {
      return left(const PaymentExpiredFailure());
    }
    if (current.status != ReservationStatus.pendingPayment) {
      return left(
        const InvalidReservationTransitionFailure(
          'Hanya reservasi menunggu pembayaran yang dapat dikonfirmasi.',
        ),
      );
    }

    final pin = ReservationPolicy.generateUniquePin(
      _activePinsForPartner(current.partnerId),
    );
    final confirmed = current.copyWith(
      status: ReservationStatus.confirmed,
      pickupPin: pin,
    );
    _reservations[index] = confirmed;
    return right(confirmed);
  }

  @override
  Future<Either<ReservationFailure, Reservation>> cancelReservation({
    required String reservationId,
  }) async {
    await reconcileExpired();

    final index = _reservations.indexWhere((r) => r.id == reservationId);
    if (index == -1) return left(const ReservationNotFoundFailure());

    final current = _reservations[index];
    if (!current.canCancel(now: _clock())) {
      return left(
        const InvalidReservationTransitionFailure(
          'Reservasi ini tidak dapat dibatalkan.',
        ),
      );
    }

    await _listingRepository.releaseStock(
      listingId: current.listingId,
      quantity: current.quantity,
    );
    if (current.channel == ListingChannel.donation) {
      await _kycRepository.refundDailyQuota(
        userId: current.customerId,
        quantity: current.quantity,
      );
    }

    final cancelled = current.copyWith(
      status: ReservationStatus.cancelled,
      clearPickupPin: true,
    );
    _reservations[index] = cancelled;
    return right(cancelled);
  }

  @override
  Future<Either<ReservationFailure, Reservation>> validatePickupPin({
    required String reservationId,
    required String pin,
    required String staffId,
  }) async {
    await reconcileExpired();

    final index = _reservations.indexWhere((r) => r.id == reservationId);
    if (index == -1) return left(const ReservationNotFoundFailure());

    final current = _reservations[index];
    if (current.status == ReservationStatus.expired) {
      return left(const ReservationPickupExpiredFailure());
    }
    if (current.status != ReservationStatus.confirmed ||
        current.pickupPin == null) {
      return left(
        const InvalidReservationTransitionFailure(
          'Reservasi belum terkonfirmasi atau sudah selesai.',
        ),
      );
    }
    if (current.failedPinAttempts >= ReservationPolicy.maxPinAttempts) {
      return left(const PinLockedFailure());
    }

    final matched = ReservationPolicy.verifyPinConstantTime(
      current.pickupPin!,
      pin,
    );
    if (!matched) {
      final attempts = current.failedPinAttempts + 1;
      _reservations[index] = current.copyWith(failedPinAttempts: attempts);
      final remaining = ReservationPolicy.maxPinAttempts - attempts;
      if (remaining <= 0) {
        return left(const PinLockedFailure());
      }
      return left(InvalidPinFailure(remainingAttempts: remaining));
    }

    final now = _clock().toUtc();
    final receipt = HandoverReceipt(
      receiptId: 'rcpt-${_uuid.v4()}',
      reservationId: current.id,
      listingId: current.listingId,
      listingTitle: current.listingTitle,
      partnerId: current.partnerId,
      customerId: current.customerId,
      verifiedByStaffId: staffId,
      channel: current.channel,
      quantity: current.quantity,
      totalAmount: current.totalAmount,
      handedOverAt: now,
    );

    final completed = current.copyWith(
      status: ReservationStatus.completed,
      clearPickupPin: true,
      receipt: receipt,
    );
    _reservations[index] = completed;
    return right(completed);
  }

  @override
  Future<Either<ReservationFailure, List<Reservation>>> getReservationsForUser(
    String userId,
  ) async {
    await reconcileExpired();
    final list = _reservations
        .where((r) => r.customerId == userId)
        .toList(growable: false);
    return right(List<Reservation>.unmodifiable(list));
  }

  @override
  Future<Either<ReservationFailure, List<Reservation>>>
  getReservationsForPartner(String partnerId) async {
    await reconcileExpired();
    final list = _reservations
        .where((r) => r.partnerId == partnerId)
        .toList(growable: false);
    return right(List<Reservation>.unmodifiable(list));
  }

  @override
  Future<void> reconcileExpired() async {
    final now = _clock().toUtc();
    for (var i = 0; i < _reservations.length; i++) {
      final item = _reservations[i];
      if (item.status == ReservationStatus.pendingPayment &&
          item.effectiveStatus(now: now) == ReservationStatus.expired) {
        _reservations[i] = item.copyWith(
          status: ReservationStatus.expired,
          clearPickupPin: true,
        );
        await _listingRepository.releaseStock(
          listingId: item.listingId,
          quantity: item.quantity,
        );
      } else if (item.status == ReservationStatus.confirmed &&
          item.effectiveStatus(now: now) == ReservationStatus.expired) {
        _reservations[i] = item.copyWith(
          status: ReservationStatus.expired,
          clearPickupPin: true,
        );
      }
    }
  }

  Set<String> _activePinsForPartner(String partnerId) {
    return {
      for (final r in _reservations)
        if (r.partnerId == partnerId &&
            r.status == ReservationStatus.confirmed &&
            r.pickupPin != null)
          r.pickupPin!,
    };
  }

  ReservationFailure _mapListingFailure(ListingFailure failure) {
    return switch (failure) {
      ListingExpiredFailure() => const ReservationPickupExpiredFailure(),
      InsufficientStockFailure(:final message) =>
        ReservationStockUnavailableFailure(message),
      ListingNotFoundFailure(:final message) => ReservationNotFoundFailure(
        message,
      ),
      ListingPermissionDeniedFailure(:final message) =>
        ReservationPermissionDeniedFailure(message),
      ListingQuotaExceededFailure(:final remaining, :final dailyLimit) =>
        ReservationQuotaExceededFailure(
          remaining: remaining,
          dailyLimit: dailyLimit,
        ),
      ListingValidationFailure(:final message) => ReservationValidationFailure(
        message,
      ),
      InvalidChannelTransitionFailure(:final message) ||
      ListingUnknownFailure(
        :final message,
      ) => ReservationValidationFailure(message),
    };
  }

  ReservationFailure _mapKycFailure(KycFailure failure) {
    return switch (failure) {
      DailyQuotaExceededFailure(:final remaining, :final dailyLimit) =>
        ReservationQuotaExceededFailure(
          remaining: remaining,
          dailyLimit: dailyLimit,
        ),
      KycPermissionDeniedFailure(:final message) =>
        ReservationPermissionDeniedFailure(message),
      _ => ReservationValidationFailure(failure.message),
    };
  }
}
