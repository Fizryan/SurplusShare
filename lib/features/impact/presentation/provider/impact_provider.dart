import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/permission/permission_provider.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/features/impact/data/csr_pdf_report_generator.dart';
import 'package:surplus_share/features/impact/domain/models/csr_report_data.dart';
import 'package:surplus_share/features/impact/domain/models/impact_failure.dart';
import 'package:surplus_share/features/impact/domain/models/impact_summary.dart';
import 'package:surplus_share/features/impact/domain/policy/impact_calculator.dart';
import 'package:surplus_share/features/listing/domain/models/food_safety_declaration.dart';
import 'package:surplus_share/features/listing/presentation/provider/listing_provider.dart';
import 'package:surplus_share/features/reservation/domain/models/handover_receipt.dart';
import 'package:surplus_share/features/reservation/presentation/provider/reservation_provider.dart';
import 'package:uuid/uuid.dart';

@immutable
class CsrReportState {
  const new({
    this.lastReportData,
    this.lastPdfBytes,
    this.isGenerating = false,
    this.failure,
  });

  final CsrReportData? lastReportData;
  final Uint8List? lastPdfBytes;
  final bool isGenerating;
  final ImpactFailure? failure;

  CsrReportState copyWith({
    CsrReportData? lastReportData,
    Uint8List? lastPdfBytes,
    bool? isGenerating,
    ImpactFailure? failure,
    bool clearFailure = false,
  }) {
    return CsrReportState(
      lastReportData: lastReportData ?? this.lastReportData,
      lastPdfBytes: lastPdfBytes ?? this.lastPdfBytes,
      isGenerating: isGenerating ?? this.isGenerating,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CsrReportState &&
        other.lastReportData == lastReportData &&
        listEquals(other.lastPdfBytes, lastPdfBytes) &&
        other.isGenerating == isGenerating &&
        other.failure == failure;
  }

  @override
  int get hashCode =>
      Object.hash(lastReportData, lastPdfBytes?.length, isGenerating, failure);
}

final csrReportGeneratorProvider = Provider<CsrReportGenerator>((ref) {
  return const PdfCsrReportGenerator();
});

Map<String, FoodCategory> _listingCategories(Ref ref) {
  final listings = ref.watch(
    listingNotifierProvider.select((state) => state.items),
  );
  return {
    for (final item in listings)
      if (item.foodSafety != null) item.id: item.foodSafety!.category,
  };
}

/// Live personal impact summary for the currently authenticated user.
final myImpactSummaryProvider = Provider<ImpactSummary>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    return ImpactCalculator.computeSummary(receipts: const []);
  }

  final reservations = ref.watch(
    reservationNotifierProvider.select((state) => state.items),
  );
  final receipts = [
    for (final r in reservations)
      if (r.receipt != null && r.customerId == userId) r.receipt!,
  ];

  return ImpactCalculator.computeSummary(
    receipts: receipts,
    categoryByListingId: _listingCategories(ref),
  );
});

/// Live partner business impact summary, optionally filtered by date period.
/// Auto-disposes so date-ranged queries never leak memory.
final ProviderFamily<ImpactSummary, ({DateTime? start, DateTime? end})>
partnerImpactSummaryProvider = Provider.autoDispose
    .family<ImpactSummary, ({DateTime? start, DateTime? end})>((ref, period) {
      final partnerId = ref.watch(currentUserIdProvider);
      if (partnerId == null) {
        return ImpactCalculator.computeSummary(receipts: const []);
      }

      final reservations = ref.watch(
        reservationNotifierProvider.select((state) => state.items),
      );
      final receipts = [
        for (final r in reservations)
          if (r.receipt != null && r.partnerId == partnerId) r.receipt!,
      ];

      return ImpactCalculator.computeSummary(
        receipts: receipts,
        categoryByListingId: _listingCategories(ref),
        periodStart: period.start,
        periodEnd: period.end,
      );
    });

final csrReportNotifierProvider =
    NotifierProvider<CsrReportNotifier, CsrReportState>(CsrReportNotifier.new);

class CsrReportNotifier extends Notifier<CsrReportState> {
  static const _uuid = Uuid();

  @override
  CsrReportState build() {
    // Watching currentUserIdProvider ensures a previous partner's exported PDF
    // never leaks to the next logged-in account.
    ref.watch(currentUserIdProvider);
    return const CsrReportState();
  }

  /// Generates an official CSR/ESG PDF report (`Uint8List`) for the active
  /// partner within `[periodStart, periodEnd]`.
  Future<Uint8List?> exportPartnerCsrPdf({
    required String organizationName,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    if (state.isGenerating) return null;
    final permissions = ref.read(currentPermissionProvider);
    if (!ImpactCalculator.canExportCsrReport(permissions)) {
      state = state.copyWith(failure: const ImpactPermissionDeniedFailure());
      return null;
    }

    if (organizationName.trim().isEmpty) {
      state = state.copyWith(
        failure: const ImpactValidationFailure(
          'Nama organisasi/mitra wajib diisi.',
        ),
      );
      return null;
    }
    if (!periodEnd.isAfter(periodStart)) {
      state = state.copyWith(
        failure: const ImpactValidationFailure(
          'Tanggal akhir periode harus setelah tanggal mulai.',
        ),
      );
      return null;
    }

    final partnerId = ref.read(currentUserIdProvider);
    if (partnerId == null) {
      state = state.copyWith(failure: const ImpactPermissionDeniedFailure());
      return null;
    }

    state = state.copyWith(isGenerating: true, clearFailure: true);

    try {
      final startUtc = periodStart.toUtc();
      final endUtc = periodEnd.toUtc();
      final reservations = ref.read(reservationNotifierProvider).items;
      final receipts = <HandoverReceipt>[
        for (final r in reservations)
          if (r.receipt != null &&
              r.partnerId == partnerId &&
              !r.receipt!.handedOverAt.toUtc().isBefore(startUtc) &&
              !r.receipt!.handedOverAt.toUtc().isAfter(endUtc))
            r.receipt!,
      ];

      final summary = ref.read(
        partnerImpactSummaryProvider((start: periodStart, end: periodEnd)),
      );
      final reportData = CsrReportData(
        reportId: 'CSR-${_uuid.v4().substring(0, 8).toUpperCase()}',
        organizationName: organizationName.trim(),
        partnerId: partnerId,
        periodStart: periodStart,
        periodEnd: periodEnd,
        generatedAt: ref.read(clockProvider)().toUtc(),
        summary: summary,
        receipts: List<HandoverReceipt>.unmodifiable(receipts),
      );

      final bytes = await ref
          .read(csrReportGeneratorProvider)
          .generatePdf(reportData);
      if (!ref.mounted) return bytes;
      state = state.copyWith(
        isGenerating: false,
        lastReportData: reportData,
        lastPdfBytes: bytes,
      );
      return bytes;
    } on Object {
      if (!ref.mounted) return null;
      state = state.copyWith(
        isGenerating: false,
        failure: const ImpactExportFailure(),
      );
      return null;
    }
  }
}
