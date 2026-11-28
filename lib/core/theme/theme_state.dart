import 'package:material_ui/material_ui.dart';

enum AppThemeColor { green }

@immutable
class ThemeState {
  const new({required this.mode, required this.color});

  final ThemeMode mode;
  final AppThemeColor color;

  ThemeState copyWith({ThemeMode? mode, AppThemeColor? color}) {
    return ThemeState(mode: mode ?? this.mode, color: color ?? this.color);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ThemeState && other.mode == mode && other.color == color;
  }

  @override
  int get hashCode => Object.hash(mode, color);
}
