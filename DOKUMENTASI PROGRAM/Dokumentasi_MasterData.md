# Dokumentasi Program — Halaman **Master Data** (Star Schema PMB) - master_data.ascx

## 1) Ringkasan Modul
Halaman **Master Data** berfungsi sebagai **panel kontrol data** untuk:
1) Menjalankan **ETL reset & load** ke database `star_schema_pmb` (dimensi + fact)  
2) Menjalankan **Proses Clustering (K-Means)** melalui Stored Procedure (fixed periode 2017–2023)  
3) Menjalankan **Proses Regresi Linier** melalui Stored Procedure (periode mengikuti dropdown)  
4) Menampilkan **ringkasan jumlah baris** tiap tabel utama star schema dalam GridView

> Catatan: modul ini melakukan operasi destruktif (TRUNCATE + DROP FK). Idealnya hanya bisa diakses oleh admin/pengembang.

---

## 2) Teknologi & Dependensi
- **ASP.NET WebForms** (inline VB: `<script runat="server">`)
- **OleDb** (`System.Data.OleDb`) untuk koneksi SQL Server (Provider `SQLOLEDB`)
- `Regex` untuk memecah batch SQL berdasarkan baris `GO`
- Komponen UI: `DropDownList`, `Button`, `GridView`, `Literal`, `ScriptManager` (alert)

---

## 3) Konfigurasi Koneksi Database
Koneksi tunggal ke data mart:

- `ConnStar` → `star_schema_pmb`

**Catatan keamanan penting:**
- Username/password DB **jangan hardcode** di file jika akan dibagikan (GitHub / repo publik).
- Pindahkan ke `web.config` + gunakan akun DB dengan hak minimum (idealnya tidak pakai `sa`).

---

## 4) Konstanta, State, dan Batasan Data
- `YEAR_AVAILABLE_MAX = 2023` → sistem memberi peringatan bahwa data saat ini tersedia sampai 2023.
- Default filter:
  - `TahunAwal = 2017`
  - `TahunAkhir = 2023`
- **Clustering**: selalu fixed 2017–2023 (tidak mengikuti dropdown).
- **ETL**: script ETL yang dibangun juga memuat dimensi waktu 2017–2023 dan load fact pada `tahun_lulus BETWEEN 2017 AND 2023`.

---

## 5) Daftar Tabel yang Ditampilkan di Grid (Whitelist)
Variabel `TableList` membatasi tabel yang dihitung row-nya agar aman dari injection:

- `dim_gender`
- `dim_jurusan_sekolah`
- `dim_prodi`
- `dim_waktu`
- `dim_wilayah`
- `dim_sekolah`
- `fact_pmb`

Grid menampilkan kolom: **No | Nama Tabel | Jumlah Row**.

---

## 6) Komponen UI dan Perannya

### 6.1 Banner Peringatan
Menjelaskan bahwa:
- Proses perbarui data akan **reset** data
- Clustering & regresi memproses **2017–2023**
- Menampilkan “Tahun tersedia saat ini: 2023”

### 6.2 Filter Tahun
- `ddlYearFrom` dan `ddlYearTo` (AutoPostBack → `OnYearChanged`)
- Digunakan untuk:
  - Regresi linier (mengambil nilai dropdown saat tombol diklik)
  - Informasi pilihan user (bukan untuk Grid count)

### 6.3 Tombol Aksi
- `btnPerbarui` → `btnPerbarui_Click` (ETL reset & load)
- `btnProcCluster` → `btnClustering_Click` (jalankan SP clustering)
- `btnProcReg` → `btnRegresi_Click` (jalankan SP regresi)

### 6.4 Status & Last Updated
- `litLastUpdated` menampilkan waktu terakhir proses (ETL berhasil).
- “Status: Idle” masih statis (belum ada state running/progress).

---

## 7) Alur Eksekusi Halaman

### 7.1 `Page_Load`
Saat pertama kali halaman dibuka (`Not IsPostBack`):
1. `PopulateYearFilters()`
2. `BindGridTableCounts()` → menghitung row count tiap tabel
3. Set `LastRefreshed = DateTime.Now`
4. Isi `litLastUpdated` dan `litYearMax`

### 7.2 `OnYearChanged`
Saat dropdown berubah:
- Menyimpan `TahunAwal` dan `TahunAkhir` dari dropdown.
- Tidak melakukan refresh grid (karena ringkasan tabel tidak tergantung tahun).

---

## 8) Detail Fungsi dan Event Penting

## 8.1 Perbarui Data (ETL)
### `btnPerbarui_Click`
**Tujuan:** Menjalankan ETL reset & load.

Langkah:
1. `BuildEtlSql()` menyusun SQL panjang (dengan `GO`).
2. `RunSqlByBatches(sql)` mengeksekusi SQL per batch di dalam **transaction**.
3. Jika sukses:
   - `BindGridTableCounts()` refresh ringkasan tabel
   - `litLastUpdated` diupdate
   - Alert sukses
4. Jika gagal:
   - rollback transaction
   - alert error (escape `'`)

### `RunSqlByBatches(fullSql)`
- Memanggil `SplitBatches()` untuk memecah SQL berdasarkan baris `GO`
- Menjalankan setiap batch dengan:
  - `CommandTimeout = 0` (tanpa batas)
  - transaction `BeginTransaction()` →
