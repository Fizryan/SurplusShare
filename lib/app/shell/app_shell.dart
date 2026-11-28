import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/permission/app_role.dart';
import 'package:surplus_share/core/permission/permission.dart';
import 'package:surplus_share/core/permission/permission_provider.dart';
import 'package:surplus_share/core/theme/app_tokens.dart';
import 'package:surplus_share/features/distribution/domain/models/distribution_task.dart';
import 'package:surplus_share/features/distribution/presentation/provider/distribution_provider.dart';
import 'package:surplus_share/features/kyc/presentation/provider/kyc_provider.dart';
import 'package:surplus_share/features/listing/presentation/provider/listing_provider.dart';
import 'package:surplus_share/features/location/presentation/provider/pinned_location_provider.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation_status.dart';
import 'package:surplus_share/features/reservation/presentation/provider/reservation_provider.dart';

final tabReselectProvider =
    NotifierProvider<TabReselectNotifier, ({int branchIndex, int count})>(
      TabReselectNotifier.new,
    );

class TabReselectNotifier extends Notifier<({int branchIndex, int count})> {
  @override
  ({int branchIndex, int count}) build() => (branchIndex: -1, count: 0);

  void reselect(int branchIndex) {
    state = (branchIndex: branchIndex, count: state.count + 1);
  }
}

class AppShell extends ConsumerStatefulWidget {
  const new({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    unawaited(
      Future.microtask(() async {
        if (!mounted) return;
        final permissions = ref.read(currentPermissionProvider);
        final role = ref.read(currentClaimsProvider)?.role;
        final isPartner = permissions.contains(Permission.validatePickupPin);
        final needsFixedLocation =
            role == AppRole.donorPartner ||
            role == AppRole.verifiedRecipient ||
            role == AppRole.admin;
        final needsDistribution =
            role == AppRole.volunteer ||
            role == AppRole.donorPartner ||
            role == AppRole.verifiedRecipient ||
            role == AppRole.admin;
        await Future.wait([
          ref.read(listingNotifierProvider.notifier).loadListings(),
          ref.read(kycNotifierProvider.notifier).loadMyKyc(),
          if (needsFixedLocation)
            ref.read(pinnedLocationNotifierProvider.notifier).loadMyLocation(),
          if (isPartner || role == AppRole.admin)
            ref
                .read(pinnedLocationNotifierProvider.notifier)
                .loadVerifiedRecipients(),
          if (needsDistribution)
            ref.read(distributionNotifierProvider.notifier).loadTasks(),
          if (isPartner)
            ref
                .read(reservationNotifierProvider.notifier)
                .loadPartnerReservations()
          else
            ref.read(reservationNotifierProvider.notifier).loadMyReservations(),
        ]);
      }),
    );
  }

  void _onSelect(int index) {
    final isReselect = index == widget.navigationShell.currentIndex;
    widget.navigationShell.goBranch(index, initialLocation: isReselect);
    if (isReselect) {
      ref.read(tabReselectProvider.notifier).reselect(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentIndex = widget.navigationShell.currentIndex;
    final role = ref.watch(currentClaimsProvider.select((c) => c?.role));
    final isVolunteer = role == AppRole.volunteer;

    final activityBadgeCount = isVolunteer
        ? ref.watch(
            distributionNotifierProvider.select(
              (s) => s.tasks
                  .where((t) => t.status == DistributionStatus.open)
                  .length,
            ),
          )
        : ref.watch(
            reservationNotifierProvider.select(
              (s) => s.items
                  .where(
                    (r) =>
                        r.status == ReservationStatus.pendingPayment ||
                        r.status == ReservationStatus.confirmed,
                  )
                  .length,
            ),
          );

    final thirdTabLabel = isVolunteer ? 'Distribusi' : 'Reservasi';
    final thirdTabIcon = Badge(
      isLabelVisible: activityBadgeCount > 0,
      label: Text('$activityBadgeCount'),
      child: Icon(
        isVolunteer
            ? Icons.local_shipping_outlined
            : Icons.receipt_long_outlined,
      ),
    );
    final thirdTabSelectedIcon = Badge(
      isLabelVisible: activityBadgeCount > 0,
      label: Text('$activityBadgeCount'),
      child: Icon(
        isVolunteer ? Icons.local_shipping_rounded : Icons.receipt_long_rounded,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= AppBreakpoints.tabletMax;

        if (useRail) {
          return Scaffold(
            backgroundColor: colorScheme.surface,
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: currentIndex,
                  onDestinationSelected: _onSelect,
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: colorScheme.surfaceContainerLow,
                  destinations: [
                    const NavigationRailDestination(
                      icon: Icon(Icons.storefront_outlined),
                      selectedIcon: Icon(Icons.storefront_rounded),
                      label: Text('Beranda'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.explore_outlined),
                      selectedIcon: Icon(Icons.explore_rounded),
                      label: Text('Sekitar'),
                    ),
                    NavigationRailDestination(
                      icon: thirdTabIcon,
                      selectedIcon: thirdTabSelectedIcon,
                      label: Text(thirdTabLabel),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.eco_outlined),
                      selectedIcon: Icon(Icons.eco_rounded),
                      label: Text('Dampak'),
                    ),
                  ],
                ),
                VerticalDivider(
                  width: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
                Expanded(child: widget.navigationShell),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: colorScheme.surface,
          body: widget.navigationShell,
          bottomNavigationBar: NavigationBar(
            selectedIndex: currentIndex,
            onDestinationSelected: _onSelect,
            backgroundColor: colorScheme.surfaceContainerLow,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.storefront_outlined),
                selectedIcon: Icon(Icons.storefront_rounded),
                label: 'Beranda',
              ),
              const NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                selectedIcon: Icon(Icons.explore_rounded),
                label: 'Sekitar',
              ),
              NavigationDestination(
                icon: thirdTabIcon,
                selectedIcon: thirdTabSelectedIcon,
                label: thirdTabLabel,
              ),
              const NavigationDestination(
                icon: Icon(Icons.eco_outlined),
                selectedIcon: Icon(Icons.eco_rounded),
                label: 'Dampak',
              ),
            ],
          ),
        );
      },
    );
  }
}
