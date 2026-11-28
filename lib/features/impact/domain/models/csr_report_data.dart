import 'package:flutter/foundation.dart';
import 'package:surplus_share/features/impact/domain/models/impact_summary.dart';
import 'package:surplus_share/features/reservation/domain/models/handover_receipt.dart';

@immutable
class CsrReportData {
  const new({
    required this.reportId,
    required this.organizationName,
    required this.partnerId,
    required this.periodStart,
    required this.periodEnd,
    required this.generatedAt,
    required this.summary,
    required this.receipts,
    this.methodologyNote =
        'Estimasi pengurangan emisi karbon menggunakan faktor standar FAO/WRAP '
        'sebesar 2.5 kg CO2e per 1 kg makanan yang diselamatkan dari TPA. '
        'Seluruh transaksi telah diverifikasi melalui bukti serah terima PIN '
        'di lokasi.',
  });

  final String reportId;
  final String organizationName;
  final String partnerId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime generatedAt;
  final ImpactSummary summary;
  final List<HandoverReceipt> receipts;
  final String methodologyNote;
}
