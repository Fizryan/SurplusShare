import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

class LoggerConfig {
  new _();

  static final Logger logger = Logger(
    filter: ProductionFilter(),
    level: kReleaseMode ? Level.warning : Level.debug,
    printer: PrettyPrinter(
      lineLength: 0,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );
}
