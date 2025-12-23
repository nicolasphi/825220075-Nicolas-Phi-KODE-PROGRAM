<!-- #INCLUDE file = "/path/to/your/page_or_master.aspx" --> 'NOTE: include file tergantung modul / layout aplikasi (internal).
<%@ Import Namespace="System.Data" %>
<%@ Import Namespace="System.Data.OleDb" %>
<%@ Import Namespace="System.Globalization" %>
<%@ Import Namespace="System.Text.RegularExpressions" %>

<script runat="server">
'================= KONFIG KONEKSI =================

Private ReadOnly ConnStar As String =
  "Provider=SQLOLEDB;Data Source=<DB_HOST>,<PORT>;Initial Catalog=<STAR_DB_NAME>;User ID=<DB_USER>;Password=<DB_PASS>;"

'================= KONST & STATE ==================
Private Const YEAR_AVAILABLE_MAX As Integer = 2023   ' peringatan tahun hanya sampai 2023
Protected Property LastRefreshed As DateTime
Protected Property TahunAwal As Integer = 2017
Protected Property TahunAkhir As Integer = YEAR_AVAILABLE_MAX

' Daftar tabel yang ditampilkan (whitelist)
Private ReadOnly TableList As String() = {
  "dim_gender",
  "dim_jurusan_sekolah",
  "dim_prodi",
  "dim_waktu",
  "dim_wilayah",
  "dim_sekolah",
  "fact_pmb"
}

'================= PAGE LOAD ======================
Protected Sub Page_Load(ByVal sender As Object, ByVal e As EventArgs)
  If Not IsPostBack Then
    PopulateYearFilters()
    BindGridTableCounts()
    LastRefreshed = DateTime.Now
    litLastUpdated.Text = LastRefreshed.ToString("dd MMM yyyy HH:mm")
    litYearMax.Text = YEAR_AVAILABLE_MAX.ToString()
  End If
End Sub

'================= FILTER TAHUN ===================
Private Sub PopulateYearFilters()
  ddlYearFrom.Items.Clear()
  ddlYearTo.Items.Clear()

  ' Isi pilihan (ambil rentang masuk akal, kunci max ke 2023)
  For y As Integer = YEAR_AVAILABLE_MAX To 2016 Step -1
    ddlYearFrom.Items.Add(New ListItem(y.ToString(), y.ToString()))
    ddlYearTo.Items.Add(New ListItem(y.ToString(), y.ToString()))
  Next
  ddlYearFrom.SelectedValue = TahunAwal.ToString()
  ddlYearTo.SelectedValue = TahunAkhir.ToString()
End Sub

Protected Sub OnYearChanged(sender As Object, e As EventArgs)
  ' hanya simpan pilihan; tabel di bawah memang tidak bergantung tahun
  TahunAwal  = CInt(ddlYearFrom.SelectedValue)
  TahunAkhir = CInt(ddlYearTo.SelectedValue)
  litYearMax.Text = YEAR_AVAILABLE_MAX.ToString()
End Sub

'================= EVENT BUTTON ===================
' Tombol ini SEKARANG menjalankan ETL dummy + refresh tabel
Protected Sub btnPerbarui_Click(sender As Object, e As EventArgs)
  Try
    Dim sql As String = BuildEtlSql()
    RunSqlByBatches(sql)

    ' Sukses: refresh ringkasan tabel
    BindGridTableCounts()
    LastRefreshed = DateTime.Now
    litLastUpdated.Text = LastRefreshed.ToString("dd MMM yyyy HH:mm")

    ScriptManager.RegisterStartupScript(Me, Me.GetType(), "ok",
      "alert('Data telah selesai diperbarui. Ringkasan tabel sudah diperbarui.');", True)
  Catch ex As Exception
    ScriptManager.RegisterStartupScript(Me, Me.GetType(), "err",
      ("alert('Data gagal diperbarui: " & ex.Message.Replace("'", "\'") & "');"), True)
  End Try
End Sub

