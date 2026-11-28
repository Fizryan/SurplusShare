/// Single Source of Truth for interactive OpenStreetMap tile configuration.
abstract final class AppMapConfig {
  static const String tileUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String userAgentPackageName = 'id.surplusshare.app';
}
