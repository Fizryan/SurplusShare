import 'package:fpdart/fpdart.dart';
import 'package:surplus_share/core/auth/dummy/dummy_auth_repository.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/features/distribution/domain/models/distribution_failure.dart';
import 'package:surplus_share/features/distribution/domain/models/distribution_task.dart';
import 'package:surplus_share/features/location/domain/models/geo_point.dart';
import 'package:surplus_share/features/reservation/domain/policy/reservation_policy.dart';
import 'package:uuid/uuid.dart';

abstract interface class DistributionRepository {
  Future<Either<DistributionFailure, List<DistributionTask>>> getTasks();

  Future<Either<DistributionFailure, DistributionTask>> createTask(
    CreateDistributionInput input,
  );

  Future<Either<DistributionFailure, DistributionTask>> acceptTask({
    required String taskId,
    required String volunteerId,
    required String volunteerName,
  });

  Future<Either<DistributionFailure, DistributionTask>> markPickedUp({
    required String taskId,
    required String volunteerId,
    required String pin,
  });

  Future<Either<DistributionFailure, DistributionTask>> markDelivered({
    required String taskId,
    required String volunteerId,
    required String pin,
  });

  Future<Either<DistributionFailure, DistributionTask>> cancelTask({
    required String taskId,
  });
}

class InMemoryDistributionRepository implements DistributionRepository {
  new({List<DistributionTask>? seed, Uuid? uuid, Clock? clock})
    : _clock = clock ?? DateTime.now,
      _uuid = uuid ?? const Uuid(),
      _items = List<DistributionTask>.of(
        seed ?? _defaultSeed((clock ?? DateTime.now)()),
      );

  final List<DistributionTask> _items;
  final Uuid _uuid;
  final Clock _clock;

  @override
  Future<Either<DistributionFailure, List<DistributionTask>>> getTasks() async {
    return right(List<DistributionTask>.unmodifiable(_items));
  }

  @override
  Future<Either<DistributionFailure, DistributionTask>> createTask(
    CreateDistributionInput input,
  ) async {
    final error = input.validate();
    if (error != null) {
      return left(DistributionValidationFailure(error));
    }

    final task = DistributionTask(
      id: _uuid.v4(),
      listingId: input.listingId.trim(),
      listingTitle: input.listingTitle.trim(),
      partnerId: input.partnerId.trim(),
      partnerName: input.partnerName.trim(),
      storeAddress: input.storeAddress.trim(),
      storeLocation: input.storeLocation,
      recipientId: input.recipientId.trim(),
      recipientName: input.recipientName.trim(),
      recipientAddress: input.recipientAddress.trim(),
      recipientLocation: input.recipientLocation,
      portions: input.portions,
      status: DistributionStatus.open,
      createdAt: _clock().toUtc(),
    );
    _items.insert(0, task);
    return right(task);
  }

  @override
  Future<Either<DistributionFailure, DistributionTask>> acceptTask({
    required String taskId,
    required String volunteerId,
    required String volunteerName,
  }) async {
    final index = _items.indexWhere((t) => t.id == taskId);
    if (index == -1) return left(const DistributionNotFoundFailure());

    final current = _items[index];
    if (current.status != DistributionStatus.open) {
      return left(
        const InvalidDistributionTransitionFailure(
          'Hanya tugas berstatus terbuka yang dapat diambil relawan.',
        ),
      );
    }

    final activePins = <String>{
      for (final item in _items) ...[
        if (item.pickupPin != null) item.pickupPin!,
        if (item.deliveryPin != null) item.deliveryPin!,
      ],
    };
    final pickupPin = ReservationPolicy.generateUniquePin(activePins);
    activePins.add(pickupPin);
    final deliveryPin = ReservationPolicy.generateUniquePin(activePins);

    final updated = current.copyWith(
      status: DistributionStatus.accepted,
      volunteerId: volunteerId,
      volunteerName: volunteerName,
      pickupPin: pickupPin,
      deliveryPin: deliveryPin,
      failedPinAttempts: 0,
      acceptedAt: _clock().toUtc(),
    );
    _items[index] = updated;
    return right(updated);
  }