Protected Sub btnClustering_Click(sender As Object, e As EventArgs)
  Try
    Dim kOpt As Integer? = Nothing
    Dim sil  As Double?  = Nothing

    ' Panggil SP fixed 2017-2023
    RunKMeansSilhouette_Fixed(kOpt, sil)

    Cache.Remove("pmb:kmeans:global")  ' bust cache 

    ' (Opsional) verifikasi yang tersimpan:
    Dim savedInfo As String = ""
    Using cn As New OleDb.OleDbConnection(ConnStar)
      cn.Open()
      Dim q As String =
        "SELECT TOP 1 k_optimal, silhouette, created_at " &
        "FROM dbo.fact_kmeans_wilayah " &
        "WHERE tahun_from=2017 AND tahun_to=2023 " &
        "ORDER BY id_run DESC"
      Using cmd As New OleDb.OleDbCommand(q, cn)
        Using r = cmd.ExecuteReader()
          If r.Read() Then
  Dim kx = ReadInt(r.GetValue(0))
  Dim sx = ReadDouble(r.GetValue(1))
  Dim txObj = r.GetValue(2)

  Dim kxS As String = If(kx.HasValue, kx.Value.ToString(), "N/A")
  Dim sxS As String = If(sx.HasValue, sx.Value.ToString("0.000", CultureInfo.InvariantCulture), "N/A")
  Dim txS As String
  If TypeOf txObj Is DBNull Then
    txS = "N/A"
  Else
    Dim dt As Date = Convert.ToDateTime(txObj)
    txS = dt.ToString("dd MMM yyyy HH:mm")
  End If

  savedInfo = " | Tersimpan: K=" & kxS & ", Sil=" & sxS & ", " & txS
End If
  End Using
      End Using
        End Using

    Dim msg As String = "Clustering selesai. " &
                        "K optimal=" & If(kOpt.HasValue, kOpt.Value.ToString(), "N/A") & ", " &
                        "Silhouette=" & If(sil.HasValue, sil.Value.ToString("0.000"), "N/A") & savedInfo
    ScriptManager.RegisterStartupScript(Me, Me.GetType(), "cluster_ok",
      "alert('" & msg.Replace("'", "\'") & "');", True)

  Catch ex As Exception
    ScriptManager.RegisterStartupScript(Me, Me.GetType(), "cluster_err",
      "alert('Proses clustering gagal: " & ex.Message.Replace("'", "\'") & "');", True)
  End Try
End Sub


Protected Sub btnRegresi_Click(sender As Object, e As EventArgs)
  Try
    Dim fromY As Integer = CInt(ddlYearFrom.SelectedValue)
    Dim toY   As Integer = CInt(ddlYearTo.SelectedValue)
    If fromY > toY Then Dim tmp = fromY : fromY = toY : toY = tmp

    ' Jalankan SP → simpan chart_json + metrik ke dbo.fact_reg_tren
    RunRegresiLinier(fromY, toY, 3, True)

    ' — ringkasan hasil (AMAN untuk VB.NET) —
    Dim info As String = ""
    Using cn As New OleDb.OleDbConnection(ConnStar)
      cn.Open()

      Dim sqlSum As String = _
        "SELECT TOP 1 slope, intercept, r2, mae, rmse, mape, created_at " & _
        "FROM dbo.fact_reg_tren " & _
        "WHERE tahun_from=? AND tahun_to=? " & _
        "ORDER BY id_run DESC"

      Using c As New OleDb.OleDbCommand(sqlSum, cn)
        c.Parameters.Add("@a", OleDb.OleDbType.Integer).Value = fromY
        c.Parameters.Add("@b", OleDb.OleDbType.Integer).Value = toY

        Using r = c.ExecuteReader()
          If r.Read() Then
            Dim a As Double = Convert.ToDouble(r("intercept"))
            Dim b As Double = Convert.ToDouble(r("slope"))
            Dim r2 As Double = Convert.ToDouble(r("r2"))
            info = String.Format(" (α={0:0.###}, β={1:0.###}, R²={2:0.###})", a, b, r2)
          End If
        End Using
      End Using
    End Using

    ScriptManager.RegisterStartupScript(Me, Me.GetType(), "reg_ok", _
      "alert('Regresi selesai & tersimpan untuk " & fromY & "-" & toY & info & "');", True)

    'Response.Redirect("/dashboard_pmb/regresi.aspx", False)  ' jika ingin langsung lihat grafik
  Catch ex As Exception
    ScriptManager.RegisterStartupScript(Me, Me.GetType(), "reg_err", _
      "alert('Gagal menjalankan regresi: " & ex.Message.Replace("'", "\'") & "');", True)
  End Try
End Sub

