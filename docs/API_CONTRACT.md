# Surplus Share — Backend REST API Contract (v1)

Dokumen ini menjadi **Single Source of Truth (SSOT)** antara aplikasi Flutter (`lib/core/network/api_endpoints.dart` & `Remote*Repository`) dan server Backend.

---

## 1. Konvensi Global

- **Base URL**: Dikonfigurasi saat build melalui `--dart-define=API_BASE_URL=https://api.surplusshare.id/api/v1` (wajib terisi pada build `--profile` & `--release`, dan wajib **HTTPS** pada `--release`).
- **Headers Wajib**:
  ```http
  Accept: application/json
  Content-Type: application/json
  Authorization: Bearer <access_token>   # untuk semua endpoint terproteksi
  ```
- **Format Waktu**: Semua timestamp wajib **ISO-8601 UTC** (contoh: `2026-11-28T11:30:00Z`).
- **Format Mata Uang**: Rupiah (IDR) dalam integer tanpa desimal (`25000` = Rp 25.000).
- **Format Response Sukses (Envelope)**:
  ```json
  { "data": { ... } }
  ```
  atau untuk daftar:
  ```json
  { "data": [ { ... }, { ... } ] }
  ```
- **Format Error Standar**:
  ```json
  {
    "code": "INSUFFICIENT_STOCK",
    "message": "Stok makanan tidak mencukupi."
  }
  ```
  - `401 Unauthorized`: Access token kedaluwarsa/tidak valid → aplikasi otomatis memanggil `POST /auth/refresh` lalu mengulang request 1x.
  - `403 Forbidden`: Role / KYC / permission tidak mencukupi.
  - `404 Not Found`: Resource tidak ditemukan.
  - `409 Conflict`: Konflik stok / pengajuan KYC duplikat.
  - `422 Unprocessable Entity`: Gagal validasi bisnis.
  - `423 Locked`: PIN serah terima terkunci setelah 5x percobaan salah.

---

## 2. JWT Claims & Matriks RBAC

Access Token JWT yang diterbitkan oleh `/auth/google` dan `/auth/refresh` **wajib** memuat payload berikut:

```json
{
  "sub": "usr-partner-1",
  "email": "partner@surplusshare.id",
  "name": "Resto Nusantara",
  "picture": "https://lh3.googleusercontent.com/...",
  "role": "donorPartner",
  "kyc_status": "approved",
  "granted_permissions": [],
  "revoked_permissions": [],
  "exp": 1795865400
}
```

### Enum `role` & `kyc_status`
- `role`: `consumer` | `verifiedRecipient` | `donorPartner` | `partnerStaff` | `admin`
- `kyc_status`: `unverified` | `pending` | `approved` | `rejected`

### Matriks Permission Default per Role

> **Catatan KYC Gate**: Role `verifiedRecipient`, `donorPartner`, dan `partnerStaff` hanya memperoleh permission di bawah saat `kyc_status == "approved"`. Jika belum `approved`, permission turun ke default `consumer` (`browseDiscountListings`).

| Permission | `consumer` | `verifiedRecipient` (KYC `approved`) | `donorPartner` (KYC `approved`) | `partnerStaff` (KYC `approved`) | `admin` |
|---|:---:|:---:|:---:|:---:|:---:|
| `browseDiscountListings` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `browseDonationListings` | ❌ | ✅ | ❌ | ❌ | ✅ |
| `claimDonationListings` | ❌ | ✅ | ❌ | ❌ | ✅ |
| `createListing` | ❌ | ❌ | ✅ | ✅ | ✅ |
| `manageListing` | ❌ | ❌ | ✅ | ✅ | ✅ |
| `validatePickupPin` | ❌ | ❌ | ✅ | ✅ | ✅ |
| `exportCsrReport` | ❌ | ❌ | ✅ | ✅ | ✅ |
| `reviewKyc` | ❌ | ❌ | ❌ | ❌ | ✅ |

---

## 3. Auth Endpoints (Google OAuth + JWT)

### 3.1 `POST /auth/google` *(Public)*
Menukar Google ID Token (dari `google_sign_in`) menjadi pasangan JWT aplikasi. Jika email belum terdaftar, backend otomatis membuat akun baru dengan role `consumer` & `kyc_status: unverified`.

- **Request**:
  ```json
  {
    "id_token": "<google_id_token>",
    "email": "budi@gmail.com",
    "name": "Budi Santoso",
    "picture": "https://lh3.googleusercontent.com/..."
  }
  ```
- **Response `200 OK`**:
  ```json
  {
    "data": {
      "access_token": "<jwt>",
      "refresh_token": "<opaque_or_jwt_refresh>"
    }
  }
  ```

