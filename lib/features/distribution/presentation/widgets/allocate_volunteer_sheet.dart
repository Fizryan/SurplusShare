import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/di/global_provider.dart';
import 'package:surplus_share/core/shared/widgets/app_bottom_sheet_scaffold.dart';
import 'package:surplus_share/core/theme/app_tokens.dart';
import 'package:surplus_share/features/auth/presentation/widgets/auth_submit_button.dart';
import 'package:surplus_share/features/distribution/domain/models/distribution_task.dart';
import 'package:surplus_share/features/distribution/presentation/provider/distribution_provider.dart';
import 'package:surplus_share/features/listing/domain/models/surplus_listing.dart';
import 'package:surplus_share/features/listing/presentation/provider/listing_provider.dart';
import 'package:surplus_share/features/location/domain/models/pinned_location.dart';
import 'package:surplus_share/features/location/presentation/provider/pinned_location_provider.dart';

class AllocateVolunteerSheet extends ConsumerStatefulWidget {
  const new({required this.listing, super.key});

  final SurplusListing listing;

  @override
  ConsumerState<AllocateVolunteerSheet> createState() =>
      _AllocateVolunteerSheetState();
}

class _AllocateVolunteerSheetState
    extends ConsumerState<AllocateVolunteerSheet> {
  final _formKey = GlobalKey<FormState>();
  final _portionsController = TextEditingController(text: '1');
  String? _selectedRecipientId;

  @override
  void initState() {
    super.initState();
    final recipients = ref
        .read(pinnedLocationNotifierProvider)
        .verifiedRecipients;
    if (recipients.isNotEmpty) {
      _selectedRecipientId = recipients.first.ownerId;
    } else {
      unawaited(
        Future.microtask(
          () => ref
              .read(pinnedLocationNotifierProvider.notifier)
              .loadVerifiedRecipients(),
        ),
      );
    }
  }

  @override
  void dispose() {
    _portionsController.dispose();
    super.dispose();
  }

  Future<void> _submit(List<PinnedLocation> recipients) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final snack = ref.read(snackbarServiceProvider);

    final storeLoc = ref.read(pinnedLocationNotifierProvider).myLocation;
    final storePoint = storeLoc?.point ?? widget.listing.location;
    final storeAddress = storeLoc?.address ?? widget.listing.address ?? '';
    if (storePoint == null || storeAddress.trim().length < 5) {
      snack.showError(
        'Titik lokasi toko tetap belum diatur. Silakan atur di Dampak & '
        'Profil terlebih dahulu.',
      );
      return;
    }

    final target = _resolveRecipient(recipients);
    if (target == null) {
      snack.showError('Pilih panti / penerima terverifikasi tujuan.');
      return;
    }

    final portions = int.tryParse(_portionsController.text.trim()) ?? 0;
    final allocated = await ref
        .read(listingNotifierProvider.notifier)
        .allocateVolunteerPortions(
          listingId: widget.listing.id,
          portions: portions,
        );
    if (!mounted) return;
    if (!allocated) {
      snack.showError(
        ref.read(listingNotifierProvider).failure?.message ??
            'Gagal mengalokasikan porsi relawan.',
      );
      return;
    }

    final created = await ref
        .read(distributionNotifierProvider.notifier)
        .createTask(
          CreateDistributionInput(
            listingId: widget.listing.id,
            listingTitle: widget.listing.title,
            partnerId: widget.listing.partnerId,
            partnerName: widget.listing.partnerName,
            storeAddress: storeAddress,
            storeLocation: storePoint,
            recipientId: target.ownerId,
            recipientName: target.placeName,
            recipientAddress: target.address,
            recipientLocation: target.point,
            portions: portions,
          ),
        );
    if (!mounted) return;
    if (created) {
      snack.showSuccess(
        '$portions porsi dialokasikan untuk diantar relawan ke '
        '${target.placeName}.',
      );
      Navigator.of(context).pop(true);
    } else {
      snack.showError(
        ref.read(distributionNotifierProvider).failure?.message ??
            'Gagal membuat tugas distribusi relawan.',
      );
    }
  }

  PinnedLocation? _resolveRecipient(List<PinnedLocation> recipients) {
    if (recipients.isEmpty) return null;
    for (final r in recipients) {
      if (r.ownerId == _selectedRecipientId) return r;
    }
    return recipients.first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final recipients = ref.watch(
      pinnedLocationNotifierProvider.select((s) => s.verifiedRecipients),
    );
    final isBusy =
        ref.watch(listingNotifierProvider.select((s) => s.isLoading)) ||
        ref.watch(distributionNotifierProvider.select((s) => s.isLoading));
    final selected = _resolveRecipient(recipients);

    return AppBottomSheetScaffold(
      title: 'Alokasi Porsi untuk Relawan',
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.listing.title} • Sisa stok publik: '
              '${widget.listing.remainingQuantity} porsi',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const Key('allocate_volunteer_portions_field'),
              controller: _portionsController,
              enabled: !isBusy,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Jumlah Porsi untuk Relawan',
                helperText:
                    'Maksimal ${widget.listing.remainingQuantity} porsi',
              ),
              validator: (raw) {
                final v = int.tryParse(raw?.trim() ?? '') ?? 0;
                if (v <= 0) return 'Minimal 1 porsi.';
                if (v > widget.listing.remainingQuantity) {
                  return 'Maksimal ${widget.listing.remainingQuantity} porsi.';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            if (recipients.isEmpty)
              Text(
                'Belum ada penerima terverifikasi dengan titik peta tetap.',
                style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
              )
            else ...[
              Text(
                'Tujuan Penerima Terverifikasi',
                style: textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              for (final recipient in recipients)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: !isBusy,
                  leading: Icon(
                    selected?.ownerId == recipient.ownerId
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected?.ownerId == recipient.ownerId
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  title: Text(recipient.placeName),
                  subtitle: Text(recipient.address),
                  onTap: isBusy
                      ? null
                      : () => setState(
                          () => _selectedRecipientId = recipient.ownerId,
                        ),
                ),
            ],
            const SizedBox(height: AppSpacing.md),
            AuthSubmitButton(
              key: const Key('allocate_volunteer_submit'),
              label: 'Kirim ke Antrean Relawan',
              isLoading: isBusy,
              onPressed: () {
                if (recipients.isEmpty) {
                  ref
                      .read(snackbarServiceProvider)
                      .showError(
                        'Belum ada penerima terverifikasi dengan titik peta.',
                      );
                  return;
                }
                unawaited(_submit(recipients));
              },
            ),
          ],
        ),
      ),
    );
  }
}
