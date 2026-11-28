import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/core/utils/constants/box_strings.dart';

/// Lightweight JSON cache with optional TTL for fast stale-while-revalidate UX.
abstract interface class CacheStore {
  Future<void> writeJson(
    String key,
    Map<String, dynamic> data, {
    Duration? ttl,
  });

  Map<String, dynamic>? readJson(String key, {bool allowStale = false});

  Future<void> delete(String key);

  Future<void> clear();
}

class HiveCacheStore implements CacheStore {
  new(this._box, {Clock? clock}) : _clock = clock ?? DateTime.now;

  final Box<dynamic> _box;
  final Clock _clock;

  @override
  Future<void> writeJson(
    String key,
    Map<String, dynamic> data, {
    Duration? ttl,
  }) async {
    final now = _clock().toUtc();
    final envelope = <String, dynamic>{
      'cached_at': now.millisecondsSinceEpoch,
      'expires_at': ttl == null ? null : now.add(ttl).millisecondsSinceEpoch,
      'data': data,
    };
    await _box.put(key, jsonEncode(envelope));
  }

  @override
  Map<String, dynamic>? readJson(String key, {bool allowStale = false}) {
    final raw = _box.get(key);
    if (raw is! String || raw.isEmpty) return null;

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final envelope = Map<String, dynamic>.from(decoded);
      final expiresAtMs = envelope['expires_at'];
      if (!allowStale && expiresAtMs is int) {
        final nowMs = _clock().toUtc().millisecondsSinceEpoch;
        if (nowMs >= expiresAtMs) return null;
      }

      final payload = envelope['data'];
      if (payload is Map<String, dynamic>) return payload;
      if (payload is Map) return Map<String, dynamic>.from(payload);
      return null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> delete(String key) => _box.delete(key);

  @override
  Future<void> clear() async {
    await _box.clear();
  }
}

class InMemoryCacheStore implements CacheStore {
  new({Clock? clock}) : _clock = clock ?? DateTime.now;

  final Clock _clock;
  final Map<String, ({Map<String, dynamic> data, DateTime? expiresAt})> _store =
      {};

  @override
  Future<void> writeJson(
    String key,
    Map<String, dynamic> data, {
    Duration? ttl,
  }) async {
    final expiresAt = ttl == null ? null : _clock().toUtc().add(ttl);
    _store[key] = (data: Map<String, dynamic>.from(data), expiresAt: expiresAt);
  }

  @override
  Map<String, dynamic>? readJson(String key, {bool allowStale = false}) {
    final entry = _store[key];
    if (entry == null) return null;
    if (!allowStale &&
        entry.expiresAt != null &&
        !_clock().toUtc().isBefore(entry.expiresAt!)) {
      return null;
    }
    return Map<String, dynamic>.from(entry.data);
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }

  @override
  Future<void> clear() async {
    _store.clear();
  }
}

final cacheStoreProvider = Provider<CacheStore>((ref) {
  final clock = ref.watch(clockProvider);
  if (Hive.isBoxOpen(HiveBoxes.cacheBox)) {
    return HiveCacheStore(Hive.box<dynamic>(HiveBoxes.cacheBox), clock: clock);
  }
  return InMemoryCacheStore(clock: clock);
});
