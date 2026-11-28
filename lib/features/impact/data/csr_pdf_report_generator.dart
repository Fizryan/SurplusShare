import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:surplus_share/features/impact/domain/models/csr_report_data.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';

abstract interface class CsrReportGenerator {
  Future<Uint8List> generatePdf(CsrReportData data);
}

/// Generates an official CSR/ESG PDF impact report using `package:pdf`.
class PdfCsrReportGenerator implements CsrReportGenerator {
  const new();

  @override
  Future<Uint8List> generatePdf(CsrReportData data) {
    final doc = pw.Document(
      title: 'Laporan CSR & ESG - ${data.organizationName}',
      author: 'Surplus Share',
    );
    final dateFormat = DateFormat('yyyy-MM-dd');
    final dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm');
    final summary = data.summary;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text(
            'LAPORAN DAMPAK CSR & ESG',
            style: const pw.TextStyle(
              fontSize: 18,
              color: PdfColors.teal900,
            ).copyWith(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Surplus Share - Food Rescue & Zero Hunger Program',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.Divider(height: 24, color: PdfColors.grey400),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    data.organizationName,
                    style: const pw.TextStyle(fontSize: 13)
                        .copyWith(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    'Partner ID: ${data.partnerId}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Periode: ${dateFormat.format(data.periodStart.toUtc())} '
                    's/d ${dateFormat.format(data.periodEnd.toUtc())}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  pw.Text(
                    'ID Laporan: ${data.reportId}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  pw.Text(
                    'Dicetak: '
                    '${dateTimeFormat.format(data.generatedAt.toUtc())} UTC',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Ringkasan Dampak Lingkungan & Sosial',
            style: const pw.TextStyle(fontSize: 12)
                .copyWith(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headerStyle: const pw.TextStyle(fontSize: 10)
                .copyWith(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            headers: const ['Metrik', 'Nilai'],
            data: [
              ['Total Makanan Diselamatkan', '${summary.totalFoodSavedKg} kg'],
              [
                'Estimasi Pengurangan Emisi Karbon',
                '${summary.co2AvoidedKg} kg CO2e',
              ],
              ['Total Porsi Tersalurkan', '${summary.totalPortions} porsi'],
              [
                '  - Mode Flash Sale / Diskon',
                '${summary.discountPortions} porsi',
              ],
              ['  - Mode Donasi Gratis', '${summary.donationPortions} porsi'],
              [
                'Total Serah Terima Terverifikasi PIN',
                '${summary.completedHandovers} transaksi',
              ],
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Log Bukti Serah Terima Terverifikasi',
            style: const pw.TextStyle(fontSize: 12)
                .copyWith(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          if (data.receipts.isEmpty)
            pw.Text(
              'Belum ada transaksi serah terima pada periode ini.',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            )
          else
            pw.TableHelper.fromTextArray(
              headerStyle: const pw.TextStyle(fontSize: 9)
                  .copyWith(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              headers: const [
                'Tanggal (UTC)',
                'Item',
                'Channel',
                'Porsi',
                'ID Bukti',
              ],
              data: [
                for (final r in data.receipts)
                  [
                    dateTimeFormat.format(r.handedOverAt.toUtc()),
                    r.listingTitle,
                    if (r.channel == ListingChannel.donation)
                      'Donasi'
                    else
                      'Diskon',
                    '${r.quantity}',
                    r.receiptId,
                  ],
              ],
            ),
          pw.SizedBox(height: 20),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text(
              'Metodologi: ${data.methodologyNote}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }
}
