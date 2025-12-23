# Dokumentasi Dashboard Mahasiswa Baru (Universitas) — biodata.ascx

## 1) Deskripsi Singkat
Modul ini menampilkan **dashboard monitoring PMB tingkat Universitas** berbasis data **star_schema_pmb** (realisasi) dan **Pmbregol.kpi_maba** (target). Dashboard menyediakan:
- **Filter rentang tahun** (Tahun Dari / Tahun Sampai)
- **KPI cards**: Realisasi pendaftaran & Target KPI MABA
- **Gauge**: Realisasi vs Sisa Target
- **Grafik utama**:
  - Target vs Realisasi per Tahun (bar, multi dataset)
  - Komposisi Gender (pie)
  - Top 10 Sekolah (bar horizontal)
  - Top 10 Provinsi (bar horizontal)
- **Analitik tambahan**:
  - **K-Means clustering wilayah** (scatter + legend custom)
  - **Regresi linier tren** 2017–2023 + tabel prediksi

> File menggunakan `<!-- #INCLUDE file="/con_ascx2022/conlintar2022.ascx" -->` untuk dependensi layout/koneksi internal aplikasi.

---

## 2) Teknologi & Dependensi
**Server-side**
- ASP.NET WebForms (UserControl/ASCX atau page ASPX inline) dengan VB (`<script runat="server">`)
- Akses database via `OleDbConnection` (Provider SQLOLEDB) ke SQL Server

**Client-side**
- Chart.js via CDN:
  - `https://cdn.jsdelivr.net/npm/chart.js`
- Custom Chart.js plugins:
  - `PiePercentLabels` (label persen untuk pie/doughnut khusus `#pieGender`)
  - `ValueLabels` (angka di atas batang untuk chart bar)

---

## 3) Konfigurasi Koneksi (Catatan Keamanan)
Di kode terdapat `ConnPmb` dan `ConnStar` untuk koneksi ke:
- Database operasional: `Pmbregol`
- Data warehouse / mart: `star_schema_pmb`

**Rekomendasi keamanan (wajib jika di GitHub / repo publik):**
- Pindahkan connection string ke `web.config` (atau secrets manager internal)
- Jangan hardcode user/password DB di source code
- Minimal gunakan account DB khusus read-only untuk dashboard

---

## 4) Struktur Data yang Dipakai

### 4.1. Database `star_schema_pmb`
Dipakai untuk **realisasi** & dimensi:
- `fact_pmb`  
  Dipakai untuk hitung realisasi pendaftaran (filter `kd_jur IS NOT NULL`).
- `dim_waktu`  
  Dipakai untuk filter tahun (`w.tahun`) dan join ke fact.
- `dim_sekolah`  
  Dipakai untuk Top 10 sekolah.
- `dim_wilayah`  
  Dipakai untuk Top 10 provinsi.

Analitik:
- `fact_kmeans_wilayah`  
  Menyimpan hasil K-Means wilayah (minimal: `k_optimal`, `silhouette`, `chart_json`, plus metadata tahun).
- `fact_reg_tren`  
  Menyimpan hasil regresi linier (minimal: `chart_json`, `slope`, `intercept`, `r2`, `mae`, `rmse`, `mape`).

### 4.2. Database `Pmbregol`
- `kpi_maba`  
  Dipakai untuk target KPI (`SUM(target_total)` per tahun / rentang tahun).

---

## 5) Komponen UI yang Harus Ada
Kontrol ASP.NET yang dipakai di markup:
- `ddlYearFrom`, `ddlYearTo` (DropDownList, AutoPostBack, handler `OnYearChanged`)
- `rptDashboard` (Repeater KPI cards)
- Canvas Chart.js:
  - `gaugeProgress`
  - `barFakultas`
  - `pieGender`
  - `barTopSekolah`
  - `barTopProv`
  - `scKMeansWilayah`
  - `regTrend`
- Legend container: `kmLegend`
- Prediksi table body: `tblPredBody`

---

## 6) Variabel State & Output

### 6.1. Filter Tahun
- `TahunFrom`, `TahunTo` disimpan ke `ViewState("YFROM")` & `ViewState("YTO")`

### 6.2. Output untuk Chart / Statistik
**K-Means**
- `clusterChartJson` (JSON chart)
- `clusterKOptimal` (angka K)
- `clusterSilhouette`, `clusterWCSS`, `clusterCH` (string tampilan)

**Regresi**
- `regChartJson` (JSON chart)
- `regEqText`, `regR2Text`, `regMAEText`, `regMAPEText`, `regRMSEText`

