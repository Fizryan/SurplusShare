import 'package:flutter/foundation.dart';
import 'package:surplus_share/features/kyc/domain/models/kyc_document.dart';
import 'package:surplus_share/features/kyc/domain/models/recipient_category.dart';
import 'package:surplus_share/features/kyc/domain/policy/kyc_quota_policy.dart';

@immutable
class SubmitKycInput {
  const new({
    required this.userId,
    required this.organizationName,
    required this.category,
    required this.address,
    required this.contactPhone,
    required this.beneficiaryCount,
    required this.documents,
    this.registrationNumber,
  });

  static final RegExp _phoneRegex = RegExp(r'^\+?[0-9]{10,15}$');

  final String userId;
  final String organizationName;
  final RecipientCategory category;
  final String? registrationNumber;
  final String address;
  final String contactPhone;
  final int beneficiaryCount;
  final List<KycDocument> documents;

  /// Validates organization info, phone format, beneficiary count,
  /// required documents per category, and each document's file constraints.
  String? validate() {
    if (userId.trim().isEmpty) {
      return 'Identitas pengguna tidak valid.';
    }
    if (organizationName.trim().isEmpty) {
      return 'Nama panti, yayasan, atau komunitas tidak boleh kosong.';
    }
    if (address.trim().isEmpty) {
      return 'Alamat lengkap tidak boleh kosong.';
    }
    final sanitizedPhone = contactPhone.replaceAll(RegExp(r'[\s-]'), '');
    if (!_phoneRegex.hasMatch(sanitizedPhone)) {
      return 'Nomor telepon harus terdiri dari 10–15 digit angka.';
    }
    if (beneficiaryCount <= 0) {
      return 'Jumlah penerima manfaat harus lebih dari 0.';
    }

    final seenTypes = <KycDocumentType>{};
    for (final doc in documents) {
      if (!seenTypes.add(doc.type)) {
        return 'Tipe dokumen tidak boleh duplikat.';
      }
      final docError = doc.validate();
      if (docError != null) return docError;
    }

    final requiredTypes = KycQuotaPolicy.requiredDocumentsFor(category);
    if (!seenTypes.containsAll(requiredTypes)) {
      return 'Dokumen wajib untuk kategori ini belum lengkap.';
    }

    return null;
  }
}
