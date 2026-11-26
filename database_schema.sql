-- ============================================================================
-- StoichioMaster - Skema Database PostgreSQL & Kebijakan RLS (Supabase)
-- Jalankan seluruh skrip ini di menu SQL Editor pada Dashboard Supabase.
-- ============================================================================

-- 1. Schema internal untuk fungsi trigger (tidak diekspos ke Data API)
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- 2. Tabel Profil Pengguna
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default 'Pelajar Kimia',
  education_level text not null default 'sma'
    check (education_level in ('sma', 'mahasiswa')),
  is_anonymous boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 3. Tabel Modul Materi & Rangkuman Stoikiometri
create table if not exists public.learning_modules (
  id bigint generated always as identity primary key,
  slug text not null unique,
  title text not null,
  subtitle text not null,
  summary text not null,
  formulas_json jsonb not null default '[]'::jsonb,
  content_blocks jsonb not null default '[]'::jsonb,
  order_index integer not null default 1,
  updated_at timestamptz not null default now()
);

-- 4. Tabel Bank Soal Kuis & Pembahasan Langkah demi Langkah
create table if not exists public.quiz_questions (
  id bigint generated always as identity primary key,
  module_id bigint references public.learning_modules (id) on delete set null,
  question_text text not null,
  options jsonb not null,
  correct_index integer not null check (correct_index >= 0 and correct_index <= 3),
  explanation_steps jsonb not null default '[]'::jsonb,
  difficulty text not null default 'dasar'
    check (difficulty in ('dasar', 'menengah', 'lanjut')),
  created_at timestamptz not null default now()
);

-- 5. Tabel Progres & Bookmark Materi Pengguna
create table if not exists public.learning_progress (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  module_id bigint not null references public.learning_modules (id) on delete cascade,
  is_completed boolean not null default false,
  is_bookmarked boolean not null default false,
  last_accessed_at timestamptz not null default now(),
  unique (user_id, module_id)
);

-- 6. Tabel Riwayat Perhitungan Kalkulator Stoikiometri
create table if not exists public.calculation_history (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  calc_type text not null
    check (calc_type in ('mol_massa', 'gas_stp', 'molaritas', 'pereaksi_pembatas')),
  title text not null,
  input_summary jsonb not null default '{}'::jsonb,
  result_summary jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- 7. Tabel Riwayat Skor Kuis Pengguna
create table if not exists public.quiz_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  module_id bigint references public.learning_modules (id) on delete set null,
  score integer not null check (score >= 0),
  total_questions integer not null check (total_questions > 0),
  percentage numeric(5, 2) not null check (percentage >= 0 and percentage <= 100),
  answers_detail jsonb not null default '[]'::jsonb,
  completed_at timestamptz not null default now()
);

-- 8. Indeks untuk Performa Query & Foreign Key
create index if not exists quiz_questions_module_id_idx
  on public.quiz_questions (module_id);

create index if not exists learning_progress_user_id_idx
  on public.learning_progress (user_id);

create index if not exists learning_progress_module_id_idx
  on public.learning_progress (module_id);

create index if not exists calculation_history_user_id_created_idx
  on public.calculation_history (user_id, created_at desc);

create index if not exists quiz_attempts_user_id_completed_idx
  on public.quiz_attempts (user_id, completed_at desc);

create index if not exists quiz_attempts_module_id_idx
  on public.quiz_attempts (module_id);

-- 9. Fungsi & Trigger Otomatis Profil & Proteksi Kolom Sensitif
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, is_anonymous)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), 'Pelajar Kimia'),
    coalesce(new.is_anonymous, false)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create or replace function private.sync_user_anonymous_flag()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles
  set
    is_anonymous = coalesce(new.is_anonymous, false),
    updated_at = now()
  where id = new.id;
  return new;
end;
$$;

create or replace function private.protect_profile_system_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Pastikan pengguna tidak bisa memalsukan status is_anonymous lewat API klien
  new.is_anonymous := old.is_anonymous;
  new.updated_at := now();
  return new;
end;
$$;

revoke execute on function private.handle_new_user() from public, anon, authenticated;
revoke execute on function private.sync_user_anonymous_flag() from public, anon, authenticated;
revoke execute on function private.protect_profile_system_fields() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