### 3.2 `POST /auth/refresh` *(Public)*
Memperbarui access token yang mendekati/melewati `exp`.
- **Request**: `{ "refresh_token": "<refresh_token>" }`
- **Response `200 OK`**: `{ "data": { "access_token": "...", "refresh_token": "..." } }`
- **Error `401`**: Refresh token kedaluwarsa / dicabut (aplikasi otomatis logout).

### 3.3 `POST /auth/logout` *(Public / Best-effort)*
Mencabut refresh token aktif di server.
- **Request**: `{ "refresh_token": "<refresh_token>" }`
- **Response `204 No Content`** atau `200 OK`.

---

## 4. Dual-Channel Surplus Listings Endpoints

### Schema Objek `SurplusListing`
```json
{
  "id": "lst-flash-1",
  "partner_id": "usr-partner-1",
  "partner_name": "Resto Nusantara",
  "title": "Paket Nasi Campur Nusantara",
  "description": "Porsi siap saji berkualitas, dikemas higienis.",
  "channel": "discount",
  "discount_format": "flashSale",
  "original_price": 50000,
  "discounted_price": 22500,
  "total_quantity": 10,
  "remaining_quantity": 8,
  "pickup_window": {
    "start": "2026-11-28T11:00:00Z",
    "end": "2026-11-28T13:00:00Z"
  },
  "status": "active",
  "created_at": "2026-11-28T10:30:00Z",
  "converted_to_donation_at": null,
  "address": "Jl. M.H. Thamrin No. 12, Jakarta Pusat",
  "location": { "latitude": -6.2088, "longitude": 106.8456 },
  "food_safety": {
    "halal_status": "halalCertified",
    "category": "readyToEat",
    "allergens": ["peanuts"],
    "safe_until": "2026-11-28T17:00:00Z",
    "hygiene_confirmed": true,
    "storage_note": "Simpan di suhu sejuk"
  }
}
```
- `channel`: `discount` | `donation`
- `discount_format`: `flashSale` | `surpriseBag` | `null` (wajib `null` saat `donation`)
- `status`: `active` | `soldOut` | `expired` | `closed`
- `food_safety.halal_status`: `halalCertified` | `halalFriendly` | `nonHalal`
- `food_safety.category`: `readyToEat` | `bakery` | `rawIngredients` | `beverages`
- `food_safety.allergens[]`: `peanuts` | `dairy` | `seafood` | `eggs` | `gluten` | `soy`

### 4.1 `GET /listings` *(Auth: `browseDiscountListings`)*
- **Query Opsional**: `?channel=discount|donation`
- **Aturan Server**: Pengguna tanpa `browseDonationListings` **dilarang** menerima item `channel: "donation"`.
- **Response `200 OK`**: `{ "data": [ SurplusListing ] }`

### 4.2 `POST /listings` *(Auth: `createListing`)*
- **Request**:
  ```json
  {
    "partner_id": "usr-partner-1",
    "partner_name": "Resto Nusantara",
    "title": "Paket Nasi Campur Sore",
    "description": "Segar dan higienis",
    "channel": "discount",
    "discount_format": "flashSale",
    "original_price": 50000,
    "discounted_price": 25000,
    "quantity": 5,
    "pickup_start": "2026-11-28T11:15:00Z",
    "pickup_end": "2026-11-28T13:15:00Z",
    "address": "Jl. M.H. Thamrin No. 12, Jakarta Pusat",
    "location": { "latitude": -6.2088, "longitude": 106.8456 },
    "food_safety": {
      "halal_status": "halalCertified",
      "category": "readyToEat",
      "allergens": ["peanuts"],
      "safe_until": "2026-11-28T17:15:00Z",
      "hygiene_confirmed": true
    }
  }
  ```
- **Validasi Server**: Durasi pickup 15 menit – 24 jam, diskon 10%–90% untuk `discount`, `discounted_price == 0` untuk `donation`, `safe_until` maksimal +72 jam setelah `pickup_end`, `hygiene_confirmed == true`.
- **Response `201 Created`**: `{ "data": SurplusListing }`

### 4.3 `POST /listings/{id}/convert-donation` *(Auth: `manageListing`, owner/admin)*
Mengalihkan listing `discount` aktif menjadi `donation` (`discounted_price: 0`, `discount_format: null`).
- **Response `200 OK`**: `{ "data": SurplusListing }`

### 4.4 `POST /listings/{id}/claim` *(Auth: sesuai channel)*
- **Request**: `{ "quantity": 1 }`
- **Response `200 OK`**: `{ "data": SurplusListing }`
- **Error `409`**: `{ "code": "INSUFFICIENT_STOCK", "message": "..." }` | **`422`**: `{ "code": "LISTING_EXPIRED", "message": "..." }`

### 4.5 `POST /listings/{id}/release` *(Auth: internal/owner)*
- **Request**: `{ "quantity": 1 }`
- **Response `200 OK`**: `{ "data": SurplusListing }`

