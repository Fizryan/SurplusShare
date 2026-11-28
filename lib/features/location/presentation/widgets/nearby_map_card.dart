import 'package:flutter_map/flutter_map.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/theme/app_tokens.dart';
import 'package:surplus_share/features/location/domain/models/geo_point.dart';
import 'package:surplus_share/features/location/domain/models/nearby_listing.dart';

class NearbyMapCard extends StatefulWidget {
  const new({
    required this.userLocation,
    required this.radiusKm,
    required this.nearbyListings,
    this.enableNetworkTiles = true,
    super.key,
  });

  final GeoPoint userLocation;
  final double radiusKm;
  final List<NearbyListing> nearbyListings;
  final bool enableNetworkTiles;

  @override
  State<NearbyMapCard> createState() => _NearbyMapCardState();
}

class _NearbyMapCardState extends State<NearbyMapCard> {
  final MapController _mapController = MapController();

  @override
  void didUpdateWidget(covariant NearbyMapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userLocation != widget.userLocation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _mapController.move(
            widget.userLocation.toLatLng(),
            _mapController.camera.zoom,
          );
        } on Object {
          // Ignore if map controller is not yet attached.
        }
      });
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final center = widget.userLocation.toLatLng();

    return ClipRRect(
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
          height: 210,
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: center, initialZoom: 13.5),
            children: [
              if (widget.enableNetworkTiles)
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.surplus_share',
                ),
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: center,
                    radius: widget.radiusKm * 1000,
                    useRadiusInMeter: true,
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    borderColor: colorScheme.primary.withValues(alpha: 0.55),
                    borderStrokeWidth: 1.5,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: center,
                    width: 34,
                    height: 34,
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
                        Icons.my_location_rounded,
                        size: 16,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ),
                  for (final item in widget.nearbyListings)
                    if (item.listing.location != null)
                      Marker(
                        point: item.listing.location!.toLatLng(),
                        width: 34,
                        height: 34,
                        child: Tooltip(
                          message:
                              '${item.listing.partnerName} '
                              '(${item.formattedDistance})',
                          child: Container(
                            decoration: BoxDecoration(
                              color: colorScheme.tertiaryContainer,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colorScheme.tertiary,
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              Icons.storefront_outlined,
                              size: 16,
                              color: colorScheme.onTertiaryContainer,
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
    );
  }
}
