# Dokumentasi Program — kpi_input.ascx

## 1) Ringkasan Modul
`kpi_input.ascx` adalah modul **CRUD KPI Mahasiswa Baru** untuk mengelola target penerimaan mahasiswa baru (MABA) pada tabel `dbo.kpi`.

Modul ini memiliki 2 mode tampilan:
1. **Panel List (pnlList)**: menampilkan daftar KPI per tahun + paging + aksi Edit/Hapus.
2. **Panel Form (pnlForm)**: form input KPI (insert banyak jurusan sekaligus) dan mode edit (update 1 baris KPI).

Fitur utama:
- Filter list berdasarkan **tahun**.
- Input KPI: pilih **tahun**, pilih **1+ fakultas**, pilih jurusan (otomatis difilter) lalu isi target.
- Edit KPI: update 1 jurusan (1 baris KPI).
- Delete KPI: hapus 1 baris KPI.
- Notifikasi **toast** saat simpan/update berhasil.

---

## 2) Teknologi & Dependensi
- **ASP.NET WebForms** UserControl (`<%@ Control ... %>`)
- Bahasa: **VB.NET** (inline server script)
- Data access: **OLE DB** (`System.Data.OleDb`) ke SQL Server
- UI: **AdminLTE** + **FontAwesome**
- Komponen WebForms:
  - `Panel`, `ListView`, `DataPager`, `GridView`
  - `CheckBoxList`, `DropDownList`, `Button`, `HiddenField`, `Label`

---

## 3) Konfigurasi Database
### 3.1 Connection String
Konstanta `CONN`:
- Server: `10.200.120.83,1433`
- Database: `Pmbregol`
- User: `sa` (catatan: sebaiknya dipindahkan ke `web.config` untuk produksi)

### 3.2 Tabel yang Digunakan
1) `dbo.kpi_maba`
- Kolom: `tahun`, `kd_fak`, `kd_jur`, `target_total`, `created_at`, `update_at`

2) `dbo.tjurus`
- Dipakai untuk lookup:
  - `kd_jur` → dianggap sebagai **kode fakultas** (kd_fak)
  - `kode_jurnim` → dianggap sebagai **kode jurusan/prodi** (kd_jur)
  - `nm_fak`, `nm_jur`

---

## 4) Struktur UI & Komponen
### 4.1 Panel List (`pnlList`)
Komponen utama:
- `ddlTahunList` : dropdown filter tahun
- `btnInputKPI` : tombol masuk ke form input
- `lvKpi` : ListView menampilkan daftar KPI
- `dpKpi` : DataPager paging ListView

Kolom list:
- Tahun
- Nama Fakultas
- Nama Jurusan
- Target MABA
- Aksi: Edit, Hapus

Aksi:
- `EditRow` → memanggil `LoadEdit()` lalu `ShowForm()`
- `DeleteRow` → DELETE `kpi_maba` berdasarkan (tahun, kd_fak, kd_jur)

### 4.2 Panel Form (`pnlForm`)
Komponen utama:
- Hidden fields:
  - `hfEditMode` : "0" insert, "1" edit/update
  - `hfEditTahun`, `hfEditKdFak`, `hfEditKdJur` : kunci baris saat edit
- `ddlTahunForm` : tahun input/update
- `cblFakultas` : daftar fakultas (bisa multi-select)
- `gvJurusan` : grid jurusan (checkbox pilih + textbox target)
- `btnSimpan` : simpan / update
- `btnBatal` : kembali ke list
- `lblMsg` : pesan status

---

## 5) Alur Eksekusi Halaman
### 5.1 `Page_Load`
Pada `Not IsPostBack`:
1. Isi `ddlTahunList` (2017–2023) dan set default ke tahun terakhir
2. Isi `ddlTahunForm` (2017–2023) dan set default ke tahun terakhir
3. `ShowList()` → halaman awal selalu panel list

### 5.2 Navigasi Panel
- `ShowList()`:
  - `pnlList.Visible = True`
  - `pnlForm.Visible = False`
  - `BindGrid()` memuat data list KPI
- `ShowForm()`:
  - `pnlList.Visible = False`
  - `pnlForm.Visible = True`
  - `LoadFakultas()` dan `LoadJurusan()` menyiapkan data form

Event tombol:
- `btnInputKPI_Click` → reset edit mode, ganti teks tombol jadi “Simpan KPI”, lalu `ShowForm()`
- `btnBatal_Click` → `ShowList()`

---

## 6) Mapping Fakultas–Jurusan (Filter Jurusan)
Modul menggunakan mapping statis `FakJurMap` untuk membatasi jurusan yang boleh dipilih berdasarkan fakultas.

