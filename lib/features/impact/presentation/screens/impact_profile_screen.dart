import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/app/shell/app_shell.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/di/global_provider.dart';
import 'package:surplus_share/core/permission/app_role.dart';
import 'package:surplus_share/core/permission/permission.dart';
import 'package:surplus_share/core/permission/permission_gate.dart';
import 'package:surplus_share/core/shared/widgets/app_bottom_sheet_scaffold.dart';
import 'package:surplus_share/core/shared/widgets/app_status_chip.dart';
import 'package:surplus_share/core/shared/widgets/app_surface_card.dart';
import 'package:surplus_share/core/theme/app_tokens.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/core/utils/formatters/app_formatters.dart';
import 'package:surplus_share/features/impact/presentation/provider/impact_provider.dart';
import 'package:surplus_share/features/kyc/domain/models/kyc_application.dart';
import 'package:surplus_share/features/kyc/domain/policy/kyc_quota_policy.dart';
import 'package:surplus_share/features/kyc/presentation/provider/kyc_provider.dart';
import 'package:surplus_share/features/kyc/presentation/widgets/submit_kyc_sheet.dart';

class ImpactProfileScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ImpactProfileScreen> createState() =>
      _ImpactProfileScreenState();
}

class _ImpactProfileScreenState extends ConsumerState<ImpactProfileScreen> {
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

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Keluar dari Akun?'),
        content: const Text(
          'Anda perlu masuk kembali dengan Google untuk mengakses aplikasi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authNotifierProvider.notifier).logout();
    }
  }

  Future<void> _approveKyc(WidgetRef ref, KycApplication app) async {
    final recommendedQuota = KycQuotaPolicy.recommendedDailyQuota(
      category: app.category,
      beneficiaryCount: app.beneficiaryCount,
    );
    final ok = await ref
        .read(kycNotifierProvider.notifier)
        .approveKyc(applicationId: app.id, dailyQuota: recommendedQuota);
    final snack = ref.read(snackbarServiceProvider);
    if (ok) {
      snack.showSuccess(
        'KYC ${app.organizationName} disetujui ($recommendedQuota porsi/hari).',
      );
    } else {
      final err = ref.read(kycNotifierProvider).failure;
      snack.showError(err?.message ?? 'Gagal menyetujui KYC.');
    }
  }

  Future<void> _rejectKycDialog(
    BuildContext context,
    WidgetRef ref,
    String applicationId,
  ) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tolak Pengajuan KYC'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Alasan Penolakan',
            hintText: 'Mis. Dokumen legalitas belum jelas',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Tolak'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty) return;

    final ok = await ref
        .read(kycNotifierProvider.notifier)
        .rejectKyc(applicationId: applicationId, reason: reason);
    final snack = ref.read(snackbarServiceProvider);
    if (ok) {
      snack.showInfo('Pengajuan KYC ditolak.');
    } else {
      snack.showError(
        ref.read(kycNotifierProvider).failure?.message ??
            'Gagal menolak pengajuan KYC.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<({int branchIndex, int count})>(tabReselectProvider, (_, next) {
      if (next.branchIndex == 3) _scrollToTop();
    });

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final claims = ref.watch(currentClaimsProvider);
    final isPartner =
        claims?.role == AppRole.donorPartner ||
        claims?.role == AppRole.partnerStaff;
    final impact = isPartner
        ? ref.watch(partnerImpactSummaryProvider((start: null, end: null)))
        : ref.watch(myImpactSummaryProvider);
    final csrState = ref.watch(csrReportNotifierProvider);
    final kycState = ref.watch(kycNotifierProvider);
    final themeMode = ref.watch(
      themeNotifierProvider.select((state) => state.mode),
    );
    final effectiveKycStatus =
        kycState.application?.status ??
        claims?.kycStatus ??
        KycStatus.unverified;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        title: const Text('Dampak & Profil'),
        actions: [
          IconButton(
            key: const Key('profile_logout_button'),
            tooltip: 'Keluar',
            onPressed: () => _confirmLogout(context, ref),
            icon: const Icon(Icons.logout_rounded),
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
              if (claims != null) ...[
                AppSurfaceCard(
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: colorScheme.primaryContainer,
                        foregroundColor: colorScheme.onPrimaryContainer,
                        child: Text(
                          (claims.displayName ?? claims.email ?? 'U')
                              .characters
                              .first
                              .toUpperCase(),
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              claims.displayName ?? 'Pengguna Surplus Share',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleSmall?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (claims.email != null)
                              Text(
                                claims.email!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      AppStatusChip(
                        label: AppFormatters.roleLabel(claims.role),
                        tone: AppChipTone.primary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: AppRadius.circular(AppRadius.md),
                          ),
                          child: Icon(
                            Icons.eco_outlined,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                impact.badgeLevel.label,
                                style: textTheme.titleMedium?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                impact.nextBadge == null
                                    ? 'Tingkat tertinggi tercapai!'
                                    : '${impact.portionsToNextBadge} porsi lagi'
                                          ' ke ${impact.nextBadge!.label}',
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ClipRRect(
                      borderRadius: AppRadius.circular(AppRadius.sm),
                      child: LinearProgressIndicator(
                        value: impact.badgeProgress,
                        minHeight: 8,
                        semanticsLabel: 'Progres lencana dampak pangan',
                        backgroundColor: colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        _MetricTile(
                          label: 'Diselamatkan',
                          value: '${impact.totalFoodSavedKg} kg',
                        ),
                        _MetricTile(
                          label: 'CO2e Dicegah',
                          value: '${impact.co2AvoidedKg} kg',
                        ),
                        _MetricTile(
                          label: 'Total Porsi',
                          value: '${impact.totalPortions}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              PermissionGate(
                requiredPermission: const {Permission.exportCsrReport},
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: AppSurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Laporan CSR & ESG Otomatis (PDF)',
                          style: textTheme.titleSmall?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Unduh ringkasan resmi penyelamatan pangan dan '
                          'estimasi pengurangan karbon untuk pelaporan ESG.',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (csrState.lastReportData != null &&
                            csrState.lastPdfBytes != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          AppStatusChip(
                            label: _formatReportBadge(
                              csrState.lastReportData!.reportId,
                              csrState.lastPdfBytes!.length,
                            ),
                            icon: Icons.picture_as_pdf_outlined,
                            tone: AppChipTone.primary,
                          ),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        FilledButton.icon(
                          key: const Key('impact_export_csr_button'),
                          onPressed: csrState.isGenerating
                              ? null
                              : () async {
                                  final now = ref.read(clockProvider)().toUtc();
                                  final bytes = await ref
                                      .read(csrReportNotifierProvider.notifier)
                                      .exportPartnerCsrPdf(
                                        organizationName:
                                            claims?.displayName ??
                                            'Mitra Surplus Share',
                                        periodStart: now.subtract(
                                          const Duration(days: 30),
                                        ),
                                        periodEnd: now,
                                      );
                                  final snack = ref.read(
                                    snackbarServiceProvider,
                                  );
                                  if (bytes != null) {
                                    final kb = (bytes.length / 1024)
                                        .toStringAsFixed(1);
                                    snack.showSuccess(
                                      'Laporan CSR PDF siap ($kb KB).',
                                    );
                                  } else {
                                    snack.showError(
                                      ref
                                              .read(csrReportNotifierProvider)
                                              .failure
                                              ?.message ??
                                          'Gagal membuat PDF.',
                                    );
                                  }
                                },
                          icon: csrState.isGenerating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.picture_as_pdf_outlined,
                                  size: 18,
                                ),
                          label: const Text('Buat Laporan CSR (PDF)'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Verifikasi Penerima Donasi (KYC)',
                          style: textTheme.titleSmall?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        AppStatusChip(
                          label: AppFormatters.kycStatusLabel(
                            effectiveKycStatus,
                          ),
                          tone: effectiveKycStatus == KycStatus.approved
                              ? AppChipTone.primary
                              : effectiveKycStatus == KycStatus.rejected
                              ? AppChipTone.error
                              : AppChipTone.neutral,
                        ),
                      ],
                    ),
                    if (kycState.dailyQuota != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Kuota Donasi Hari Ini: '
                        '${kycState.dailyQuota!.remaining} / '
                        '${kycState.dailyQuota!.dailyLimit} porsi tersisa',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      ClipRRect(
                        borderRadius: AppRadius.circular(AppRadius.sm),
                        child: LinearProgressIndicator(
                          value: kycState.dailyQuota!.dailyLimit == 0
                              ? 0
                              : kycState.dailyQuota!.remaining /
                                    kycState.dailyQuota!.dailyLimit,
                          minHeight: 6,
                          semanticsLabel: 'Sisa kuota donasi harian',
                        ),
                      ),
                    ],
                    if (kycState.application == null ||
                        kycState.application!.canResubmit) ...[
                      const SizedBox(height: AppSpacing.md),
                      OutlinedButton.icon(
                        key: const Key('impact_submit_kyc_button'),
                        onPressed: () => showAppBottomSheet<void>(
                          context: context,
                          builder: (_) => const SubmitKycSheet(),
                        ),
                        icon: const Icon(
                          Icons.verified_user_outlined,
                          size: 18,
                        ),
                        label: const Text(
                          'Ajukan Verifikasi Panti / Komunitas',
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              PermissionGate(
                requiredPermission: const {Permission.reviewKyc},
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: AppSurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Antrean Review KYC (Admin)',
                                style: textTheme.titleSmall?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: kycState.isLoading
                                  ? null
                                  : () => ref
                                        .read(kycNotifierProvider.notifier)
                                        .loadPendingApplications(),
                              child: const Text('Muat'),
                            ),
                          ],
                        ),
                        if (kycState.pendingApplications.isEmpty)
                          Text(
                            'Tidak ada pengajuan KYC yang menunggu review.',
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          )
                        else
                          for (final app in kycState.pendingApplications)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.sm,
                              ),
                              child: Wrap(
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.xs,
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        app.organizationName,
                                        style: textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        _kycApplicantSubtitle(app),
                                        style: textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Wrap(
                                    spacing: AppSpacing.xs,
                                    children: [
                                      OutlinedButton(
                                        onPressed: kycState.isLoading
                                            ? null
                                            : () => _rejectKycDialog(
                                                context,
                                                ref,
                                                app.id,
                                              ),
                                        style: OutlinedButton.styleFrom(
                                          minimumSize: const Size(0, 34),
                                        ),
                                        child: const Text('Tolak'),
                                      ),
                                      FilledButton(
                                        onPressed: kycState.isLoading
                                            ? null
                                            : () => _approveKyc(ref, app),
                                        style: FilledButton.styleFrom(
                                          minimumSize: const Size(0, 34),
                                        ),
                                        child: const Text('Setujui'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Tampilan Tema',
                      style: textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('Sistem'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('Terang'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('Gelap'),
                        ),
                      ],
                      selected: {themeMode},
                      onSelectionChanged: (s) => ref
                          .read(themeNotifierProvider.notifier)
                          .setThemeMode(s.first),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const new({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _kycApplicantSubtitle(KycApplication app) {
  final category = AppFormatters.recipientCategoryLabel(app.category);
  return '$category • ${app.beneficiaryCount} penerima';
}

String _formatReportBadge(String reportId, int byteLength) {
  final sizeKb = (byteLength / 1024).toStringAsFixed(1);
  return '$reportId • $sizeKb KB';
}
