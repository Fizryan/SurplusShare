import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/di/global_provider.dart';
import 'package:surplus_share/core/shared/widgets/app_bottom_sheet_scaffold.dart';
import 'package:surplus_share/core/theme/app_tokens.dart';
import 'package:surplus_share/features/auth/presentation/widgets/auth_submit_button.dart';
import 'package:surplus_share/features/distribution/presentation/provider/distribution_provider.dart';
import 'package:surplus_share/features/reservation/domain/policy/reservation_policy.dart';

enum DistributionPinMode { pickup, delivery }

class DistributionPinSheet extends ConsumerStatefulWidget {
  const new({
    required this.taskId,
    required this.listingTitle,
    required this.counterpartyName,
    required this.mode,
    super.key,
  });

  final String taskId;
  final String listingTitle;
  final String counterpartyName;
  final DistributionPinMode mode;

  @override
  ConsumerState<DistributionPinSheet> createState() =>
      _DistributionPinSheetState();
}

class _DistributionPinSheetState extends ConsumerState<DistributionPinSheet> {
  final _formKey = GlobalKey<FormState>();
  final _pinController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final notifier = ref.read(distributionNotifierProvider.notifier);
    final pin = _pinController.text.trim();
    final isPickup = widget.mode == DistributionPinMode.pickup;

    final ok = isPickup
        ? await notifier.markPickedUp(taskId: widget.taskId, pin: pin)
        : await notifier.markDelivered(taskId: widget.taskId, pin: pin);
    if (!mounted) return;

    final snack = ref.read(snackbarServiceProvider);
    if (ok) {
      snack.showSuccess(
        isPickup
            ? 'PIN Pickup valid! Silakan antar paket ke penerima.'
            : 'PIN Terima valid! Distribusi selesai diserahkan.',
      );
      Navigator.of(context).pop(true);
    } else {
      snack.showError(
        ref.read(distributionNotifierProvider).failure?.message ??
            'Verifikasi PIN distribusi gagal.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(
      distributionNotifierProvider.select((s) => s.isLoading),
    );
    final isPickup = widget.mode == DistributionPinMode.pickup;

    return AppBottomSheetScaffold(
      title: isPickup
          ? 'Verifikasi PIN Pickup Toko'
          : 'Verifikasi PIN Penerima Donasi',
      subtitle: '${widget.listingTitle} • ${widget.counterpartyName}',
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const Key('distribution_pin_input'),
              controller: _pinController,
              enabled: !isLoading,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: ReservationPolicy.pinLength,
              decoration: InputDecoration(
                labelText: isPickup
                    ? 'Masukkan 6 Digit PIN dari Mitra Toko'
                    : 'Masukkan 6 Digit PIN dari Panti / Penerima',
                prefixIcon: const Icon(Icons.pin_outlined),
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
              key: const Key('distribution_pin_submit'),
              label: isPickup
                  ? 'Konfirmasi Pickup Paket'
                  : 'Selesaikan Pengantaran',
              isLoading: isLoading,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
