<!-- #INCLUDE file = "/path/to/your/page_or_master.aspx" --> 'NOTE: include file tergantung modul / layout aplikasi (internal).

<script runat="server">
'============= STATE ====================
' range filter
Private TahunFrom As Integer = 0
Private TahunTo   As Integer = 0
Private Const PRODI_ALL As String = "(Semua Prodi)"
Private SelectedProdi As String = PRODI_ALL      
Private SelectedProdiText As String = PRODI_ALL 

Public PctRealisasiText As String = ""
Public PctSisaText As String = ""
Public SisaAbs As Integer = 0


'================= UTIL =================
Private Function PrettyFak(raw As String) As String
    If String.IsNullOrWhiteSpace(raw) Then Return raw
    If raw.Equals("Tidak Terpetakan", StringComparison.OrdinalIgnoreCase) Then Return raw
    Dim ti As System.Globalization.TextInfo = New System.Globalization.CultureInfo("id-ID", False).TextInfo
    Dim s As String = ti.ToTitleCase(raw.ToLowerInvariant())
    s = s.Replace(" Dan ", " dan ")
    Return "Fakultas " & s
End Function

Protected Function IsNonEmpty(o As Object) As Boolean
    Return o IsNot Nothing AndAlso Not String.IsNullOrEmpty(o.ToString())
End Function

Public chartConfigJson As String = ""
Public gaugeConfigJson As String = ""
Private Shared rng As New System.Random()

Private Sub EnsureRangeOrder()
    If TahunFrom > TahunTo Then
        Dim t = TahunFrom : TahunFrom = TahunTo : TahunTo = t
    End If
End Sub

Private Sub PopulateYearFilters()
    Const MIN_FIX As Integer = 2017
    Const MAX_FIX As Integer = 2060

    Dim minY As Integer = 0, maxY As Integer = 0
    Using cs As New OleDb.OleDbConnection(ConnStar)
        cs.Open()
        ' ambil rentang tahun yang muncul di fact
        Using cmd As New OleDb.OleDbCommand( _
        "SELECT MIN(w.tahun), MAX(w.tahun) " & _
        "FROM fact_pmb f JOIN dim_waktu w ON w.id_waktu=f.id_waktu " & _
        "WHERE w.tahun BETWEEN ? AND ?", cs)
            cmd.Parameters.AddWithValue("@p1", MIN_FIX)
            cmd.Parameters.AddWithValue("@p2", MAX_FIX)
            Using rd = cmd.ExecuteReader()
                If rd.Read() Then
                    If Not rd.IsDBNull(0) Then minY = CInt(rd.GetValue(0))
                    If Not rd.IsDBNull(1) Then maxY = CInt(rd.GetValue(1))
                End If
            End Using
        End Using
    End Using

    If minY = 0 Then minY = MIN_FIX
    If maxY = 0 Then maxY = Math.Min(MAX_FIX, DateTime.Now.Year)

    ddlYearFrom.Items.Clear() : ddlYearTo.Items.Clear()
    For y As Integer = maxY To minY Step -1
        Dim it As New ListItem(y.ToString(), y.ToString())
        ddlYearFrom.Items.Add(it) : ddlYearTo.Items.Add(it)
    Next

    Dim defFrom As Integer = If(ViewState("YFROM") Is Nothing, minY, CInt(ViewState("YFROM")))
    Dim defTo   As Integer = If(ViewState("YTO")   Is Nothing, maxY, CInt(ViewState("YTO")))
    If defFrom > defTo Then Dim t = defFrom : defFrom = defTo : defTo = t

    ddlYearFrom.SelectedValue = defFrom.ToString()
    ddlYearTo.SelectedValue   = defTo.ToString()
    TahunFrom = defFrom : TahunTo = defTo
End Sub

Private Sub PopulateProdiFilter()
    Dim rows As New List(Of Tuple(Of String,String,String))() ' (kd_jur, nm_jur, nm_fak)
    Using cs As New OleDb.OleDbConnection(ConnStar)
        cs.Open()
        Dim sql = "SELECT DISTINCT LTRIM(RTRIM(kd_jur)) AS kd, " &
                  "       ISNULL(nm_jur,'(Tanpa Nama)') AS jur, " &
                  "       ISNULL(nm_fak,'Tidak Terpetakan') AS fak " &
                  "FROM dim_prodi ORDER BY fak, jur"
        Using cmd As New OleDb.OleDbCommand(sql, cs)
            Using rd = cmd.ExecuteReader()
                While rd.Read()
                    rows.Add(Tuple.Create(rd("kd").ToString(), rd("jur").ToString(), rd("fak").ToString()))
                End While
            End Using
        End Using
    End Using

    ddlProdi.Items.Clear()
    ddlProdi.Items.Add(New ListItem(PRODI_ALL, PRODI_ALL))
    For Each r In rows
        Dim txt = r.Item2 & " - " & PrettyFak(r.Item3).Replace("Fakultas ","")
        ddlProdi.Items.Add(New ListItem(txt, r.Item1))
    Next

    Dim defKd As String = If(ViewState("PRODI_KD") Is Nothing, PRODI_ALL, ViewState("PRODI_KD").ToString())
    Dim defTx As String = If(ViewState("PRODI_TX") Is Nothing, PRODI_ALL, ViewState("PRODI_TX").ToString())

    If ddlProdi.Items.FindByValue(defKd) Is Nothing Then
        defKd = PRODI_ALL : defTx = PRODI_ALL
    End If
    ddlProdi.SelectedValue = defKd
    SelectedProdi = defKd : SelectedProdiText = defTx