drop trigger if exists on_auth_user_updated on auth.users;
create trigger on_auth_user_updated
  after update of is_anonymous on auth.users
  for each row execute function private.sync_user_anonymous_flag();

drop trigger if exists before_profile_update on public.profiles;
create trigger before_profile_update
  before update on public.profiles
  for each row execute function private.protect_profile_system_fields();

-- 10. Aktifkan Row Level Security (RLS) pada Semua Tabel Publik
alter table public.profiles enable row level security;
alter table public.learning_modules enable row level security;
alter table public.quiz_questions enable row level security;
alter table public.learning_progress enable row level security;
alter table public.calculation_history enable row level security;
alter table public.quiz_attempts enable row level security;

-- 11. Hak Akses Schema & Tabel (Principle of Least Privilege)
grant usage on schema public to anon, authenticated;

grant select, update on public.profiles to authenticated;
grant select on public.learning_modules to anon, authenticated;
grant select on public.quiz_questions to authenticated;
grant select, insert, update, delete on public.learning_progress to authenticated;
grant select, insert, delete on public.calculation_history to authenticated;
grant select, insert, delete on public.quiz_attempts to authenticated;

-- 12. Kebijakan RLS (Row Level Security)
-- A. profiles: hanya pemilik yang dapat membaca & memperbarui profilnya
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
  on public.profiles
  for select
  to authenticated
  using ((select auth.uid()) = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles
  for update
  to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- B. learning_modules: dapat dibaca publik (termasuk mode offline sync awal)
drop policy if exists "learning_modules_select_public" on public.learning_modules;
create policy "learning_modules_select_public"
  on public.learning_modules
  for select
  to anon, authenticated
  using (true);

-- C. quiz_questions: dapat dibaca pengguna terautentikasi (termasuk anonymous auth)
drop policy if exists "quiz_questions_select_authenticated" on public.quiz_questions;
create policy "quiz_questions_select_authenticated"
  on public.quiz_questions
  for select
  to authenticated
  using (true);

-- D. learning_progress: isolasi ketat per user_id
drop policy if exists "learning_progress_select_own" on public.learning_progress;
create policy "learning_progress_select_own"
  on public.learning_progress
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "learning_progress_insert_own" on public.learning_progress;
create policy "learning_progress_insert_own"
  on public.learning_progress
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "learning_progress_update_own" on public.learning_progress;
create policy "learning_progress_update_own"
  on public.learning_progress
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "learning_progress_delete_own" on public.learning_progress;
create policy "learning_progress_delete_own"
  on public.learning_progress
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);

-- E. calculation_history: isolasi ketat per user_id
drop policy if exists "calculation_history_select_own" on public.calculation_history;
create policy "calculation_history_select_own"
  on public.calculation_history
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "calculation_history_insert_own" on public.calculation_history;
create policy "calculation_history_insert_own"
  on public.calculation_history
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "calculation_history_delete_own" on public.calculation_history;
create policy "calculation_history_delete_own"
  on public.calculation_history
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);

-- F. quiz_attempts: isolasi ketat per user_id
drop policy if exists "quiz_attempts_select_own" on public.quiz_attempts;
create policy "quiz_attempts_select_own"
  on public.quiz_attempts
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "quiz_attempts_insert_own" on public.quiz_attempts;
create policy "quiz_attempts_insert_own"
  on public.quiz_attempts
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "quiz_attempts_delete_own" on public.quiz_attempts;
create policy "quiz_attempts_delete_own"
  on public.quiz_attempts
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);

-- ============================================================================
-- 13. Seed Data Awal (4 Modul Materi + 12 Soal Kuis Stoikiometri)
-- ============================================================================

