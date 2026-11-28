import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/app/shell/app_shell.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/di/global_provider.dart';
import 'package:surplus_share/core/permission/app_role.dart';
import 'package:surplus_share/core/permission/permission.dart';
import 'package:surplus_share/core/permission/permission_provider.dart';
import 'package:surplus_share/core/shared/widgets/app_bottom_sheet_scaffold.dart';
import 'package:surplus_share/core/shared/widgets/app_empty_state.dart';
import 'package:surplus_share/core/shared/widgets/app_error_banner.dart';
import 'package:surplus_share/core/shared/widgets/app_skeleton_card.dart';
import 'package:surplus_share/core/theme/app_tokens.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/features/distribution/domain/models/distribution_task.dart';
import 'package:surplus_share/features/distribution/presentation/provider/distribution_provider.dart';
import 'package:surplus_share/features/distribution/presentation/widgets/distribution_pin_sheet.dart';
import 'package:surplus_share/features/distribution/presentation/widgets/distribution_task_card.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation_status.dart';
import 'package:surplus_share/features/reservation/domain/policy/reservation_policy.dart';
import 'package:surplus_share/features/reservation/presentation/provider/reservation_provider.dart';
import 'package:surplus_share/features/reservation/presentation/widgets/pin_validation_sheet.dart';
import 'package:surplus_share/features/reservation/presentation/widgets/reservation_card.dart';

enum _ReservationView { incoming, mine, distribution }

enum _VolunteerView { available, mine }

class ReservationsScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ReservationsScreen> createState() => _ReservationsScreenState();
}

class _ReservationsScreenState extends ConsumerState<ReservationsScreen> {
  final _scrollController = ScrollController();
  _ReservationView _view = _ReservationView.incoming;
  _VolunteerView _volunteerView = _VolunteerView.available;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _refresh({
    required bool isPartner,
    required bool isVolunteer,
    required _ReservationView activeView,
  }) {
    if (isVolunteer || activeView == _ReservationView.distribution) {
      return ref.read(distributionNotifierProvider.notifier).loadTasks();
    }
    final notifier = ref.read(reservationNotifierProvider.notifier);
    if (isPartner && activeView == _ReservationView.incoming) {
      return notifier.loadPartnerReservations();
    }
    return notifier.loadMyReservations();
  }

  Future<void> _confirmPayment(String reservationId) async {
    final ok = await ref
        .read(reservationNotifierProvider.notifier)
        .confirmPayment(reservationId);
    final snack = ref.read(snackbarServiceProvider);
    if (ok) {
      snack.showSuccess('Pembayaran dikonfirmasi! PIN siap digunakan.');
    } else {
      final err = ref.read(reservationNotifierProvider).failure;
      snack.showError(err?.message ?? 'Gagal mengonfirmasi pembayaran.');
    }
  }

