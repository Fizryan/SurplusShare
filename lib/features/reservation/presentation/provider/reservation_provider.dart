import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/permission/app_role.dart';
import 'package:surplus_share/core/permission/permission_provider.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/features/kyc/presentation/provider/kyc_provider.dart';
import 'package:surplus_share/features/listing/domain/models/surplus_listing.dart';
import 'package:surplus_share/features/listing/domain/policy/listing_access_policy.dart';
import 'package:surplus_share/features/listing/presentation/provider/listing_provider.dart';
import 'package:surplus_share/features/reservation/data/payment_gateway_service.dart';
import 'package:surplus_share/features/reservation/data/remote_reservation_repository.dart';
import 'package:surplus_share/features/reservation/data/reservation_repository.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation_failure.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation_status.dart';
import 'package:surplus_share/features/reservation/domain/policy/reservation_policy.dart';

@immutable
class ReservationState {
  const new({
    this.items = const <Reservation>[],
    this.isLoading = false,
    this.failure,
  });

  final List<Reservation> items;
  final bool isLoading;
  final ReservationFailure? failure;

  ReservationState copyWith({
    List<Reservation>? items,
    bool? isLoading,
    ReservationFailure? failure,
    bool clearFailure = false,
  }) {
    return ReservationState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReservationState &&
        listEquals(other.items, items) &&
        other.isLoading == isLoading &&
        other.failure == failure;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(items), isLoading, failure);
}

final paymentGatewayServiceProvider = Provider<PaymentGatewayService>((ref) {
  return const StubPaymentGatewayService();
});

final reservationRepositoryProvider = Provider<ReservationRepository>((ref) {
  final config = ref.watch(apiConfigProvider);
  if (config.isDemoMode) {
    return InMemoryReservationRepository(
      listingRepository: ref.watch(listingRepositoryProvider),
      kycRepository: ref.watch(kycRepositoryProvider),
      paymentGatewayService: ref.watch(paymentGatewayServiceProvider),
      clock: ref.watch(clockProvider),
    );
  }
  return RemoteReservationRepository(dio: ref.watch(authenticatedDioProvider));
});

final reservationNotifierProvider =
    NotifierProvider<ReservationNotifier, ReservationState>(
      ReservationNotifier.new,
    );

class ReservationNotifier extends Notifier<ReservationState> {
  @override
  ReservationState build() {
    // Watching currentUserIdProvider ensures previous user's reservations and
    // pickup PINs are cleared immediately upon logout or account switch.
    ref.watch(currentUserIdProvider);
    return const ReservationState();
  }

