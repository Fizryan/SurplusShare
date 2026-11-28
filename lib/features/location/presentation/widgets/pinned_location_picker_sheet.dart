import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/config/app_map_config.dart';
import 'package:surplus_share/core/di/global_provider.dart';
import 'package:surplus_share/core/permission/app_role.dart';
import 'package:surplus_share/core/shared/widgets/app_bottom_sheet_scaffold.dart';
import 'package:surplus_share/core/theme/app_tokens.dart';
import 'package:surplus_share/features/auth/presentation/widgets/auth_submit_button.dart';
import 'package:surplus_share/features/location/domain/models/geo_point.dart';
import 'package:surplus_share/features/location/presentation/provider/location_provider.dart';
import 'package:surplus_share/features/location/presentation/provider/pinned_location_provider.dart';

class PinnedLocationPickerSheet extends ConsumerStatefulWidget {
  const new({this.enableNetworkTiles = true, super.key});

  final bool enableNetworkTiles;

  @override
  ConsumerState<PinnedLocationPickerSheet> createState() =>
      _PinnedLocationPickerSheetState();
}

class _PinnedLocationPickerSheetState
    extends ConsumerState<PinnedLocationPickerSheet> {
  final _formKey = GlobalKey<FormState>();
  final _mapController = MapController();
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late GeoPoint _selectedPoint;

  static const _defaultPoint = GeoPoint(latitude: -6.2088, longitude: 106.8456);

  @override
  void initState() {
    super.initState();
    final existing = ref.read(pinnedLocationNotifierProvider).myLocation;
    final claims = ref.read(currentClaimsProvider);
    final fallbackPoint = ref.read(locationNotifierProvider).currentLocation;

    _selectedPoint = existing?.point ?? fallbackPoint ?? _defaultPoint;
    _nameController = TextEditingController(
      text: existing?.placeName ?? claims?.displayName ?? '',
    );
    _addressController = TextEditingController(text: existing?.address ?? '');
  }

  @override
  void dispose() {
    _mapController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _selectPoint(GeoPoint point) {
    setState(() => _selectedPoint = point);
    try {
      _mapController.move(point.toLatLng(), _mapController.camera.zoom);
    } on Object {
      // Ignore if map controller is not yet attached.
    }
  }

  Future<void> _useCurrentGps() async {
    final ok = await ref
        .read(locationNotifierProvider.notifier)
        .refreshLocation();
    if (!mounted) return;
    final current = ref.read(locationNotifierProvider).currentLocation;
    if (ok && current != null) {
      _selectPoint(current);
    } else {
      ref
          .read(snackbarServiceProvider)
          .showError(
            ref.read(locationNotifierProvider).failure?.message ??
                'Gagal membaca lokasi GPS. Silakan ketuk peta secara manual.',
          );
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final ok = await ref
        .read(pinnedLocationNotifierProvider.notifier)
        .saveMyLocation(
          placeName: _nameController.text.trim(),
          address: _addressController.text.trim(),
          point: _selectedPoint,
        );
    if (!mounted) return;

    final snack = ref.read(snackbarServiceProvider);
    if (ok) {
      snack.showSuccess('Titik lokasi tetap berhasil disimpan.');
      Navigator.of(context).pop(true);
    } else {
      snack.showError(
        ref.read(pinnedLocationNotifierProvider).failure?.message ??
            'Gagal menyimpan titik lokasi.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final role = ref.watch(currentClaimsProvider)?.role;
    final isRecipient = role == AppRole.verifiedRecipient;
    final isLoading = ref.watch(
      pinnedLocationNotifierProvider.select((s) => s.isLoading),
    );
    final isLocating = ref.watch(
      locationNotifierProvider.select((s) => s.isLocating),
    );

    final title = isRecipient
        ? 'Atur Titik Lokasi Panti / Penerima'
        : 'Atur Titik Lokasi Toko Tetap';
    final nameLabel = isRecipient
        ? 'Nama Panti / Komunitas'
        : 'Nama Toko / Gerai';

    return AppBottomSheetScaffold(
      title: title,
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isRecipient
                  ? 'Ketuk peta untuk menandai titik pengantaran tetap agar '
                        'relawan tahu lokasi tujuan pengantaran.'
                  : 'Ketuk peta untuk mengunci titik toko Anda sehingga lokasi '
                        'stok tidak berubah mengikuti GPS perangkat.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: AppRadius.circular(AppRadius.lg),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                  borderRadius: AppRadius.circular(AppRadius.lg),
                ),
                child: SizedBox(
                  height: 220,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _selectedPoint.toLatLng(),
                      initialZoom: 15,
                      onTap: (_, latLng) => _selectPoint(
                        GeoPoint(
                          latitude: latLng.latitude,
                          longitude: latLng.longitude,
                        ),
                      ),
                    ),
                    children: [
                      if (widget.enableNetworkTiles)
                        TileLayer(
                          urlTemplate: AppMapConfig.tileUrlTemplate,
                          userAgentPackageName:
                              AppMapConfig.userAgentPackageName,
                        ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _selectedPoint.toLatLng(),
                            width: 44,
                            height: 44,
                            child: Icon(
                              Icons.location_pin,
                              size: 40,
                              color: colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Koordinat: '
                    '${_selectedPoint.latitude.toStringAsFixed(5)}, '
                    '${_selectedPoint.longitude.toStringAsFixed(5)}',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: isLocating ? null : _useCurrentGps,
                  icon: isLocating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded, size: 16),
                  label: const Text('Gunakan GPS'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              key: const Key('pinned_location_name'),
              controller: _nameController,
              enabled: !isLoading,
              maxLength: 80,
              decoration: InputDecoration(labelText: nameLabel),
              validator: (v) {
                final text = v?.trim() ?? '';
                if (text.length < 3) return 'Minimal 3 karakter.';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              key: const Key('pinned_location_address'),
              controller: _addressController,
              enabled: !isLoading,
              maxLines: 2,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Alamat Lengkap',
                hintText: 'Jl. Sudirman No. 10, Jakarta Pusat',
              ),
              validator: (v) {
                final text = v?.trim() ?? '';
                if (text.length < 10) {
                  return 'Alamat lengkap minimal 10 karakter.';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            AuthSubmitButton(
              key: const Key('pinned_location_save_button'),
              label: 'Simpan Titik Lokasi Tetap',
              isLoading: isLoading,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
