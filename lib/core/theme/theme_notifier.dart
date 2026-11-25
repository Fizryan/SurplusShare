import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/di/global_provider.dart';
import 'package:surplus_share/core/theme/theme_state.dart';

class ThemeNotifier extends Notifier<ThemeState> {
  @override
  ThemeState build() {
    return ref.read(themeServiceProvider).getThemeState();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (state.mode == mode) return;
    state = state.copyWith(mode: mode);
    await ref.read(themeServiceProvider).saveThemeMode(mode);
  }

  Future<void> setThemeColor(AppThemeColor color) async {
    if (state.color == color) return;
    state = state.copyWith(color: color);
    await ref.read(themeServiceProvider).saveThemeColor(color);
  }
}