'================= BIND GRID (No | Nama | Row) ====
Private Sub BindGridTableCounts()
  Dim dt As New DataTable()
  dt.Columns.Add("No", GetType(Integer))
  dt.Columns.Add("NamaTabel", GetType(String))
  dt.Columns.Add("JumlahRow", GetType(Long))

  Using cn As New OleDb.OleDbConnection(ConnStar)
    cn.Open()
    Dim i As Integer = 1
    For Each t In TableList
      Dim sql As String = "SELECT COUNT(*) FROM dbo." & t
      Using cmd As New OleDb.OleDbCommand(sql, cn)
        cmd.CommandTimeout = 0
        Dim rows As Long = CLng(cmd.ExecuteScalar())
        dt.Rows.Add(i, t, rows)
        i += 1
      End Using
    Next
  End Using

  gvTables.DataSource = dt
  gvTables.DataBind()
End Sub

'================= HELPER: SPLIT & RUN BATCHES ====
Private Sub RunSqlByBatches(fullSql As String)
  Dim batches = SplitBatches(fullSql)

  Using cn As New OleDbConnection(ConnStar)
    cn.Open()
    Dim tx = cn.BeginTransaction()
    Try
      For Each b In batches
        Dim trimmed As String = If(b, "").Trim()
        If trimmed.Length = 0 Then Continue For

        Using cmd As New OleDbCommand(trimmed, cn, tx)
          cmd.CommandTimeout = 0
          cmd.ExecuteNonQuery()
        End Using
      Next
      tx.Commit()
    Catch
      Try : tx.Rollback() : Catch : End Try
      Throw
    End Try
  End Using
End Sub

Private Function SplitBatches(sql As String) As List(Of String)
  ' Pisah di baris yang hanya berisi "GO"
  Dim list As New List(Of String)()
  Dim sb As New System.Text.StringBuilder()

  Dim lines = sql.Replace(vbCrLf, vbLf).Split(ControlChars.Lf)
  For Each line In lines
    If Regex.IsMatch(line, "^\s*GO\s*$", RegexOptions.IgnoreCase) Then
      If sb.Length > 0 Then
        list.Add(sb.ToString())
        sb.Clear()
      End If
    Else
      sb.AppendLine(line)
    End If
  Next
  If sb.Length > 0 Then list.Add(sb.ToString())
  Return list
End Function

'================= HELPER: JALANKAN SP KMEANS W/ OLE DB ==================
Private Sub RunKMeansSilhouette_Fixed(ByRef kOptimal As Integer?, ByRef silhouette As Double?)
  Using cn As New OleDb.OleDbConnection(ConnStar)
    cn.Open()
    Using cmd As New OleDb.OleDbCommand("EXEC dbo.sp_KMeansWilayah_Silhouette_2017_2023;", cn)
      cmd.CommandTimeout = 0
      Using rd = cmd.ExecuteReader()
        If rd.Read() Then
          kOptimal   = ReadInt(rd.GetValue(0))
          silhouette = ReadDouble(rd.GetValue(1))
        End If
      End Using
    End Using
  End Using
End Sub

'=== Jalankan SP Regresi (Chart JSON + metrik tersimpan ke fact_reg_tren) ===
Private Sub RunRegresiLinier(tFrom As Integer, tTo As Integer, _
                             Optional nForecast As Integer = 3, _
                             Optional useIndexX As Boolean = True)
  Using cn As New OleDb.OleDbConnection(ConnStar)
    cn.Open()
    ' OleDb pakai positional params (?), urutan HARUS sama.
    Using cmd As New OleDb.OleDbCommand(
      "EXEC dbo.sp_build_regresi_pmb @tahun_from=?, @tahun_to=?, @n_forecast=?, @use_index_x=?;", cn)
      cmd.CommandTimeout = 0
      cmd.Parameters.Add("@p1", OleDb.OleDbType.Integer).Value = tFrom
      cmd.Parameters.Add("@p2", OleDb.OleDbType.Integer).Value = tTo
      cmd.Parameters.Add("@p3", OleDb.OleDbType.Integer).Value = nForecast
      cmd.Parameters.Add("@p4", OleDb.OleDbType.Boolean).Value = If(useIndexX, 1, 0)
      cmd.ExecuteNonQuery()
    End Using
  End Using
End Sub

Private Function ReadInt(obj As Object) As Nullable(Of Integer)
  If obj Is Nothing OrElse TypeOf obj Is DBNull Then Return Nothing
  If TypeOf obj Is Integer OrElse TypeOf obj Is Int16 OrElse TypeOf obj Is Int64 OrElse TypeOf obj Is Decimal Then
    Return Convert.ToInt32(obj)
  End If
  Dim s = obj.ToString().Trim()
  Dim v As Integer
  If Integer.TryParse(s, v) Then Return v
  Dim d As Double
  If Double.TryParse(s, NumberStyles.Any, CultureInfo.InvariantCulture, d) Then Return Convert.ToInt32(Math.Round(d))
  Return Nothing
