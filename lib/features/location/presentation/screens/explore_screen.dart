import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/app/shell/app_shell.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/di/global_provider.dart';
import 'package:surplus_share/core/permission/permission_provider.dart';
import 'package:surplus_share/core/shared/widgets/app_bottom_sheet_scaffold.dart';
import 'package:surplus_share/core/shared/widgets/app_empty_state.dart';
import 'package:surplus_share/core/shared/widgets/app_error_banner.dart';
import 'package:surplus_share/core/shared/widgets/app_surface_card.dart';
import 'package:surplus_share/core/theme/app_tokens.dart';
import 'package:surplus_share/features/listing/domain/policy/listing_access_policy.dart';
import 'package:surplus_share/features/listing/presentation/widgets/listing_card.dart';
import 'package:surplus_share/features/location/domain/models/geo_point.dart';
import 'package:surplus_share/features/location/domain/models/location_failure.dart';
import 'package:surplus_share/features/location/domain/policy/radius_notification_policy.dart';
import 'package:surplus_share/features/location/presentation/provider/location_provider.dart';
import 'package:surplus_share/features/location/presentation/widgets/nearby_map_card.dart';
import 'package:surplus_share/features/reservation/presentation/helpers/reservation_action_helper.dart';

@immutable
class _AreaPreset {
  const new({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.point,
  });

  final String id;
  final String name;
  final String subtitle;
  final GeoPoint point;
}

const List<_AreaPreset> _areaPresets = [
  _AreaPreset(
    id: 'jakarta_pusat',
    name: 'Jakarta Pusat',
    subtitle: 'Thamrin, Menteng, Monas',
    point: GeoPoint(latitude: -6.2088, longitude: 106.8456),
  ),
  _AreaPreset(
    id: 'jakarta_selatan',
    name: 'Jakarta Selatan',
    subtitle: 'SCBD, Kemang, Blok M',
    point: GeoPoint(latitude: -6.2297, longitude: 106.8095),
  ),
  _AreaPreset(
    id: 'bandung',
    name: 'Bandung',
    subtitle: 'Dago, Braga, Riau',
    point: GeoPoint(latitude: -6.9175, longitude: 107.6191),
  ),
  _AreaPreset(
    id: 'surabaya',
    name: 'Surabaya',
    subtitle: 'Tunjungan, Gubeng',
    point: GeoPoint(latitude: -7.2575, longitude: 112.7521),
  ),
];

class ExploreScreen extends ConsumerStatefulWidget {
  const new({this.enableNetworkTiles = true, super.key});

  final bool enableNetworkTiles;

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _scrollController = ScrollController();

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