### 4.6 `POST /listings/{id}/close` *(Auth: `manageListing`, owner/admin)*
- **Response `200 OK`**: `{ "data": SurplusListing }`

---

## 5. Verifikasi Penerima Donasi (KYC) & Kuota Harian

### Schema `KycApplication` & `DailyDonationQuota`
```json
{
  "id": "kyc-001",
  "user_id": "usr-recipient-1",
  "organization_name": "Panti Asuhan Harapan",
  "category": "orphanage",
  "registration_number": "SK-KEMENSOS-123",
  "address": "Jl. Merdeka No. 10, Jakarta Pusat",
  "contact_phone": "081234567890",
  "beneficiary_count": 35,
  "documents": [
    {
      "type": "legalCertificate",
      "file_name": "akta_yayasan.pdf",
      "file_path": "/uploads/akta_yayasan.pdf",
      "mime_type": "application/pdf",
      "file_size_bytes": 420000
    }
  ],
  "status": "approved",
  "approved_daily_quota": 35,
  "rejection_reason": null,
  "submitted_at": "2026-11-20T08:00:00Z",
  "reviewed_at": "2026-11-21T09:00:00Z",
  "reviewed_by": "usr-admin-1"
}
```
```json
{
  "user_id": "usr-recipient-1",
  "date_key": "2026-11-28",
  "daily_limit": 35,
  "used_today": 5
}
```
- `category`: `orphanage` | `socialFoundation` | `distributionVolunteer`
- `documents[].type`: `legalCertificate` | `officialRecommendationLetter` | `representativeIdCard` | `operationalPhoto`

### 5.1 Upload Dokumen KYC (`POST /kyc/documents`) *(Authenticated, `multipart/form-data`)*
Mengunggah file dokumen legalitas, surat rekomendasi, atau KTP penanggung jawab sebelum mengirim `POST /kyc/applications`.

- **Content-Type**: `multipart/form-data`
- **Form Fields**:
  - `type` *(string, wajib)*: `legalCertificate` | `officialRecommendationLetter` | `representativeIdCard` | `operationalPhoto`
  - `file` *(binary, wajib)*: Maksimal **5 MB** (`5242880` bytes). MIME yang diizinkan: `application/pdf`, `image/jpeg`, `image/png`, `image/webp`.
- **Response `201 Created`**:
  ```json
  {
    "data": {
      "type": "representativeIdCard",
      "file_name": "ktp_penanggung_jawab.jpg",
      "file_path": "https://cdn.surplusshare.id/kyc/usr-1/ktp_penanggung_jawab.jpg",
      "mime_type": "image/jpeg",
      "file_size_bytes": 240120
    }
  }
  ```
- **Error `413 Payload Too Large` / `422 Unprocessable Entity`**: Ukuran > 5 MB atau format MIME tidak diizinkan.

### 5.2 Endpoints Pengajuan & Kuota KYC
| Method & Path | Auth / Permission | Request Body | Response `200`/`201` |
|---|---|---|---|
| `POST /kyc/documents` | Authenticated | `multipart/form-data` (`type`, `file`) | `{ "data": KycDocument }` |
| `GET /kyc/me` | Authenticated | — | `{ "data": KycApplication \| null }` (atau `404`) |
| `POST /kyc/applications` | Authenticated | `organization_name`, `category`, `registration_number?`, `address`, `contact_phone`, `beneficiary_count`, `documents[]` | `{ "data": KycApplication }` (`409` `KYC_ALREADY_SUBMITTED`) |
| `GET /kyc/applications/pending` | `reviewKyc` | — | `{ "data": [ KycApplication ] }` |
| `POST /kyc/applications/{id}/approve` | `reviewKyc` | `{ "daily_quota": 35 }` | `{ "data": KycApplication }` |
| `POST /kyc/applications/{id}/reject` | `reviewKyc` | `{ "reason": "Dokumen buram" }` | `{ "data": KycApplication }` |
| `GET /kyc/quota/me` | Authenticated (KYC `approved`) | — | `{ "data": DailyDonationQuota }` |
| `POST /kyc/quota/consume` | `claimDonationListings` | `{ "quantity": 2 }` | `{ "data": DailyDonationQuota }` |
| `POST /kyc/quota/refund` | `claimDonationListings` | `{ "quantity": 2 }` | `{ "data": DailyDonationQuota }` |

---

## 6. Reservasi, Payment Gateway WebView & Validasi PIN 6-Digit

