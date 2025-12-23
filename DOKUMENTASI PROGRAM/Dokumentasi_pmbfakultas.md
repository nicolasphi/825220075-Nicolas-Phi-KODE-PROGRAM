# Dokumentasi Program — Dashboard Mahasiswa Baru Fakultas - pmb_fakultas.ascx

## 1) Ringkasan Modul
Halaman **Dashboard Mahasiswa Baru Fakultas** menampilkan ringkasan dan visualisasi PMB pada level **fakultas** berdasarkan data dari **star_schema_pmb** dan target dari **Pmbregol**. Pengguna dapat memfilter:
- **Rentang tahun** (Tahun Dari – Tahun Sampai)
- **Fakultas** (Semua / fakultas tertentu)

Output utama yang ditampilkan:
1) **Kartu KPI**: Total Realisasi & Total Target KPI MABA pada rentang tahun
2) **Gauge**: Persentase capaian (Realisasi vs Target) + teks ringkasan realisasi/target/sisa
3) **Grafik Bar**: Target vs Realisasi per Tahun (mengikuti filter tahun dan fakultas)
4) **Pie**: Komposisi Gender
5) **Bar Top 10**: Sekolah asal terbanyak
6) **Bar Top 10**: Provinsi asal terbanyak

---

## 2) Teknologi & Dependensi
- **ASP.NET WebForms** (inline VB: `<script runat="server">`)
- **OLE DB SQL Server** (`System.Data.OleDb`) untuk query
- **Chart.js** untuk visualisasi
- **chartjs-plugin-datalabels** untuk label nilai/persen pada chart

---

## 3) Sumber Data & Koneksi
### 3.1 Database
- `ConnStar` → `star_schema_pmb` (data realisasi, gender, sekolah, provinsi, dim_prodi)
- `ConnPmb` → `Pmbregol` (target KPI dari `kpi_maba`)

> Catatan: Target difilter fakultas dengan join ke `star_schema_pmb.dbo.dim_prodi` memakai `kd_jur` atau `kode_jurnim`.

---

## 4) State & Variabel Penting
### 4.1 Filter
- `TahunFrom`, `TahunTo` → rentang tahun aktif
- `SelectedFak` → fakultas terpilih (default: `(Semua Fakultas)`)

### 4.2 KPI & Output Teks
- `TotalRealisasi` → hasil hitung pendaftar (count `fact_pmb`)
- `TotalTarget` → total target KPI (sum `kpi_maba.target_total`)
- `PctRealisasiText` → persentase capaian (format teks)
- `PctSisaText` → persentase sisa target (format teks)
- `SisaAbs` → sisa target absolut

### 4.3 Konfigurasi Chart
- `chartConfigJson` → JSON array config untuk Chart.js (bar/pie/top10)
- `gaugeConfigJson` → JSON config gauge (doughnut setengah lingkaran)

---

## 5) Fungsi Utilitas
### 5.1 `PrettyFak(raw)`
Menormalisasi nama fakultas:
- Mengubah menjadi Title Case sesuai kultur `id-ID`
- Mengembalikan string dengan prefix **“Fakultas ”**
- Menjaga nilai `Tidak Terpetakan` apa adanya

### 5.2 `EnsureRangeOrder()`
Jika user memilih Tahun Dari > Tahun Sampai, maka nilai ditukar agar tetap valid.

### 5.3 Filter Fakultas di SQL
Agar filter fakultas konsisten dan aman:
- `AppendFakFilter(sql, aliasDp)`  
  Menambahkan kondisi:
hanya jika `SelectedFak` bukan “Semua Fakultas”.

- `AddFakParamIfNeeded(cmd)`  
Menambahkan parameter `@pfak` jika filter fakultas aktif.

---

