import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:surplus_share/core/theme/theme_service.dart';
import 'package:surplus_share/core/theme/theme_state.dart';
import 'package:surplus_share/core/utils/constants/box_strings.dart';

class _MockBox extends Mock implements Box<dynamic>;

void main() {
  late _MockBox box;
  late ThemeService service;

  setUp(() {
    box = _MockBox();
    service = ThemeService(box);
  });

  group('ThemeService', () {
    test('returns saved dark mode and green color', () {
      when(() => box.get(HiveKeys.themeMode)).thenReturn(ThemeMode.dark.name);
      when(() => box.get(HiveKeys.themeColor))
          .thenReturn(AppThemeColor.green.name);

      final state = service.getThemeState();

      expect(
        state,
        const ThemeState(mode: ThemeMode.dark, color: AppThemeColor.green),
      );
    });

    test('safely falls back to defaults when box contains corrupted types', () {
      when(() => box.get(HiveKeys.themeMode)).thenReturn(12345);
      when(() => box.get(HiveKeys.themeColor)).thenReturn(true);

      final state = service.getThemeState();

      expect(
        state,
        const ThemeState(mode: ThemeMode.system, color: AppThemeColor.green),
      );
    });
  });
}
