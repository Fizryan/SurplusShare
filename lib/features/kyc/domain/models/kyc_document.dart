import 'package:flutter/foundation.dart';

enum KycDocumentType {
  legalCertificate,
  officialRecommendationLetter,
  representativeIdCard,
  operationalPhoto,
}

@immutable
class KycDocument {
  const new({
    required this.type,
    required this.fileName,
    required this.filePath,
    required this.mimeType,
    required this.fileSizeBytes,
  });

  factory fromJson(Map<String, dynamic> json) {
    final rawType = json['type'] as String? ?? '';
    return KycDocument(
      type: KycDocumentType.values.firstWhere(
        (e) => e.name == rawType,
        orElse: () => KycDocumentType.legalCertificate,
      ),
      fileName:
          json['file_name'] as String? ?? json['fileName'] as String? ?? '',
      filePath:
          json['file_path'] as String? ?? json['filePath'] as String? ?? '',
      mimeType:
          json['mime_type'] as String? ?? json['mimeType'] as String? ?? '',
      fileSizeBytes:
          (json['file_size_bytes'] as num? ?? json['fileSizeBytes'] as num?)
              ?.toInt() ??
          0,
    );
  }

  static const int maxFileSizeBytes = 5 * 1024 * 1024;
  static const Set<String> allowedMimeTypes = {
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  final KycDocumentType type;
  final String fileName;
  final String filePath;
  final String mimeType;
  final int fileSizeBytes;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'file_name': fileName,
    'file_path': filePath,
    'mime_type': mimeType,
    'file_size_bytes': fileSizeBytes,
  };

  /// Validates document metadata (non-empty name/path, MIME type, <= 5 MB).
  String? validate() {
    if (fileName.trim().isEmpty || filePath.trim().isEmpty) {
      return 'File dokumen tidak valid.';
    }
    final normalizedMime = mimeType.trim().toLowerCase();
    if (!allowedMimeTypes.contains(normalizedMime)) {
      return 'Format dokumen harus PDF, JPG, PNG, atau WebP.';
    }
    if (fileSizeBytes <= 0) {
      return 'File dokumen tidak boleh kosong.';
    }
    if (fileSizeBytes > maxFileSizeBytes) {
      return 'Ukuran dokumen maksimal 5 MB.';
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is KycDocument &&
        other.type == type &&
        other.fileName == fileName &&
        other.filePath == filePath &&
        other.mimeType == mimeType &&
        other.fileSizeBytes == fileSizeBytes;
  }

  @override
  int get hashCode =>
      Object.hash(type, fileName, filePath, mimeType, fileSizeBytes);
}