End Function

Private Function ReadDouble(obj As Object) As Nullable(Of Double)
  If obj Is Nothing OrElse TypeOf obj Is DBNull Then Return Nothing
  If TypeOf obj Is Double OrElse TypeOf obj Is Single OrElse TypeOf obj Is Decimal Then
    Return Convert.ToDouble(obj, CultureInfo.InvariantCulture)
  End If
  Dim s = obj.ToString().Trim()
  Dim d As Double
  If Double.TryParse(s, NumberStyles.Any, CultureInfo.InvariantCulture, d) Then Return d
  If Double.TryParse(s, NumberStyles.Any, CultureInfo.GetCultureInfo("id-ID"), d) Then Return d
  Return Nothing
End Function


'================= BANGUN SQL ETL (pakai & + vbCrLf) ====
Private Function BuildEtlSql() As String
  Dim sql As String = ""

  sql = sql & _
"USE star_schema_pmb;" & vbCrLf & _
"GO" & vbCrLf & _
"/* ==== DROP FK dari FACT_PMB ==== */" & vbCrLf & _
"ALTER TABLE fact_pmb DROP CONSTRAINT IF EXISTS FK_fact_pmb_dim_waktu;" & vbCrLf & _
"ALTER TABLE fact_pmb DROP CONSTRAINT IF EXISTS FK_fact_pmb_dim_prodi;" & vbCrLf & _
"ALTER TABLE fact_pmb DROP CONSTRAINT IF EXISTS FK_fact_pmb_dim_wilayah;" & vbCrLf & _
"ALTER TABLE fact_pmb DROP CONSTRAINT IF EXISTS FK_fact_pmb_dim_wilayah_id;" & vbCrLf & _
"ALTER TABLE fact_pmb DROP CONSTRAINT IF EXISTS FK_fact_pmb_dim_jurusan_sekolah;" & vbCrLf & _
"ALTER TABLE fact_pmb DROP CONSTRAINT IF EXISTS FK_fact_pmb_dim_gender;" & vbCrLf & _
"ALTER TABLE fact_pmb DROP CONSTRAINT IF EXISTS FK_fact_pmb_dim_sekolah;" & vbCrLf & _
"/* ==== DROP FK dari FACT_KPI_MABA ==== */" & vbCrLf & _
"ALTER TABLE fact_kpi_maba DROP CONSTRAINT IF EXISTS FK_fact_kpi_maba_dim_waktu;" & vbCrLf & _
"ALTER TABLE fact_kpi_maba DROP CONSTRAINT IF EXISTS FK_fact_kpi_maba_dim_prodi;" & vbCrLf & _
"PRINT 'Semua FK dari fact_pmb & fact_kpi_maba sudah di-drop.';" & vbCrLf & _
"GO" & vbCrLf & _
"/* ==== DROP Isi ==== */" & vbCrLf & _
"TRUNCATE TABLE fact_pmb;" & vbCrLf & _
"TRUNCATE TABLE fact_kpi_maba;" & vbCrLf & _
"TRUNCATE TABLE dim_waktu;" & vbCrLf & _
"TRUNCATE TABLE dim_prodi;" & vbCrLf & _
"TRUNCATE TABLE dim_jurusan_sekolah;" & vbCrLf & _
"TRUNCATE TABLE dim_gender;" & vbCrLf & _
"TRUNCATE TABLE dim_wilayah;" & vbCrLf & _
"TRUNCATE TABLE dim_sekolah;" & vbCrLf & _
"PRINT 'Semua tabel dimensi & fakta dikosongkan.';" & vbCrLf & _
"GO" & vbCrLf & _
"-- LOAD DIMENSI" & vbCrLf & _
"/* ==== Dim Waktu (2017-2023) ==== */" & vbCrLf & _
"INSERT INTO dim_waktu (id_waktu, tahun, start_date, end_date)" & vbCrLf & _
"VALUES" & vbCrLf & _
"(2017, 2017, '2017-01-01', '2017-12-31')," & vbCrLf & _
"(2018, 2018, '2018-01-01', '2018-12-31')," & vbCrLf & _
"(2019, 2019, '2019-01-01', '2019-12-31')," & vbCrLf & _
"(2020, 2020, '2020-01-01', '2020-12-31')," & vbCrLf & _
"(2021, 2021, '2021-01-01', '2021-12-31')," & vbCrLf & _
"(2022, 2022, '2022-01-01', '2022-12-31')," & vbCrLf & _
"(2023, 2023, '2023-01-01', '2023-12-31');" & vbCrLf & _
"/* ==== Dim Prodi (dari Pmbregol.tjurus) ==== */" & vbCrLf & _
"INSERT INTO dim_prodi (kd_jur, nm_jur, nm_fak, kode_jurnim)" & vbCrLf & _
"SELECT DISTINCT kd_jur, nm_jur, nm_fak, kode_jurnim" & vbCrLf & _
"FROM Pmbregol.dbo.tjurus;" & vbCrLf & _
"/* ==== Dim Jurusan Sekolah ==== */" & vbCrLf & _
"INSERT INTO dim_jurusan_sekolah (kd_jursek, nm_jursek)" & vbCrLf & _
"SELECT DISTINCT kd_jursek, nm_jursek" & vbCrLf & _
"FROM Pmbregol.dbo.t_jursek;" & vbCrLf & _
"/* ==== Dim Gender ==== */" & vbCrLf & _
"INSERT INTO dim_gender (kd_gender, nm_gender)" & vbCrLf & _
"VALUES ('L', 'Laki-laki'), ('P', 'Perempuan'), ('U', 'Tidak diketahui');" & vbCrLf & _
"/* ==== Dim Wilayah (Raw Wilayah) ==== */" & vbCrLf & _
"INSERT INTO dim_wilayah (id_wil, id_negara, nm_wil, id_induk_wilayah, id_level_wil, kd_wil)" & vbCrLf & _
"SELECT DISTINCT id_wil, id_negara, nm_wil, id_induk_wilayah, id_level_wil, kd_wil" & vbCrLf & _
"FROM Pmbregol.dbo.wilayah;" & vbCrLf & _
"/* ==== Dim Sekolah ==== */" & vbCrLf & _
"INSERT INTO dim_sekolah (nm_sekolah)" & vbCrLf & _
"SELECT DISTINCT nama_sekolah FROM Pmbregol.dbo.data_sekolah WHERE nama_sekolah IS NOT NULL;" & vbCrLf & _
"INSERT INTO dim_sekolah (nm_sekolah) VALUES ('(Tidak diketahui)');" & vbCrLf & _
"GO" & vbCrLf & _
"/* ==== fact_pmb ==== */" & vbCrLf & _
"CREATE OR ALTER VIEW dbo.vw_src_pmb AS" & vbCrLf & _
"SELECT b.no_reg, b.nim, TRY_CAST(b.tahun AS INT) AS tahun_lulus, b.kd_propinsi, b.jk, b.kd_jur, ds.nama_sekolah" & vbCrLf & _
"FROM Pmbregol.dbo.biodata b" & vbCrLf & _
"LEFT JOIN Pmbregol.dbo.data_sekolah ds ON ds.no_reg = b.no_reg;" & vbCrLf & _
"GO" & vbCrLf & _
";WITH src AS (" & vbCrLf & _
"    SELECT no_reg, nim, tahun_lulus, kd_propinsi, jk, kd_jur, nama_sekolah," & vbCrLf & _
"           ROW_NUMBER() OVER (PARTITION BY no_reg, tahun_lulus ORDER BY no_reg) AS rn" & vbCrLf & _
"    FROM dbo.vw_src_pmb" & vbCrLf & _
"    WHERE tahun_lulus BETWEEN 2017 AND 2023" & vbCrLf & _
")" & vbCrLf & _
"INSERT INTO fact_pmb (" & vbCrLf & _
"      no_reg, nim, id_waktu, kd_jur, kd_wil, kd_jursek, kd_gender, tahun_lulus, id_sekolah, id_wil)" & vbCrLf & _
"SELECT s.no_reg, s.nim," & vbCrLf & _
"       w.id_waktu," & vbCrLf & _
"       s.kd_jur," & vbCrLf & _
"       wila.kd_wil," & vbCrLf & _
"       NULL AS kd_jursek," & vbCrLf & _
"       CASE s.jk WHEN 1 THEN 'L' WHEN 2 THEN 'P' ELSE 'U' END AS kd_gender," & vbCrLf & _
"       s.tahun_lulus," & vbCrLf & _
"       ISNULL(sek.id_sekolah, (SELECT TOP 1 id_sekolah FROM dim_sekolah WHERE nm_sekolah = '(Tidak diketahui)')) AS id_sekolah," & vbCrLf & _
"       wila.id_wil" & vbCrLf & _
"FROM src AS s" & vbCrLf & _
"JOIN dim_waktu AS w  ON w.tahun = s.tahun_lulus" & vbCrLf & _
"LEFT JOIN dim_wilayah AS wila ON wila.kd_wil = s.kd_propinsi" & vbCrLf & _
"LEFT JOIN dim_sekolah AS sek  ON sek.nm_sekolah = s.nama_sekolah" & vbCrLf & _
"WHERE s.rn = 1;" & vbCrLf & _
"GO" & vbCrLf & _
"/* ==== isi wilayah di star  ==== */" & vbCrLf & _
"WITH map_wil AS (" & vbCrLf & _
"    SELECT v.id_wil, v.kd_wil FROM (VALUES" & vbCrLf & _
"        ('010000','09'),('020000','10'),('030000','11'),('040000','12'),('050000','13')," & vbCrLf & _
"        ('060000','01'),('070000','02'),('080000','03'),('090000','04'),('100000','05')," & vbCrLf & _
"        ('110000','06'),('120000','08'),('130000','14'),('140000','15'),('150000','17')," & vbCrLf & _
"        ('160000','16'),('170000','18'),('180000','19'),('190000','21'),('200000','20')," & vbCrLf & _
"        ('210000','25'),('220000','22'),('230000','23'),('240000','24'),('250000','26')," & vbCrLf & _
"        ('260000','07'),('270000','29'),('280000','30'),('290000','31'),('300000','32')," & vbCrLf & _
"        ('310000','34'),('320000','27'),('330000','33'),('340000','28')" & vbCrLf & _
"    ) AS v(id_wil, kd_wil)" & vbCrLf & _
")" & vbCrLf & _
"UPDATE f SET f.id_wil = m.id_wil, f.kd_wil = m.kd_wil" & vbCrLf & _
"FROM fact_pmb AS f" & vbCrLf & _
"JOIN Pmbregol.dbo.biodata AS b ON b.no_reg = f.no_reg" & vbCrLf & _
"JOIN map_wil AS m ON b.kd_propinsi = m.id_wil" & vbCrLf & _
"WHERE f.id_wil IS NULL;" & vbCrLf & _
"UPDATE b" & vbCrLf & _
"SET id_wil = v.id_wil" & vbCrLf & _
"FROM star_schema_pmb.dbo.fact_pmb AS b" & vbCrLf & _
"CROSS APPLY (" & vbCrLf & _
"    SELECT TOP 1 id_wil FROM (" & vbCrLf & _
"        VALUES" & vbCrLf & _
"        ('010000'),('020000'),('030000'),('040000'),('050000')," & vbCrLf & _
"        ('060000'),('070000'),('080000'),('090000'),('100000')," & vbCrLf & _
"        ('110000'),('120000'),('130000'),('140000'),('150000')," & vbCrLf & _
"        ('160000'),('170000'),('180000'),('190000'),('200000')," & vbCrLf & _
"        ('210000'),('220000'),('230000'),('240000'),('250000')," & vbCrLf & _
"        ('260000'),('270000'),('280000'),('290000'),('300000')," & vbCrLf & _
"        ('310000'),('320000'),('330000'),('340000')" & vbCrLf & _
"    ) AS w(id_wil)" & vbCrLf & _
"    ORDER BY NEWID()" & vbCrLf & _
") AS v" & vbCrLf & _
"WHERE b.id_wil IS NULL;" & vbCrLf & _
"UPDATE f" & vbCrLf & _
"SET kd_wil = v.kd_wil" & vbCrLf & _
"FROM star_schema_pmb.dbo.fact_pmb AS f" & vbCrLf & _
"CROSS APPLY (" & vbCrLf & _
"    SELECT TOP 1 kd_wil FROM (" & vbCrLf & _
"        VALUES" & vbCrLf & _
"        ('09'),('10'),('11'),('12'),('13')," & vbCrLf & _
"        ('01'),('02'),('03'),('04'),('05')," & vbCrLf & _
"        ('06'),('08'),('14'),('15'),('17')," & vbCrLf & _
"        ('16'),('18'),('19'),('21'),('20')," & vbCrLf & _
"        ('25'),('22'),('23'),('24'),('26')," & vbCrLf & _
"        ('07'),('29'),('30'),('31'),('32')," & vbCrLf & _
"        ('34'),('27'),('33'),('28')" & vbCrLf & _
"    ) AS w(kd_wil)" & vbCrLf & _
"    ORDER BY NEWID()" & vbCrLf & _
") AS v" & vbCrLf & _
"WHERE f.kd_wil IS NULL;" & vbCrLf & _
"/* ==== FK yang belum ada  ==== */" & vbCrLf & _
"IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_fact_pmb_dim_waktu' AND parent_object_id = OBJECT_ID('dbo.fact_pmb'))" & vbCrLf & _
"BEGIN" & vbCrLf & _
"    ALTER TABLE fact_pmb ADD CONSTRAINT FK_fact_pmb_dim_waktu FOREIGN KEY (id_waktu) REFERENCES dim_waktu(id_waktu);" & vbCrLf & _
"END" & vbCrLf & _
"GO" & vbCrLf & _
"IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_fact_pmb_dim_prodi' AND parent_object_id = OBJECT_ID('dbo.fact_pmb'))" & vbCrLf & _
"BEGIN" & vbCrLf & _
"    ALTER TABLE fact_pmb ADD CONSTRAINT FK_fact_pmb_dim_prodi FOREIGN KEY (kd_jur) REFERENCES dim_prodi(kd_jur);" & vbCrLf & _
"END" & vbCrLf & _
"GO" & vbCrLf & _
"IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_fact_pmb_dim_gender' AND parent_object_id = OBJECT_ID('dbo.fact_pmb'))" & vbCrLf & _
"BEGIN" & vbCrLf & _
"    ALTER TABLE fact_pmb ADD CONSTRAINT FK_fact_pmb_dim_gender FOREIGN KEY (kd_gender) REFERENCES dim_gender(kd_gender);" & vbCrLf & _
"END" & vbCrLf & _
"GO" & vbCrLf & _
"IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_fact_pmb_dim_sekolah' AND parent_object_id = OBJECT_ID('dbo.fact_pmb'))" & vbCrLf & _
"BEGIN" & vbCrLf & _
"    ALTER TABLE fact_pmb ADD CONSTRAINT FK_fact_pmb_dim_sekolah FOREIGN KEY (id_sekolah) REFERENCES dim_sekolah(id_sekolah);" & vbCrLf & _
"END" & vbCrLf & _
"GO" & vbCrLf & _
"IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_fact_pmb_dim_wilayah' AND parent_object_id = OBJECT_ID('dbo.fact_pmb'))" & vbCrLf & _
"BEGIN" & vbCrLf & _
"    ALTER TABLE fact_pmb ADD CONSTRAINT FK_fact_pmb_dim_wilayah FOREIGN KEY (id_wil) REFERENCES dim_wilayah(id_wil);" & vbCrLf & _
"END" & vbCrLf & _
"GO" & vbCrLf
  Return sql
