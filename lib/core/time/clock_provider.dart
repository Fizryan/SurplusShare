import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef Clock = DateTime Function();

/// Injectable clock for deterministic time-based business logic and testing.
final clockProvider = Provider<Clock>((ref) => DateTime.now);

/// Single shared 1-second ticker across all active countdown consumers.
/// Automatically stops and cancels its timer synchronously on dispose.
final StreamProvider<DateTime> countdownTickerProvider =
    StreamProvider.autoDispose<DateTime>((ref) {
      final clock = ref.watch(clockProvider);
      Timer? timer;
      late final StreamController<DateTime> controller;

      void stopTimer() {
        timer?.cancel();
        timer = null;
      }

      controller = StreamController<DateTime>(
        onListen: () {
          controller.add(clock());
          timer = Timer.periodic(const Duration(seconds: 1), (_) {
            if (!controller.isClosed) {
              controller.add(clock());
            }
          });
        },
        onCancel: stopTimer,
      );

      ref.onDispose(() {
        stopTimer();
        unawaited(controller.close());
      });

      return controller.stream;
    });
