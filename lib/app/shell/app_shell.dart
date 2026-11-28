import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/permission/permission.dart';
import 'package:surplus_share/core/permission/permission_provider.dart';
import 'package:surplus_share/core/theme/app_tokens.dart';
import 'package:surplus_share/features/kyc/presentation/provider/kyc_provider.dart';
import 'package:surplus_share/features/listing/presentation/provider/listing_provider.dart';
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
        final isPartnerOrStaff = permissions.contains(
          Permission.validatePickupPin,
        );
        await Future.wait([
          ref.read(listingNotifierProvider.notifier).loadListings(),
          ref.read(kycNotifierProvider.notifier).loadMyKyc(),
          if (isPartnerOrStaff)
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
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.storefront_outlined),
                      selectedIcon: Icon(Icons.storefront_rounded),
                      label: Text('Beranda'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.explore_outlined),
                      selectedIcon: Icon(Icons.explore_rounded),
                      label: Text('Sekitar'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.receipt_long_outlined),
                      selectedIcon: Icon(Icons.receipt_long_rounded),
                      label: Text('Reservasi'),
                    ),
                    NavigationRailDestination(
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
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.storefront_outlined),
                selectedIcon: Icon(Icons.storefront_rounded),
                label: 'Beranda',
              ),
              NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                selectedIcon: Icon(Icons.explore_rounded),
                label: 'Sekitar',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long_rounded),
                label: 'Reservasi',
              ),
              NavigationDestination(
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
