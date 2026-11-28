import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/di/global_provider.dart';
import 'package:surplus_share/core/shared/widgets/app_bottom_sheet_scaffold.dart';
import 'package:surplus_share/core/shared/widgets/app_surface_card.dart';
import 'package:surplus_share/core/theme/app_tokens.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/core/utils/formatters/app_formatters.dart';
import 'package:surplus_share/features/auth/presentation/widgets/auth_submit_button.dart';
import 'package:surplus_share/features/distribution/domain/models/distribution_task.dart';
import 'package:surplus_share/features/distribution/presentation/provider/distribution_provider.dart';
import 'package:surplus_share/features/listing/domain/models/create_listing_input.dart';
import 'package:surplus_share/features/listing/domain/models/food_safety_declaration.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/listing/presentation/provider/listing_provider.dart';
import 'package:surplus_share/features/location/domain/models/pinned_location.dart';
import 'package:surplus_share/features/location/presentation/provider/pinned_location_provider.dart';
import 'package:surplus_share/features/location/presentation/widgets/pinned_location_picker_sheet.dart';

class CreateListingSheet extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<CreateListingSheet> createState() => _CreateListingSheetState();
}

class _CreateListingSheetState extends ConsumerState<CreateListingSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _origPriceController = TextEditingController(text: '50000');
  final _discPriceController = TextEditingController(text: '25000');
  final _qtyController = TextEditingController(text: '5');
  final _volunteerPortionsController = TextEditingController(text: '0');

  ListingChannel _channel = ListingChannel.discount;
  DiscountFormat _format = DiscountFormat.flashSale;
  HalalStatus _halalStatus = HalalStatus.halalCertified;
  FoodCategory _category = FoodCategory.readyToEat;
  final Set<FoodAllergen> _allergens = {};
  int _pickupDurationHours = 2;
  final int _safeHoursAfterPickup = 4;
  bool _hygieneConfirmed = true;
  bool _showHygieneError = false;
  String? _selectedRecipientId;

  @override
  void initState() {
    super.initState();
    unawaited(
      Future.microtask(() async {
        final notifier = ref.read(pinnedLocationNotifierProvider.notifier);
        final state = ref.read(pinnedLocationNotifierProvider);
        if (state.myLocation == null) await notifier.loadMyLocation();
        if (state.verifiedRecipients.isEmpty) {
          await notifier.loadVerifiedRecipients();
        }
      }),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _origPriceController.dispose();
    _discPriceController.dispose();
    _qtyController.dispose();
    _volunteerPortionsController.dispose();
    super.dispose();
  }

  String? _validateOriginalPrice(String? raw) {
    if (_channel == ListingChannel.donation) return null;
    final price = int.tryParse(raw?.trim() ?? '');
    if (price == null || price < 1000) {
      return 'Min. Rp 1.000';
    }
    if (price > 10000000) {
      return 'Maks. Rp 10 jt';
    }
    return null;
  }

  String? _validateDiscountPrice(String? raw) {
    if (_channel != ListingChannel.discount) return null;
    final disc = int.tryParse(raw?.trim() ?? '');
    if (disc == null || disc <= 0) {
      return 'Harus > 0';
    }
    final orig = int.tryParse(_origPriceController.text.trim()) ?? 0;
    if (orig > 0 && disc >= orig) {
      return 'Harus < harga asli';
    }
    if (orig > 0) {
      final ratio = (orig - disc) / orig;
      if (ratio < 0.10 || ratio > 0.90) {
        return 'Diskon wajib 10%–90%';
      }
    }
    return null;
  }

  String? _validateVolunteerPortions(String? raw) {
    final v = int.tryParse(raw?.trim() ?? '');
    if (v == null || v < 0) return 'Min. 0';
    final total = int.tryParse(_qtyController.text.trim()) ?? 0;
    if (total > 0 && v > total) {
      return 'Maks. $total porsi';
    }
    return null;
  }

  PinnedLocation? _resolveRecipient(List<PinnedLocation> recipients) {
    if (recipients.isEmpty) return null;
    for (final r in recipients) {
      if (r.ownerId == _selectedRecipientId) return r;
    }
    return recipients.first;
  }

  Future<void> _submit() async {
    final validForm = _formKey.currentState?.validate() ?? false;
    if (!_hygieneConfirmed) {
      setState(() => _showHygieneError = true);
      return;
    }
    if (!validForm) return;

    final snack = ref.read(snackbarServiceProvider);
    final claims = ref.read(currentClaimsProvider);
    final partnerId = claims?.subject;
    if (partnerId == null || partnerId.trim().isEmpty) {
      snack.showError('Sesi mitra tidak valid. Silakan masuk kembali.');
      return;
    }

    final pinnedState = ref.read(pinnedLocationNotifierProvider);
    final storeLocation = pinnedState.myLocation;
    if (storeLocation == null) {
      snack.showError(
        'Titik lokasi toko tetap wajib diatur terlebih dahulu sebelum '
        'mengunggah stok.',
      );
      return;
    }

    final qty = int.tryParse(_qtyController.text.trim()) ?? 0;
    final volunteerPortions =
        int.tryParse(_volunteerPortionsController.text.trim()) ?? 0;
    final recipient = _resolveRecipient(pinnedState.verifiedRecipients);
    if (volunteerPortions > 0 && recipient == null) {
      snack.showError(
        'Pilih panti / penerima terverifikasi tujuan untuk porsi relawan.',
      );
      return;
    }

    final now = ref.read(clockProvider)().toUtc();
    final pickupStart = now.add(const Duration(minutes: 15));
    final pickupEnd = pickupStart.add(Duration(hours: _pickupDurationHours));
    final origPrice = _channel == ListingChannel.donation
        ? 0
        : (int.tryParse(_origPriceController.text.trim()) ?? 0);
    final discPrice = _channel == ListingChannel.donation
        ? 0
        : (int.tryParse(_discPriceController.text.trim()) ?? 0);

    final input = CreateListingInput(
      partnerId: partnerId,
      partnerName: storeLocation.placeName,
      title: _titleController.text.trim(),
      description: _descController.text.trim(),
      channel: _channel,
      discountFormat: _channel == ListingChannel.discount ? _format : null,
      originalPrice: origPrice,
      discountedPrice: discPrice,
      quantity: qty,
      volunteerAllocatedPortions: volunteerPortions,
      pickupStart: pickupStart,
      pickupEnd: pickupEnd,
      location: storeLocation.point,
      address: storeLocation.address,
      foodSafety: FoodSafetyDeclaration(
        halalStatus: _halalStatus,
        category: _category,
        allergens: Set<FoodAllergen>.unmodifiable(_allergens),
        safeUntil: pickupEnd.add(Duration(hours: _safeHoursAfterPickup)),
        hygieneConfirmed: _hygieneConfirmed,
      ),
    );

    final ok = await ref
        .read(listingNotifierProvider.notifier)
        .createListing(input);
    if (!mounted) return;
    if (!ok) {
      final msg =
          ref.read(listingNotifierProvider).failure?.message ??
          'Gagal mengunggah stok.';
      snack.showError(msg);
      return;
    }

    if (volunteerPortions > 0 && recipient != null) {
      final createdListing = ref.read(listingNotifierProvider).items.first;
      await ref
          .read(distributionNotifierProvider.notifier)
          .createTask(
            CreateDistributionInput(
              listingId: createdListing.id,
              listingTitle: createdListing.title,
              partnerId: partnerId,
              partnerName: storeLocation.placeName,
              storeAddress: storeLocation.address,
              storeLocation: storeLocation.point,
              recipientId: recipient.ownerId,
              recipientName: recipient.placeName,
              recipientAddress: recipient.address,
              recipientLocation: recipient.point,
              portions: volunteerPortions,
            ),
          );
      if (!mounted) return;
    }

    snack.showSuccess(
      volunteerPortions > 0
          ? 'Stok diunggah & $volunteerPortions porsi dikirim ke relawan.'
          : 'Stok berhasil diunggah.',
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final isLoading = ref.watch(
      listingNotifierProvider.select((s) => s.isLoading),
    );
    final storeLocation = ref.watch(
      pinnedLocationNotifierProvider.select((s) => s.myLocation),
    );
    final recipients = ref.watch(
      pinnedLocationNotifierProvider.select((s) => s.verifiedRecipients),
    );
    final volunteerPortions =
        int.tryParse(_volunteerPortionsController.text.trim()) ?? 0;
    final selectedRecipient = _resolveRecipient(recipients);

    return AppBottomSheetScaffold(
      title: 'Unggah Stok Makanan Surplus',
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSurfaceCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.location_pin,
                    color: storeLocation != null
                        ? colorScheme.primary
                        : colorScheme.error,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          storeLocation != null
                              ? 'Lokasi Toko Tetap: ${storeLocation.placeName}'
                              : 'Lokasi Toko Tetap Belum Diatur',
                          style: textTheme.labelLarge?.copyWith(
                            color: storeLocation != null
                                ? colorScheme.onSurface
                                : colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          storeLocation?.address ??
                              'Wajib tandai titik peta toko agar posisi '
                                  'listing tidak mengikuti GPS perangkat.',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    key: const Key('create_listing_pin_store_button'),
                    onPressed: () => showAppBottomSheet<void>(
                      context: context,
                      builder: (_) => const PinnedLocationPickerSheet(),
                    ),
                    child: Text(storeLocation != null ? 'Ubah' : 'Atur Pin'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<ListingChannel>(
              segments: const [
                ButtonSegment(
                  value: ListingChannel.discount,
                  label: Text('Mode Diskon'),
                  icon: Icon(Icons.local_offer_outlined),
                ),
                ButtonSegment(
                  value: ListingChannel.donation,
                  label: Text('Donasi Gratis'),
                  icon: Icon(Icons.volunteer_activism_outlined),
                ),
              ],
              selected: {_channel},
              onSelectionChanged: (s) => setState(() => _channel = s.first),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const Key('create_listing_title'),
              controller: _titleController,
              enabled: !isLoading,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Nama Paket Makanan',
                hintText: 'Mis. Paket Nasi Campur Sore',
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Nama paket wajib diisi.';
                if (text.length < 3) return 'Minimal 3 karakter.';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              key: const Key('create_listing_desc'),
              controller: _descController,
              enabled: !isLoading,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Deskripsi Singkat',
                hintText: 'Kondisi segar, dikemas rapi',
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Deskripsi wajib diisi.';
                if (text.length < 5) return 'Minimal 5 karakter.';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_channel == ListingChannel.discount)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('create_listing_orig_price'),
                      controller: _origPriceController,
                      enabled: !isLoading,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Harga Asli (Rp)',
                      ),
                      onChanged: (_) => _formKey.currentState?.validate(),
                      validator: _validateOriginalPrice,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextFormField(
                      key: const Key('create_listing_disc_price'),
                      controller: _discPriceController,
                      enabled: !isLoading,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Harga Diskon (Rp)',
                      ),
                      validator: _validateDiscountPrice,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(
                    width: 84,
                    child: TextFormField(
                      key: const Key('create_listing_qty'),
                      controller: _qtyController,
                      enabled: !isLoading,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Porsi'),
                      onChanged: (_) => _formKey.currentState?.validate(),
                      validator: (v) {
                        final qty = int.tryParse(v?.trim() ?? '') ?? 0;
                        if (qty <= 0) return 'Min. 1';
                        if (qty > 500) return 'Maks. 500';
                        return null;
                      },
                    ),
                  ),
                ],
              )
            else
              TextFormField(
                key: const Key('create_listing_qty'),
                controller: _qtyController,
                enabled: !isLoading,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Jumlah Porsi Donasi Gratis',
                  helperText:
                      'Langsung terbit sebagai Donasi Gratis tanpa perlu '
                      'mode Flash Sale / Surprise Bag.',
                ),
                onChanged: (_) => _formKey.currentState?.validate(),
                validator: (v) {
                  final qty = int.tryParse(v?.trim() ?? '') ?? 0;
                  if (qty <= 0) return 'Min. 1';
                  if (qty > 500) return 'Maks. 500';
                  return null;
                },
              ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              key: const Key('create_listing_volunteer_portions'),
              controller: _volunteerPortionsController,
              enabled: !isLoading,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Porsi untuk Relawan Distribusi (Opsional)',
                helperText:
                    'Diisi > 0 jika sebagian porsi diantar relawan ke panti.',
              ),
              onChanged: (_) => setState(() {}),
              validator: _validateVolunteerPortions,
            ),
            if (volunteerPortions > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              if (recipients.isEmpty)
                Text(
                  'Belum ada penerima terverifikasi yang menandai titik peta.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                  ),
                )
              else
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final r in recipients)
                      ChoiceChip(
                        label: Text(r.placeName),
                        selected: selectedRecipient?.ownerId == r.ownerId,
                        onSelected: (_) =>
                            setState(() => _selectedRecipientId = r.ownerId),
                      ),
                  ],
                ),
            ],
            if (_channel == ListingChannel.discount) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  ChoiceChip(
                    label: const Text('Flash Sale (10–90%)'),
                    selected: _format == DiscountFormat.flashSale,
                    onSelected: (_) =>
                        setState(() => _format = DiscountFormat.flashSale),
                  ),
                  ChoiceChip(
                    label: const Text('Surprise Bag'),
                    selected: _format == DiscountFormat.surpriseBag,
                    onSelected: (_) =>
                        setState(() => _format = DiscountFormat.surpriseBag),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Text(
              'Jendela Pengambilan: $_pickupDurationHours jam '
              '• Aman konsumsi: +$_safeHoursAfterPickup jam',
              style: textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Slider(
              value: _pickupDurationHours.toDouble(),
              min: 1,
              max: 12,
              divisions: 11,
              label: '$_pickupDurationHours jam',
              onChanged: (v) =>
                  setState(() => _pickupDurationHours = v.round()),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Deklarasi Halal & Kategori',
              style: textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final h in HalalStatus.values)
                  ChoiceChip(
                    label: Text(AppFormatters.halalLabel(h)),
                    selected: _halalStatus == h,
                    onSelected: (_) => setState(() => _halalStatus = h),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final c in FoodCategory.values)
                  ChoiceChip(
                    label: Text(AppFormatters.foodCategoryLabel(c)),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final a in FoodAllergen.values)
                  FilterChip(
                    label: Text(AppFormatters.allergenLabel(a)),
                    selected: _allergens.contains(a),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _allergens.add(a);
                      } else {
                        _allergens.remove(a);
                      }
                    }),
                  ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _hygieneConfirmed,
              onChanged: (v) => setState(() {
                _hygieneConfirmed = v ?? false;
                if (_hygieneConfirmed) _showHygieneError = false;
              }),
              title: const Text(
                'Saya menyatakan makanan higienis dan layak konsumsi.',
              ),
            ),
            if (_showHygieneError && !_hygieneConfirmed)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  'Konfirmasi higienitas wajib dicentang sebelum publikasi.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            AuthSubmitButton(
              key: const Key('create_listing_submit'),
              label: 'Publikasikan Stok',
              isLoading: isLoading,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
