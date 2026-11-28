import 'package:intl/intl.dart';
import 'package:surplus_share/core/permission/app_role.dart';
import 'package:surplus_share/features/kyc/domain/models/recipient_category.dart';
import 'package:surplus_share/features/listing/domain/models/food_safety_declaration.dart';

/// Single Source of Truth for Indonesian domain labels & currency formatting.
abstract final class AppFormatters {
  static final NumberFormat _rupiah = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  static String formatRupiah(int amount) => _rupiah.format(amount);

  static String halalLabel(HalalStatus status) => switch (status) {
    HalalStatus.halalCertified => 'Halal MUI',
    HalalStatus.halalFriendly => 'Halal Friendly',
    HalalStatus.nonHalal => 'Non-Halal',
  };

  static String foodCategoryLabel(FoodCategory category) => switch (category) {
    FoodCategory.readyToEat => 'Siap Saji',
    FoodCategory.bakery => 'Bakery',
    FoodCategory.rawIngredients => 'Bahan Mentah',
    FoodCategory.beverages => 'Minuman',
  };

  static String allergenLabel(FoodAllergen allergen) => switch (allergen) {
    FoodAllergen.peanuts => 'Kacang',
    FoodAllergen.dairy => 'Susu',
    FoodAllergen.seafood => 'Seafood',
    FoodAllergen.eggs => 'Telur',
    FoodAllergen.gluten => 'Gluten',
    FoodAllergen.soy => 'Kedelai',
  };

  static String recipientCategoryLabel(RecipientCategory category) =>
      switch (category) {
        RecipientCategory.orphanage => 'Panti Asuhan',
        RecipientCategory.socialFoundation => 'Yayasan Sosial',
        RecipientCategory.distributionVolunteer => 'Relawan Distribusi',
      };

  static String kycStatusLabel(KycStatus status) => switch (status) {
    KycStatus.unverified => 'Belum Terverifikasi',
    KycStatus.pending => 'Menunggu Review',
    KycStatus.approved => 'Terverifikasi',
    KycStatus.rejected => 'Ditolak',
  };

  static String roleLabel(AppRole role) => switch (role) {
    AppRole.consumer => 'Konsumen',
    AppRole.verifiedRecipient => 'Penerima Donasi',
    AppRole.donorPartner => 'Mitra Donatur',
    AppRole.volunteer => 'Relawan',
    AppRole.admin => 'Admin',
  };
}
