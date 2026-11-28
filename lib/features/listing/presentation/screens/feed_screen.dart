import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/app/shell/app_shell.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/di/global_provider.dart';
import 'package:surplus_share/core/permission/app_role.dart';
import 'package:surplus_share/core/permission/permission.dart';
import 'package:surplus_share/core/permission/permission_gate.dart';
import 'package:surplus_share/core/permission/permission_provider.dart';
import 'package:surplus_share/core/shared/widgets/app_bottom_sheet_scaffold.dart';
import 'package:surplus_share/core/shared/widgets/app_empty_state.dart';
import 'package:surplus_share/core/shared/widgets/app_error_banner.dart';
import 'package:surplus_share/core/shared/widgets/app_skeleton_card.dart';
import 'package:surplus_share/core/theme/app_tokens.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/listing/domain/models/surplus_listing.dart';
import 'package:surplus_share/features/listing/domain/policy/listing_access_policy.dart';
import 'package:surplus_share/features/listing/presentation/provider/listing_provider.dart';
import 'package:surplus_share/features/listing/presentation/widgets/create_listing_sheet.dart';
import 'package:surplus_share/features/listing/presentation/widgets/food_safety_filter_sheet.dart';
import 'package:surplus_share/features/listing/presentation/widgets/listing_card.dart';
import 'package:surplus_share/features/reservation/presentation/helpers/reservation_action_helper.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
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
      if (next.branchIndex != 0) return;
      _scrollToTop();
      if (ref.read(listingChannelFilterProvider) != null) {
        ref.read(listingChannelFilterProvider.notifier).filter = null;
      }
    });

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final listings = ref.watch(activeVisibleListingsProvider);
    final isLoading = ref.watch(
      listingNotifierProvider.select((state) => state.isLoading),
    );
    final failure = ref.watch(
      listingNotifierProvider.select((state) => state.failure),
    );
    final channelFilter = ref.watch(listingChannelFilterProvider);
    final isSafetyFilterActive = ref.watch(
      foodSafetyFilterProvider.select((filter) => filter.isActive),
    );
    final permissions = ref.watch(currentPermissionProvider);
    final claims = ref.watch(currentClaimsProvider);
    final canBrowseDonation = permissions.contains(
      Permission.browseDonationListings,
    );

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Surplus Share'),
        centerTitle: false,
        actions: [
          IconButton(
            key: const Key('feed_safety_filter_button'),
            tooltip: 'Filter Halal & Alergen',
            onPressed: () => showAppBottomSheet<void>(
              context: context,
              builder: (_) => const FoodSafetyFilterSheet(),
            ),
            icon: Badge(
              isLabelVisible: isSafetyFilterActive,
              child: const Icon(Icons.tune_rounded),
            ),
          ),
        ],
      ),
      floatingActionButton: PermissionGate(
        requiredPermission: const {Permission.createListing},
        child: FloatingActionButton.extended(
          key: const Key('feed_create_listing_fab'),
          onPressed: () => showAppBottomSheet<void>(
            context: context,
            builder: (_) => const CreateListingSheet(),
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Unggah Stok'),
        ),
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
                    onRetry: () => ref
                        .read(listingNotifierProvider.notifier)
                        .loadListings(),
                  ),
                ),
              if (canBrowseDonation)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.xs,
                  ),
                  child: SegmentedButton<ListingChannel?>(
                    key: const Key('feed_channel_segmented'),
                    segments: const [
                      ButtonSegment(value: null, label: Text('Semua')),
                      ButtonSegment(
                        value: ListingChannel.discount,
                        label: Text('Diskon'),
                      ),
                      ButtonSegment(
                        value: ListingChannel.donation,
                        label: Text('Donasi'),
                      ),
                    ],
                    selected: {channelFilter},
                    onSelectionChanged: (selected) {
                      ref.read(listingChannelFilterProvider.notifier).filter =
                          selected.first;
                    },
                  ),
                ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: isLoading && listings.isEmpty
                      ? ListView.separated(
                          key: const ValueKey('feed_skeleton'),
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          itemCount: 3,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.md),
                          itemBuilder: (_, _) => const AppSkeletonCard(),
                        )
                      : listings.isEmpty
                      ? AppEmptyState(
                          key: const ValueKey('feed_empty'),
                          icon: Icons.eco_outlined,
                          title: 'Belum Ada Stok Tersedia',
                          subtitle: isSafetyFilterActive
                              ? 'Filter Halal/Alergen Anda menyembunyikan '
                                    'semua stok saat ini.'
                              : 'Cek kembali saat mitra mengunggah makanan '
                                    'surplus terbaru.',
                          action: isSafetyFilterActive
                              ? FilledButton.tonal(
                                  onPressed: () => ref
                                      .read(foodSafetyFilterProvider.notifier)
                                      .reset(),
                                  child: const Text('Reset Filter'),
                                )
                              : null,
                        )
                      : RefreshIndicator(
                          key: const ValueKey('feed_list'),
                          onRefresh: () => ref
                              .read(listingNotifierProvider.notifier)
                              .loadListings(),
                          child: ListView.separated(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            itemCount: listings.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: AppSpacing.md),
                            itemBuilder: (context, index) {
                              final item = listings[index];
                              final canConvert =
                                  item.canConvertToDonation() &&
                                  ListingAccessPolicy.canManage(
                                    item,
                                    currentUserId: claims?.subject,
                                    role: claims?.role ?? AppRole.consumer,
                                    permissions: permissions,
                                  );

                              return ListingCard(
                                listing: item,
                                canConvertToDonation: canConvert,
                                onConvertToDonation: () =>
                                    _convertToDonation(ref, item),
                                onAction: () => bookOrClaimListing(ref, item),
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

  Future<void> _convertToDonation(WidgetRef ref, SurplusListing item) async {
    final ok = await ref
        .read(listingNotifierProvider.notifier)
        .convertToDonation(item.id);
    final snack = ref.read(snackbarServiceProvider);
    if (ok) {
      snack.showSuccess('${item.title} dialihkan ke Donasi Gratis.');
    } else {
      final err = ref.read(listingNotifierProvider).failure;
      if (err != null) snack.showError(err.message);
    }
  }
}