End Sub


'============= KONN =====================

Private ReadOnly ConnPmb  As String =
  "Provider=SQLOLEDB;Data Source=<DB_HOST>,<PORT>;Initial Catalog=<PMB_DB_NAME>;User ID=<DB_USER>;Password=<DB_PASS>;"
Private ReadOnly ConnStar As String =
  "Provider=SQLOLEDB;Data Source=<DB_HOST>,<PORT>;Initial Catalog=<STAR_DB_NAME>;User ID=<DB_USER>;Password=<DB_PASS>;"

'============= STATE ====================
Private TahunAktif As Integer = 0
Private TotalRealisasi As Integer = 0
Private TotalTarget As Integer = 0

Sub Page_Load(sender As Object, e As EventArgs)
    If Not Page.IsPostBack Then
        ResolveTahunAktif()                ' set TahunAktif (untuk default)
        PopulateYearFilters()              ' isi ddl + set TahunFrom/TahunTo
        PopulateProdiFilter()
        EnsureRangeOrder()
        LoadHeaderTiles()
        BuildGauges()
        BuildCharts()
    Else
        ' pada postback, ambil dari ViewState jika ada
        If ViewState("YFROM") IsNot Nothing Then TahunFrom = CInt(ViewState("YFROM"))
        If ViewState("YTO")   IsNot Nothing Then TahunTo   = CInt(ViewState("YTO"))
        If ViewState("PRODI_KD") IsNot Nothing Then SelectedProdi = ViewState("PRODI_KD").ToString()
        If ViewState("PRODI_TX") IsNot Nothing Then SelectedProdiText = ViewState("PRODI_TX").ToString()
        EnsureRangeOrder()
    End If
End Sub

Protected Sub OnYearChanged(sender As Object, e As EventArgs)
    ' Ambil nilai dari dropdown
    TahunFrom = CInt(ddlYearFrom.SelectedValue)
    TahunTo   = CInt(ddlYearTo.SelectedValue)

    ' Pastikan urutan benar (From <= To)
    EnsureRangeOrder()

    ' Simpan ke ViewState agar persist di postback berikutnya
    ViewState("YFROM") = TahunFrom
    ViewState("YTO")   = TahunTo

    ' Rebind semua komponen yang bergantung pada rentang tahun
    LoadHeaderTiles()
    BuildGauges()
    BuildCharts()
End Sub

Protected Sub OnProdiChanged(sender As Object, e As EventArgs)
    SelectedProdi = ddlProdi.SelectedValue
    SelectedProdiText = ddlProdi.SelectedItem.Text
    ViewState("PRODI_KD") = SelectedProdi
    ViewState("PRODI_TX") = SelectedProdiText
    LoadHeaderTiles()
    BuildGauges()
    BuildCharts()
End Sub

Private Function AppendProdiFilter(sql As String, aliasObj As String) As String
    If String.IsNullOrEmpty(SelectedProdi) OrElse SelectedProdi = PRODI_ALL Then Return sql
    Return sql & " AND LTRIM(RTRIM(" & aliasObj & ".kd_jur)) = ? "
End Function

Private Sub AddProdiParamIfNeeded(cmd As OleDb.OleDbCommand)
    If String.IsNullOrEmpty(SelectedProdi) OrElse SelectedProdi = PRODI_ALL Then Exit Sub
    cmd.Parameters.AddWithValue("@pkjur", SelectedProdi)
End Sub

'----------------------------------------
' Tentukan tahun aktif
'----------------------------------------
Private Sub ResolveTahunAktif()
    If Not String.IsNullOrEmpty(Request("tahun")) AndAlso IsNumeric(Request("tahun")) Then
        TahunAktif = Convert.ToInt32(Request("tahun")) : Exit Sub
    End If

    Using cs As New OleDb.OleDbConnection(ConnStar)
        cs.Open()
        Using cmd As New OleDb.OleDbCommand( _
        "SELECT MAX(w.tahun) FROM fact_pmb f JOIN dim_waktu w ON w.id_waktu=f.id_waktu", cs)
            Dim v = cmd.ExecuteScalar()
            If v IsNot DBNull.Value AndAlso v IsNot Nothing Then TahunAktif = Convert.ToInt32(v)
        End Using
    End Using

    If TahunAktif = 0 Then TahunAktif = DateTime.Now.Year
End Sub

