import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/di/global_provider.dart';
import 'package:surplus_share/core/shared/widgets/app_bottom_sheet_scaffold.dart';
import 'package:surplus_share/core/theme/app_tokens.dart';
import 'package:surplus_share/core/utils/formatters/app_formatters.dart';
import 'package:surplus_share/features/auth/presentation/widgets/auth_submit_button.dart';
import 'package:surplus_share/features/kyc/domain/models/kyc_document.dart';
import 'package:surplus_share/features/kyc/domain/models/recipient_category.dart';
import 'package:surplus_share/features/kyc/domain/models/submit_kyc_input.dart';
import 'package:surplus_share/features/kyc/presentation/provider/kyc_provider.dart';

class SubmitKycSheet extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<SubmitKycSheet> createState() => _SubmitKycSheetState();
}

class _SubmitKycSheetState extends ConsumerState<SubmitKycSheet> {
  static final _phonePattern = RegExp(r'^[0-9]{10,15}$');

  final _formKey = GlobalKey<FormState>();
  final _orgController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _beneficiaryController = TextEditingController(text: '25');

  RecipientCategory _category = RecipientCategory.orphanage;
  KycDocument? _primaryDoc;
  KycDocument? _idCardDoc;
  bool _uploadingPrimary = false;
  bool _uploadingIdCard = false;
  bool _showDocError = false;

  KycDocumentType get _primaryDocType =>
      _category == RecipientCategory.distributionVolunteer
      ? KycDocumentType.officialRecommendationLetter
      : KycDocumentType.legalCertificate;

  @override
  void dispose() {
    _orgController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _beneficiaryController.dispose();
    super.dispose();
  }

  Future<void> _pickDocument({
    required bool isPrimary,
    required bool fromCamera,
  }) async {
    setState(() {
      if (isPrimary) {
        _uploadingPrimary = true;
      } else {
        _uploadingIdCard = true;
      }
    });

    final type = isPrimary
        ? _primaryDocType
        : KycDocumentType.representativeIdCard;
    final result = await ref
        .read(kycDocumentServiceProvider)
        .pickAndUpload(type: type, fromCamera: fromCamera);
    if (!mounted) return;

    setState(() {
      if (isPrimary) {
        _uploadingPrimary = false;
      } else {
        _uploadingIdCard = false;
      }
    });

    result.fold(
      (failure) => ref.read(snackbarServiceProvider).showError(failure.message),
      (uploaded) {
        if (uploaded == null) return;
        setState(() {
          if (isPrimary) {
            _primaryDoc = uploaded;
          } else {
            _idCardDoc = uploaded;
          }
          if (_primaryDoc != null && _idCardDoc != null) {
            _showDocError = false;
          }
        });
        ref
            .read(snackbarServiceProvider)
            .showSuccess('Dokumen ${uploaded.fileName} berhasil diunggah.');
      },
    );
  }

  Future<void> _submit() async {
    final validForm = _formKey.currentState?.validate() ?? false;
    if (_primaryDoc == null || _idCardDoc == null) {
      setState(() => _showDocError = true);
      return;
    }
    if (!validForm) return;

    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      ref
          .read(snackbarServiceProvider)
          .showError('Sesi tidak valid. Silakan masuk kembali.');
      return;
    }

    final input = SubmitKycInput(
      userId: userId,
      organizationName: _orgController.text.trim(),
      category: _category,
      address: _addressController.text.trim(),
      contactPhone: _phoneController.text.trim(),
      beneficiaryCount: int.tryParse(_beneficiaryController.text.trim()) ?? 0,
      documents: [_primaryDoc!, _idCardDoc!],
    );

