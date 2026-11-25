import 'package:logger/logger.dart';

class LoggerConfig {
  new _();

  static final Logger logger = Logger(
    filter: ProductionFilter(),
    printer: PrettyPrinter(
      lineLength: 0,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );
}
