# StoichioMaster

Aplikasi edukasi interaktif stoikiometri kimia untuk siswa SMA dan mahasiswa tingkat awal, dibangun dengan **Flutter (Material 3)** dan **Supabase**.

## Fitur Utama
1. **Materi & Rangkuman Interaktif**: Konsep Mol, Massa Molar ($M_r$), Kadar Zat, dan Pereaksi Pembatas (termasuk status selesai & bookmark).
2. **Kalkulator Stoikiometri**: Parser rumus kimia otomatis (mendukung tanda kurung & hidrat seperti `Ca(OH)2` atau `CuSO4.5H2O`), konversi Mol ↔ Massa, Volume Gas STP, Molaritas Larutan, dan Pereaksi Pembatas.
3. **Kuis & Latihan Soal**: Soal pilihan ganda per topik dengan pembahasan langkah demi langkah.
4. **Riwayat Belajar & Skor Kuis**: Sinkronisasi otomatis ke Supabase dengan proteksi **Row Level Security (RLS)**.

---

## 1. Setup Database Supabase

1. Buat proyek baru di [Supabase](https://supabase.com/dashboard).
2. Buka menu **Authentication → Providers → Anonymous Sign-Ins**, lalu aktifkan **Allow anonymous sign-ins** agar pelajar dapat langsung memakai aplikasi tanpa login wajib (dengan opsi tautkan email di layar Profil).
3. Buka menu **SQL Editor → New Query**, salin seluruh isi file `database_schema.sql`, lalu klik **Run**.
4. Salin **Project URL** dan **Anon / Publishable Key** dari menu **Project Settings → API**.

---

## 2. Menjalankan Aplikasi Secara Lokal (`--dart-define`)

```bash
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://PROJECT-REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_KEY
```

Atau salin `env.example.json` menjadi `env.json` (jangan di-commit), lalu jalankan:

```bash
flutter run --dart-define-from-file=env.json
```

---

## 3. Build APK Otomatis via GitHub Actions

1. Buka repositori GitHub Anda → **Settings → Secrets and variables → Actions**.
2. Tambahkan dua *Repository Secrets*:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
3. Setiap kali ada `push` ke branch `main` (atau dijalankan manual lewat tab **Actions → Build Android APK → Run workflow**), file `app-release.apk` akan tersedia di bagian **Artifacts**.
