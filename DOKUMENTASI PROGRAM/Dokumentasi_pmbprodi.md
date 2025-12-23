# Dokumentasi Program — Dashboard Mahasiswa Baru Prodi - pmb_prodi.ascx

## 1) Ringkasan Modul
Halaman **Dashboard Mahasiswa Baru Prodi** menampilkan ringkasan dan visualisasi data PMB berdasarkan **Program Studi (Prodi)**. Data realisasi diambil dari **data mart `star_schema_pmb`** dan target diambil dari **database operasional `Pmbregol`** (tabel KPI).

Filter yang tersedia:
- **Tahun Dari – Tahun Sampai** (rentang tahun analisis)
- **Program Studi** (Semua Prodi / prodi tertentu)

Output yang ditampilkan:
1) **Kartu KPI**: Realisasi Pendaftaran dan Target KPI MABA pada rentang tahun terpilih
2) **Gauge**: Capaian Realisasi terhadap Target (persentase dan sisa)
3) **Bar Chart**: Target vs Realisasi per Tahun
4) **Pie Chart**: Komposisi Gender
5) **Bar Chart**: Top 10 Sekolah Asal
6) **Bar Chart**: Top 10 Provinsi Asal

---

## 2) Teknologi & Dependensi
- **ASP.NET WebForms** (inline VB di `<script runat="server">`)
- **OLE DB** (`System.Data.OleDb`) untuk koneksi ke SQL Server
- **Chart.js** (CDN)
- **chartjs-plugin-datalabels** (CDN) untuk label angka/persen pada chart

---

## 3) Sumber Data & Koneksi Database
### 3.1 Koneksi
- `ConnStar` → `star_schema_pmb`  
  Digunakan untuk: realisasi (fact_pmb), dimensi waktu, prodi, sekolah, wilayah, gender.
- `ConnPmb` → `Pmbregol`  
  Digunakan untuk: target KPI dari `kpi_maba`.

### 3.2 Tabel yang Dipakai
**star_schema_pmb**
- `fact_pmb` (fakta pendaftaran: no_reg, kd_jur, kd_gender, id_wil, id_sekolah, id_waktu, dst.)
- `dim_waktu` (tahun)
- `dim_prodi` (kd_jur, nm_jur, nm_fak, kode_jurnim)
- `dim_sekolah` (nama sekolah)
- `dim_wilayah` (nama wilayah / hirarki wilayah)

**Pmbregol**
- `kpi_maba` (target_total per tahun & prodi)

> Catatan mapping target: `kpi_maba.kd_jur` dicocokkan ke `dim_prodi.kd_jur` ATAU `dim_prodi.kode_jurnim` (pakai TRIM) agar fleksibel terhadap format kode.

---

## 4) State & Variabel Penting
### 4.1 Filter
- `TahunFrom`, `TahunTo` → rentang tahun aktif
- `SelectedProdi` → nilai dropdown prodi (kd_jur)
- `SelectedProdiText` → teks yang tampil di dropdown (Nama Prodi – Fakultas)
- Konstanta:
  - `PRODI_ALL = "(Semua Prodi)"`

### 4.2 KPI & Informasi Gauge
- `TotalRealisasi` → jumlah realisasi pendaftaran pada rentang tahun + prodi
- `TotalTarget` → total target KPI pada rentang tahun + prodi
- `PctRealisasiText` → teks persentase capaian
- `PctSisaText` → teks persentase sisa
- `SisaAbs` → sisa target absolut

### 4.3 JSON Konfigurasi Chart
- `gaugeConfigJson` → config gauge doughnut (semi-circle)
- `chartConfigJson` → array config chart (bar/pie/top10)

---

## 5) Fungsi Utilitas
### 5.1 `PrettyFak(raw)`
Format nama fakultas agar rapi:
- Title Case kultur `id-ID`
- Menghasilkan teks `Fakultas <Nama>`
- Nilai “Tidak Terpetakan” tidak diubah.

### 5.2 `EnsureRangeOrder()`
Menjamin `TahunFrom <= TahunTo` dengan cara menukar nilai jika user memilih terbalik.

### 5.3 Filter Prodi ke Query (Parameterized)
- `AppendProdiFilter(sql, aliasObj)`
  Menambahkan kondisi jika `SelectedProdi` bukan “Semua Prodi”:
