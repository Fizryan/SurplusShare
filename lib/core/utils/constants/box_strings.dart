abstract final class HiveBoxes {
  static const settingsBox = 'settingsBox';
  static const cacheBox = 'cacheBox';
}

abstract final class HiveKeys {
  static const themeMode = 'themeMode';
  static const themeColor = 'themeColor';
}

abstract final class CacheKeys {
  static const lastLocation = 'cache_last_location';
  static const listingsSnapshot = 'cache_listings_snapshot';

  // User-scoped keys prevent cross-account cache leakage.
  static String favoritePartnersFor(String userId) =>
      'cache_favorite_partners_$userId';
  static String notificationRadiusFor(String userId) =>
      'cache_notification_radius_km_$userId';
  static String foodSafetyFilterFor(String userId) =>
      'cache_food_safety_filter_$userId';
  static String dailyQuotaFor(String userId) =>
      'cache_daily_quota_snapshot_$userId';
}
