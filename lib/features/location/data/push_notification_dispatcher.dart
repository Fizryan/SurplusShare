import 'dart:async';

import 'package:surplus_share/features/location/domain/models/radius_notification_event.dart';

/// Abstraction for dispatching real-time surplus push notifications.
abstract interface class PushNotificationDispatcher {
  Stream<RadiusNotificationEvent> get stream;

  List<RadiusNotificationEvent> get history;

  Future<void> dispatch(RadiusNotificationEvent event);

  void dispose();
}

/// In-memory broadcast dispatcher for local/debug mode and deterministic tests.
class InMemoryPushNotificationDispatcher implements PushNotificationDispatcher {
  final _controller = StreamController<RadiusNotificationEvent>.broadcast();
  final List<RadiusNotificationEvent> _history = [];

  @override
  Stream<RadiusNotificationEvent> get stream => _controller.stream;

  @override
  List<RadiusNotificationEvent> get history =>
      List<RadiusNotificationEvent>.unmodifiable(_history);

  @override
  Future<void> dispatch(RadiusNotificationEvent event) async {
    _history.insert(0, event);
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  @override
  void dispose() {
    unawaited(_controller.close());
  }
}
