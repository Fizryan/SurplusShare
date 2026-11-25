import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:surplus_share/core/shared/service/snackbar_service.dart';
import 'package:surplus_share/core/theme/theme_notifier.dart';
import 'package:surplus_share/core/theme/theme_service.dart';
import 'package:surplus_share/core/theme/theme_state.dart';
import 'package:surplus_share/core/utils/constants/box_strings.dart';

final settingsBoxProvider = Provider<Box<dynamic>>((ref) {
  return Hive.box(HiveBoxes.settingsBox);
});

final themeServiceProvider = Provider<ThemeService>((ref) {
  final box = ref.watch(settingsBoxProvider);
  return ThemeService(box);
});

final themeNotifierProvider = NotifierProvider<ThemeNotifier, ThemeState>(
  ThemeNotifier.new,
);

final snackbarServiceProvider = Provider<SnackbarService>((ref) {
  return SnackbarService();
});