  Future<void> loadMyReservations() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      state = const ReservationState();
      return;
    }

    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await ref
        .read(reservationRepositoryProvider)
        .getReservationsForUser(userId);
    if (!ref.mounted) return;
    state = result.fold(
      (failure) => state.copyWith(isLoading: false, failure: failure),
      (items) => state.copyWith(isLoading: false, items: items),
    );
  }

  Future<void> loadPartnerReservations() async {
    final partnerId = ref.read(currentUserIdProvider);
    if (partnerId == null) {
      state = const ReservationState();
      return;
    }

    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await ref
        .read(reservationRepositoryProvider)
        .getReservationsForPartner(partnerId);
    if (!ref.mounted) return;
    state = result.fold(
      (failure) => state.copyWith(isLoading: false, failure: failure),
      (items) => state.copyWith(isLoading: false, items: items),
    );
  }

  Future<Reservation?> bookDiscount({
    required SurplusListing listing,
    required int quantity,
    required PaymentMethod paymentMethod,
  }) async {
    if (state.isLoading) return null;
    final claims = ref.read(currentClaimsProvider);
    final userId = claims?.subject;
    final permissions = ref.read(currentPermissionProvider);
    final now = ref.read(clockProvider)();

    if (userId == null ||
        !ListingAccessPolicy.canClaim(listing, permissions, now: now)) {
      state = state.copyWith(
        failure: const ReservationPermissionDeniedFailure(),
      );
      return null;
    }

    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await ref
        .read(reservationRepositoryProvider)
        .createDiscountReservation(
          listing: listing,
          customerId: userId,
          quantity: quantity,
          paymentMethod: paymentMethod,
        );
    if (!ref.mounted) return null;
    return await result.fold<Future<Reservation?>>(
      (failure) async {
        state = state.copyWith(isLoading: false, failure: failure);
        return null;
      },
      (created) async {
        await ref.read(listingNotifierProvider.notifier).loadListings();
        if (!ref.mounted) return created;
        state = state.copyWith(
          isLoading: false,
          items: [created, ...state.items],
        );
        return created;
      },
    );
  }

  Future<Reservation?> bookDonation({
    required SurplusListing listing,
    required int quantity,
  }) async {
    if (state.isLoading) return null;
    final claims = ref.read(currentClaimsProvider);
    final userId = claims?.subject;
    final permissions = ref.read(currentPermissionProvider);
    final now = ref.read(clockProvider)();

    if (userId == null ||
        !ListingAccessPolicy.canClaim(listing, permissions, now: now)) {
      state = state.copyWith(
        failure: const ReservationPermissionDeniedFailure(
          'Donasi Gratis hanya dapat diklaim oleh panti asuhan atau '
          'komunitas terverifikasi.',
        ),
      );
      return null;
    }

    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await ref
        .read(reservationRepositoryProvider)
        .createDonationReservation(
          listing: listing,
          customerId: userId,
          quantity: quantity,
          bypassQuota: claims?.role == AppRole.admin,
        );
    if (!ref.mounted) return null;
    return await result.fold<Future<Reservation?>>(
      (failure) async {
        state = state.copyWith(isLoading: false, failure: failure);
        return null;
      },
      (created) async {
        await ref.read(listingNotifierProvider.notifier).loadListings();
        await ref.read(kycNotifierProvider.notifier).loadMyKyc();
        if (!ref.mounted) return created;
        state = state.copyWith(
          isLoading: false,
          items: [created, ...state.items],
        );
        return created;
      },
    );
  }

  Future<bool> confirmPayment(String reservationId) async {
    if (state.isLoading) return false;
    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await ref
        .read(reservationRepositoryProvider)
        .confirmPayment(reservationId: reservationId);
    if (!ref.mounted) return false;
    return await result.fold<Future<bool>>(
      (failure) async {
        await ref.read(listingNotifierProvider.notifier).loadListings();
        if (!ref.mounted) return false;
        state = state.copyWith(isLoading: false, failure: failure);
        return false;
      },
      (updated) async {
        state = state.copyWith(isLoading: false, items: _upsertItem(updated));
        return true;
      },
    );
  }

  Future<bool> cancelReservation(String reservationId) async {
    if (state.isLoading) return false;
    final claims = ref.read(currentClaimsProvider);
    final actorId = claims?.subject;
    final target = _findById(reservationId);
    if (actorId == null ||
        (target != null &&
            target.customerId != actorId &&
            target.partnerId != actorId &&
            claims?.role != AppRole.admin)) {
      state = state.copyWith(
        failure: const ReservationPermissionDeniedFailure(),
      );
      return false;
    }

    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await ref
        .read(reservationRepositoryProvider)
        .cancelReservation(reservationId: reservationId);
    if (!ref.mounted) return false;
    return await result.fold<Future<bool>>(
      (failure) async {
        state = state.copyWith(isLoading: false, failure: failure);
        return false;
      },
      (updated) async {
        await ref.read(listingNotifierProvider.notifier).loadListings();
        await ref.read(kycNotifierProvider.notifier).loadMyKyc();
        if (!ref.mounted) return true;
        state = state.copyWith(isLoading: false, items: _upsertItem(updated));
        return true;
      },
    );
  }

  Future<bool> validatePickupPin({
    required String reservationId,
    required String pin,
  }) async {
    if (state.isLoading) return false;
    final claims = ref.read(currentClaimsProvider);
    final staffId = claims?.subject;
    final target = _findById(reservationId);
    if (staffId == null || target == null) {
      state = state.copyWith(
        failure: target == null
            ? const ReservationNotFoundFailure()
            : const ReservationPermissionDeniedFailure(),
      );
      return false;
    }

    final permissions = ref.read(currentPermissionProvider);
    final canValidate = ReservationPolicy.canValidateHandover(
      target,
      actorUserId: staffId,
      role: claims!.role,
      permissions: permissions,
    );
    if (!canValidate) {
      state = state.copyWith(
        failure: const ReservationPermissionDeniedFailure(
          'Hanya staf mitra pemilik listing yang dapat memvalidasi PIN ini.',
        ),
      );
      return false;
    }

    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await ref
        .read(reservationRepositoryProvider)
        .validatePickupPin(
          reservationId: reservationId,
          pin: pin,
          staffId: staffId,
        );
    if (!ref.mounted) return false;
    return result.fold<bool>(
      (failure) {
        var nextItems = state.items;
        if (failure is InvalidPinFailure) {
          nextItems = _upsertItem(
            target.copyWith(failedPinAttempts: target.failedPinAttempts + 1),
          );
        } else if (failure is PinLockedFailure) {
          nextItems = _upsertItem(
            target.copyWith(
              failedPinAttempts: ReservationPolicy.maxPinAttempts,
            ),
          );
        }
        state = state.copyWith(
          isLoading: false,
          items: nextItems,
          failure: failure,
        );
        return false;
      },
      (completed) {
        state = state.copyWith(isLoading: false, items: _upsertItem(completed));
        return true;
      },
    );
  }

  Reservation? _findById(String id) {
    for (final item in state.items) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<Reservation> _upsertItem(Reservation updated) {
    final exists = state.items.any((item) => item.id == updated.id);
    if (!exists) return [updated, ...state.items];
    return [
      for (final item in state.items)
        if (item.id == updated.id) updated else item,
    ];
  }
}