**Chart umum & gauge**
- `chartConfigJson` (array JSON beberapa chart)
- `gaugeConfigJson`, `gaugePctHtml`

---

## 7) Alur Eksekusi Halaman

### 7.1. `Page_Load`
Jika `Not IsPostBack`:
1. `PopulateYearFilters()` → isi dropdown tahun + set default
2. `EnsureRangeOrder()` → pastikan From ≤ To
3. `LoadHeaderTiles()` → hitung realisasi & target, bind KPI cards
4. `BuildGauges()` → hitung % dan JSON gauge
5. `BuildCharts()` → buat JSON semua chart utama (dengan cache 3 menit)
6. `BuildClusterWilayah()` → ambil hasil K-Means (cache 3 menit global)
7. `BuildRegressionTrend()` → ambil hasil regresi tren (2017–2023)

Jika PostBack:
- Ambil `TahunFrom/TahunTo` dari ViewState lalu `EnsureRangeOrder()`

### 7.2. `OnYearChanged`
Dipanggil saat dropdown Tahun Dari/Sampai berubah:
1. Update `TahunFrom`, `TahunTo`
2. `EnsureRangeOrder()`
3. Simpan ke ViewState
4. Rebuild komponen:
   - `LoadHeaderTiles()`, `BuildGauges()`, `BuildCharts()`, `BuildClusterWilayah()`, `BuildRegressionTrend()`

> Catatan: `BuildClusterWilayah()` saat ini **global** (tidak mengikuti filter tahun) karena memakai cache `pmb:kmeans:global` dan query `TOP 1 ORDER BY tahun_to DESC`.

---

## 8) Dokumentasi Fungsi Server-Side (VB)

### 8.1. Utility
#### `PrettyFak(raw As String) As String`
Memformat nama fakultas ke Title Case + prefix “Fakultas …”.  
Dipakai jika ada label fakultas; pada file ini fungsi masih tersedia walau tidak selalu dipanggil.

#### `EnsureRangeOrder()`
Menukar nilai jika `TahunFrom > TahunTo` agar rentang valid.

---

### 8.2. Filter Tahun
#### `PopulateYearFilters()`
- Mengambil `MIN(w.tahun)` dan `MAX(w.tahun)` dari `fact_pmb JOIN dim_waktu`
- Membatasi rentang (default) `2017..2060`
- Mengisi `ddlYearFrom` & `ddlYearTo` dari `maxY` turun ke `minY`
- Default nilai dari ViewState bila ada

---

### 8.3. KPI Header (Realisasi & Target)
#### `LoadHeaderTiles()`
- Realisasi: `COUNT(*)` dari `star_schema_pmb.dbo.fact_pmb` (tahun filter, `kd_jur IS NOT NULL`)
- Target: `SUM(target_total)` dari `Pmbregol.dbo.kpi_maba` (tahun filter)
- Membuat list object untuk `rptDashboard` (2 kartu)

---

### 8.4. Gauge
#### `BuildGauges()`
- Menghitung:
  - `pctRealisasi = realisasi/target * 100`
  - `pctSisa = (target - realisasi)/target * 100`
- Menyusun:
  - `gaugeConfigJson` → doughnut setengah lingkaran (di JS)
  - `gaugePctHtml` → teks ringkasan di bawah gauge

---

### 8.5. Grafik Utama (Bar/Pie/Top-10)
#### `BuildCharts()`
**Tujuan:** men-generate `chartConfigJson` (array beberapa chart) dan cache 3 menit.

**Query multi-resultset** (1 command, 5 result sets):
1. RS1: realisasi per tahun (COUNT fact)
2. RS2: target per tahun (SUM kpi_maba)
3. RS3: pie gender (L/P/unknown)
4. RS4: Top 10 sekolah (filter nama kosong & “TIDAK DIKETAHUI”)
5. RS5: Top 10 provinsi

**Proses penting:**
- `dictReal` & `dictTarget` digabung berdasarkan union tahun → membentuk label tahun konsisten
- Data diserialisasi ke format string sederhana, lalu dibangun jadi JSON Chart.js via:
  - `BuildChartConfig()`
  - `BuildMultiDatasets()` untuk chart bar multi dataset (Target & Realisasi)
  - `BuildSingleDataset()` untuk chart pie/top10

---

### 8.6. K-Means Wilayah
#### `BuildClusterWilayah()`
- Mengambil `TOP 1 k_optimal, silhouette, chart_json` dari `fact_kmeans_wilayah`
- Menetapkan:
  - `clusterKOptimal`
  - `clusterSilhouette`
  - `clusterChartJson`