## 6) Alur Proses Halaman
### 6.1 `Page_Load`
Saat halaman pertama dibuka (`Not IsPostBack`):
1) `ResolveTahunAktif()` (untuk default tahun aktif)
2) `PopulateYearFilters()` → isi dropdown Tahun Dari/Sampai berdasarkan data di `fact_pmb`
3) `PopulateFakultasFilter()` → isi dropdown fakultas dari `dim_prodi`
4) `EnsureRangeOrder()`
5) `LoadHeaderTiles()` → hitung KPI Realisasi & Target
6) `BuildGauges()` → hitung persentase capaian + siapkan config gauge
7) `BuildCharts()` → query data dan susun JSON chart

Saat postback:
- Mengambil `YFROM`, `YTO`, `FAK` dari ViewState agar filter tidak hilang.

---

## 7) Event Handler Filter
### 7.1 `OnYearChanged`
Dipanggil saat Tahun Dari / Tahun Sampai berubah:
1) Set `TahunFrom`, `TahunTo`
2) `EnsureRangeOrder()`
3) Simpan ke ViewState (`YFROM`, `YTO`)
4) Refresh semua komponen:
 - `LoadHeaderTiles()`
 - `BuildGauges()`
 - `BuildCharts()`

### 7.2 `OnFakChanged`
Dipanggil saat dropdown Fakultas berubah:
1) Set `SelectedFak`
2) Simpan ke ViewState (`FAK`)
3) Refresh semua komponen:
 - `LoadHeaderTiles()`
 - `BuildGauges()`
 - `BuildCharts()`

---

## 8) Perhitungan KPI Utama
### 8.1 Realisasi (Star Schema)
Query utama:
- hitung `COUNT(*)` dari `fact_pmb`
- join `dim_waktu` untuk filter tahun
- join `dim_prodi` untuk filter fakultas (opsional)
- syarat `f.kd_jur IS NOT NULL`

Hasil disimpan ke `TotalRealisasi`.

### 8.2 Target (Pmbregol)
Query utama:
- `SUM(k.target_total)` dari `kpi_maba`
- join `dim_prodi` untuk mapping prodi:
- `k.kd_jur = dp.kd_jur` atau `k.kd_jur = dp.kode_jurnim`
- filter tahun `k.tahun BETWEEN TahunFrom AND TahunTo`
- filter fakultas opsional via `dp.nm_fak`

Hasil disimpan ke `TotalTarget`.

---

## 9) Gauge Realisasi vs Target
### 9.1 Logika
- `target = Max(TotalTarget, 1)` untuk menghindari pembagian nol
- `pct = realisasi/target * 100`
- `pctClamped` dibatasi maksimal 100
- `SisaAbs = Max(target - realisasi, 0)`
- `PctRealisasiText` dan `PctSisaText` disiapkan untuk teks ringkasan

### 9.2 Output
- `gaugeConfigJson` berisi dataset doughnut:
- data = `[pctClamped, 100 - pctClamped]`
- UI menampilkan teks:
- Realisasi (angka + %)
- Target (angka)
- Sisa (angka + %)

---

## 10) Grafik yang Dibangun (`BuildCharts`)
### 10.1 Bar: Target vs Realisasi per Tahun
- Realisasi per tahun dari `star_schema_pmb.fact_pmb`
- Target per tahun dari `Pmbregol.kpi_maba`
- Dibuat deret kontinu `For y = TahunFrom To TahunTo` agar tahun kosong tetap tampil 0

Output:
- labels: tahun
- dataset multi: Target & Realisasi

### 10.2 Pie: Komposisi Gender
- Menggunakan `fact_pmb.kd_gender`:
- L → Laki-laki
- P → Perempuan
- selain itu → Tidak Diketahui
- difilter tahun + fakultas

### 10.3 Top 10 Sekolah
- join `dim_sekolah` melalui `id_sekolah`
- buang nilai kosong & variasi “tidak diketahui”
- order `COUNT(*) DESC`
- difilter tahun + fakultas

