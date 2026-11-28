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
import 'package:surplus_share/features/reservation/domain/models/reservation_status.dart';
import 'package:surplus_share/features/reservation/domain/policy/reservation_policy.dart';
import 'package:surplus_share/features/reservation/presentation/provider/reservation_provider.dart';
import 'package:surplus_share/features/reservation/presentation/widgets/pin_validation_sheet.dart';
import 'package:surplus_share/features/reservation/presentation/widgets/reservation_card.dart';

enum _ReservationView { incoming, mine }

class ReservationsScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ReservationsScreen> createState() => _ReservationsScreenState();
}

class _ReservationsScreenState extends ConsumerState<ReservationsScreen> {
  final _scrollController = ScrollController();
  _ReservationView _view = _ReservationView.incoming;

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

  Future<void> _refresh(bool isPartnerOrStaff) {
    final notifier = ref.read(reservationNotifierProvider.notifier);
    if (isPartnerOrStaff && _view == _ReservationView.incoming) {
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

  @override
  Widget build(BuildContext context) {
    ref.listen<({int branchIndex, int count})>(tabReselectProvider, (_, next) {
      if (next.branchIndex == 2) _scrollToTop();
    });

    final colorScheme = Theme.of(context).colorScheme;
    final items = ref.watch(reservationNotifierProvider.select((s) => s.items));
    final isLoading = ref.watch(
      reservationNotifierProvider.select((s) => s.isLoading),
    );
    final failure = ref.watch(
      reservationNotifierProvider.select((s) => s.failure),
    );
    final permissions = ref.watch(currentPermissionProvider);
    final claims = ref.watch(currentClaimsProvider);
    final isPartnerOrStaff = permissions.contains(Permission.validatePickupPin);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        title: const Text('Reservasi & PIN'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            children: [
              if (failure != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    0,
                  ),
                  child: AppErrorBanner(
                    message: failure.message,
                    onRetry: () => _refresh(isPartnerOrStaff),
                  ),
                ),
              if (isPartnerOrStaff)
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
                        label: Text('Pesanan Masuk'),
                        icon: Icon(Icons.storefront_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: _ReservationView.mine,
                        label: Text('Reservasi Saya'),
                        icon: Icon(Icons.receipt_long_outlined, size: 18),
                      ),
                    ],
                    selected: {_view},
                    onSelectionChanged: (selected) {
                      setState(() => _view = selected.first);
                      unawaited(_refresh(isPartnerOrStaff));
                    },
                  ),
                ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: isLoading && items.isEmpty
                      ? ListView.separated(
                          key: const ValueKey('reservations_skeleton'),
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          itemCount: 3,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.md),
                          itemBuilder: (_, _) => const AppSkeletonCard(),
                        )
                      : items.isEmpty
                      ? AppEmptyState(
                          key: const ValueKey('reservations_empty'),
                          icon: Icons.receipt_long_outlined,
                          title:
                              isPartnerOrStaff &&
                                  _view == _ReservationView.incoming
                              ? 'Belum Ada Pesanan Masuk'
                              : 'Belum Ada Reservasi',
                          subtitle:
                              isPartnerOrStaff &&
                                  _view == _ReservationView.incoming
                              ? 'Pesanan pelanggan untuk gerai Anda akan '
                                    'muncul di sini untuk validasi PIN.'
                              : 'Pesan paket diskon atau klaim donasi di '
                                    'Beranda untuk mendapatkan kode PIN.',
                        )
                      : RefreshIndicator(
                          key: const ValueKey('reservations_list'),
                          onRefresh: () => _refresh(isPartnerOrStaff),
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
                                    actorUserId: claims?.subject,
                                    role: claims?.role ?? AppRole.consumer,
                                    permissions: permissions,
                                  );

                              return ReservationCard(
                                reservation: item,
                                now: now,
                                isBusy: isLoading,
                                onPinCopied: () => ref
                                    .read(snackbarServiceProvider)
                                    .showInfo('Kode PIN disalin.'),
                                onConfirmPayment:
                                    status == ReservationStatus.pendingPayment
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