insert into public.learning_modules (
  slug,
  title,
  subtitle,
  summary,
  formulas_json,
  content_blocks,
  order_index
)
values
  (
    'konsep-mol',
    'Konsep Mol & Tetapan Avogadro',
    'Satuan dasar jumlah zat dalam stoikiometri kimia',
    'Mol adalah jembatan utama yang menghubungkan jumlah partikel, massa zat, volume gas pada STP, dan molaritas larutan.',
    '[
      {"label": "Mol dari Massa", "formula": "n = m / Mr"},
      {"label": "Jumlah Partikel", "formula": "N = n × 6,022 × 10^23"},
      {"label": "Volume Gas STP (0°C, 1 atm)", "formula": "V = n × 22,4 L"},
      {"label": "Molaritas Larutan", "formula": "M = n / V(liter)"}
    ]'::jsonb,
    '[
      {
        "heading": "Mengapa Memakai Mol?",
        "body": "Atom dan molekul sangat kecil sehingga tidak praktis dihitung satu per satu. Satu mol zat mengandung tepat 6,022 × 10^23 partikel (bilangan Avogadro, NA)."
      },
      {
        "heading": "Jembatan Mol",
        "body": "Untuk mengubah satuan dari massa ke volume gas atau jumlah partikel, selalu ubah terlebih dahulu ke satuan mol (n), lalu konversikan ke besaran tujuan."
      },
      {
        "heading": "Contoh Cepat",
        "body": "Berapa mol dalam 36 gram air (H2O, Mr = 18)?\nn = 36 / 18 = 2 mol. Jumlah molekulnya = 2 × 6,022 × 10^23 = 1,2044 × 10^24 molekul."
      }
    ]'::jsonb,
    1
  ),
  (
    'massa-molar',
    'Massa Atom Relatif (Ar) & Massa Molar (Mr)',
    'Menghitung massa 1 mol unsur, molekul, dan senyawa hidrat',
    'Massa molar (Mr) menyatakan massa 1 mol suatu zat dalam satuan g/mol dan dihitung dari penjumlahan Ar seluruh atom penyusun rumus kimianya.',
    '[
      {"label": "Massa Molekul Relatif", "formula": "Mr = Σ (jumlah atom × Ar unsur)"},
      {"label": "Hubungan Massa & Mol", "formula": "m = n × Mr"}
    ]'::jsonb,
    '[
      {
        "heading": "Aturan Menghitung Mr",
        "body": "Kalikan jumlah setiap atom pada rumus kimia dengan massa atom relatifnya (Ar). Jika terdapat tanda kurung seperti Ca(OH)2, indeks di luar kurung mengalikan seluruh atom di dalamnya."
      },
      {
        "heading": "Senyawa Hidrat",
        "body": "Pada senyawa kristal berair seperti CuSO4·5H2O, massa molar dihitung dari Mr CuSO4 ditambah 5 × Mr H2O."
      },
      {
        "heading": "Contoh: Mr Ca(OH)2",
        "body": "Ar Ca = 40,08; O = 16,00; H = 1,008.\nMr Ca(OH)2 = 40,08 + 2×(16,00 + 1,008) = 74,096 g/mol."
      }
    ]'::jsonb,
    2
  ),
  (
    'kadar-zat',
    'Kadar Zat & Komposisi Persen',
    'Menentukan persentase massa unsur serta rumus empiris',
    'Kadar zat menggambarkan proporsi massa komponen atau unsur di dalam campuran maupun senyawa murni.',
    '[
      {"label": "Persen Massa Unsur", "formula": "% Unsur = (n_atom × Ar / Mr senyawa) × 100%"},
      {"label": "Persen Massa Campuran", "formula": "% Zat = (m_zat / m_sampel) × 100%"},
      {"label": "Bagian per Sejuta (ppm)", "formula": "ppm = (m_zat / m_larutan) × 10^6"}
    ]'::jsonb,
    '[
      {
        "heading": "Komposisi Persen dalam Senyawa",
        "body": "Setiap senyawa murni memiliki perbandingan massa unsur penyusun yang tetap (Hukum Proust). Contoh: kadar N dalam urea CO(NH2)2 (Mr = 60) adalah (2×14 / 60) × 100% = 46,67%."
      },
      {
        "heading": "Dari Persen Massa ke Rumus Empiris",
        "body": "Anggap total sampel 100 gram sehingga % massa menjadi gram, bagi masing-masing massa unsur dengan Ar-nya untuk memperoleh perbandingan mol paling sederhana."
      }
    ]'::jsonb,
    3
  ),
  (
    'pereaksi-pembatas',
    'Pereaksi Pembatas & Persen Hasil',
    'Menentukan reaktan yang habis bereaksi dan sisa zat',
    'Dalam reaksi kimia nyata, reaktan sering tidak dicampur dalam rasio stoikiometri tepat. Pereaksi pembatas menentukan jumlah maksimum produk yang terbentuk.',
    '[
      {"label": "Rasio Uji Pembatas", "formula": "Rasio = mol_awal / koefisien_reaksi"},
      {"label": "Mol Produk Teoretis", "formula": "n_produk = (koef_produk / koef_pembatas) × n_pembatas"},
      {"label": "Persen Hasil (% Yield)", "formula": "% Hasil = (hasil_nyata / hasil_teoretis) × 100%"}
    ]'::jsonb,
    '[
      {
        "heading": "Langkah Menentukan Pereaksi Pembatas",
        "body": "1) Setarakan persamaan reaksi.\n2) Ubah semua reaktan ke satuan mol.\n3) Bagi mol awal masing-masing reaktan dengan koefisien reaksinya.\n4) Reaktan dengan hasil bagi terkecil adalah pereaksi pembatas (habis bereaksi)."
      },
      {
        "heading": "Menghitung Sisa Reaktan",
        "body": "Mol reaktan lain yang bereaksi = (koefisien reaktan lain / koefisien pembatas) × mol pereaksi pembatas. Sisa = mol awal − mol bereaksi."
      }
    ]'::jsonb,
    4
  )