- `AddProdiParamIfNeeded(cmd)`
Menambahkan parameter prodi `@pkjur` jika filter aktif.

> Tujuan: query tetap aman (parameter), tidak string-concat nilai user.

---

## 6) Alur Eksekusi Halaman
### 6.1 `Page_Load`
Saat pertama kali buka halaman (`Not IsPostBack`):
1) `ResolveTahunAktif()` → menentukan default tahun (max tahun di `fact_pmb`)
2) `PopulateYearFilters()` → isi dropdown tahun dari data nyata (min/max)
3) `PopulateProdiFilter()` → isi dropdown prodi dari `dim_prodi`
4) `EnsureRangeOrder()`
5) `LoadHeaderTiles()` → hitung KPI Realisasi & Target
6) `BuildGauges()` → hitung persentase capaian + susun config gauge
7) `BuildCharts()` → query data & susun JSON chart

Saat postback:
- Mengambil nilai dari `ViewState`:
- `YFROM`, `YTO`
- `PRODI_KD`, `PRODI_TX`
- Memastikan urutan tahun tetap valid.

---

## 7) Event Handler Filter
### 7.1 `OnYearChanged`
Dipicu saat Tahun Dari / Sampai berubah:
1) set `TahunFrom`, `TahunTo`
2) `EnsureRangeOrder()`
3) simpan ke ViewState (`YFROM`, `YTO`)
4) refresh komponen:
 - `LoadHeaderTiles()`
 - `BuildGauges()`
 - `BuildCharts()`

### 7.2 `OnProdiChanged`
Dipicu saat dropdown Prodi berubah:
1) set `SelectedProdi` dan `SelectedProdiText`
2) simpan ke ViewState (`PRODI_KD`, `PRODI_TX`)
3) refresh komponen:
 - `LoadHeaderTiles()`
 - `BuildGauges()`
 - `BuildCharts()`

---

## 8) Perhitungan KPI (Header Tiles)
### 8.1 Realisasi (star_schema_pmb)
Query:
- COUNT pendaftaran dari `fact_pmb`
- join `dim_waktu` untuk filter tahun
- join `dim_prodi` untuk filter prodi (opsional)
- kondisi minimal: `f.kd_jur IS NOT NULL`

Hasil → `TotalRealisasi`.

### 8.2 Target (Pmbregol.kpi_maba)
Query:
- SUM `k.target_total`
- join `star_schema_pmb.dbo.dim_prodi dp` untuk mapping kd_jur:
- `k.kd_jur = dp.kd_jur` atau `k.kd_jur = dp.kode_jurnim`
- filter tahun
- filter prodi opsional via `dp.kd_jur = ?`

Hasil → `TotalTarget`.

### 8.3 Output UI
Repeater `rptDashboard` menampilkan 2 kartu:
- Realisasi Pendaftaran (rentang tahun)
- Target KPI MABA (rentang tahun)

---

## 9) Gauge Realisasi vs Target
### 9.1 Logika
- Hindari pembagian nol: `target = Max(TotalTarget, 1)`
- `pct = realisasi / target * 100`
- `pctClamped = Min(100, Round(pct))`
- `SisaAbs = Max(target - realisasi, 0)`
- `PctRealisasiText` dan `PctSisaText` disiapkan untuk footer.

### 9.2 Output
- `gaugeConfigJson` menghasilkan doughnut setengah lingkaran:
- data = `[pctClamped, 100 - pctClamped]`
- Pada UI, footer menampilkan:
- Realisasi (angka + %)
- Target (angka)
- Sisa (angka + %)

---

## 10) Grafik yang Dibangun (`BuildCharts`)
### 10.1 Bar: Target vs Realisasi per Tahun
- Realisasi per tahun (DW):
- group by `w.tahun`
- difilter tahun + prodi (opsional)
- Target per tahun (KPI):
- group by `k.tahun`
- difilter tahun + prodi (opsional)

Dibentuk deret kontinu tahun:
- Loop `For y = TahunFrom To TahunTo`  
Jika tahun tidak ada data, diisi 0 agar grafik tetap konsisten.

### 10.2 Pie: Komposisi Gender
- Menghitung jumlah pendaftaran per kategori:
- `L` → Laki-laki
- `P` → Perempuan
- lainnya → Tidak Diketahui
- difilter tahun + prodi.

