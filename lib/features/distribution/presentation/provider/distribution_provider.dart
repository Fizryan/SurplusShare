import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/permission/app_role.dart';
import 'package:surplus_share/core/permission/permission.dart';
import 'package:surplus_share/core/permission/permission_provider.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/features/distribution/data/distribution_repository.dart';
import 'package:surplus_share/features/distribution/data/remote_distribution_repository.dart';
import 'package:surplus_share/features/distribution/domain/models/distribution_failure.dart';
import 'package:surplus_share/features/distribution/domain/models/distribution_task.dart';
import 'package:surplus_share/features/listing/presentation/provider/listing_provider.dart';

@immutable
class DistributionState {
  const new({
    this.tasks = const <DistributionTask>[],
    this.isLoading = false,
    this.failure,
  });

  final List<DistributionTask> tasks;
  final bool isLoading;
  final DistributionFailure? failure;

  DistributionState copyWith({
    List<DistributionTask>? tasks,
    bool? isLoading,
    DistributionFailure? failure,
    bool clearFailure = false,
  }) {
    return DistributionState(
      tasks: tasks ?? this.tasks,
      isLoading: isLoading ?? this.isLoading,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DistributionState &&
        listEquals(other.tasks, tasks) &&
        other.isLoading == isLoading &&
        other.failure == failure;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(tasks), isLoading, failure);
}

final distributionRepositoryProvider = Provider<DistributionRepository>((ref) {
  final config = ref.watch(apiConfigProvider);
  if (config.isDemoMode) {
    return InMemoryDistributionRepository(clock: ref.watch(clockProvider));
  }
  return RemoteDistributionRepository(dio: ref.watch(authenticatedDioProvider));
});

final distributionNotifierProvider =
    NotifierProvider<DistributionNotifier, DistributionState>(
      DistributionNotifier.new,
    );

class DistributionNotifier extends Notifier<DistributionState> {
  @override
  DistributionState build() {
    ref.watch(currentUserIdProvider);
    return const DistributionState();
  }

  Future<void> loadTasks() async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await ref.read(distributionRepositoryProvider).getTasks();
    if (!ref.mounted) return;
    result.fold(
      (failure) => state = state.copyWith(isLoading: false, failure: failure),
      (tasks) => state = state.copyWith(isLoading: false, tasks: tasks),
    );
  }

  Future<bool> createTask(CreateDistributionInput input) async {
    if (state.isLoading) return false;
    final permissions = ref.read(currentPermissionProvider);
    if (!permissions.contains(Permission.manageListing)) {
      state = state.copyWith(
        failure: const DistributionPermissionDeniedFailure(
          'Hanya mitra terverifikasi yang dapat membuat tugas distribusi.',
        ),
      );
      return false;
    }

    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await ref
        .read(distributionRepositoryProvider)
        .createTask(input);
    if (!ref.mounted) return false;
    return result.fold<bool>(
      (failure) {
        state = state.copyWith(isLoading: false, failure: failure);
        return false;
      },
      (created) {
        state = state.copyWith(
          isLoading: false,
          tasks: [created, ...state.tasks],
        );
        return true;
      },
    );
  }

  Future<bool> acceptTask(String taskId) async {
    final claims = ref.read(currentClaimsProvider);
    final permissions = ref.read(currentPermissionProvider);
    final userId = claims?.subject;
    if (claims == null ||
        userId == null ||
        !permissions.contains(Permission.manageDistribution)) {
      state = state.copyWith(
        failure: const DistributionPermissionDeniedFailure(
          'Hanya relawan terverifikasi yang dapat mengambil tugas distribusi.',
        ),
      );
      return false;
    }

    return await _runUpdate(
      () => ref
          .read(distributionRepositoryProvider)
          .acceptTask(
            taskId: taskId,
            volunteerId: userId,
            volunteerName: claims.displayName ?? 'Relawan',
          ),
    );
  }

  Future<bool> markPickedUp({
    required String taskId,
    required String pin,
  }) async {
    final claims = ref.read(currentClaimsProvider);
    final permissions = ref.read(currentPermissionProvider);
    final userId = claims?.subject;
    if (claims == null ||
        userId == null ||
        !permissions.contains(Permission.manageDistribution)) {
      state = state.copyWith(
        failure: const DistributionPermissionDeniedFailure(),
      );
      return false;
    }

    return await _runUpdate(
      () => ref
          .read(distributionRepositoryProvider)
          .markPickedUp(taskId: taskId, volunteerId: userId, pin: pin),
    );
  }

  Future<bool> markDelivered({
    required String taskId,
    required String pin,
  }) async {
    final claims = ref.read(currentClaimsProvider);
    final permissions = ref.read(currentPermissionProvider);
    final userId = claims?.subject;
    if (claims == null ||
        userId == null ||
        !permissions.contains(Permission.manageDistribution)) {
      state = state.copyWith(
        failure: const DistributionPermissionDeniedFailure(),
      );
      return false;
    }

    return await _runUpdate(
      () => ref
          .read(distributionRepositoryProvider)
          .markDelivered(taskId: taskId, volunteerId: userId, pin: pin),
    );
  }

  Future<bool> cancelTask(String taskId) async {
    final claims = ref.read(currentClaimsProvider);
    final target = _findById(taskId);
    if (target == null) {
      state = state.copyWith(failure: const DistributionNotFoundFailure());
      return false;
    }

    final isOwner = claims?.subject == target.partnerId;
    final isAdmin = claims?.role == AppRole.admin;
    if (!isOwner && !isAdmin) {
      state = state.copyWith(
        failure: const DistributionPermissionDeniedFailure(
          'Hanya mitra pemilik atau admin yang dapat membatalkan distribusi.',
        ),
      );
      return false;
    }

    final ok = await _runUpdate(
      () => ref.read(distributionRepositoryProvider).cancelTask(taskId: taskId),
    );
    if (ok && ref.mounted) {
      await ref
          .read(listingRepositoryProvider)
          .releaseStock(listingId: target.listingId, quantity: target.portions);
      await ref.read(listingNotifierProvider.notifier).loadListings();
    }
    return ok;
  }

  Future<bool> _runUpdate(
    Future<Either<DistributionFailure, DistributionTask>> Function() action,
  ) async {
    if (state.isLoading) return false;
    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await action();
    if (!ref.mounted) return false;
    return result.fold<bool>(
      (failure) {
        state = state.copyWith(isLoading: false, failure: failure);
        return false;
      },
      (updated) {
        state = state.copyWith(
          isLoading: false,
          tasks: [
            for (final item in state.tasks)
              if (item.id == updated.id) updated else item,
          ],
        );
        return true;
      },
    );
  }

  DistributionTask? _findById(String id) {
    for (final item in state.tasks) {
      if (item.id == id) return item;
    }
    return null;
  }
}