  @override
  Future<Either<DistributionFailure, DistributionTask>> markPickedUp({
    required String taskId,
    required String volunteerId,
    required String pin,
  }) async {
    final index = _items.indexWhere((t) => t.id == taskId);
    if (index == -1) return left(const DistributionNotFoundFailure());

    final current = _items[index];
    if (current.status != DistributionStatus.accepted) {
      return left(
        const InvalidDistributionTransitionFailure(
          'Tugas harus berstatus diterima sebelum dikonfirmasi diambil.',
        ),
      );
    }
    if (current.volunteerId != volunteerId) {
      return left(
        const DistributionPermissionDeniedFailure(
          'Hanya relawan yang mengambil tugas ini yang dapat mengonfirmasi.',
        ),
      );
    }
    final pinFailure = _verifyPin(
      index: index,
      current: current,
      expectedPin: current.pickupPin,
      providedPin: pin,
    );
    if (pinFailure != null) return left(pinFailure);

    final updated = current.copyWith(
      status: DistributionStatus.pickedUp,
      failedPinAttempts: 0,
      pickedUpAt: _clock().toUtc(),
    );
    _items[index] = updated;
    return right(updated);
  }

  @override
  Future<Either<DistributionFailure, DistributionTask>> markDelivered({
    required String taskId,
    required String volunteerId,
    required String pin,
  }) async {
    final index = _items.indexWhere((t) => t.id == taskId);
    if (index == -1) return left(const DistributionNotFoundFailure());

    final current = _items[index];
    if (current.status != DistributionStatus.pickedUp) {
      return left(
        const InvalidDistributionTransitionFailure(
          'Paket harus diambil dari toko terlebih dahulu sebelum selesai '
          'diantar.',
        ),
      );
    }
    if (current.volunteerId != volunteerId) {
      return left(
        const DistributionPermissionDeniedFailure(
          'Hanya relawan yang mengambil tugas ini yang dapat menyelesaikan.',
        ),
      );
    }
    final pinFailure = _verifyPin(
      index: index,
      current: current,
      expectedPin: current.deliveryPin,
      providedPin: pin,
    );
    if (pinFailure != null) return left(pinFailure);

    final updated = current.copyWith(
      status: DistributionStatus.delivered,
      failedPinAttempts: 0,
      deliveredAt: _clock().toUtc(),
    );
    _items[index] = updated;
    return right(updated);
  }

  DistributionFailure? _verifyPin({
    required int index,
    required DistributionTask current,
    required String? expectedPin,
    required String providedPin,
  }) {
    if (current.failedPinAttempts >= ReservationPolicy.maxPinAttempts) {
      return const DistributionPinLockedFailure();
    }
    if (expectedPin == null ||
        !ReservationPolicy.verifyPinConstantTime(expectedPin, providedPin)) {
      final attempts = current.failedPinAttempts + 1;
      _items[index] = current.copyWith(failedPinAttempts: attempts);
      if (attempts >= ReservationPolicy.maxPinAttempts) {
        return const DistributionPinLockedFailure();
      }
      return InvalidDistributionPinFailure(
        remainingAttempts: ReservationPolicy.maxPinAttempts - attempts,
      );
    }
    return null;
  }

  @override
  Future<Either<DistributionFailure, DistributionTask>> cancelTask({
    required String taskId,
  }) async {
    final index = _items.indexWhere((t) => t.id == taskId);
    if (index == -1) return left(const DistributionNotFoundFailure());

    final current = _items[index];
    if (!current.canCancel) {
      return left(
        const InvalidDistributionTransitionFailure(
          'Tugas yang sudah diambil dari toko tidak dapat dibatalkan.',
        ),
      );
    }

    final updated = current.copyWith(status: DistributionStatus.cancelled);
    _items[index] = updated;
    return right(updated);
  }

  static List<DistributionTask> _defaultSeed(DateTime referenceTime) {
    return [
      DistributionTask(
        id: 'dist-seed-1',
        listingId: 'lst-donation-1',
        listingTitle: 'Donasi Kotak Makan Malam',
        partnerId: DummyAuthAccounts.donorPartner.id,
        partnerName: DummyAuthAccounts.donorPartner.displayName,
        storeAddress: 'Jl. Sudirman No. 10, Jakarta Pusat',
        storeLocation: const GeoPoint(latitude: -6.2088, longitude: 106.8456),
        recipientId: DummyAuthAccounts.verifiedRecipient.id,
        recipientName: DummyAuthAccounts.verifiedRecipient.displayName,
        recipientAddress: 'Jl. Tebet Timur Dalam No. 18, Jakarta Selatan',
        recipientLocation: const GeoPoint(
          latitude: -6.2297,
          longitude: 106.8570,
        ),
        portions: 5,
        status: DistributionStatus.open,
        createdAt: referenceTime.toUtc(),
      ),
    ];
  }
}