### 10.3 Top 10 Sekolah
- Join `dim_sekolah` via `id_sekolah`
- Filter nama kosong dan kata-kata non-informatif:
- “Tidak diketahui”, “Tidak terpetakan”, “Lain-lain”, dsb.
- Order `COUNT(*) DESC`
- difilter tahun + prodi.

### 10.4 Top 10 Provinsi
- Ambil nama provinsi dari `dim_wilayah` menggunakan level wilayah:
- level 2/3 → gunakan `p.nm_wil`
- level 4 → naik ke induk `p2.nm_wil`
- level 5 → naik ke induk `p3.nm_wil`
- Filter nilai kosong / tidak valid
- difilter tahun + prodi.

---

## 11) Builder JSON Chart.js
### 11.1 `BuildChartConfig(c)`
Membuat struktur config:
- `responsive: true`
- `maintainAspectRatio: false`
- legend on/off sesuai `showLegend`
- khusus Top 10:
- chart bar dibuat **horizontal** (`indexAxis: "y"`)
- skala nilai di `x.beginAtZero = true`

### 11.2 Dataset Builder
- `BuildMultiDatasets()` → untuk grafik bar per tahun (Target & Realisasi)
- `BuildSingleDataset()` → untuk pie dan top-10

### 11.3 Warna Otomatis
- `GenerateColors()` / `GetColorFromPalette()` membuat warna berbeda (golden angle) agar dataset tidak seragam.

---

## 12) Frontend Rendering (JavaScript)
### 12.1 Inisialisasi
- `Chart.register(ChartDataLabels)`

### 12.2 Gauge
- `circumference: 180`, `rotation: 270` (setengah lingkaran)
- `cutout: "70%"`
- tooltip dimatikan
- datalabels dimatikan (gauge cukup komposisi warna)

### 12.3 Datalabels Chart
- Bar: angka ribuan (`toLocaleString('id-ID')`)
- Pie: persentase dari total dataset (dibulatkan 1 desimal)

---

## 13) Komponen UI (ASP.NET)
- Dropdown filter:
- `ddlYearFrom`, `ddlYearTo`
- `ddlProdi`
- Kartu KPI:
- `rptDashboard` (Repeater)
- Canvas Chart.js:
- `gaugeProgress`
- `barYearByFak` *(nama id tetap “ByFak”, tapi konteksnya prodi—tidak masalah selama konsisten di JS)*
- `pieGender`
- `barTopSekolah`
- `barTopProv`

---

## 14) Styling (CSS)
- `filter-range` dibuat responsif (wrap di mobile)
- Kartu KPI menggunakan style `small-box plain`:
- background lembut, border tipis
- ikon besar di kanan
- strip warna di bagian atas (varian `tile-sky` dan `tile-red`)
- Ukuran teks label dibuat seragam (18px) agar konsisten.

---

## 15) Cara Pakai (Panduan Pengguna)
1) Pilih **Tahun Dari** dan **Tahun Sampai**
2) Pilih **Program Studi** (atau “Semua Prodi”)
3) Perhatikan KPI:
 - Realisasi pendaftaran
 - Target KPI
 - Gauge capaian dan sisa
4) Analisis grafik:
 - Tren Target vs Realisasi per tahun
 - Komposisi gender
 - Sekolah dan provinsi asal terbanyak

---

## 16) Catatan Teknis & Saran Peningkatan
1) **Konsistensi nama ID chart**
 - `barYearByFak` sebenarnya menampilkan per tahun untuk prodi.
 - Jika ingin lebih rapi, bisa diganti `barYearByProdi` (harus ubah id di VB + HTML + JS).

2) **Performa**
 - Semua query dieksekusi ulang saat filter berubah.
 - Jika data besar, pertimbangkan cache berdasarkan kunci:
   - `TahunFrom|TahunTo|SelectedProdi`

3) **Validasi data sekolah/wilayah**
 - Top 10 sangat dipengaruhi konsistensi penulisan (mis. “SMA X” vs “SMA X ”).
 - Standarisasi di ETL akan memperbaiki kualitas top-10.

4) **Target = 0**
 - Sudah aman karena `target = Max(TotalTarget, 1)`.
 - Namun, pada sisi interpretasi, kalau target sebenarnya 0, persentase jadi “besar” secara matematis.
 - Opsional: jika `TotalTarget = 0`, tampilkan teks “Target belum tersedia” dan set gauge 0.

---
