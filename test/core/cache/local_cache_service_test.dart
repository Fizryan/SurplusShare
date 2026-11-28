import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:surplus_share/core/cache/local_cache_service.dart';

class _MockBox extends Mock implements Box<dynamic>;

void main() {
  group('InMemoryCacheStore', () {
    test(
      'writes, reads before TTL, expires after TTL, supports allowStale',
      () async {
        var now = DateTime.utc(2026, 11, 27, 10);
        final cache = InMemoryCacheStore(clock: () => now);

        await cache.writeJson('k1', {'v': 42}, ttl: const Duration(minutes: 5));
        expect(cache.readJson('k1'), {'v': 42});

        now = now.add(const Duration(minutes: 6));
        expect(cache.readJson('k1'), isNull);
        expect(cache.readJson('k1', allowStale: true), {'v': 42});

        await cache.delete('k1');
        expect(cache.readJson('k1', allowStale: true), isNull);
      },
    );
  });

  group('HiveCacheStore', () {
    test(
      'persists JSON with TTL and safely handles corrupted entries',
      () async {
        final storage = <dynamic, dynamic>{};
        final box = _MockBox();
        when(() => box.put(any<dynamic>(), any<dynamic>()))
            .thenAnswer((inv) async {
              storage[inv.positionalArguments[0]] = inv.positionalArguments[1];
            });
        when(() => box.get(any<dynamic>()))
            .thenAnswer((inv) => storage[inv.positionalArguments[0]]);
        when(box.clear).thenAnswer((_) async {
          storage.clear();
          return 0;
        });

        var now = DateTime.utc(2026, 11, 27, 10);
        final cache = HiveCacheStore(box, clock: () => now);

        await cache.writeJson('loc', {
          'latitude': -6.2,
          'longitude': 106.8,
        }, ttl: const Duration(minutes: 30));
        expect(cache.readJson('loc'), {'latitude': -6.2, 'longitude': 106.8});

        now = now.add(const Duration(minutes: 31));
        expect(cache.readJson('loc'), isNull);
        expect(cache.readJson('loc', allowStale: true), {
          'latitude': -6.2,
          'longitude': 106.8,
        });

        // Corrupted non-JSON entry returns null safely.
        storage['broken'] = '{not-valid-json';
        expect(cache.readJson('broken'), isNull);

        await cache.clear();
        expect(cache.readJson('loc', allowStale: true), isNull);
      },
    );
  });
}
