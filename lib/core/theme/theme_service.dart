import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/theme/theme_state.dart';
import 'package:surplus_share/core/utils/constants/box_strings.dart';

class ThemeService {
  new(this._box);

  final Box<dynamic> _box;

  ThemeState getThemeState() {
    final themeString = _box.get(HiveKeys.themeMode) as String?;
    _box.get(HiveKeys.themeColor);

    var mode = ThemeMode.system;
    if (themeString == ThemeMode.light.name) mode = ThemeMode.light;
    if (themeString == ThemeMode.dark.name) mode = ThemeMode.dark;

    const color = AppThemeColor.green;

    return ThemeState(mode: mode, color: color);
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    await _box.put(HiveKeys.themeMode, mode.name);
  }

  Future<void> saveThemeColor(AppThemeColor color) async {
    await _box.put(HiveKeys.themeColor, color.name);
  }
}
