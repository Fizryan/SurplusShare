abstract final class ApiEndpoints {
  static const googleAuth = '/auth/google';
  static const refresh = '/auth/refresh';
  static const logout = '/auth/logout';

  static const listings = '/listings';
  static String convertListingToDonation(String id) =>
      '/listings/$id/convert-donation';
  static String claimListingStock(String id) => '/listings/$id/claim';
  static String releaseListingStock(String id) => '/listings/$id/release';
  static String closeListing(String id) => '/listings/$id/close';

  static const myKyc = '/kyc/me';
  static const uploadKycDocument = '/kyc/documents';
  static const kycApplications = '/kyc/applications';
  static const pendingKycApplications = '/kyc/applications/pending';
  static String approveKyc(String id) => '/kyc/applications/$id/approve';
  static String rejectKyc(String id) => '/kyc/applications/$id/reject';
  static const myDailyQuota = '/kyc/quota/me';
  static const consumeDailyQuota = '/kyc/quota/consume';
  static const refundDailyQuota = '/kyc/quota/refund';

  static const myReservations = '/reservations/me';
  static const partnerReservations = '/reservations/partner';
  static const discountReservation = '/reservations/discount';
  static const donationReservation = '/reservations/donation';
  static String confirmReservationPayment(String id) =>
      '/reservations/$id/confirm-payment';
  static String cancelReservation(String id) => '/reservations/$id/cancel';
  static String validateReservationPin(String id) =>
      '/reservations/$id/validate-pin';
}
