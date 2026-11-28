import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:surplus_share/core/network/api_endpoints.dart';
import 'package:surplus_share/core/network/api_response_parser.dart';
import 'package:surplus_share/features/kyc/domain/models/kyc_document.dart';
import 'package:surplus_share/features/kyc/domain/models/kyc_failure.dart';

/// Picks and uploads KYC verification documents (`POST /kyc/documents`).
abstract interface class KycDocumentService {
  Future<Either<KycFailure, KycDocument?>> pickAndUpload({
    required KycDocumentType type,
    bool fromCamera = false,
  });

  Future<Either<KycFailure, KycDocument>> uploadFile({
    required KycDocumentType type,
    required String filePath,
    required String fileName,
    required String mimeType,
    required int fileSizeBytes,
  });
}

class RemoteKycDocumentService implements KycDocumentService {
  new({required this._dio, ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final Dio _dio;
  final ImagePicker _picker;

  @override
  Future<Either<KycFailure, KycDocument?>> pickAndUpload({
    required KycDocumentType type,
    bool fromCamera = false,
  }) async {
    final picked = await _pickImage(
      picker: _picker,
      type: type,
      fromCamera: fromCamera,
    );
    if (picked == null) return right(null);
    return await picked.fold<Future<Either<KycFailure, KycDocument?>>>(
      (failure) async => left(failure),
      (doc) => uploadFile(
        type: doc.type,
        filePath: doc.filePath,
        fileName: doc.fileName,
        mimeType: doc.mimeType,
        fileSizeBytes: doc.fileSizeBytes,
      ),
    );
  }

  @override
  Future<Either<KycFailure, KycDocument>> uploadFile({
    required KycDocumentType type,
    required String filePath,
    required String fileName,
    required String mimeType,
    required int fileSizeBytes,
  }) async {
    final safeFileName = p.basename(fileName.trim());
    final candidate = KycDocument(
      type: type,
      fileName: safeFileName,
      filePath: filePath,
      mimeType: mimeType,
      fileSizeBytes: fileSizeBytes,
    );
    final validationError = candidate.validate();
    if (validationError != null) {
      return left(KycValidationFailure(validationError));
    }

    try {
      final formData = FormData.fromMap(<String, dynamic>{
        'type': type.name,
        'file': await MultipartFile.fromFile(filePath, filename: safeFileName),
      });
      final response = await _dio.post<dynamic>(
        ApiEndpoints.uploadKycDocument,
        data: formData,
        options: Options(contentType: Headers.multipartFormDataContentType),
      );
      return right(
        KycDocument.fromJson(ApiResponseParser.unwrapMap(response.data)),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final message = ApiResponseParser.extractErrorMessage(
        e,
        'Gagal mengunggah dokumen KYC.',
      );
      if (status == 401 || status == 403) {
        return left(KycPermissionDeniedFailure(message));
      }
      return left(KycValidationFailure(message));
    } on Object catch (e) {
      return left(KycValidationFailure(e.toString()));
    }
  }
}

/// Debug-only document service that validates picked files locally without
/// calling a remote server when `API_BASE_URL` is not configured.
class DemoKycDocumentService implements KycDocumentService {
  new({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<Either<KycFailure, KycDocument?>> pickAndUpload({
    required KycDocumentType type,
    bool fromCamera = false,
  }) async {
    final picked = await _pickImage(
      picker: _picker,
      type: type,
      fromCamera: fromCamera,
    );
    if (picked == null) return right(null);
    return picked.fold<Either<KycFailure, KycDocument?>>(left, right);
  }

  @override
  Future<Either<KycFailure, KycDocument>> uploadFile({
    required KycDocumentType type,
    required String filePath,
    required String fileName,
    required String mimeType,
    required int fileSizeBytes,
  }) async {
    final doc = KycDocument(
      type: type,
      fileName: fileName,
      filePath: filePath,
      mimeType: mimeType,
      fileSizeBytes: fileSizeBytes,
    );
    final error = doc.validate();
    if (error != null) return left(KycValidationFailure(error));
    return right(doc);
  }
}

Future<Either<KycFailure, KycDocument>?> _pickImage({
  required ImagePicker picker,
  required KycDocumentType type,
  required bool fromCamera,
}) async {
  try {
    final file = await picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (file == null) return null;

    final fileName = p.basename(file.path);
    final sizeBytes = await file.length();
    final mimeType = _inferMimeType(file.mimeType, fileName);
    final doc = KycDocument(
      type: type,
      fileName: fileName,
      filePath: file.path,
      mimeType: mimeType,
      fileSizeBytes: sizeBytes,
    );
    final error = doc.validate();
    if (error != null) return left(KycValidationFailure(error));
    return right(doc);
  } on Object catch (e) {
    return left(KycValidationFailure('Gagal memilih file: $e'));
  }
}

String _inferMimeType(String? explicitMime, String fileName) {
  if (explicitMime != null && explicitMime.trim().isNotEmpty) {
    return explicitMime.trim().toLowerCase();
  }
  return switch (p.extension(fileName).toLowerCase()) {
    '.pdf' => 'application/pdf',
    '.png' => 'image/png',
    '.webp' => 'image/webp',
    '.jpg' || '.jpeg' => 'image/jpeg',
    _ => 'application/octet-stream',
  };
}