### Schema `Reservation`
```json
{
  "id": "res-001",
  "listing_id": "lst-flash-1",
  "listing_title": "Paket Nasi Campur Nusantara",
  "partner_id": "usr-partner-1",
  "customer_id": "usr-consumer-1",
  "channel": "discount",
  "quantity": 2,
  "total_amount": 45000,
  "pickup_window": {
    "start": "2026-11-28T11:00:00Z",
    "end": "2026-11-28T13:00:00Z"
  },
  "status": "confirmed",
  "created_at": "2026-11-28T10:45:00Z",
  "payment_session": {
    "session_id": "pay-xyz",
    "checkout_url": "https://pay.surplusshare.id/checkout/pay-xyz",
    "method": "qris",
    "amount": 45000,
    "expires_at": "2026-11-28T11:00:00Z"
  },
  "pickup_pin": "482910",
  "failed_pin_attempts": 0,
  "receipt": null
}
```
- `status`: `pendingPayment` | `confirmed` | `completed` | `cancelled` | `expired`
- `payment_session.method`: `qris` | `eWallet`
- `receipt` (terisi saat `status == "completed"`):
  ```json
  {
    "receipt_id": "rcpt-001",
    "reservation_id": "res-001",
    "listing_id": "lst-flash-1",
    "listing_title": "Paket Nasi Campur Nusantara",
    "partner_id": "usr-partner-1",
    "customer_id": "usr-consumer-1",
    "verified_by_staff_id": "usr-staff-1",
    "channel": "discount",
    "quantity": 2,
    "total_amount": 45000,
    "handed_over_at": "2026-11-28T11:20:00Z"
  }
  ```

### Endpoints Reservasi
| Method & Path | Auth / Permission | Request Body | Response & Aturan Bisnis |
|---|---|---|---|
| `GET /reservations/me` | Authenticated | — | `{ "data": [ Reservation ] }` (milik `customer_id == sub`) |
| `GET /reservations/partner` | `validatePickupPin` | — | `{ "data": [ Reservation ] }` (pesanan masuk gerai mitra) |
| `POST /reservations/discount` | `browseDiscountListings` | `{ "listing_id": "...", "quantity": 1, "payment_method": "qris" }` | `201`: `{ "data": Reservation }` (`status: pendingPayment`, batas bayar 15 menit & tidak melewati `pickup_end`, stok langsung dikunci). |
| `POST /reservations/donation` | `claimDonationListings` | `{ "listing_id": "...", "quantity": 1 }` | `201`: `{ "data": Reservation }` (`status: confirmed`, langsung menerbitkan `pickup_pin` 6 digit & mengurangi kuota harian). |
| `POST /reservations/{id}/confirm-payment` | Authenticated / Webhook | — | `200`: `{ "data": Reservation }` (`status: confirmed` + menerbitkan `pickup_pin` 6 digit). Error `422` `PAYMENT_EXPIRED` atau `RESERVATION_EXPIRED` (stok dilepas). |
| `POST /reservations/{id}/cancel` | Owner / Partner / Admin | — | `200`: `{ "data": Reservation }` (`status: cancelled`, melepas stok & refund kuota donasi). |
| `POST /reservations/{id}/validate-pin` | `validatePickupPin` | `{ "pin": "482910" }` | `200`: `{ "data": Reservation }` (`status: completed` + menerbitkan `receipt`). Salah PIN: `422` `{ "code": "INVALID_PIN", "remaining_attempts": 4, "message": "..." }`. Salah 5x: `423` `{ "code": "PIN_LOCKED", "message": "..." }`. |

---

## 7. Push Notification Payload (Geolocation Radius 1–3 km & Mitra Favorit)

Saat mitra mempublikasikan listing baru (`POST /listings`), backend disarankan mengirim push notification FCM/APNs hanya ke pengguna yang:
1. Memiliki izin akses channel listing (`donation` hanya untuk `verifiedRecipient` / `approved`),
2. Memenuhi filter Halal & Alergen pengguna, dan
3. Berada dalam radius 1–3 km ATAU memfavoritkan `partner_id`.

```json
{
  "listing_id": "lst-flash-1",
  "partner_id": "usr-partner-1",
  "partner_name": "Resto Nusantara",
  "channel": "discount",
  "reason": "withinRadius",
  "distance_km": 1.2,
  "title": "Stok Surplus Baru di Resto Nusantara",
  "body": "Paket Nasi Campur Nusantara tersedia 1.2 km dari Anda."
}
```
- `reason`: `withinRadius` | `favoritePartner` | `both`

---

## 8. Konfigurasi Build Produksi

Mode Demo (`DummyAuthRepository`, `InMemory*Repository`, `DemoKycDocumentService`, dan pemilih role debug di `LoginScreen`) **otomatis nonaktif dan ter-tree-shake** pada build `--release` (dan `--profile` juga memvalidasi `API_BASE_URL` via `!kDebugMode`).

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.surplusshare.id/api/v1 \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=<web_oauth_client_id>.apps.googleusercontent.com
  # Opsional (untuk target Web / iOS):
  # --dart-define=GOOGLE_CLIENT_ID=<platform_oauth_client_id>.apps.googleusercontent.com
```
