import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:logger/logger.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/app/app.dart';
import 'package:surplus_share/core/config/api_config.dart';
import 'package:surplus_share/core/config/logger_config.dart';
import 'package:surplus_share/core/utils/constants/box_strings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kDebugMode) {
    const ApiConfig.fromEnvironment().validate();
  }

  GoogleFonts.config.allowRuntimeFetching = true;

  final logger = LoggerConfig.logger;
  _setupGlobalErrorHandling(logger);

  try {
    await Hive.initFlutter();
    await Future.wait([
      Hive.openBox<dynamic>(HiveBoxes.settingsBox),
      Hive.openBox<dynamic>(HiveBoxes.cacheBox),
    ]);

    runApp(
      ProviderScope(
        observers: [if (kDebugMode) _RiverpodObserver(logger)],
        child: const MainApp(),
      ),
    );
  } on Object catch (e, stack) {
    logger.e(
      '[${e.runtimeType}]: Gagal inisiasi database Hive saat startup.',
      error: e,
      stackTrace: stack,
    );

    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Gagal memuat data aplikasi, silahkan coba restart aplikasi.',
            ),
          ),
        ),
      ),
    );
  }
}

void _setupGlobalErrorHandling(Logger logger) {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    logger.e(
      '[${details.runtimeType}]: ${details.exception}',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    logger.e('[${error.runtimeType}]: $error', error: error, stackTrace: stack);
    return true;
  };
}

final class _RiverpodObserver extends ProviderObserver {
  new(this._logger);

  final Logger _logger;

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousState,
    Object? newValue,
  ) {
    _logger.d(
      '[_RiverpodObserver] '
      '${context.provider.name ?? context.provider.runtimeType}: '
      '$previousState -> $newValue',
    );
  }

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    _logger.d(
      '[_RiverpodObserver] disposed '
      '${context.provider.name ?? context.provider.runtimeType}',
    );
  }
}
