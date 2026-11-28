import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:surplus_share/core/auth/models/auth_failure.dart';
import 'package:surplus_share/core/auth/models/auth_state.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/di/global_provider.dart';

/// Listens to [authNotifierProvider] and displays deduplicated error snackbars
/// whenever an auth action fails (ignoring voluntary user cancellations).
void listenAuthError(WidgetRef ref) {
  ref.listen<AuthState>(authNotifierProvider, (previous, next) {
    if (next is AuthUnauthenticated &&
        next.failure != null &&
        next.failure is! AuthCancelledFailure) {
      final prevFailure = previous is AuthUnauthenticated
          ? previous.failure
          : null;
      if (next.failure != prevFailure) {
        ref.read(snackbarServiceProvider).showError(next.failure!.message);
      }
    }
  });
}