'----------------------------------------
' HEADER: 2 label (Realisasi & Target)
'----------------------------------------
Private Sub LoadHeaderTiles()
    Dim tiles As New List(Of Object)()

    ' Reailisasi (DW)
        Dim sqlR = "SELECT COUNT(*) " &
                "FROM fact_pmb f " &
                "JOIN dim_waktu w ON w.id_waktu=f.id_waktu " &
                "LEFT JOIN dim_prodi dp ON dp.kd_jur=f.kd_jur " &
                "WHERE w.tahun BETWEEN ? AND ? AND f.kd_jur IS NOT NULL"
        sqlR = AppendProdiFilter(sqlR, "dp")
        Using cs As New OleDb.OleDbConnection(ConnStar)
            cs.Open()
            Using cmd As New OleDb.OleDbCommand(sqlR, cs)
                cmd.Parameters.AddWithValue("@p1", TahunFrom)
                cmd.Parameters.AddWithValue("@p2", TahunTo)
                AddProdiParamIfNeeded(cmd)
                TotalRealisasi = CInt(cmd.ExecuteScalar())
            End Using
        End Using

    ' Target (kpi_maba)
        Dim sqlT = "SELECT ISNULL(SUM(k.target_total),0) " &
                "FROM kpi_maba k " &
                "LEFT JOIN star_schema_pmb.dbo.dim_prodi dp ON " &
                "  LTRIM(RTRIM(k.kd_jur)) = LTRIM(RTRIM(dp.kd_jur)) " &
                "  OR LTRIM(RTRIM(k.kd_jur)) = LTRIM(RTRIM(dp.kode_jurnim)) " &
                "WHERE k.tahun BETWEEN ? AND ?"
        sqlT = AppendProdiFilter(sqlT, "dp")
        Using cp As New OleDb.OleDbConnection(ConnPmb)
            cp.Open()
            Using cmd As New OleDb.OleDbCommand(sqlT, cp)
                cmd.Parameters.AddWithValue("@p1", TahunFrom)
                cmd.Parameters.AddWithValue("@p2", TahunTo)
                AddProdiParamIfNeeded(cmd)
                TotalTarget = CInt(cmd.ExecuteScalar())
            End Using
        End Using



    Dim rentang As String = If(TahunFrom = TahunTo, TahunTo.ToString(), TahunFrom & "-" & TahunTo)
    tiles.Add(New With {.Total = TotalRealisasi.ToString("N0"), .Title = "Realisasi Pendaftaran " & rentang,
                        .ColorClass = "tile-sky", .Icon="fa-solid fa-users",
                        .ColClass="col-lg-4 col-md-4 col-sm-6 col-xs-12"})
    tiles.Add(New With {.Total = TotalTarget.ToString("N0"), .Title = "Target KPI MABA " & rentang,
                        .ColorClass = "tile-red", .Icon="fa-solid fa-bullseye",
                        .ColClass="col-lg-4 col-md-4 col-sm-6 col-xs-12"})
    rptDashboard.DataSource = tiles
    rptDashboard.DataBind()
End Sub