  Future<void> _confirmAndCancel(String reservationId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Batalkan Reservasi?'),
        content: const Text(
          'Stok makanan akan dilepas kembali untuk pengguna lain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Ya, Batalkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await ref
        .read(reservationNotifierProvider.notifier)
        .cancelReservation(reservationId);
    final snack = ref.read(snackbarServiceProvider);
    if (ok) {
      snack.showInfo('Reservasi dibatalkan.');
    } else {
      snack.showError(
        ref.read(reservationNotifierProvider).failure?.message ??
            'Gagal membatalkan reservasi.',
      );
    }
  }

  Future<void> _runDistributionAction(
    Future<bool> Function() action,
    String successMessage,
  ) async {
    final ok = await action();
    final snack = ref.read(snackbarServiceProvider);
    if (ok) {
      snack.showSuccess(successMessage);
    } else {
      snack.showError(
        ref.read(distributionNotifierProvider).failure?.message ??
            'Gagal memperbarui status distribusi.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<({int branchIndex, int count})>(tabReselectProvider, (_, next) {
      if (next.branchIndex == 2) _scrollToTop();
    });

    final colorScheme = Theme.of(context).colorScheme;
    final permissions = ref.watch(currentPermissionProvider);
    final claims = ref.watch(currentClaimsProvider);
    final role = claims?.role ?? AppRole.consumer;
    final isVolunteer = role == AppRole.volunteer;
    final isPartner = permissions.contains(Permission.validatePickupPin);
    final isRecipient = role == AppRole.verifiedRecipient;

    final activeView = isPartner
        ? _view
        : (isRecipient && _view == _ReservationView.distribution)
        ? _ReservationView.distribution
        : _ReservationView.mine;

    final showDistribution =
        isVolunteer || activeView == _ReservationView.distribution;

    final items = ref.watch(reservationNotifierProvider.select((s) => s.items));
    final isLoading = showDistribution
        ? ref.watch(distributionNotifierProvider.select((s) => s.isLoading))
        : ref.watch(reservationNotifierProvider.select((s) => s.isLoading));
    final failureMessage = showDistribution
        ? ref.watch(
            distributionNotifierProvider.select((s) => s.failure?.message),
          )
        : ref.watch(
            reservationNotifierProvider.select((s) => s.failure?.message),
          );

    final allTasks = ref.watch(
      distributionNotifierProvider.select((s) => s.tasks),
    );
    final visibleTasks = _filterTasks(
      allTasks,
      role: role,
      userId: claims?.subject,
      volunteerView: _volunteerView,
    );

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        title: Text(isVolunteer ? 'Distribusi Relawan' : 'Reservasi & PIN'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            children: [
              if (failureMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    0,
                  ),
                  child: AppErrorBanner(
                    message: failureMessage,
                    onRetry: () => _refresh(
                      isPartner: isPartner,
                      isVolunteer: isVolunteer,
                      activeView: activeView,
                    ),
                  ),
                ),
              if (isVolunteer)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.xs,
                  ),
                  child: SegmentedButton<_VolunteerView>(
                    key: const Key('volunteer_view_segmented'),
                    segments: const [
                      ButtonSegment(
                        value: _VolunteerView.available,
                        label: Text('Tugas Tersedia'),
                        icon: Icon(Icons.local_shipping_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: _VolunteerView.mine,
                        label: Text('Tugas Saya'),
                        icon: Icon(
                          Icons.assignment_turned_in_outlined,
                          size: 18,
                        ),
                      ),
                    ],
                    selected: {_volunteerView},
                    onSelectionChanged: (selected) {
                      setState(() => _volunteerView = selected.first);
                      unawaited(
                        ref
                            .read(distributionNotifierProvider.notifier)
                            .loadTasks(),
                      );
                    },
                  ),
                )
              else if (isPartner)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.xs,
                  ),
                  child: SegmentedButton<_ReservationView>(
                    key: const Key('reservations_view_segmented'),
                    segments: const [
                      ButtonSegment(
                        value: _ReservationView.incoming,
                        label: Text('Masuk'),
                        icon: Icon(Icons.storefront_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: _ReservationView.distribution,
                        label: Text('Distribusi'),
                        icon: Icon(Icons.local_shipping_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: _ReservationView.mine,
                        label: Text('Saya'),
                        icon: Icon(Icons.receipt_long_outlined, size: 18),
                      ),
                    ],
                    selected: {activeView},
                    onSelectionChanged: (selected) {
                      final next = selected.first;
                      setState(() => _view = next);
                      unawaited(
                        _refresh(
                          isPartner: isPartner,
                          isVolunteer: isVolunteer,
                          activeView: next,
                        ),
                      );
                    },
                  ),
                )
              else if (isRecipient)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.xs,
                  ),
                  child: SegmentedButton<_ReservationView>(
                    key: const Key('recipient_view_segmented'),
                    segments: const [
                      ButtonSegment(
                        value: _ReservationView.mine,
                        label: Text('Reservasi Saya'),
                        icon: Icon(Icons.receipt_long_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: _ReservationView.distribution,
                        label: Text('Antar Relawan'),
                        icon: Icon(Icons.local_shipping_outlined, size: 18),
                      ),
                    ],
                    selected: {activeView},
                    onSelectionChanged: (selected) {
                      final next = selected.first;
                      setState(() => _view = next);
                      unawaited(
                        _refresh(
                          isPartner: isPartner,
                          isVolunteer: isVolunteer,
                          activeView: next,
                        ),
                      );
                    },
                  ),
                ),
              Expanded(
                child: showDistribution
                    ? _buildDistributionBody(
                        tasks: visibleTasks,
                        isLoading: isLoading,
                        isVolunteer: isVolunteer,
                        isPartner: isPartner,
                        userId: claims?.subject,
                        permissions: permissions,
                      )
                    : _buildReservationsBody(
                        items: items,
                        isLoading: isLoading,
                        isPartner: isPartner,
                        activeView: activeView,
                        claimsUserId: claims?.subject,
                        role: role,
                        permissions: permissions,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDistributionBody({
    required List<DistributionTask> tasks,
    required bool isLoading,
    required bool isVolunteer,
    required bool isPartner,
    required String? userId,
    required Set<Permission> permissions,
  }) {
    final canActAsVolunteer = permissions.contains(
      Permission.manageDistribution,
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: isLoading && tasks.isEmpty
          ? ListView.separated(
              key: const ValueKey('distribution_skeleton'),
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: 3,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (_, _) => const AppSkeletonCard(),
            )
          : tasks.isEmpty
          ? AppEmptyState(
              key: const ValueKey('distribution_empty'),
              icon: Icons.local_shipping_outlined,
              title: isVolunteer && _volunteerView == _VolunteerView.available
                  ? 'Belum Ada Tugas Distribusi'
                  : 'Belum Ada Pengantaran Relawan',
              subtitle: isVolunteer
                  ? 'Tugas distribusi dari mitra ke panti terverifikasi akan '
                        'muncul di sini.'
                  : 'Alokasikan porsi relawan saat unggah stok atau pada '
                        'listing aktif di Beranda.',
            )
          : RefreshIndicator(
              key: const ValueKey('distribution_list'),
              onRefresh: () =>
                  ref.read(distributionNotifierProvider.notifier).loadTasks(),
              child: ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: tasks.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, index) {
                  final task = tasks[index];
                  final notifier = ref.read(
                    distributionNotifierProvider.notifier,
                  );
                  final isAssignedToMe =
                      userId != null && task.volunteerId == userId;
                  final isOwnerPartner =
                      isPartner && userId != null && task.partnerId == userId;
                  final isRecipientOwner =
                      userId != null && task.recipientId == userId;
                  final isAdmin =
                      ref.read(currentClaimsProvider)?.role == AppRole.admin;

                  return DistributionTaskCard(
                    task: task,
                    isBusy: isLoading,
                    showPickupPin: isOwnerPartner || isAdmin,
                    showDeliveryPin: isRecipientOwner || isAdmin,
                    onPinCopied: () => ref
                        .read(snackbarServiceProvider)
                        .showInfo('Kode PIN disalin.'),
                    onAccept:
                        canActAsVolunteer &&
                            task.status == DistributionStatus.open
                        ? () => _runDistributionAction(
                            () => notifier.acceptTask(task.id),
                            'Tugas distribusi diambil. Minta PIN Pickup ke '
                            '${task.partnerName}.',
                          )
                        : null,
                    onMarkPickedUp:
                        canActAsVolunteer &&
                            isAssignedToMe &&
                            task.status == DistributionStatus.accepted
                        ? () => showAppBottomSheet<void>(
                            context: context,
                            builder: (_) => DistributionPinSheet(
                              taskId: task.id,
                              listingTitle: task.listingTitle,
                              counterpartyName: task.partnerName,
                              mode: DistributionPinMode.pickup,
                            ),
                          )
                        : null,
                    onMarkDelivered:
                        canActAsVolunteer &&
                            isAssignedToMe &&
                            task.status == DistributionStatus.pickedUp
                        ? () => showAppBottomSheet<void>(
                            context: context,
                            builder: (_) => DistributionPinSheet(
                              taskId: task.id,
                              listingTitle: task.listingTitle,
                              counterpartyName: task.recipientName,
                              mode: DistributionPinMode.delivery,
                            ),
                          )
                        : null,
                    onCancel: isOwnerPartner && task.canCancel
                        ? () => _runDistributionAction(
                            () => notifier.cancelTask(task.id),
                            'Tugas distribusi dibatalkan & porsi dikembalikan.',
                          )
                        : null,
                  );
                },
              ),
            ),
    );
  }

  Widget _buildReservationsBody({
    required List<Reservation> items,
    required bool isLoading,
    required bool isPartner,
    required _ReservationView activeView,
    required String? claimsUserId,
    required AppRole role,
    required Set<Permission> permissions,
  }) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: isLoading && items.isEmpty
          ? ListView.separated(
              key: const ValueKey('reservations_skeleton'),
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: 3,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (_, _) => const AppSkeletonCard(),
            )
          : items.isEmpty
          ? AppEmptyState(
              key: const ValueKey('reservations_empty'),
              icon: Icons.receipt_long_outlined,
              title: isPartner && activeView == _ReservationView.incoming
                  ? 'Belum Ada Pesanan Masuk'
                  : 'Belum Ada Reservasi',
              subtitle: isPartner && activeView == _ReservationView.incoming
                  ? 'Pesanan pelanggan untuk gerai Anda akan muncul di sini '
                        'untuk validasi PIN.'
                  : 'Pesan paket diskon atau klaim donasi di Beranda untuk '
                        'mendapatkan kode PIN.',
            )
          : RefreshIndicator(
              key: const ValueKey('reservations_list'),
              onRefresh: () => _refresh(
                isPartner: isPartner,
                isVolunteer: false,
                activeView: activeView,
              ),
              child: ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: items.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final now = ref.read(clockProvider)();
                  final status = item.effectiveStatus(now: now);
                  final canValidate =
                      status == ReservationStatus.confirmed &&
                      ReservationPolicy.canValidateHandover(
                        item,
                        actorUserId: claimsUserId,
                        role: role,
                        permissions: permissions,
                      );

                  return ReservationCard(
                    reservation: item,
                    now: now,
                    isBusy: isLoading,
                    showPickupPin: item.customerId == claimsUserId,
                    onPinCopied: () => ref
                        .read(snackbarServiceProvider)
                        .showInfo('Kode PIN disalin.'),
                    onConfirmPayment: status == ReservationStatus.pendingPayment
                        ? () => _confirmPayment(item.id)
                        : null,
                    onCancel: item.canCancel(now: now)
                        ? () => _confirmAndCancel(item.id)
                        : null,
                    onValidatePin: canValidate
                        ? () => showAppBottomSheet<void>(
                            context: context,
                            builder: (_) => PinValidationSheet(
                              reservationId: item.id,
                              listingTitle: item.listingTitle,
                            ),
                          )
                        : null,
                  );
                },
              ),
            ),
    );
  }
}

List<DistributionTask> _filterTasks(
  List<DistributionTask> tasks, {
  required AppRole role,
  required String? userId,
  required _VolunteerView volunteerView,
}) {
  if (role == AppRole.volunteer) {
    if (volunteerView == _VolunteerView.available) {
      return tasks
          .where((t) => t.status == DistributionStatus.open)
          .toList(growable: false);
    }
    return tasks
        .where((t) => userId != null && t.volunteerId == userId)
        .toList(growable: false);
  }
  if (role == AppRole.donorPartner) {
    return tasks
        .where((t) => userId != null && t.partnerId == userId)
        .toList(growable: false);
  }
  if (role == AppRole.verifiedRecipient) {
    return tasks
        .where((t) => userId != null && t.recipientId == userId)
        .toList(growable: false);
  }
  return tasks;
}