on conflict (slug) do update set
  title = excluded.title,
  subtitle = excluded.subtitle,
  summary = excluded.summary,
  formulas_json = excluded.formulas_json,
  content_blocks = excluded.content_blocks,
  order_index = excluded.order_index,
  updated_at = now();

-- Reset seed soal hanya jika tabel masih kosong agar aman dijalankan ulang
insert into public.quiz_questions (
  module_id,
  question_text,
  options,
  correct_index,
  explanation_steps,
  difficulty
)
select
  m.id,
  q.question_text,
  q.options,
  q.correct_index,
  q.explanation_steps,
  q.difficulty
from (
  values
    (
      'konsep-mol',
      'Berapakah jumlah mol dari 11 gram gas CO2 (Ar C = 12, O = 16)?',
      '["0,25 mol", "0,50 mol", "1,00 mol", "2,00 mol"]'::jsonb,
      0,
      '[
        "Hitung massa molar CO2: Mr = 12 + (2 × 16) = 44 g/mol.",
        "Gunakan rumus mol: n = m / Mr = 11 g / 44 g/mol = 0,25 mol."
      ]'::jsonb,
      'dasar'
    ),
    (
      'konsep-mol',
      'Berapa volume 0,5 mol gas oksigen (O2) jika diukur pada keadaan standar STP (0°C, 1 atm)?',
      '["5,6 liter", "11,2 liter", "22,4 liter", "44,8 liter"]'::jsonb,
      1,
      '[
        "Pada keadaan STP, 1 mol gas ideal memiliki volume molar 22,4 liter.",
        "V = n × 22,4 L/mol = 0,5 × 22,4 = 11,2 liter."
      ]'::jsonb,
      'dasar'
    ),
    (
      'konsep-mol',
      'Sebanyak 4 gram NaOH (Mr = 40) dilarutkan hingga volume larutan menjadi 500 mL. Berapa molaritasnya?',
      '["0,1 M", "0,2 M", "0,4 M", "0,8 M"]'::jsonb,
      1,
      '[
        "Hitung mol NaOH: n = 4 / 40 = 0,1 mol.",
        "Konversi volume ke liter: V = 500 mL = 0,5 L.",
        "Molaritas M = n / V = 0,1 / 0,5 = 0,2 M."
      ]'::jsonb,
      'menengah'
    ),
    (
      'massa-molar',
      'Berapa massa molekul relatif (Mr) dari kalsium hidroksida Ca(OH)2 jika Ar Ca = 40, O = 16, H = 1?',
      '["57", "58", "74", "90"]'::jsonb,
      2,
      '[
        "Uraikan jumlah atom pada Ca(OH)2: 1 atom Ca, 2 atom O, dan 2 atom H.",
        "Mr = 40 + (2 × 16) + (2 × 1) = 40 + 32 + 2 = 74."
      ]'::jsonb,
      'dasar'
    ),
    (
      'massa-molar',
      'Berapa massa dari 0,2 mol asam sulfat H2SO4 (Ar H = 1, S = 32, O = 16)?',
      '["9,8 gram", "19,6 gram", "49,0 gram", "98,0 gram"]'::jsonb,
      1,
      '[
        "Hitung Mr H2SO4 = (2 × 1) + 32 + (4 × 16) = 98 g/mol.",
        "Hitung massa: m = n × Mr = 0,2 × 98 = 19,6 gram."
      ]'::jsonb,
      'dasar'
    ),
    (
      'massa-molar',
      'Berapakah Mr senyawa hidrat MgSO4·7H2O (Ar Mg = 24, S = 32, O = 16, H = 1)?',
      '["120", "138", "246", "264"]'::jsonb,
      2,
      '[
        "Mr MgSO4 = 24 + 32 + (4 × 16) = 120.",
        "Mr 7H2O = 7 × (2 × 1 + 16) = 7 × 18 = 126.",
        "Total Mr = 120 + 126 = 246."
      ]'::jsonb,
      'menengah'
    ),
    (
      'kadar-zat',
      'Berapa persentase massa nitrogen (N) dalam pupuk urea CO(NH2)2 (Ar C=12, O=16, N=14, H=1)?',
      '["23,33%", "40,00%", "46,67%", "53,33%"]'::jsonb,
      2,
      '[
        "Hitung Mr CO(NH2)2 = 12 + 16 + 2×(14 + 2×1) = 60.",
        "Massa N dalam 1 mol urea = 2 × 14 = 28.",
        "% N = (28 / 60) × 100% = 46,67%."
      ]'::jsonb,
      'menengah'
    ),
    (
      'kadar-zat',
      'Sebanyak 15 gram gula dilarutkan dalam 85 gram air. Berapakah kadar (% massa) gula dalam larutan?',
      '["15%", "17,65%", "20%", "85%"]'::jsonb,
      0,
      '[
        "Total massa larutan = massa gula + massa air = 15 + 85 = 100 gram.",
        "% massa = (15 / 100) × 100% = 15%."
      ]'::jsonb,
      'dasar'
    ),
    (
      'kadar-zat',
      'Suatu senyawa hidrokarbon mengandung 80% karbon dan 20% hidrogen (Ar C=12, H=1). Apa rumus empirisnya?',
      '["CH", "CH2", "CH3", "C2H5"]'::jsonb,
      2,
      '[
        "Misalkan 100 g sampel: m C = 80 g, m H = 20 g.",
        "Perbandingan mol C : H = (80/12) : (20/1) = 6,67 : 20.",
        "Bagi keduanya dengan 6,67 sehingga diperoleh rasio 1 : 3 → CH3."
      ]'::jsonb,
      'lanjut'
    ),
    (
      'pereaksi-pembatas',
      'Reaksi: 2 H2 + O2 -> 2 H2O. Jika 3 mol H2 direaksikan dengan 2 mol O2, zat apakah yang menjadi pereaksi pembatas?',
      '["H2", "O2", "H2O", "Keduanya habis bersamaan"]'::jsonb,
      0,
      '[
        "Hitung rasio mol awal / koefisien untuk tiap reaktan.",
        "Rasio H2 = 3 / 2 = 1,5; Rasio O2 = 2 / 1 = 2,0.",
        "Karena rasio H2 lebih kecil (1,5 < 2,0), H2 adalah pereaksi pembatas."
      ]'::jsonb,
      'dasar'
    ),
    (
      'pereaksi-pembatas',
      'Pada reaksi N2 + 3 H2 -> 2 NH3, dicampurkan 2 mol N2 dan 3 mol H2. Berapa mol NH3 maksimum yang terbentuk?',
      '["1 mol", "2 mol", "3 mol", "4 mol"]'::jsonb,
      1,
      '[
        "Cek pembatas: N2 = 2/1 = 2; H2 = 3/3 = 1 → H2 habis lebih dulu.",
        "Mol NH3 = (koef NH3 / koef H2) × mol H2 = (2 / 3) × 3 = 2 mol."
      ]'::jsonb,
      'menengah'
    ),
    (
      'pereaksi-pembatas',
      'Jika hasil teoretis reaksi adalah 25 gram dan hasil nyata di laboratorium 20 gram, berapakah persen hasilnya?',
      '["75%", "80%", "85%", "125%"]'::jsonb,
      1,
      '[
        "% Hasil = (hasil nyata / hasil teoretis) × 100%.",
        "% Hasil = (20 / 25) × 100% = 80%."
      ]'::jsonb,
      'dasar'
    )
) as q (slug, question_text, options, correct_index, explanation_steps, difficulty)
join public.learning_modules m on m.slug = q.slug
where not exists (select 1 from public.quiz_questions);