### 10.4 Top 10 Provinsi
- mapping provinsi dari `dim_wilayah` dengan mempertimbangkan level wilayah:
- level 2/3 → gunakan `p.nm_wil`
- level 4 → naik ke induk (`p2.nm_wil`)
- level 5 → naik lagi (`p3.nm_wil`)
- buang nilai “Tidak Terpetakan”, “Tidak Diketahui”, “Lain-lain”, dsb.
- difilter tahun + fakultas

---

## 11) Builder JSON Chart.js
### 11.1 `BuildChartConfig(c)`
Menyusun konfigurasi final chart:
- `responsive: true`, `maintainAspectRatio: false`
- Legend ditampilkan sesuai `showLegend`
- Untuk bar top-10 sekolah & provinsi dibuat **horizontal bar** (`indexAxis="y"`)

### 11.2 Dataset
- `BuildMultiDatasets()` untuk bar tahun (Target vs Realisasi)
- `BuildSingleDataset()` untuk pie dan bar top-10

### 11.3 Warna
Warna dataset dibuat otomatis melalui `GetColorFromPalette()` (golden-angle) sehingga antar dataset tetap berbeda tanpa hardcode warna.

---

## 12) Frontend Rendering (JavaScript)
### 12.1 Library
- `chart.js`
- `chartjs-plugin-datalabels`

### 12.2 Format Angka
- `numfmt()` menggunakan `toLocaleString('id-ID')`

### 12.3 DataLabels
- Bar: tampilkan angka di ujung bar
- Pie: tampilkan **persentase** berdasarkan total dataset

### 12.4 Gauge
Gauge menggunakan doughnut setengah lingkaran:
- `circumference: 180`
- `rotation: 270`
- `cutout: "70%"`
- tooltip dimatikan

> Catatan: plugin `CenterText` sudah didefinisikan, tetapi pada config gauge belum diberi `plugins.centerText`. Jika ingin menampilkan teks persentase di tengah, tambahkan `plugins: { centerText: { text: 'xx%' } }`.

---

## 13) Komponen UI (ASP.NET)
- Dropdown:
- `ddlYearFrom`, `ddlYearTo` → filter rentang tahun
- `ddlFak` → filter fakultas
- Repeater `rptDashboard` → menampilkan 2 kartu KPI (Realisasi & Target)
- Canvas Chart.js:
- `gaugeProgress`
- `barYearByFak`
- `pieGender`
- `barTopSekolah`
- `barTopProv`

---

## 14) Styling (CSS)
- `filter-range` dibuat responsive (wrap pada layar kecil)
- Kartu KPI menggunakan style “plain” dengan:
- strip warna di atas
- ikon besar di kanan
- tipografi angka & label konsisten
- Varian warna:
- realisasi: `tile-sky`
- target: `tile-red`

---

## 15) Cara Pakai (User Guide Singkat)
1) Pilih **Tahun Dari** dan **Tahun Sampai**
2) Pilih **Fakultas** (atau biarkan “Semua Fakultas”)
3) Amati:
 - KPI Realisasi & Target
 - Gauge capaian (Realisasi vs Target)
4) Gunakan grafik:
 - Bar per Tahun untuk membandingkan target vs realisasi
 - Pie gender untuk komposisi pendaftar
 - Top 10 sekolah dan provinsi untuk asal pendaftar

---

## 16) Catatan Teknis & Saran Peningkatan
1) **Parameter mapping target**  
 Join target menggunakan `kd_jur` atau `kode_jurnim` sudah baik untuk variasi kode prodi. Pastikan data `kpi_maba.kd_jur` konsisten trimming-nya.

2) **Caching**  
 Modul ini belum memakai cache untuk chart (berbeda dari versi universitas). Jika performa berat, bisa cache berdasarkan:
 - TahunFrom–TahunTo–SelectedFak

3) **Data kualitas wilayah & sekolah**  
 Karena memakai filter “buang tidak diketahui”, pastikan nilai di dimensi sudah distandarisasi agar top10 tidak pecah-pecah.

4) **Center text gauge**  
 Jika mau menampilkan `PctRealisasiText` di tengah gauge, aktifkan plugin `CenterText` pada config chart gauge.

---
