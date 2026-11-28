# Surplus Share — Don't Waste Your Food

**Surplus Share** adalah aplikasi mobile berbasis Flutter untuk menyelamatkan makanan surplus layak konsumsi dari restoran, hotel, katering, dan bakery melalui **dua jalur distribusi terintegrasi**:

1. **Mode Diskon Surplus** (*Flash Sale* & *Surprise Bag* dengan diskon 10%–90%) bagi konsumen umum.
2. **Mode Donasi Gratis Terverifikasi** khusus bagi panti asuhan, yayasan sosial, dan komunitas terverifikasi (KYC), lengkap dengan **jaringan relawan distribusi** (*volunteer*) dari titik toko hingga titik panti penerima.

---

## Fitur Utama

### 1. Dual-Channel Surplus Listing & Keamanan Pangan

- **Publikasi Dua Jalur**: Mitra (`donorPartner`) dapat mengunggah stok sebagai **Mode Diskon** (*Flash Sale* / *Surprise Bag*) maupun langsung sebagai **Donasi Gratis** tanpa harus melewati format komersial terlebih dahulu.
- **Konversi ke Donasi**: Stok diskon yang belum terjual dapat dialihkan satu klik ke **Donasi Gratis** menjelang jam tutup.
- **Deklarasi Halal, Kategori & Alergen**: Setiap paket memuat status halal (*Halal MUI*, *Halal Friendly*, *Non-Halal*), kategori makanan, daftar alergen, batas waktu aman konsumsi, serta konfirmasi higienitas.
- **Filter Real-Time & Countdown**: Hitung mundur jendela pengambilan (*pickup window*) otomatis menandai stok kedaluwarsa (`expired`) tanpa membebani rebuild UI.

### 2. Peran Pengguna (RBAC) & Verifikasi KYC

Aplikasi menerapkan kontrol akses berbasis peran (**RBAC**) dan gerbang verifikasi (**KYC Gate**):

| Role | Label | Akses & Kemampuan Utama |
| --- | --- | --- |
| `consumer` | Konsumen | Menjelajahi & memesan stok **Diskon Surplus**, filter Halal/Alergen, peta sekitar 1–3 km, lacak dampak pribadi. |
| `verifiedRecipient` | Penerima Donasi | Semua akses konsumen + melihat & mengklaim **Donasi Gratis** (multi-porsi sesuai kuota harian), mengatur **Lokasi Panti Tetap**, dan menerima paket antaran relawan dengan **PIN Terima**. |
| `donorPartner` | Mitra Donatur | Mengatur **Lokasi Toko Tetap**, mengunggah & mengelola stok (Diskon / Donasi), mengalokasikan porsi untuk relawan, memvalidasi **PIN Pelanggan**, memberikan **PIN Pickup** ke relawan, dan mengekspor **Laporan CSR/ESG (PDF)**. |
| `volunteer` | Relawan | Menjelajahi & memesan stok diskon, mengambil tugas distribusi dari toko ke panti di tab **Distribusi**, melihat peta rute pickup → drop-off, serta menyelesaikan pengantaran dengan **PIN Pickup & PIN Terima**. |
| `admin` | Admin | Akses penuh lintas fitur + antrean review **Persetujuan / Penolakan KYC** dengan rekomendasi kuota donasi harian otomatis. |

- **Visibilitas Beranda Berbasis Hak Aksi**: Beranda dan tab Sekitar hanya menampilkan stok yang benar-benar dapat dipesan/diklaim (`canClaim`) atau dikelola pemiliknya (`canManage`) — tanpa tombol aksi yang berujung error izin.
- **Upload Dokumen KYC**: Mendukung pengambilan gambar dari galeri/kamera (`image_picker`) dengan validasi MIME (`PDF`, `JPG`, `PNG`, `WEBP`) dan batas ukuran 5 MB.

### 3. Titik Lokasi Tetap (`PinnedLocation`) & Eksplorasi Radius 1–3 km

- **Anti-GPS Drift**: `donorPartner` (toko) dan `verifiedRecipient` (panti/komunitas) mengunci koordinat tetap melalui peta interaktif (`flutter_map` tap-to-pin + alamat lengkap). Koordinat listing selalu diambil dari titik toko tetap, bukan GPS perangkat mitra.
- **GPS Bertingkat & Fallback Area**: Akuisisi lokasi 3 lapis (*Fused Location* → *Android LocationManager* → *Last Known Position*) dilengkapi pemilih area manual (*Jakarta Pusat*, *Jakarta Selatan*, *Bandung*, *Surabaya*) saat GPS tidak tersedia/indoor.
- **Peta & Notifikasi Radius**: Menampilkan toko terdekat dalam radius 1–3 km (diurutkan berbasis formula Haversine) dan notifikasi real-time untuk mitra favorit atau stok dalam radius.

### 4. Reservasi, Pemilih Multi-Porsi & Distribusi Relawan Ber-PIN

- **Pemilih Jumlah Porsi (`BookListingSheet`)**:
  - **Donasi Gratis**: Panti/komunitas dapat memilih banyak porsi sekaligus melalui stepper `- / +` atau tombol cepat (`1`, `5`, `10`, `Maks`) yang otomatis dibatasi `min(sisaStok, sisaKuotaHarian)`.
  - **Mode Diskon**: Memilih jumlah porsi, melihat total harga real-time, dan memilih metode bayar (**QRIS** / **E-Wallet**).