    final ok = await ref.read(kycNotifierProvider.notifier).submitKyc(input);
    if (!mounted) return;
    final snack = ref.read(snackbarServiceProvider);
    if (ok) {
      snack.showSuccess('Pengajuan KYC berhasil dikirim untuk verifikasi.');
      Navigator.of(context).pop();
    } else {
      snack.showError(
        ref.read(kycNotifierProvider).failure?.message ??
            'Gagal mengirim pengajuan KYC.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final isLoading = ref.watch(kycNotifierProvider.select((s) => s.isLoading));
    final isBusy = isLoading || _uploadingPrimary || _uploadingIdCard;

    return AppBottomSheetScaffold(
      title: 'Verifikasi Penerima Donasi (KYC)',
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final c in RecipientCategory.values)
                  ChoiceChip(
                    label: Text(AppFormatters.recipientCategoryLabel(c)),
                    selected: _category == c,
                    onSelected: isBusy
                        ? null
                        : (_) => setState(() {
                            _category = c;
                            if (_primaryDoc != null &&
                                _primaryDoc!.type != _primaryDocType) {
                              _primaryDoc = null;
                            }
                          }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const Key('kyc_org_name_field'),
              controller: _orgController,
              enabled: !isBusy,
              decoration: const InputDecoration(
                labelText: 'Nama Panti / Yayasan / Komunitas',
              ),
              validator: (v) {
                final text = v?.trim() ?? '';
                if (text.isEmpty) return 'Nama organisasi wajib diisi.';
                if (text.length < 3) return 'Minimal 3 karakter.';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const Key('kyc_address_field'),
              controller: _addressController,
              enabled: !isBusy,
              decoration: const InputDecoration(labelText: 'Alamat Lengkap'),
              validator: (v) {
                final text = v?.trim() ?? '';
                if (text.isEmpty) return 'Alamat lengkap wajib diisi.';
                if (text.length < 10) return 'Minimal 10 karakter.';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: const Key('kyc_phone_field'),
                    controller: _phoneController,
                    enabled: !isBusy,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'No. Telepon',
                      hintText: '081234567890',
                    ),
                    validator: (v) {
                      final digits = (v ?? '').replaceAll(
                        RegExp(r'[\s\-\+]'),
                        '',
                      );
                      if (!_phonePattern.hasMatch(digits)) {
                        return 'Wajib 10–15 digit angka.';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    key: const Key('kyc_beneficiary_field'),
                    controller: _beneficiaryController,
                    enabled: !isBusy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Penerima'),
                    validator: (v) {
                      final count = int.tryParse(v?.trim() ?? '') ?? 0;
                      if (count <= 0) return 'Min. 1';
                      if (count > 10000) return 'Maks. 10rb';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Unggah Dokumen Wajib (Maks. 5 MB)',
              style: textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _DocumentUploadTile(
              key: const Key('kyc_upload_primary_doc'),
              title: _category == RecipientCategory.distributionVolunteer
                  ? 'Surat Keterangan RT/RW/Komunitas'
                  : 'Akta / SK Legalitas Yayasan',
              document: _primaryDoc,
              isUploading: _uploadingPrimary,
              onPickGallery: isBusy
                  ? null
                  : () => _pickDocument(isPrimary: true, fromCamera: false),
              onPickCamera: isBusy
                  ? null
                  : () => _pickDocument(isPrimary: true, fromCamera: true),
              onRemove: isBusy
                  ? null
                  : () => setState(() => _primaryDoc = null),
            ),
            const SizedBox(height: AppSpacing.sm),
            _DocumentUploadTile(
              key: const Key('kyc_upload_id_card_doc'),
              title: 'KTP Penanggung Jawab',
              document: _idCardDoc,
              isUploading: _uploadingIdCard,
              onPickGallery: isBusy
                  ? null
                  : () => _pickDocument(isPrimary: false, fromCamera: false),
              onPickCamera: isBusy
                  ? null
                  : () => _pickDocument(isPrimary: false, fromCamera: true),
              onRemove: isBusy ? null : () => setState(() => _idCardDoc = null),
            ),
            if (_showDocError && (_primaryDoc == null || _idCardDoc == null))
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  'Kedua dokumen wajib diunggah sebelum mengirim pengajuan.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            AuthSubmitButton(
              key: const Key('kyc_submit_button'),
              label: 'Kirim Pengajuan KYC',
              isLoading: isLoading,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentUploadTile extends StatelessWidget {
  const new({
    required this.title,
    required this.document,
    required this.isUploading,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onRemove,
    super.key,
  });

  final String title;
  final KycDocument? document;
  final bool isUploading;
  final VoidCallback? onPickGallery;
  final VoidCallback? onPickCamera;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final uploaded = document;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.circular(AppRadius.md),
        border: Border.all(
          color: uploaded != null
              ? colorScheme.primary.withValues(alpha: 0.6)
              : colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                uploaded != null
                    ? Icons.check_circle_outline_rounded
                    : Icons.upload_file_outlined,
                size: 18,
                color: uploaded != null
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (uploaded != null && !isUploading)
                IconButton(
                  tooltip: 'Hapus dokumen',
                  visualDensity: VisualDensity.compact,
                  onPressed: onRemove,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (uploaded != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${uploaded.fileName} • '
              '${(uploaded.fileSizeBytes / 1024).toStringAsFixed(0)} KB',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(color: colorScheme.primary),
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.sm),
            if (isUploading)
              const LinearProgressIndicator(minHeight: 3)
            else
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  OutlinedButton.icon(
                    onPressed: onPickGallery,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.photo_library_outlined, size: 16),
                    label: const Text('Galeri'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onPickCamera,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.photo_camera_outlined, size: 16),
                    label: const Text('Kamera'),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
