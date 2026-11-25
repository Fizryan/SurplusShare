import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/config/logger_config.dart';

class SnackbarService {
  final GlobalKey<ScaffoldMessengerState> scaffoldKey =
      GlobalKey<ScaffoldMessengerState>();

  void showSuccess(
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    _show(message, _SnackbarType.success, duration: duration, action: action);
  }

  void showError(
    String message, {
    Duration duration = const Duration(seconds: 5),
    SnackBarAction? action,
  }) {
    _show(message, _SnackbarType.error, duration: duration, action: action);
  }

  void showInfo(
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    _show(message, _SnackbarType.info, duration: duration, action: action);
  }

  void _show(
    String message,
    _SnackbarType type, {
    required Duration duration,
    SnackBarAction? action,
  }) {
    final messenger = scaffoldKey.currentState;
    final context = scaffoldKey.currentContext;

    if (messenger == null || context == null) {
      LoggerConfig.logger.w(
        '[SnackbarService] ScaffoldMessenger tidak tersedia. '
        'Pastikan scaffoldKey tersambung di MaterialApp.',
      );
      return;
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final (bgColor, fgColor, borderColor, icon) = switch (type) {
      _SnackbarType.success => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
        colorScheme.primary.withValues(alpha: 0.35),
        Icons.check_circle_outline,
      ),
      _SnackbarType.error => (
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
        colorScheme.error.withValues(alpha: 0.35),
        Icons.error_outline,
      ),
      _SnackbarType.info => (
        colorScheme.secondaryContainer,
        colorScheme.onSecondaryContainer,
        colorScheme.secondary.withValues(alpha: 0.35),
        Icons.info_outline,
      ),
    };

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, size: 20, color: fgColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: fgColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: bgColor,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          duration: duration,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: borderColor),
          ),
          action: action,
        ),
      );
  }
}

enum _SnackbarType { success, error, info }