- **Verifikasi PIN 6-Digit Ganda**:
  - **Reservasi Pelanggan**: PIN 6-digit hanya tampil pada akun pemilik reservasi (tersembunyi dari tab *Pesanan Masuk* mitra) dan divalidasi mitra saat pengambilan untuk menerbitkan bukti digital (*Handover Receipt*).
  - **Pengantaran Relawan**: Saat relawan mengambil tugas (`open → accepted`), sistem menerbitkan **PIN Pickup** (dipegang mitra toko) dan **PIN Terima** (dipegang panti penerima). Relawan wajib memverifikasi kedua PIN saat pickup (`accepted → pickedUp`) dan drop-off (`pickedUp → delivered`).

### 5. Pelacakan Dampak Lingkungan & Laporan CSR/ESG (PDF)

- Menghitung estimasi kilogram pangan terselamatkan, pengurangan emisi CO₂e, total porsi, dan progres lencana dampak.
- Mitra dapat mengekspor ringkasan **Laporan CSR & ESG** dalam format **PDF** secara langsung dari tab **Dampak & Profil**.

---

## Arsitektur & Struktur Proyek

Aplikasi dibangun dengan pendekatan **Feature-First Clean Architecture**, prinsip **SSOT (Single Source of Truth)**, **SRP**, dan **DRY**:

```text
lib/
├── app/
│   ├── router/          # GoRouter dengan auth redirect & RBAC route guards
│   └── shell/           # AppShell adaptif (NavigationBar mobile / NavigationRail desktop, badge aktif, tab re-tap reset)
├── core/
│   ├── auth/            # Google OAuth v7 (Single Session Token), JwtClaims, SecureTokenStorage, DummyAuthRepository (debug-only)
│   ├── cache/           # LocalCacheService (Hive CE + TTL & user-scoped CacheKeys)
│   ├── config/          # ApiConfig (SSOT isDemoMode & validasi HTTPS), AppMapConfig, LoggerConfig
│   ├── network/         # Dio clients, AuthInterceptor (Bearer + 401 expiry), SanitizedLogInterceptor, ApiEndpoints
│   ├── permission/      # AppRole, Permission, PermissionPolicy, PermissionGate
│   ├── shared/          # Reusable Material 3 widgets (AppBottomSheetScaffold, AppSurfaceCard, AppStatusChip, dll.)
│   ├── theme/           # Material 3 theming & design tokens (light/dark/system)
│   └── time/            # Clock provider & shared 1-second countdown ticker
└── features/
    ├── auth/            # LoginScreen (Google Sign-In + pemilih role debug-only) & UnauthorizedScreen
    ├── distribution/    # Tugas distribusi relawan, alokasi porsi mitra, peta rute & verifikasi PIN pickup/delivery
    ├── impact/          # Dashboard dampak lingkungan, kalkulator CO2e & generator laporan CSR PDF
    ├── kyc/             # Pengajuan KYC, upload dokumen multipart, review admin & kuota donasi harian
    ├── listing/         # Feed Beranda, Unggah Stok, ListingCard, filter Halal/Alergen & ListingAccessPolicy
    ├── location/        # Peta Sekitar 1–3 km, GPS 3-tier, PinnedLocation (toko & panti tetap) & notifikasi radius
    └── reservation/     # Pemilih porsi (BookListingSheet), reservasi diskon/donasi, validasi PIN & bukti serah terima
```

---

## Menjalankan & Membangun Aplikasi

### Prasyarat

- Flutter SDK yang mendukung **Dart `^3.14.0`**
- Android Studio / Xcode / Chrome (sesuai target perangkat)

### 1. Instalasi Dependensi

```bash
flutter pub get
```

### 2. Menjalankan Mode Demo Lokal (Pengembangan)

Tanpa `API_BASE_URL`, aplikasi otomatis berjalan dalam **Mode Demo Lokal** (hanya di `debug` mode) dengan 5 akun Google demo yang dapat dipilih langsung di layar Login (`Konsumen`, `Penerima Donasi`, `Mitra Donatur`, `Relawan`, `Admin`):

```bash
flutter run
```

### 3. Menjalankan / Build Mode Produksi (Terhubung Backend)

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.surplusshare.id/api/v1 \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=<web_oauth_client_id>.apps.googleusercontent.com
```

*(Untuk target iOS/Web, tambahkan `--dart-define=GOOGLE_CLIENT_ID=<platform_oauth_client_id>.apps.googleusercontent.com`. Sebelum rilis ke Play Store, perbarui `applicationId` dan `signingConfigs.release` pada `android/app/build.gradle.kts`.)*

### 4. Analisis Statis & Pengujian Otomatis

```bash
dart format lib test
flutter analyze --no-pub
flutter test --no-pub
```

---

## Dokumentasi API Server & Kontrak Endpoint

Seluruh kontrak endpoint REST API (skema JSON, JWT claims, matriks RBAC, upload multipart KYC, lokasi tetap, distribusi relawan, reservasi, dan kode error) terdokumentasi secara sinkron 1:1 di:

- [`docs/API_CONTRACT.md`](docs/API_CONTRACT.md)