End Function
</script>

<section class="content-header">
  <h1>Master Data</h1>
  <ol class="breadcrumb">
    <li><a href="/utama.aspx"><i class="fa fa-dashboard"></i> Beranda</a></li>
    <li class="active">Master Data</li>
  </ol>
</section>

<section class="content">
  <!-- PERINGATAN -->
  <div class="alert alert-warn">
    <strong>Peringatan:</strong>
    Saat memperbarui data, semua data akan direset dan dashboard hanya akan menampilkan data untuk tahun yang dipilih. Saat memproses clustering dan regresi linier hanya akan memproses data 2017-2023.
    <div class="mt-6"><strong>Tahun tersedia saat ini:</strong> <span id="yearMax"><asp:Literal ID="litYearMax" runat="server" /></span></div>
  </div>

  <!-- FILTER + TOMBOL (kiri-kanan) -->
  <div class="filters flex-split">
    <!-- LEFT: only year filters -->
    <div class="left">
      <div class="field">
        <label>Tahun Awal:</label>
        <asp:DropDownList ID="ddlYearFrom" runat="server" CssClass="form-control input-sm"
          AutoPostBack="true" OnSelectedIndexChanged="OnYearChanged" />
      </div>
      <div class="field">
        <label>Tahun Akhir:</label>
        <asp:DropDownList ID="ddlYearTo" runat="server" CssClass="form-control input-sm"
          AutoPostBack="true" OnSelectedIndexChanged="OnYearChanged" />
      </div>
    </div>

    <!-- RIGHT: buttons + meta right-aligned -->
    <div class="right">
      <div class="btns">
        <asp:Button ID="btnPerbarui"    runat="server" Text="Perbarui Data"
                    CssClass="btn-chip btn-etl" OnClick="btnPerbarui_Click" />
        <asp:Button ID="btnProcCluster" runat="server" Text="Proses Clustering"
                    CssClass="btn-chip btn-cluster" OnClick="btnClustering_Click" />
        <asp:Button ID="btnProcReg"     runat="server" Text="Proses Regresi Linier"
                    CssClass="btn-chip btn-regresi" OnClick="btnRegresi_Click" />
      </div>
      <div class="meta-right">
        <span class="dot"></span>
        Terakhir diperbarui: <strong><asp:Literal ID="litLastUpdated" runat="server" /></strong>
        <span class="sep">|</span>
        Status: <span class="status">Idle</span>
      </div>
    </div>
  </div>

  <!-- TABEL: tambah garis kolom -->
  <div class="box box-primary">
    <div class="box-header with-border">
      <h3 class="box-title">Ringkasan Tabel Star Schema PMB</h3>
    </div>
    <div class="box-body">
      <asp:GridView ID="gvTables" runat="server" AutoGenerateColumns="False"
        CssClass="table table-md table-lined" GridLines="None" ShowHeaderWhenEmpty="True">
        <Columns>
          <asp:BoundField DataField="No"        HeaderText="No" ItemStyle-Width="70"
                          ItemStyle-HorizontalAlign="Center" />
          <asp:BoundField DataField="NamaTabel" HeaderText="Nama Tabel" />
          <asp:BoundField DataField="JumlahRow" HeaderText="Jumlah Row"
                          DataFormatString="{0:N0}" ItemStyle-HorizontalAlign="Right" />
        </Columns>
        <HeaderStyle CssClass="tbl-head" />
        <RowStyle CssClass="tbl-row" />
        <AlternatingRowStyle CssClass="tbl-row alt" />
      </asp:GridView>
    </div>
  </div>