  @override
  Widget build(BuildContext context) {
    ref.listen<({int branchIndex, int count})>(tabReselectProvider, (_, next) {
      if (next.branchIndex == 1) _scrollToTop();
    });

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final currentLocation = ref.watch(
      locationNotifierProvider.select((s) => s.currentLocation),
    );
    final radiusKm = ref.watch(
      locationNotifierProvider.select((s) => s.radiusKm),
    );
    final isLocating = ref.watch(
      locationNotifierProvider.select((s) => s.isLocating),
    );
    final failure = ref.watch(
      locationNotifierProvider.select((s) => s.failure),
    );
    final notificationCount = ref.watch(
      locationNotifierProvider.select((s) => s.recentNotifications.length),
    );
    final nearby = ref.watch(nearbyListingsProvider);
    final permissions = ref.watch(currentPermissionProvider);
    final currentUserId = ref.watch(currentUserIdProvider);
    final locNotifier = ref.read(locationNotifierProvider.notifier);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        title: const Text('Sekitar Anda'),
        actions: [
          IconButton(
            key: const Key('explore_pick_area_button'),
            tooltip: 'Pilih Area Manual',
            onPressed: () => _showAreaPickerSheet(context),
            icon: const Icon(Icons.location_city_outlined),
          ),
          IconButton(
            key: const Key('explore_notifications_button'),
            tooltip: 'Notifikasi Radius Real-Time',
            onPressed: () => _showNotificationsSheet(context),
            icon: Badge(
              isLabelVisible: notificationCount > 0,
              label: Text('$notificationCount'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          IconButton(
            key: const Key('explore_refresh_gps_button'),
            tooltip: 'Perbarui GPS',
            onPressed: isLocating ? null : locNotifier.refreshLocation,
            icon: isLocating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (failure != null) ...[
                AppErrorBanner(
                  message: failure.message,
                  onRetry: switch (failure) {
                    LocationServiceDisabledFailure() =>
                      locNotifier.openLocationSettings,
                    LocationPermissionDeniedForeverFailure() =>
                      locNotifier.openAppSettings,
                    _ => isLocating ? null : locNotifier.refreshLocation,
                  },
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (currentLocation != null) ...[
                NearbyMapCard(
                  userLocation: currentLocation,
                  radiusKm: radiusKm,
                  nearbyListings: nearby,
                  enableNetworkTiles: widget.enableNetworkTiles,
                ),
                const SizedBox(height: AppSpacing.md),
              ] else
                AppSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.location_off_outlined,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              'Aktifkan GPS atau pilih area manual untuk '
                              'melihat peta dan stok surplus dalam radius '
                              '1–3 km.',
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        alignment: WrapAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            key: const Key('explore_pick_area_cta'),
                            onPressed: () => _showAreaPickerSheet(context),
                            icon: const Icon(
                              Icons.location_city_outlined,
                              size: 18,
                            ),
                            label: const Text('Pilih Area'),
                          ),
                          FilledButton.icon(
                            onPressed: isLocating
                                ? null
                                : locNotifier.refreshLocation,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 40),
                            ),
                            icon: const Icon(
                              Icons.my_location_rounded,
                              size: 18,
                            ),
                            label: const Text('Cari GPS'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              AppSurfaceCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Radius Pencarian & Notifikasi',
                            style: textTheme.labelLarge?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${radiusKm.toStringAsFixed(1)} km',
                          style: textTheme.labelLarge?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      key: const Key('explore_radius_slider'),
                      value: radiusKm,
                      min: RadiusNotificationPolicy.minRadiusKm,
                      max: RadiusNotificationPolicy.maxRadiusKm,
                      divisions: 4,
                      label: '${radiusKm.toStringAsFixed(1)} km',
                      onChanged: locNotifier.setNotificationRadius,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (nearby.isEmpty)
                AppEmptyState(
                  icon: Icons.explore_outlined,
                  title: 'Belum Ada Toko di Radius Ini',
                  subtitle:
                      'Perbesar radius hingga 3 km, perbarui GPS, atau pilih '
                      'area lain.',
                  action: OutlinedButton.icon(
                    onPressed: () => _showAreaPickerSheet(context),
                    icon: const Icon(Icons.location_city_outlined, size: 18),
                    label: const Text('Pilih Area'),
                  ),
                )
              else
                for (final entry in nearby) ...[
                  ListingCard(
                    listing: entry.listing,
                    distanceLabel: entry.formattedDistance,
                    isFavoritePartner: entry.isFavoritePartner,
                    onToggleFavorite: () => locNotifier.toggleFavoritePartner(
                      entry.listing.partnerId,
                    ),
                    onAction:
                        ListingAccessPolicy.canClaimChannel(
                          entry.listing,
                          permissions,
                          currentUserId: currentUserId,
                        )
                        ? () => showBookListingSheet(context, entry.listing)
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
            ],
          ),
        ),
      ),
    );
  }

  void _showAreaPickerSheet(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final current = ref.read(locationNotifierProvider).currentLocation;

    unawaited(
      showAppBottomSheet<void>(
        context: context,
        builder: (sheetContext) => AppBottomSheetScaffold(
          title: 'Pilih Area Pencarian',
          subtitle: 'Gunakan area ini saat GPS belum tersedia atau indoor.',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final preset in _areaPresets)
                ListTile(
                  key: Key('area_preset_${preset.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: current == preset.point
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHigh,
                    foregroundColor: current == preset.point
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                    child: const Icon(Icons.location_on_outlined, size: 20),
                  ),
                  title: Text(preset.name),
                  subtitle: Text(preset.subtitle),
                  trailing: current == preset.point
                      ? Icon(Icons.check_rounded, color: colorScheme.primary)
                      : null,
                  onTap: () async {
                    await ref
                        .read(locationNotifierProvider.notifier)
                        .setManualLocation(preset.point);
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                    if (!context.mounted) return;
                    ref
                        .read(snackbarServiceProvider)
                        .showInfo('Lokasi diatur ke ${preset.name}.');
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNotificationsSheet(BuildContext context) {
    final events = ref.read(locationNotifierProvider).recentNotifications;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    unawaited(
      showAppBottomSheet<void>(
        context: context,
        builder: (_) => AppBottomSheetScaffold(
          title: 'Notifikasi Stok Surplus Terdekat',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (events.isEmpty)
                Text(
                  'Belum ada notifikasi baru. Notifikasi otomatis muncul saat '
                  'mitra favorit atau mitra dalam radius mengunggah stok.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                )
              else
                for (final e in events.take(5))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.notifications_active_outlined,
                      color: colorScheme.primary,
                    ),
                    title: Text(e.title),
                    subtitle: Text(e.body),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