- `CreateFakJurMap()` membangun dictionary:
  - contoh: `d("111") = {"115"}`, `d("820")={"825"}`, dst.
- `GetAllowedJurusanUnion(kdFaks)` menggabungkan seluruh jurusan yang valid dari fakultas yang dicentang.

Dipakai saat user memilih fakultas:
- `cblFakultas_SelectedIndexChanged`:
  - ambil semua `kd_fak` terpilih
  - panggil `LoadJurusan(faks)` untuk memfilter isi `gvJurusan`

---

## 7) Pengisian Dropdown & Grid Form
### 7.1 `LoadFakultas()`
Query:
- `SELECT DISTINCT CAST(kd_jur AS varchar) AS kd_fak, nm_fak FROM tjurus ...`
Menampilkan item:
- Format teks: `"<kode> - <nama fakultas>"`

Hasil masuk ke:
- `cblFakultas.Items`

### 7.2 `LoadJurusan(selectedFaks)`
Query awal:
- `SELECT kode_jurnim AS kode_jurnim, kd_jur AS kd_fak_ref, nm_jur FROM tjurus ...`

Langkah filter:
1) Ambil DataTable `dt`
2) Jika `selectedFaks` ada:
   - hitung `allowed = GetAllowedJurusanUnion(selectedFaks)`
   - buat `filtered` berisi baris yang `kode_jurnim` ada di `allowed`
3) Tambah kolom `NamaJurusan`:
   - format: `"<kode_jurnim> - <nm_jur>"`

Bind ke:
- `gvJurusan.DataSource = dt`

DataKey GridView:
- `DataKeyNames="kode_jurnim,kd_fak_ref"`
Dipakai saat insert untuk mengambil `kd_jur` dan `kd_fak`.

---

## 8) Simpan Data KPI (Insert & Update)
### 8.1 Validasi Awal (`btnSimpan_Click`)
- Reset pesan: `lblMsg`
- Tentukan mode: `isUpdate = (hfEditMode.Value="1")`
- Validasi:
  - Tahun valid dari `ddlTahunForm`
  - Minimal 1 fakultas dipilih (`cblFakultas.SelectedItem`)

### 8.2 Mode UPDATE (Edit satu baris)
Aktif jika `hfEditMode="1"`.

Kunci update:
- `tahun = ddlTahunForm`
- `kdFak = hfEditKdFak`
- `kdJur = hfEditKdJur`

Ambil nilai target:
- Loop `gvJurusan.Rows`, cari row dengan `kode_jurnim == kdJur`
- Ambil `txtTargetRow` → parse ke `target`

Query update:
- `UPDATE kpi_maba SET target_total=?, update_at=GETDATE() WHERE tahun=? AND kd_fak=? AND kd_jur=?`

Setelah update:
- Reset hidden fields edit
- `btnSimpan.Text = "Simpan KPI"`

### 8.3 Mode INSERT (Banyak baris sekaligus)
Aktif jika `hfEditMode="0"`.

Proses:
- Loop semua row `gvJurusan`:
  - `chkPilih` harus dicentang
  - `txtTargetRow` diparse ke integer
  - ambil `kdJur = DataKey("kode_jurnim")`
  - ambil `kdFak = DataKey("kd_fak_ref")`
- Insert per jurusan terpilih:

Query insert:
- `INSERT INTO kpi_maba (tahun,kd_fak,kd_jur,target_total,created_at,update_at) VALUES (?,?,?, ?, GETDATE(), GETDATE())`

### 8.4 Output Sukses
- `lblMsg` jadi hijau (`text-success`)
- Toast:
  - insert: “KPI berhasil disimpan.”
  - update: “KPI berhasil diupdate.”
- `ShowList()` untuk kembali ke daftar.

### 8.5 Penanganan Error
Jika exception:
- `lblMsg` merah (`text-danger`)
- tampilkan `Server.HtmlEncode(ex.Message)`

---

## 9) Menampilkan Data List KPI (`BindGrid`)
Fungsi `BindGrid()` memuat data `kpi_maba` (opsional filter tahun).

Filter:
- `filterByYear = Integer.TryParse(ddlTahunList.SelectedValue, tahun)`
- Jika `filterByYear`, query memakai `WHERE km.tahun = ?`

Query:
- SELECT tahun, kd_fak, nm_fak, kd_jur, nm_jur, target_total
- Join lookup:
  - Fakultas: `tjurus f` join `f.kd_jur = km.kd_fak`
  - Jurusan: `tjurus j` join `j.kode_jurnim = km.kd_jur`