- `clusterWCSS` dan `clusterCH` diset `"-"` (N/A) karena kolom disebut “dihapus”
- Cache global: `pmb:kmeans:global` selama 3 menit

> Di CSS ada aturan:
` .kpi-grid .small-box:nth-child(3), .kpi-grid .small-box:nth-child(4){ display:none !important; } `
yang menyembunyikan box WCSS & Calinski-H di tampilan.

---

### 8.7. Regresi Linier Tren
#### `BuildRegressionTrend()`
- Rentang tetap: `REG_FROM=2017`, `REG_TO=2023`
- Query: `SELECT TOP 1 chart_json, slope, intercept, r2, mae, rmse, mape FROM fact_reg_tren ... ORDER BY id_run DESC`
- Output:
  - `regChartJson` dipakai langsung oleh Chart.js
  - `regEqText` → format `ŷ = intercept + (slope × tahun)`
  - `regR2Text`, `regMAEText`, `regMAPEText`, `regRMSEText`

---

### 8.8. Builder JSON Chart.js (Internal)
#### `BuildChartConfig(c As Object)`
Menyatukan struktur JSON Chart.js:
- `id`, `type`
- `data.labels`, `data.datasets`
- `options` (legend, responsive, scale bar, horizontal bar via `indexAxis="y"`)

#### `StringToArray(str As String)`
Mengubah `"a,b,c"` → `["a","b","c"]` atau `[1,2,3]` jika numeric.

#### `GenerateColors(count)`, `GetColorFromPalette(index)`
Menghasilkan warna HEX dengan metode golden-angle (stabil, beda tiap dataset).

---

## 9) Dokumentasi JavaScript (Chart.js)

### 9.1. Plugin `PiePercentLabels`
- Hanya aktif untuk pie/doughnut dan **khusus canvas `pieGender`**
- Menampilkan label persen di dalam slice jika `pct >= minPct`

### 9.2. Plugin `ValueLabels`
- Hanya untuk chart bar
- Menampilkan nilai di atas batang (atau di kanan untuk horizontal bar)
- Ada opsi `showZero`, `formatter`, dll

### 9.3. Render saat `DOMContentLoaded`
1) Gauge: membaca `gaugeConfigJson`  
2) Chart utama: iterasi `chartConfigJson`, inject plugin option sesuai tipe/id  
3) K-Means:
   - parse `clusterChartJson`
   - bangun dataset scatter dari `km.scatter[]`
   - legend custom ditaruh di `#kmLegend`
   - tooltip menampilkan:
     - label wilayah, total, jumlah sekolah, rata-rata MABA/sekolah
   - auto-scale axis + padding 3%
4) Regresi:
   - parse `regChartJson`
   - menambah hover radius untuk dataset label “Target”
   - mengisi tabel prediksi dari dataset label mengandung “Titik Prediksi” ke `#tblPredBody`

---

## 10) Caching & Performa
- `BuildCharts()` cache key: `pmb:charts:<from>-<to>` selama 3 menit
- `BuildClusterWilayah()` cache key: `pmb:kmeans:global` selama 3 menit
- Query chart memakai:
  - `SET NOCOUNT ON`
  - `READ UNCOMMITTED` untuk mengurangi locking (perlu dipastikan sesuai kebijakan data)

---

## 11) Catatan Implementasi & Troubleshooting
- **Urutan parameter OLEDB**: karena pakai `?`, urutan `cmd.Parameters.Add(...)` harus sama persis dengan urutan placeholder di SQL.
- **JSON injection ke JS**: pastikan string JSON dari DB valid (tidak ter-escape ganda). Di JS sudah ada fallback parse bila `clusterChartJson` berupa string.
- **Null/empty data**:
  - Jika dataset K-Means kosong, chart tidak dirender dan log warning.
  - Tabel prediksi akan menampilkan “Tidak ada data prediksi” bila dataset prediksi tidak ditemukan.
- **Perubahan tampilan**:
  - Persamaan regresi versi HTML (`regStatsHtml`) sudah dihapus dari markup (comment) agar tidak tampil dobel; metrik tetap tampil lewat tabel.

---

## 12) Ringkasan Output yang Dilihat User
- Pilih Tahun Dari/Sampai → dashboard refresh otomatis
- KPI cards menunjukkan ringkasan realisasi & target
- Gauge menunjukkan capaian dan sisa target
- Grafik membantu analisis tren, gender, sekolah asal, provinsi asal
- Bagian analitik:
  - K-Means menunjukkan sebaran wilayah (jumlah mahasiswa vs jumlah sekolah) per klaster
  - Regresi menunjukkan tren + prediksi dan metrik error model
