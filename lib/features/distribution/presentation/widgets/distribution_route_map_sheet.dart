import 'package:flutter_map/flutter_map.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/config/app_map_config.dart';
import 'package:surplus_share/core/shared/widgets/app_bottom_sheet_scaffold.dart';
import 'package:surplus_share/core/theme/app_tokens.dart';
import 'package:surplus_share/features/distribution/domain/models/distribution_task.dart';
import 'package:surplus_share/features/location/domain/models/geo_point.dart';

/// Displays the fixed pickup store pin and fixed recipient drop-off pin
/// connected on a map so volunteers know exact pickup & drop-off locations.
class DistributionRouteMapSheet extends StatelessWidget {
  const new({required this.task, this.enableNetworkTiles = true, super.key});

  final DistributionTask task;
  final bool enableNetworkTiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final pickup = task.storeLocation.toLatLng();
    final dropoff = task.recipientLocation.toLatLng();
    final centerLat =
        (task.storeLocation.latitude + task.recipientLocation.latitude) / 2;
    final centerLng =
        (task.storeLocation.longitude + task.recipientLocation.longitude) / 2;
    final center = GeoPoint(latitude: centerLat, longitude: centerLng);
    final distanceKm = task.storeLocation.distanceInKmTo(
      task.recipientLocation,
    );

    return AppBottomSheetScaffold(
      title: 'Rute Pickup & Pengantaran',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                height: 240,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: center.toLatLng(),
                    initialZoom: 13,
                  ),
                  children: [
                    if (enableNetworkTiles)
                      TileLayer(
                        urlTemplate: AppMapConfig.tileUrlTemplate,
                        userAgentPackageName: AppMapConfig.userAgentPackageName,
                      ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: [pickup, dropoff],
                          strokeWidth: 3,
                          color: colorScheme.primary,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: pickup,
                          width: 40,
                          height: 40,
                          child: Tooltip(
                            message: 'Pickup: ${task.partnerName}',
                            child: Container(
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colorScheme.onPrimary,
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                Icons.storefront_rounded,
                                size: 18,
                                color: colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ),
                        Marker(
                          point: dropoff,
                          width: 40,
                          height: 40,
                          child: Tooltip(
                            message: 'Drop-off: ${task.recipientName}',
                            child: Container(
                              decoration: BoxDecoration(
                                color: colorScheme.tertiary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colorScheme.onTertiary,
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                Icons.volunteer_activism_rounded,
                                size: 18,
                                color: colorScheme.onTertiary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _StopRow(
            icon: Icons.storefront_rounded,
            color: colorScheme.primary,
            label: 'Titik Pickup (Mitra)',
            name: task.partnerName,
            address: task.storeAddress,
            point: task.storeLocation,
          ),
          const SizedBox(height: AppSpacing.sm),
          _StopRow(
            icon: Icons.volunteer_activism_rounded,
            color: colorScheme.tertiary,
            label: 'Titik Drop-off (Penerima Terverifikasi)',
            name: task.recipientName,
            address: task.recipientAddress,
            point: task.recipientLocation,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Estimasi jarak garis lurus: ${distanceKm.toStringAsFixed(1)} km '
            '• ${task.portions} porsi',
            style: textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StopRow extends StatelessWidget {
  const new({
    required this.icon,
    required this.color,
    required this.label,
    required this.name,
    required this.address,
    required this.point,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String name;
  final String address;
  final GeoPoint point;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                name,
                style: textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                address,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                '${point.latitude.toStringAsFixed(5)}, '
                '${point.longitude.toStringAsFixed(5)}',
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
