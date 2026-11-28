import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/di/global_provider.dart';
import 'package:surplus_share/core/shared/widgets/app_bottom_sheet_scaffold.dart';
import 'package:surplus_share/core/theme/app_tokens.dart';
import 'package:surplus_share/features/auth/presentation/widgets/auth_submit_button.dart';
import 'package:surplus_share/features/reservation/domain/policy/reservation_policy.dart';
import 'package:surplus_share/features/reservation/presentation/provider/reservation_provider.dart';

class PinValidationSheet extends ConsumerStatefulWidget {
  const new({
    required this.reservationId,
    required this.listingTitle,
    super.key,
  });

  final String reservationId;
  final String listingTitle;

  @override
  ConsumerState<PinValidationSheet> createState() => _PinValidationSheetState();
}

class _PinValidationSheetState extends ConsumerState<PinValidationSheet> {
  final _formKey = GlobalKey<FormState>();
  final _pinController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final ok = await ref
        .read(reservationNotifierProvider.notifier)
        .validatePickupPin(
          reservationId: widget.reservationId,
          pin: _pinController.text.trim(),
        );
    if (!mounted) return;
    final snack = ref.read(snackbarServiceProvider);
    if (ok) {
      snack.showSuccess('PIN valid! Bukti digital serah terima diterbitkan.');
      Navigator.of(context).pop();
    } else {
      snack.showError(
        ref.read(reservationNotifierProvider).failure?.message ??
            'Validasi PIN gagal.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(
      reservationNotifierProvider.select((s) => s.isLoading),
    );

    return AppBottomSheetScaffold(
      title: 'Validasi PIN Serah Terima',
      subtitle: widget.listingTitle,
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const Key('pin_validation_input'),
              controller: _pinController,
              enabled: !isLoading,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: ReservationPolicy.pinLength,
              decoration: const InputDecoration(
                labelText: 'Masukkan 6 Digit PIN Pelanggan',
                prefixIcon: Icon(Icons.pin_outlined),
              ),
              validator: (value) {
                final digits = value?.trim() ?? '';
                if (!RegExp(
                  r'^\d{'
                  '${ReservationPolicy.pinLength}'
                  r'}$',
                ).hasMatch(digits)) {
                  return 'PIN harus terdiri dari '
                      '${ReservationPolicy.pinLength} digit angka.';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            AuthSubmitButton(
              key: const Key('pin_validation_submit'),
              label: 'Verifikasi & Selesaikan',
              isLoading: isLoading,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