'----------------------------------------
' GAUGES: capaian (%) dan sisa (%)
'----------------------------------------
Private Sub BuildGauges()
    Dim realisasi As Integer = TotalRealisasi
    Dim target As Integer = Math.Max(TotalTarget, 1)

    ' === hitung persen utk footer ===
    Dim pct As Decimal = CDec(realisasi) / CDec(target) * 100D
    Dim pctClamped As Integer = CInt(Math.Min(100D, Math.Round(pct)))
    Dim sisaPct As Integer = 100 - pctClamped

    Dim ci = System.Globalization.CultureInfo.GetCultureInfo("id-ID")
    SisaAbs = Math.Max(target - realisasi, 0)
    PctRealisasiText = pct.ToString("0.0", ci) & "%"
    PctSisaText      = Math.Max(0D, 100D - pct).ToString("0.0", ci) & "%"

    ' === gauge tampilkan komposisi persen (tanpa teks tengah) ===
    gaugeConfigJson =
        "{" &
        """id"":""gaugeProgress""," &
        """type"":""doughnut""," &
        """data"":{""labels"":[""Realisasi"",""Sisa Target""],""datasets"":[{""data"":[" &
            pctClamped.ToString() & "," & sisaPct.ToString() &
        "]}]}" &
        "}"
End Sub


Private Function BuildGauge(id As String, title As String, value As Double) As String
    Dim val As Integer = CInt(Math.Round(value))
    Dim rest As Integer = Math.Max(0, 100 - val)
    Dim data As String = "[" & val.ToString() & "," & rest.ToString() & "]"
    Dim labels As String = "[""Progress"",""Sisa""]"
    Return "{" &
        """id"":""" & id & """," &
        """type"":""doughnut""," &
        """title"":""" & title & """," &
        """data"":{""labels"":" & labels & ",""datasets"":[{""data"":" & data & "}]}" &
    "}"
End Function

'----------------------------------------
' CHARTS: Bar Fakultas (Target vs Realisasi),
'         Pie Gender, Top-10 Sekolah, Top-10 Provinsi
'----------------------------------------
Private Sub BuildCharts()
    '----- hanya yang dipakai -----
    Dim yearLabels As New List(Of Integer)()
    Dim yearReal As New List(Of Integer)()
    Dim yearTarget As New List(Of Integer)()

    Dim pieGenderLabels As New List(Of String)()
    Dim pieGenderValues As New List(Of Integer)()

    Dim topSekolahLabels As New List(Of String)()
    Dim topSekolahValues As New List(Of Integer)()

    Dim topProvLabels As New List(Of String)()
    Dim topProvValues As New List(Of Integer)()

    '===== Realisasi per tahun (DW) =====
    Dim dictRealYear As New Dictionary(Of Integer, Integer)()
    Using cs As New OleDb.OleDbConnection(ConnStar)
        cs.Open()
        Dim sql = "SELECT w.tahun, COUNT(*) AS jml " &
                  "FROM fact_pmb f " &
                  "JOIN dim_waktu w ON w.id_waktu=f.id_waktu " &
                  "LEFT JOIN dim_prodi dp ON dp.kd_jur=f.kd_jur " &
                  "WHERE w.tahun BETWEEN ? AND ? AND f.kd_jur IS NOT NULL "
        sql = AppendProdiFilter(sql, "dp") & "GROUP BY w.tahun ORDER BY w.tahun"
        Using cmd As New OleDb.OleDbCommand(sql, cs)
            cmd.Parameters.AddWithValue("@p1", TahunFrom)
            cmd.Parameters.AddWithValue("@p2", TahunTo)
            AddProdiParamIfNeeded(cmd)
            Using rd = cmd.ExecuteReader()
                While rd.Read()
                    dictRealYear(CInt(rd("tahun"))) = CInt(rd("jml"))
                End While
            End Using
        End Using
    End Using

    '===== Target per tahun (kpi_maba) =====
    Dim dictTgtYear As New Dictionary(Of Integer, Integer)()
    Using cp As New OleDb.OleDbConnection(ConnPmb)
        cp.Open()
        Dim sql = "SELECT k.tahun, ISNULL(SUM(k.target_total),0) AS tgt " &
                  "FROM kpi_maba k " &
                  "LEFT JOIN star_schema_pmb.dbo.dim_prodi dp ON " &
                  "  LTRIM(RTRIM(k.kd_jur)) = LTRIM(RTRIM(dp.kd_jur)) " &
                  "  OR LTRIM(RTRIM(k.kd_jur)) = LTRIM(RTRIM(dp.kode_jurnim)) " &
                  "WHERE k.tahun BETWEEN ? AND ? "
        sql = AppendProdiFilter(sql, "dp") & "GROUP BY k.tahun ORDER BY k.tahun"
        Using cmd As New OleDb.OleDbCommand(sql, cp)
            cmd.Parameters.AddWithValue("@p1", TahunFrom)
            cmd.Parameters.AddWithValue("@p2", TahunTo)
            AddProdiParamIfNeeded(cmd)
            Using rd = cmd.ExecuteReader()
                While rd.Read()
                    dictTgtYear(CInt(rd("tahun"))) = CInt(rd("tgt"))
                End While
            End Using
        End Using
    End Using

    ' deret kontinu From..To
    For y As Integer = TahunFrom To TahunTo
        yearLabels.Add(y)
        yearReal.Add(If(dictRealYear.ContainsKey(y), dictRealYear(y), 0))
        yearTarget.Add(If(dictTgtYear.ContainsKey(y), dictTgtYear(y), 0))
    Next

    '===== Pie Gender =====
    Using cs As New OleDb.OleDbConnection(ConnStar)
        cs.Open()
        Dim sqlG = "SELECT CASE WHEN UPPER(LTRIM(RTRIM(f.kd_gender)))='L' THEN 'Laki-laki' " &
                   "            WHEN UPPER(LTRIM(RTRIM(f.kd_gender)))='P' THEN 'Perempuan' " &
                   "            ELSE 'Tidak Diketahui' END AS gender, COUNT(*) AS jml " &
                   "FROM fact_pmb f " &
                   "JOIN dim_waktu w ON w.id_waktu=f.id_waktu " &
                   "LEFT JOIN dim_prodi dp ON dp.kd_jur=f.kd_jur " &
                   "WHERE w.tahun BETWEEN ? AND ? AND f.kd_jur IS NOT NULL "
        sqlG = AppendProdiFilter(sqlG, "dp") & 
               "GROUP BY CASE WHEN UPPER(LTRIM(RTRIM(f.kd_gender)))='L' THEN 'Laki-laki' " &
               "              WHEN UPPER(LTRIM(RTRIM(f.kd_gender)))='P' THEN 'Perempuan' " &
               "              ELSE 'Tidak Diketahui' END " &
               "ORDER BY gender"
        Using cmd As New OleDb.OleDbCommand(sqlG, cs)
            cmd.Parameters.AddWithValue("@p1", TahunFrom)
            cmd.Parameters.AddWithValue("@p2", TahunTo)
            AddProdiParamIfNeeded(cmd)
            Using rd = cmd.ExecuteReader()
                While rd.Read()
                    pieGenderLabels.Add(rd("gender").ToString())
                    pieGenderValues.Add(CInt(rd("jml")))
                End While
            End Using
        End Using
    End Using

    '===== Top 10 Sekolah =====
    Using cs As New OleDb.OleDbConnection(ConnStar)
    cs.Open()
    Dim sqlS As String = _
    "SELECT TOP 10 s.nm_sekolah, COUNT(*) AS jml " & _
    "FROM fact_pmb f " & _
    "JOIN dim_waktu  w  ON w.id_waktu = f.id_waktu " & _
    "LEFT JOIN dim_prodi  dp ON dp.kd_jur   = f.kd_jur " & _
    "LEFT JOIN dim_sekolah s ON s.id_sekolah= f.id_sekolah " & _
    "WHERE w.tahun BETWEEN ? AND ? " & _
    "  AND f.kd_jur IS NOT NULL " & _
    "  AND LTRIM(RTRIM(ISNULL(s.nm_sekolah,''))) <> '' " & _
    "  AND UPPER(REPLACE(REPLACE(LTRIM(RTRIM(ISNULL(s.nm_sekolah,''))), '(', ''), ')', '')) NOT IN " & _
    "      ('TIDAK DIKETAHUI','TIDAK TERPETAKAN','LAIN-LAIN','LAINNYA','-') "

    sqlS = AppendProdiFilter(sqlS, "dp") & _
        " GROUP BY s.nm_sekolah " & _
        " ORDER BY COUNT(*) DESC, s.nm_sekolah"

    Using cmd As New OleDb.OleDbCommand(sqlS, cs)
        cmd.Parameters.AddWithValue("@p1", TahunFrom)
        cmd.Parameters.AddWithValue("@p2", TahunTo)
        AddProdiParamIfNeeded(cmd)
        Using rd = cmd.ExecuteReader()
        While rd.Read()
            topSekolahLabels.Add(rd("nm_sekolah").ToString())
            topSekolahValues.Add(CInt(rd("jml")))
        End While
        End Using
    End Using
    End Using


    '===== Top 10 Provinsi =====
    Using cs As New OleDb.OleDbConnection(ConnStar)
    cs.Open()

    Dim innerP As String =
        "SELECT CASE " &
        "  WHEN p.id_level_wil IN (2,3) THEN LTRIM(RTRIM(p.nm_wil)) " &
        "  WHEN p.id_level_wil = 4 THEN LTRIM(RTRIM(p2.nm_wil)) " &
        "  WHEN p.id_level_wil = 5 THEN LTRIM(RTRIM(p3.nm_wil)) " &
        "  ELSE LTRIM(RTRIM(p.nm_wil)) END AS prov " &
        "FROM fact_pmb f " &
        "JOIN dim_waktu  w  ON w.id_waktu = f.id_waktu " &
        "LEFT JOIN dim_prodi  dp ON dp.kd_jur = f.kd_jur " &
        "LEFT JOIN dim_wilayah p  ON p.id_wil = f.id_wil " &
        "LEFT JOIN dim_wilayah p2 ON p2.id_wil = p.id_induk_wilayah " &
        "LEFT JOIN dim_wilayah p3 ON p3.id_wil = p2.id_induk_wilayah " &
        "WHERE w.tahun BETWEEN ? AND ? AND f.kd_jur IS NOT NULL "

    innerP = AppendProdiFilter(innerP, "dp")

    Dim sqlP As String =
        "SELECT TOP 10 prov AS provinsi, COUNT(*) AS jml " &
        "FROM (" & innerP & ") X " &
        "WHERE LTRIM(RTRIM(ISNULL(prov,''))) <> '' " &
        "  AND UPPER(prov) NOT IN ('TIDAK TERPETAKAN','TIDAK DIKETAHUI','LAIN-LAIN','LAINNYA','-') " &
        "GROUP BY prov " &
        "ORDER BY COUNT(*) DESC, prov"

    Using cmd As New OleDb.OleDbCommand(sqlP, cs)
        cmd.Parameters.AddWithValue("@p1", TahunFrom)
        cmd.Parameters.AddWithValue("@p2", TahunTo)
        AddProdiParamIfNeeded(cmd)
        Using rd = cmd.ExecuteReader()
        While rd.Read()
            topProvLabels.Add(rd("provinsi").ToString())
            topProvValues.Add(CInt(rd("jml")))
        End While
        End Using
    End Using
    End Using


    '===== SUSUN JSON (tanpa barFakultas) =====
    Dim csvYearLabels  = String.Join(",", yearLabels.ConvertAll(Function(i) i.ToString()).ToArray())
    Dim csvYearTarget  = String.Join(",", yearTarget.ConvertAll(Function(i) i.ToString()).ToArray())
    Dim csvYearReal    = String.Join(",", yearReal.ConvertAll(Function(i) i.ToString()).ToArray())
    Dim csvPieValues   = String.Join(",", pieGenderValues.ConvertAll(Function(i) i.ToString()).ToArray())
    Dim csvTopSekVals  = String.Join(",", topSekolahValues.ConvertAll(Function(i) i.ToString()).ToArray())
    Dim csvTopProvVals = String.Join(",", topProvValues.ConvertAll(Function(i) i.ToString()).ToArray())

    Dim charts As New List(Of Object) From {
        New With {
            .id = "barYearByFak",
            .type = "bar",
            .labels = csvYearLabels,
            .data = "Target: " & csvYearTarget & " | Realisasi: " & csvYearReal,
            .isMulti = True,
            .showLegend = True
        },
        New With {
            .id = "pieGender",
            .type = "pie",
            .labels = String.Join(",", pieGenderLabels),
            .data = csvPieValues,
            .isMulti = False,
            .showLegend = True
        },
        New With {
            .id = "barTopSekolah",
            .type = "bar",
            .labels = String.Join(",", topSekolahLabels),
            .data = csvTopSekVals,
            .isMulti = False,
            .showLegend = False
        },
        New With {
            .id = "barTopProv",
            .type = "bar",
            .labels = String.Join(",", topProvLabels),
            .data = csvTopProvVals,
            .isMulti = False,
            .showLegend = False
        }
    }

    Dim sb As New System.Text.StringBuilder()
    sb.Append("[")
    For i As Integer = 0 To charts.Count - 1
        If i > 0 Then sb.Append(",")
        sb.Append(BuildChartConfig(charts(i)))
    Next
    sb.Append("]")
    chartConfigJson = sb.ToString()
End Sub

'============= Builder Chart.js =========
Private Function BuildChartConfig(c As Object) As String
    Dim b As New System.Text.StringBuilder()
    Dim isHorizontal As Boolean = (c.id = "barTopSekolah" OrElse c.id = "barTopProv")

    b.Append("{")
    b.Append("""id"":""" & c.id & """,")
    b.Append("""type"":""" & c.type & """,")
    b.Append("""data"":{")
    b.Append("""labels"":" & StringToArray(c.labels) & ",")
    If c.isMulti Then
        b.Append("""datasets"":" & BuildMultiDatasets(c.data, c.labels, c.type))
    Else
        b.Append("""datasets"":[" & BuildSingleDataset(c.data, c.type) & "]")
    End If
    b.Append("},")
    b.Append("""options"":{""responsive"":true,""maintainAspectRatio"":false")
    b.Append(",""plugins"":{""legend"":{""display"":" & c.showLegend.ToString().ToLower() & "}}")

    If c.type = "bar" Then
        If isHorizontal Then
            ' Horizontal bar: kategori di Y, nilai di X
            b.Append(",""indexAxis"":""y"",""scales"":{""x"":{""beginAtZero"":true}}")
        Else
            ' Vertical bar (default)
            b.Append(",""scales"":{""y"":{""beginAtZero"":true}}")
        End If
    End If

    b.Append("}}")
    Return b.ToString()
End Function

Private Function BuildSingleDataset(dataString As String, chartType As String) As String
    Dim data As String = StringToArray(dataString)
    Dim n As Integer = Math.Max(1, dataString.Split(","c).Length)
    Dim colors As String = GenerateColors(n)
    Dim ds As String = """data"":" & data & ",""backgroundColor"":" & colors
    If chartType = "line" Then ds &= ",""borderColor"":""" & GetColorFromPalette(0) & """,""tension"":0.4,""fill"":false"
    Return "{" & ds & "}"
End Function

Private Function BuildMultiDatasets(dataString As String, labelsString As String, chartType As String) As String
    Dim groups() = dataString.Split("|"c)
    Dim L As New List(Of String)()
    For i As Integer = 0 To groups.Length - 1
        Dim parts() = groups(i).Split(":"c)
        If parts.Length = 2 Then
            Dim name = parts(0).Trim()
            Dim arr = StringToArray(parts(1))
            Dim col = GetColorFromPalette(i)
            Dim ds = "{""label"":""" & name & """,""data"":" & arr & ",""backgroundColor"":""" & col & """,""borderColor"":""" & col & """}"
            L.Add(ds)
        End If
    Next
    Return "[" & String.Join(",", L.ToArray()) & "]"
End Function

Private Function StringToArray(str As String) As String
    If String.IsNullOrEmpty(str) Then Return "[]"
    Dim items() = str.Split(","c)
    Dim res As New List(Of String)()
    For Each it In items
        Dim t = it.Trim()
        If IsNumeric(t) Then res.Add(t) Else res.Add("""" & t.Replace("""","\""") & """")
    Next
    Return "[" & String.Join(",", res.ToArray()) & "]"
End Function

Private Function GenerateColors(count As Integer) As String
    Dim cols As New List(Of String)()
    For i As Integer = 0 To count - 1
        cols.Add("""" & GetColorFromPalette(i) & """")
    Next
    Return "[" & String.Join(",", cols.ToArray()) & "]"
End Function

Private Function GetColorFromPalette(index As Integer) As String
    Dim hue As Double = (index * 137.508) Mod 360
    Dim s As Double = 0.7, l As Double = 0.5

    Dim c As Double = (1 - Math.Abs(2 * l - 1)) * s
    Dim x As Double = c * (1 - Math.Abs((hue / 60) Mod 2 - 1))
    Dim m As Double = l - c / 2

    Dim r As Double = 0, g As Double = 0, b As Double = 0

    If hue < 60 Then
        r = c : g = x : b = 0
    ElseIf hue < 120 Then
        r = x : g = c : b = 0
    ElseIf hue < 180 Then
        r = 0 : g = c : b = x
    ElseIf hue < 240 Then
        r = 0 : g = x : b = c
    ElseIf hue < 300 Then
        r = x : g = 0 : b = c
    Else
        r = c : g = 0 : b = x
    End If

    ' gunakan nama berbeda untuk hasil integer
    Dim Ri As Integer = CInt(Math.Round((r + m) * 255))
    Dim Gi As Integer = CInt(Math.Round((g + m) * 255))
    Dim Bi As Integer = CInt(Math.Round((b + m) * 255))

    Return String.Format("#{0:X2}{1:X2}{2:X2}", Ri, Gi, Bi)
End Function

</script>

<section class="content-header">
  <h1>DASHBOARD MAHASISWA BARU PRODI</h1>
    <ol class="breadcrumb">
        <li><a href="/dashboard_pmb/index.aspx"><i class="fa fa-dashboard"></i> Dashboard PMB</a></li>
        <li class="active">Dashboard Mahasiswa Baru Prodi</li>
    </ol>
</section>

<section class="content">
<!-- ====== YEAR FILTERS (side-by-side) ====== -->
<div class="row" style="margin-bottom:10px">
  <div class="col-md-12">
    <div class="filter-range form-inline">
      <label style="margin-right:8px">Tahun Dari</label>
        <asp:DropDownList ID="ddlYearFrom" runat="server"
        CssClass="form-control input-sm" Style="margin-right:16px"
        AutoPostBack="true" OnSelectedIndexChanged="OnYearChanged" />

        <label style="margin-right:8px">Tahun Sampai</label>
        <asp:DropDownList ID="ddlYearTo" runat="server"
        CssClass="form-control input-sm" Style="margin-right:16px"
        AutoPostBack="true" OnSelectedIndexChanged="OnYearChanged" />

        <label style="margin:8px 8px 0 0">Program Studi</label>
        <asp:DropDownList ID="ddlProdi" runat="server"
        CssClass="form-control input-sm"
        AutoPostBack="true" OnSelectedIndexChanged="OnProdiChanged" />
    </div>
  </div>
</div>

  <!-- ====== HEADER LABELS ====== -->
<div class="row">
    <asp:Repeater ID="rptDashboard" runat="server">
      <ItemTemplate>
        <div class='<%# Eval("ColClass") %>'>
          <div class="small-box plain <%# Eval("ColorClass") %>">
            <div class="inner">
              <h3 class='<%# Eval("ColorClass") %>'><%# Eval("Total") %></h3>
              <p><%# Eval("Title") %></p>
            </div>
            <div class="icon"><i class='fa <%# Eval("Icon") %> <%# Eval("ColorClass") %>'></i></div>
          </div>
        </div>
      </ItemTemplate>
    </asp:Repeater>
     <!-- KOTAK GAUGE: kolom ke-3 sebaris -->
    <div class="col-lg-4 col-md-4 col-sm-6 col-xs-12">
        <div class="box box-primary" style="height:100%">
            <div class="box-header with-border">
                <h3 class="box-title">Realisasi vs Target</h3>
            </div>
        <div class="box-body">
            <div style="height:120px"><canvas id="gaugeProgress"></canvas></div>
                <small class="text-muted">
                    Realisasi: <%= TotalRealisasi.ToString("N0", System.Globalization.CultureInfo.GetCultureInfo("id-ID")) %>
                    (<%= PctRealisasiText %>) |
                    Target: <%= TotalTarget.ToString("N0", System.Globalization.CultureInfo.GetCultureInfo("id-ID")) %>
                    (100%) |
                    Sisa: <%= SisaAbs.ToString("N0", System.Globalization.CultureInfo.GetCultureInfo("id-ID")) %>
                    (<%= PctSisaText %>)
                </small>
            </div>
        </div>
    </div>
</div>

  <!-- ====== CHARTS ====== -->
  <div class="row">
    <div class="col-md-12">
        <div class="box box-primary">
            <div class="box-header with-border">
                <h3 class="box-title">
                    Target vs Realisasi per Tahun
                    (<%= If(TahunFrom=TahunTo, TahunTo.ToString(), TahunFrom & "-" & TahunTo) %>)
                    <% If SelectedProdi <> PRODI_ALL Then %>
                        &ndash; <%= SelectedProdiText %>
                    <% End If %>
                </h3>
            </div>
            <div class="box-body"><div style="height:320px"><canvas id="barYearByFak"></canvas></div></div>
        </div>
    </div>
    <div class="col-md-6">
        <div class="box box-primary">
            <div class="box-header with-border"><h3 class="box-title">Komposisi Gender (<%= If(TahunFrom=TahunTo, TahunTo.ToString(), TahunFrom & "-" & TahunTo) %>)</h3></div>
            <div class="box-body"><div style="height:320px"><canvas id="pieGender"></canvas></div></div>
        </div>
    </div>
    <div class="col-md-6">
      <div class="box box-primary">
        <div class="box-header with-border"><h3 class="box-title">Top 10 Sekolah (<%= If(TahunFrom=TahunTo, TahunTo.ToString(), TahunFrom & "-" & TahunTo) %>)</h3></div>
        <div class="box-body"><div style="height:320px"><canvas id="barTopSekolah"></canvas></div></div>
      </div>
    </div>
    <div class="col-md-12">
      <div class="box box-primary">
        <div class="box-header with-border"><h3 class="box-title">Top 10 Provinsi (<%= If(TahunFrom=TahunTo, TahunTo.ToString(), TahunFrom & "-" & TahunTo) %>)</h3></div>
        <div class="box-body"><div style="height:320px"><canvas id="barTopProv"></canvas></div></div>
      </div>
    </div>
  </div>
</section>

<style>
.filter-range .form-control{ min-width:110px; }
@media (max-width:576px){
  .filter-range { display:flex; flex-wrap:wrap; gap:8px 16px; }
}

.filter-range { position: relative; z-index: 50; }

/* ====== KARTU UTAMA ====== */
.small-box.plain{
  position: relative;
  overflow: hidden;
  background:#f5f7fb;
  border:1px solid #e8edf5;
  border-radius:12px;
  padding:16px 120px 16px 16px;   /* ruang untuk ikon kanan */
}

/* Strip atas dengan sudut membulat */
.small-box.plain::before{
  content:"";
  position:absolute; left:0; top:0; width:100%; height:10px;
  background:transparent; border-radius:12px 12px 0 0;
}

/* Area ikon di kanan: vertikal center, aman dari tepi */
.small-box.plain .icon{
  position:absolute;
  right:20px;
  top:50%;
  transform:translateY(-52%);     /* sedikit lebih ke atas */
  width:88px; height:88px;
  display:flex; align-items:center; justify-content:center;
}

/* Ukuran ikon */
.small-box .icon i{
  font-size:68px;
  line-height:1;
  opacity:.9;
}

/* Tipografi angka & label */
.small-box .inner h3{
  margin: 2px 0 8px;
  font-weight:800;
  line-height:1;
  letter-spacing:.2px;
}
.small-box .inner p{
  margin: 6px 0 0;
  padding-left: 0;          /* hilangkan ruang untuk bullet */
  font-size: 18px;          /* << ukuran label seragam */
  font-weight: 600;         /* opsional: biar konsisten & tegas */
  line-height: 1.35;
  color:#0f172a;
}

/* ====== VARIAN WARNA ====== */
/* Realisasi: biru langit */
.small-box.plain.tile-sky::before{ background:#38bdf8; }
.small-box.plain.tile-sky .inner h3,
.small-box.plain.tile-sky .icon i{ color:#38bdf8; }
.small-box.plain.tile-sky .inner p{ color:#0f172a; }
.small-box.plain.tile-sky .inner p::before{ background:#38bdf8; }

/* Target: merah */
.small-box.plain.tile-red::before{ background:#ef4444; }
.small-box.plain.tile-red .inner h3,
.small-box.plain.tile-red .icon i{ color:#ef4444; }
.small-box.plain.tile-red .inner p{ color:#0f172a; }
.small-box.plain.tile-red .inner p::before{ background:#ef4444; }

/* ====== RESPONSIVE ====== */
@media (max-width: 991px){
  .small-box.plain{ padding-right:100px; }
  .small-box.plain .icon{ width:72px; height:72px; right:16px; }
  .small-box .icon i{ font-size:56px; }
}
@media (max-width: 600px){
  .small-box.plain{ padding-right:76px; }
  .small-box.plain .icon{ width:56px; height:56px; }
  .small-box .icon i{ font-size:44px; }
}
</style>

<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<script src="https://cdn.jsdelivr.net/npm/chartjs-plugin-datalabels@2"></script>
<script>
  function numfmt(n){ try{ return Number(n).toLocaleString('id-ID'); }catch(e){ return n; } }
  Chart.register(ChartDataLabels);

  document.addEventListener('DOMContentLoaded', function () {
  // === GAUGE ===
  var g = <%= gaugeConfigJson %>;
  var el = document.getElementById(g.id);
  if (el){
    new Chart(el, {
      type: g.type, data: g.data,
      options: {
        responsive:true, maintainAspectRatio:false,
        circumference:180, rotation:270, cutout:"70%",
        plugins:{ legend:{display:true}, tooltip:{enabled:false}, datalabels:{display:false} }
      }
    });
  }

  // === CHARTS ===
  var cfgs = <%= chartConfigJson %>;
  cfgs.forEach(function(c){
    var el2 = document.getElementById(c.id);
    if(!el2) return;

    // datalabels default: angka (ribuan)
    var dl = {
      anchor:'end', align:'end', clamp:true, clip:false,
      font:{weight:'600'},
      formatter: (v)=> numfmt(v)
    };
    // untuk pie/doughnut: persen
    if (c.type === 'pie' || c.type === 'doughnut'){
      dl = {
        color:'#fff',
        formatter: (value, ctx)=>{
          const arr = ctx.chart.data.datasets[0].data || [];
          const sum = arr.reduce((a,b)=>a+Number(b||0),0) || 0;
          if(!sum) return '0%';
          return (Math.round((value/sum)*1000)/10).toString().replace('.',',')+'%';
        }
      };
    }

    c.options = c.options || {};
    c.options.plugins = c.options.plugins || {};
    c.options.plugins.datalabels = dl;

    new Chart(el2, { type:c.type, data:c.data, options:c.options });
  });
});

</script>