Bind ke:
- `lvKpi.DataSource = dt`

---

## 10) Aksi Edit & Hapus pada ListView
### 10.1 `lvKpi_ItemCommand`
`CommandArgument` dikirim dalam format:
- `"tahun|kd_fak|kd_jur"`

#### a) Edit (`EditRow`)
- Memanggil `LoadEdit(tahun,kdFak,kdJur)`
- `ShowForm()`

#### b) Hapus (`DeleteRow`)
- Konfirmasi via JS `confirm()`
- Query:
  - `DELETE FROM kpi_maba WHERE tahun=? AND kd_fak=? AND kd_jur=?`
- Refresh: `BindGrid()`

---

## 11) Mode Edit (`LoadEdit`)
Tujuan: mempersiapkan form untuk update 1 KPI.

Langkah:
1) Set hidden fields:
   - `hfEditMode="1"`
   - `hfEditTahun`, `hfEditKdFak`, `hfEditKdJur`
2) Ubah tombol: `btnSimpan.Text="Update"`
3) Set dropdown tahun (`ddlTahunForm`) sesuai `th`
4) Load fakultas (`LoadFakultas()`) lalu pilih item sesuai `kdFak`
5) Load jurusan untuk fakultas tersebut:
   - `LoadJurusan(New List(Of String) From {kdFak})`
6) Ambil `target_total` dari DB untuk kombinasi kunci
7) Cari row jurusan yang sama di `gvJurusan`, lalu:
   - centang checkbox
   - isi textbox target

---

## 12) Paging & Filter Tahun List
- `lvKpi_PagePropertiesChanging`:
  - `dpKpi.SetPageProperties(start, max, False)`
  - `BindGrid()`

- `ddlTahunList_SelectedIndexChanged`:
  - reset ke halaman 1 (`SetPageProperties(0, PageSize, False)`)
  - `BindGrid()`

---

## 13) Styling & UX
### 13.1 Layout
- `.content-wrapper` dibuat flex agar footer “nempel bawah”.
- `.kpi-topbar` memberi title + breadcrumb dengan gaya AdminLTE.

### 13.2 Tabel List Custom
ListView ditampilkan seperti grid dengan CSS:
- `.kpi-grid`, `.kpi-row`, `.kpi-head`
- responsive: pada layar kecil header disembunyikan dan layout menjadi 2 kolom.

### 13.3 CheckBoxList Fakultas
`cblFakultas` dibuat rapih 2 kolom:
- `RepeatColumns="2"`
- CSS `.cbl-fakultas` memberi jarak antar item dan antar kolom.

### 13.4 Toast Notification
Fungsi JS `showToast(message,type,title,position)`:
- posisi `center` (bawah) atau `middle`
- tipe: `success`, `info`, `error`
Dipanggil dari server via:
- `ScriptManager.RegisterStartupScript(...)`

---

## 14) Cara Pakai (Panduan Singkat)
### 14.1 Menambah KPI (Insert)
1) Klik **Input KPI**
2) Pilih **Tahun**
3) Centang **Fakultas** (bisa lebih dari satu)
4) Pilih **Jurusan** (centang) dan isi **Target Mahasiswa Baru**
5) Klik **Simpan KPI**
6) Sistem kembali ke list dan menampilkan toast sukses

### 14.2 Mengubah KPI (Update)
1) Pada list, klik **Edit** pada baris KPI
2) Sistem membuka form edit (mode update)
3) Ubah nilai target pada jurusan terkait
4) Klik **Update**
5) Sistem kembali ke list dan menampilkan toast sukses

### 14.3 Menghapus KPI
1) Klik **Hapus**
2) Konfirmasi prompt
3) Data terhapus dan list direfresh

---

## 15) Catatan Teknis & Saran Peningkatan
1) **Tahun hard-coded (2017–2023)**  
   Disarankan ambil dari DB:
   - `SELECT MIN(tahun), MAX(tahun) FROM kpi_maba` atau dari `fact_pmb`.

2) **Duplicate insert**  
   Saat insert, belum ada pengecekan duplikasi kunci (tahun,kd_fak,kd_jur).  
   Rekomendasi:
   - tambahkan UNIQUE INDEX di DB, atau
   - lakukan `IF EXISTS` / UPSERT (MERGE).

3) **Mapping FakJurMap statis**  
   Jika struktur prodi berubah, perlu edit kode.  
   Rekomendasi simpan mapping di tabel referensi.

4) **Keamanan koneksi**
   - Pindahkan connection string ke `web.config`
   - Jangan hardcode user/password.

5) **Validasi angka target**
   - Tambahkan validasi minimal 0, dan optional max.

---
