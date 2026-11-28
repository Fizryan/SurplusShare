enum RecipientCategory {
  orphanage(minDailyQuota: 10, maxDailyQuota: 100),
  socialFoundation(minDailyQuota: 10, maxDailyQuota: 80),
  distributionVolunteer(minDailyQuota: 5, maxDailyQuota: 30);

  new({required this.minDailyQuota, required this.maxDailyQuota});

  final int minDailyQuota;
  final int maxDailyQuota;
}