</section>

<style>
/* ===== Banner peringatan ===== */
.alert-warn{
  background:#f59e0b; color:#111; padding:14px 16px; border-radius:8px;
  font-weight:600; box-shadow:0 2px 8px rgba(0,0,0,.06); margin-bottom:14px;
}
.alert-warn .mt-6{ margin-top:6px; }

/* split kiri-kanan */
.flex-split{
  display:flex; justify-content:space-between; align-items:flex-start;
  gap:16px; flex-wrap:wrap; margin:8px 0 12px;
}
.flex-split .left{ display:flex; gap:14px; flex-wrap:wrap; }
.flex-split .left .field label{ display:block; font-weight:600; margin-bottom:4px; }

.flex-split .right{ margin-left:auto; text-align:right; }
.flex-split .right .btns{ display:flex; gap:10px; justify-content:flex-end; margin-bottom:6px; }
.meta-right{ color:#555; font-size:13.5px; }
.meta-right .dot{ display:inline-block; width:8px; height:8px; border-radius:999px; background:#22c55e; margin:0 6px 1px 0; }
.meta-right .sep{ margin:0 8px; color:#bbb; }
.meta-right .status{ font-weight:700; }

/* tombol tetap berwarna (bukan hitam) */
.btn-chip{
  color:#fff; border:0; border-radius:10px; padding:10px 16px; font-weight:800; letter-spacing:.2px;
  box-shadow:0 2px 8px rgba(0,0,0,.18); transition:background-color .18s ease, transform .02s ease;
}
.btn-chip:active{ transform:translateY(1px); }
.btn-etl{ background:#0ea5e9; }      .btn-etl:hover{ background:#0284c7; }
.btn-cluster{ background:#8b5cf6; }  .btn-cluster:hover{ background:#7c3aed; }
.btn-regresi{ background:#22c55e; }  .btn-regresi:hover{ background:#16a34a; }

/* header tabel */
.table-md{ width:100%; border-collapse:separate; border-spacing:0; }
.tbl-head{ background:#2f78a8; color:#fff; }

/* GARIS KOLOM + BARIS */
.table-lined{ border:1px solid #dce7f2; border-radius:6px; overflow:hidden; }
.table-lined .tbl-head th{ border-right:1px solid #c8d8e8; }
.table-lined .tbl-row td{
  border-top:1px solid #e7eef6;
  border-right:1px solid #e7eef6;   /* garis kolom */
  padding:10px 12px;
}
.table-lined .tbl-row td:last-child,
.table-lined .tbl-head th:last-child{ border-right:none; }
.table-lined .tbl-row.alt{ background:#f9fbff; }
</style>
