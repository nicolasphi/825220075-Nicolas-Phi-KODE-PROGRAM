<!-- #INCLUDE file = "/path/to/your/page_or_master.aspx" --> 'NOTE: include file tergantung modul / layout aplikasi (internal).

<script runat="server">
'============= STATE ====================
' range filter
Private TahunFrom As Integer = 0
Private TahunTo   As Integer = 0

'===== KMEANS (STATE & OUTPUT) =====
Public clusterChartJson As String = "{}"
Public clusterKOptimal As Integer = 0
Public clusterSilhouette As String = "0.000"
Public clusterWCSS As String = "0.000"
Public clusterCH As String = "0.000"

'===== REGRESI (STATE & OUTPUT) =====
Public regChartJson As String = "{}"   
Public regStatsHtml As String = ""     
Public regEqText As String = "-"
Public regR2Text As String = "-"
Public regMAEText As String = "-"
Public regMAPEText As String = "-"
Public regRMSEText As String = "-"


'================= UTIL =================
Private Function PrettyFak(raw As String) As String
    If String.IsNullOrWhiteSpace(raw) Then Return raw
    If raw.Equals("Tidak Terpetakan", StringComparison.OrdinalIgnoreCase) Then Return raw
    Dim ti As System.Globalization.TextInfo = New System.Globalization.CultureInfo("id-ID", False).TextInfo
    Dim s As String = ti.ToTitleCase(raw.ToLowerInvariant())
    s = s.Replace(" Dan ", " dan ")
    Return "Fakultas " & s
End Function

Public chartConfigJson As String = ""
Public gaugeConfigJson As String = ""
Public gaugePctHtml As String = ""

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

'============= KONN =====================

Private ReadOnly ConnPmb  As String =
  "Provider=SQLOLEDB;Data Source=<DB_HOST>,<PORT>;Initial Catalog=<PMB_DB_NAME>;User ID=<DB_USER>;Password=<DB_PASS>;"
Private ReadOnly ConnStar As String =
  "Provider=SQLOLEDB;Data Source=<DB_HOST>,<PORT>;Initial Catalog=<STAR_DB_NAME>;User ID=<DB_USER>;Password=<DB_PASS>;"

'============= STATE ====================
Private TotalRealisasi As Integer = 0
Private TotalTarget As Integer = 0

Sub Page_Load(sender As Object, e As EventArgs)
    If Not Page.IsPostBack Then
        PopulateYearFilters()              ' isi ddl + set TahunFrom/TahunTo
        EnsureRangeOrder()
        LoadHeaderTiles()
        BuildGauges()
        BuildCharts()
        BuildClusterWilayah()
        BuildRegressionTrend()  
    Else
        ' pada postback, ambil dari ViewState jika ada
        If ViewState("YFROM") IsNot Nothing Then TahunFrom = CInt(ViewState("YFROM"))
        If ViewState("YTO")   IsNot Nothing Then TahunTo   = CInt(ViewState("YTO"))
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
    BuildClusterWilayah()
    BuildRegressionTrend()  
End Sub

'----------------------------------------
' HEADER: 2 label (Realisasi & Target)
'----------------------------------------
Private Sub LoadHeaderTiles()
    ' --- Realisasi (STAR) ---
    Using cs As New OleDb.OleDbConnection(ConnStar)
        cs.Open()
        Using cmd As New OleDb.OleDbCommand(
            "SELECT COUNT(*) " &
            "FROM fact_pmb f JOIN dim_waktu w ON w.id_waktu=f.id_waktu " &
            "WHERE w.tahun BETWEEN ? AND ? AND f.kd_jur IS NOT NULL", cs)
            cmd.Parameters.AddWithValue("@p1", TahunFrom)
            cmd.Parameters.AddWithValue("@p2", TahunTo)
            TotalRealisasi = CInt(cmd.ExecuteScalar())
        End Using
    End Using

    ' --- Target (Pmbregol) ---
    Using cp As New OleDb.OleDbConnection(ConnPmb)
        cp.Open()
        Using cmd As New OleDb.OleDbCommand(
            "SELECT ISNULL(SUM(target_total),0) FROM kpi_maba WHERE tahun BETWEEN ? AND ?", cp)
            cmd.Parameters.AddWithValue("@p1", TahunFrom)
            cmd.Parameters.AddWithValue("@p2", TahunTo)
            TotalTarget = CInt(cmd.ExecuteScalar())
        End Using
    End Using

    Dim rentang As String = If(TahunFrom = TahunTo, TahunTo.ToString(), TahunFrom & "-" & TahunTo)

    Dim tiles As New List(Of Object) From {
        New With {.Total = TotalRealisasi.ToString("N0"),
                  .Title = "Realisasi Pendaftaran " & rentang,
                  .ColorClass = "tile-sky", .Icon="fa-solid fa-users",
                  .ColClass = "col-lg-4 col-md-4 col-sm-6 col-xs-12"},
        New With {.Total = TotalTarget.ToString("N0"),
                  .Title = "Target KPI MABA " & rentang,
                  .ColorClass = "tile-red", .Icon="fa-solid fa-bullseye",
                  .ColClass = "col-lg-4 col-md-4 col-sm-6 col-xs-12"}
    }

    rptDashboard.DataSource = tiles
    rptDashboard.DataBind()
End Sub

'----------------------------------------
' GAUGES: capaian (%) dan sisa (%)
'----------------------------------------
Private Sub BuildGauges()
    Dim realisasi As Integer = TotalRealisasi
    Dim target As Integer = Math.Max(TotalTarget, 1) ' hindari /0
    Dim sisa As Integer = Math.Max(0, target - realisasi)

    ' % relatif terhadap TARGET
    Dim ci = System.Globalization.CultureInfo.InvariantCulture
    Dim pctRealisasi As Double = (realisasi * 100.0) / target
    Dim pctSisa As Double = (sisa * 100.0) / target
    If pctRealisasi < 0 Then pctRealisasi = 0
    If pctSisa < 0 Then pctSisa = 0

    ' JSON gauge (tetap sederhana)
    gaugeConfigJson =
        "{" &
        """id"":""gaugeProgress""," &
        """type"":""doughnut""," &
        """data"":{""labels"":[""Realisasi"",""Sisa Target""],""datasets"":[{""data"":[" &
            realisasi.ToString() & "," & sisa.ToString() &
        "]}]}" &
        "}"

    ' Teks yang ditampilkan di bawah gauge
    gaugePctHtml =
        "Realisasi: " & realisasi.ToString("N0") & " (" & pctRealisasi.ToString("0.0", ci) & "%) | " &
        "Target: " & TotalTarget.ToString("N0") & " (100%) | " &
        "Sisa: " & sisa.ToString("N0") & " (" & pctSisa.ToString("0.0", ci) & "%)"
End Sub


'----------------------------------------
' CHARTS: Bar Fakultas (Target vs Realisasi),
'         Pie Gender, Top-10 Sekolah, Top-10 Provinsi
'----------------------------------------
Private Sub BuildCharts()
    Dim cacheKey As String = "pmb:charts:" & TahunFrom & "-" & TahunTo
    Dim cached = TryCast(Cache(cacheKey), String)
    If cached IsNot Nothing Then chartConfigJson = cached : Exit Sub

    Dim barLabels As New List(Of String)()
    Dim barReal As New List(Of Integer)()
    Dim barTarget As New List(Of Integer)()
    Dim pieGenderLabels As New List(Of String)()
    Dim pieGenderValues As New List(Of Integer)()
    Dim topSekolahLabels As New List(Of String)()
    Dim topSekolahValues As New List(Of Integer)()
    Dim topProvLabels As New List(Of String)()
    Dim topProvValues As New List(Of Integer)()
    Dim dictReal As New Dictionary(Of String, Integer)(StringComparer.OrdinalIgnoreCase)
    Dim dictTarget As New Dictionary(Of String, Integer)(StringComparer.OrdinalIgnoreCase)

        Dim sql As String = _
        "SET NOCOUNT ON;" & vbCrLf & _
        "SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;" & vbCrLf & _
        "" & vbCrLf & _
        "-- RS1: realisasi per TAHUN (DW)" & vbCrLf & _
        "SELECT th = w.tahun, jml = COUNT(*)" & vbCrLf & _
        "FROM star_schema_pmb.dbo.fact_pmb f" & vbCrLf & _
        "JOIN star_schema_pmb.dbo.dim_waktu w ON w.id_waktu=f.id_waktu" & vbCrLf & _
        "WHERE w.tahun BETWEEN ? AND ? AND f.kd_jur IS NOT NULL" & vbCrLf & _
        "GROUP BY w.tahun;" & vbCrLf & _
        "" & vbCrLf & _
        "-- RS2: target per TAHUN (cross-DB)" & vbCrLf & _
        "SELECT th = k.tahun, tgt = ISNULL(SUM(k.target_total),0)" & vbCrLf & _
        "FROM Pmbregol.dbo.kpi_maba k" & vbCrLf & _
        "WHERE k.tahun BETWEEN ? AND ?" & vbCrLf & _
        "GROUP BY k.tahun;" & vbCrLf & _
        "" & vbCrLf & _
        "-- RS3: pie gender" & vbCrLf & _
        "SELECT gender = CASE" & vbCrLf & _
        "        WHEN UPPER(LTRIM(RTRIM(f.kd_gender)))='L' THEN 'Laki-laki'" & vbCrLf & _
        "        WHEN UPPER(LTRIM(RTRIM(f.kd_gender)))='P' THEN 'Perempuan'" & vbCrLf & _
        "        ELSE 'Tidak Diketahui' END," & vbCrLf & _
        "       jml = COUNT(*)" & vbCrLf & _
        "FROM star_schema_pmb.dbo.fact_pmb f" & vbCrLf & _
        "JOIN star_schema_pmb.dbo.dim_waktu w ON w.id_waktu=f.id_waktu" & vbCrLf & _
        "WHERE w.tahun BETWEEN ? AND ? AND f.kd_jur IS NOT NULL" & vbCrLf & _
        "GROUP BY CASE" & vbCrLf & _
        "        WHEN UPPER(LTRIM(RTRIM(f.kd_gender)))='L' THEN 'Laki-laki'" & vbCrLf & _
        "        WHEN UPPER(LTRIM(RTRIM(f.kd_gender)))='P' THEN 'Perempuan'" & vbCrLf & _
        "        ELSE 'Tidak Diketahui' END;" & vbCrLf & _
        "" & vbCrLf & _
        "-- RS4: top sekolah (bersihkan & buang 'Tidak diketahui' + variasi)" & vbCrLf & _
        "SELECT TOP 10 nm_sekolah, jml" & vbCrLf & _
        "FROM (" & vbCrLf & _
        "  SELECT" & vbCrLf & _
        "    s.nm_sekolah," & vbCrLf & _
        "    jml = COUNT(*)" & vbCrLf & _
        "  FROM star_schema_pmb.dbo.fact_pmb f" & vbCrLf & _
        "  JOIN star_schema_pmb.dbo.dim_waktu w ON w.id_waktu=f.id_waktu" & vbCrLf & _
        "  LEFT JOIN star_schema_pmb.dbo.dim_sekolah s ON s.id_sekolah=f.id_sekolah" & vbCrLf & _
        "  WHERE w.tahun BETWEEN ? AND ?" & vbCrLf & _
        "    AND LTRIM(RTRIM(ISNULL(s.nm_sekolah,''))) <> ''" & vbCrLf & _
        "    AND UPPER(REPLACE(REPLACE(LTRIM(RTRIM(ISNULL(s.nm_sekolah,''))),'(',''),')','')) <> 'TIDAK DIKETAHUI'" & vbCrLf & _
        "  GROUP BY s.nm_sekolah" & vbCrLf & _
        ") x" & vbCrLf & _
        "ORDER BY jml DESC, nm_sekolah;" & vbCrLf & _
        "-- RS5: top provinsi" & vbCrLf & _
        "SELECT TOP 10 provinsi=ISNULL(p.nm_wil,'Tidak Terpetakan'), jml=COUNT(*)" & vbCrLf & _
        "FROM star_schema_pmb.dbo.fact_pmb f" & vbCrLf & _
        "JOIN star_schema_pmb.dbo.dim_waktu w ON w.id_waktu=f.id_waktu" & vbCrLf & _
        "LEFT JOIN star_schema_pmb.dbo.dim_wilayah p ON p.id_wil=f.id_wil" & vbCrLf & _
        "WHERE w.tahun BETWEEN ? AND ?" & vbCrLf & _
        "GROUP BY ISNULL(p.nm_wil,'Tidak Terpetakan')" & vbCrLf & _
        "ORDER BY jml DESC, provinsi;"

    Using cn As New OleDb.OleDbConnection(ConnStar)
        cn.Open()
        Using cmd As New OleDb.OleDbCommand(sql, cn)
            Dim p = cmd.Parameters
            ' Urutan parameter = urutan tanda tanya (?)
            p.Add("@y1",  OleDb.OleDbType.Integer).Value = TahunFrom ' RS1
            p.Add("@y2",  OleDb.OleDbType.Integer).Value = TahunTo
            p.Add("@y3",  OleDb.OleDbType.Integer).Value = TahunFrom ' RS2
            p.Add("@y4",  OleDb.OleDbType.Integer).Value = TahunTo
            p.Add("@y5",  OleDb.OleDbType.Integer).Value = TahunFrom ' RS3
            p.Add("@y6",  OleDb.OleDbType.Integer).Value = TahunTo
            p.Add("@y7",  OleDb.OleDbType.Integer).Value = TahunFrom ' RS4
            p.Add("@y8",  OleDb.OleDbType.Integer).Value = TahunTo
            p.Add("@y9",  OleDb.OleDbType.Integer).Value = TahunFrom ' RS5
            p.Add("@y10", OleDb.OleDbType.Integer).Value = TahunTo
            cmd.CommandTimeout = 60

            Using rd = cmd.ExecuteReader()
              ' RS1: realisasi per tahun
              While rd.Read()
                  Dim th As String = rd.GetInt32(0).ToString()
                  dictReal(th) = rd.GetInt32(1)
              End While

              ' RS2: target per tahun
              rd.NextResult()
              While rd.Read()
                  Dim th As String = rd.GetInt32(0).ToString()
                  dictTarget(th) = rd.GetInt32(1)
              End While

              ' gabung label tahun
              Dim allTh = dictReal.Keys.Union(dictTarget.Keys, StringComparer.OrdinalIgnoreCase) _
                                        .OrderBy(Function(x) x).ToList()
              For Each th In allTh
                  barLabels.Add(th) ' label = tahun
                  barReal.Add(If(dictReal.ContainsKey(th), dictReal(th), 0))
                  barTarget.Add(If(dictTarget.ContainsKey(th), dictTarget(th), 0))
              Next

              ' RS3
              rd.NextResult()
              While rd.Read() : pieGenderLabels.Add(rd.GetString(0)) : pieGenderValues.Add(rd.GetInt32(1)) : End While
              ' RS4
              rd.NextResult()
              While rd.Read()
                Dim nm As String = If(rd.IsDBNull(0), "", rd.GetString(0).Trim())
                If String.IsNullOrEmpty(nm) _
                  OrElse nm.Equals("Tidak diketahui", StringComparison.OrdinalIgnoreCase) _
                  OrElse nm.Equals("Tidak Terpetakan", StringComparison.OrdinalIgnoreCase) Then
                  Continue While
                End If
                topSekolahLabels.Add(nm)
                topSekolahValues.Add(If(rd.IsDBNull(1), 0, rd.GetInt32(1)))
              End While
              ' RS5
              rd.NextResult()
              While rd.Read() : topProvLabels.Add(rd.GetString(0)) : topProvValues.Add(rd.GetInt32(1)) : End While
          End Using
        End Using
    End Using

    ' build JSON seperti sebelumnya...
    Dim charts As New List(Of Object) From {
        New With {.id="barFakultas", .type="bar", .labels=String.Join(",", barLabels), .data="Target: " & String.Join(",", barTarget) & " | Realisasi: " & String.Join(",", barReal), .isMulti=True, .showLegend=True},
        New With {.id="pieGender", .type="pie", .labels=String.Join(",", pieGenderLabels), .data=String.Join(",", pieGenderValues), .isMulti=False, .showLegend=True},
        New With {.id="barTopSekolah", .type="bar", .labels=String.Join(",", topSekolahLabels),.data=String.Join(",", topSekolahValues),.isMulti=False, .showLegend=False, .indexAxis="y"},
        New With {.id="barTopProv", .type="bar", .labels=String.Join(",", topProvLabels),.data=String.Join(",", topProvValues),.isMulti=False, .showLegend=False, .indexAxis="y"}
    }
    Dim sb As New System.Text.StringBuilder()
    sb.Append("[")
    For i As Integer = 0 To charts.Count - 1
        If i > 0 Then
            sb.Append(",")
        End If
        sb.Append(BuildChartConfig(charts(i)))
    Next
    sb.Append("]")
    chartConfigJson = sb.ToString()
    Cache.Insert(cacheKey, chartConfigJson, Nothing, DateTime.Now.AddMinutes(3), TimeSpan.Zero)

End Sub

'================= KMEANS WILAYAH (AMBIL DARI TABEL) =================
Private Sub BuildClusterWilayah()
    ' cache global saja, tidak tergantung filter tahun
    Dim kkey As String = "pmb:kmeans:global"
    Dim ch = TryCast(Cache(kkey), Tuple(Of String, Integer, String, String, String))
    If ch IsNot Nothing Then
        clusterChartJson  = ch.Item1
        clusterKOptimal   = ch.Item2
        clusterSilhouette = ch.Item3
        clusterWCSS       = ch.Item4
        clusterCH         = ch.Item5
        Exit Sub
    End If

    ' default
    clusterChartJson  = "{}"
    clusterKOptimal   = 0
    clusterSilhouette = "0.000"
    clusterWCSS       = "0.000"
    clusterCH         = "0.000"

    Using cs As New OleDb.OleDbConnection(ConnStar)
        cs.Open()

        ' AMBIL SATU RECORD GLOBAL (misalnya yang tahun_to paling besar)
        Dim sqlKmeans As String = _
            "SELECT TOP 1 k_optimal, silhouette, chart_json " & _
            "FROM fact_kmeans_wilayah " & _
            "ORDER BY tahun_to DESC, tahun_from ASC;"

        Using cmd As New OleDb.OleDbCommand(sqlKmeans, cs)
            Using rd = cmd.ExecuteReader()
                If rd.Read() Then
                    Dim ci = System.Globalization.CultureInfo.InvariantCulture
                    Dim kOpt  As Integer = If(rd.IsDBNull(0), 0, CInt(rd.GetValue(0)))
                    Dim sil   As Double  = If(rd.IsDBNull(1), 0.0R, CDbl(rd.GetValue(1)))
                    Dim json  As String  = If(rd.IsDBNull(2), "{}", rd.GetString(2))

                    clusterKOptimal   = kOpt
                    clusterSilhouette = sil.ToString("0.000", ci)
                    clusterWCSS       = "-"          ' kolom dihapus → tampilkan N/A
                    clusterCH         = "-"          ' kolom dihapus → tampilkan N/A
                    clusterChartJson  = json

                    Cache.Insert(kkey,
                        Tuple.Create(clusterChartJson, clusterKOptimal, clusterSilhouette, clusterWCSS, clusterCH),
                        Nothing, DateTime.Now.AddMinutes(3), TimeSpan.Zero)
                End If
            End Using
        End Using
    End Using
End Sub


'============= Builder Chart.js =========
Private Function BuildChartConfig(c As Object) As String
    Dim b As New System.Text.StringBuilder()
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

    ' ---- Legend
    b.Append(",""plugins"":{""legend"":{""display"":" & c.showLegend.ToString().ToLower() & "}}")

    ' ---- Skala/Orientasi Bar
    If CStr(c.type) = "bar" Then
        Dim idx As String = ""
        Try : idx = CStr(c.indexAxis) : Catch : idx = "" : End Try

        If idx = "y" Then
            ' Horizontal bar
            b.Append(",""indexAxis"":""y"",""scales"":{""x"":{""beginAtZero"":true}}")
        Else
            ' Vertical bar (default)
            b.Append(",""scales"":{""y"":{""beginAtZero"":true}}")
        End If
    End If

    b.Append("}}")
    Return b.ToString()
End Function

'================= REGRESI LINIER (DENGAN FORECAST) =================
Private Sub BuildRegressionTrend()
  regChartJson = "{}"
  regEqText = "-" : regR2Text = "-" : regMAEText = "-" : regMAPEText = "-" : regRMSEText = "-"

  Const REG_FROM As Integer = 2017
  Const REG_TO   As Integer = 2023

  Using cn As New OleDb.OleDbConnection(ConnStar)
    cn.Open()
    Dim sqlReg As String =
      "SELECT TOP 1 chart_json, slope, intercept, r2, mae, rmse, mape " &
      "FROM fact_reg_tren WHERE tahun_from=? AND tahun_to=? ORDER BY id_run DESC"

    Using cmd As New OleDb.OleDbCommand(sqlReg, cn)
      cmd.Parameters.AddWithValue("@p1", REG_FROM)
      cmd.Parameters.AddWithValue("@p2", REG_TO)
      Using rd = cmd.ExecuteReader()
        If rd.Read() Then
          Dim ci = System.Globalization.CultureInfo.GetCultureInfo("id-ID")
          regChartJson = If(rd.IsDBNull(0), "{}", rd.GetString(0))

          Dim slope = If(rd.IsDBNull(1), Double.NaN, Convert.ToDouble(rd.GetValue(1)))
          Dim intercept = If(rd.IsDBNull(2), Double.NaN, Convert.ToDouble(rd.GetValue(2)))
          Dim r2 = If(rd.IsDBNull(3), Double.NaN, Convert.ToDouble(rd.GetValue(3)))
          Dim mae = If(rd.IsDBNull(4), Double.NaN, Convert.ToDouble(rd.GetValue(4)))
          Dim rmse = If(rd.IsDBNull(5), Double.NaN, Convert.ToDouble(rd.GetValue(5)))
          Dim mape = If(rd.IsDBNull(6), Double.NaN, Convert.ToDouble(rd.GetValue(6)))

          If Not Double.IsNaN(intercept) AndAlso Not Double.IsNaN(slope) Then
            regEqText = String.Format(ci, "ŷ = {0:0.###} + ({1:0.###} × tahun)", intercept, slope)
          End If
          If Not Double.IsNaN(r2) Then   regR2Text   = r2.ToString("0.###", ci)
          If Not Double.IsNaN(mae) Then  regMAEText  = mae.ToString("N0", ci)
          If Not Double.IsNaN(mape) Then regMAPEText = mape.ToString("0.0'%'", ci)
          If Not Double.IsNaN(rmse) Then regRMSEText = rmse.ToString("N0", ci)
        End If
      End Using
    End Using
  End Using
End Sub

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
    <h1>DASHBOARD MAHASISWA BARU UNIVERSITAS</h1>
    <ol class="breadcrumb">
      <li><a href="/dashboard_kuesioner/index.aspx"><i class="fa fa-dashboard"></i> Dashboard</a></li>
      <li class="active">Dashboard Mahasiswa Baru</li>
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
          CssClass="form-control input-sm"
          AutoPostBack="true" OnSelectedIndexChanged="OnYearChanged" />
      </div>
    </div>
  </div>

  <!-- ====== HEADER LABELS (3 kartu sejajar) ====== -->
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

  <!-- GAUGE harus di dalam .row yang sama -->
  <div class="col-lg-4 col-md-4 col-sm-6 col-xs-12">
    <div class="box box-primary" style="height:100%">
      <div class="box-header with-border"><h3 class="box-title">Realisasi vs Target</h3></div>
      <div class="box-body">
        <div style="height:120px"><canvas id="gaugeProgress"></canvas></div>
        <small class="text-muted"><%= gaugePctHtml %></small>
      </div>
    </div>
  </div>
</div>

  <!-- ====== CHARTS ====== -->
  <div class="row">
    <div class="col-md-12">
      <div class="box box-primary">
        <div class="box-header with-border"><h3 class="box-title">
            Target vs Realisasi per Tahun
            (<%= If(TahunFrom=0 Or TahunTo=0, "", If(TahunFrom=TahunTo, TahunTo.ToString(), TahunFrom & "-" & TahunTo)) %>)
          </h3>
          </div>
        <div class="box-body"><div style="height:320px"><canvas id="barFakultas"></canvas></div></div>
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
    <!-- ====== K-MEANS WILAYAH (Stat di atas, Chart di bawah) ====== -->
<div class="row">
  <!-- STATISTIK FULL WIDTH -->
  <div class="col-md-12">
    <div class="box box-primary">
      <div class="box-header with-border">
        <h3 class="box-title">Statistik Cluster</h3>
      </div>
      <div class="box-body">
        <!-- KPI cards -->
        <div class="kpi-grid">
          <div class="small-box bg-aqua">
            <div class="inner">
              <h3><%= clusterKOptimal %></h3>
              <p>K Optimal</p>
            </div>
          </div>
          <div class="small-box bg-green">
            <div class="inner">
              <h3><%= clusterSilhouette %></h3>
              <p>Silhouette</p>
            </div>
          </div>
          <div class="small-box bg-orange">
            <div class="inner">
              <h3><%= clusterWCSS %></h3>
              <p>WCSS</p>
            </div>
          </div>
          <div class="small-box bg-yellow">
            <div class="inner">
              <h3><%= clusterCH %></h3>
              <p>Calinski-H</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- CHART FULL WIDTH -->
  <div class="col-md-12">
    <div class="box box-primary">
      <div class="box-header with-border">
        <h3 class="box-title">Clustering Wilayah (Jumlah Mahasiswa/i vs Jumlah Sekolah)</h3>
      </div>
      <div class="box-body">
        <div id="kmLegend" class="legend-list"></div>
        <div style="height:420px"><canvas id="scKMeansWilayah"></canvas></div>
      </div>
    </div>
  </div>
</div>
<!-- ====== REGRESI LINIER (di bawah K-Means) ====== -->
<div class="row">
  <div class="col-md-12">
    <div class="box box-primary">
      <div class="box-header with-border">
        <h3 class="box-title">
          Tren Pendaftaran Mahasiswa Baru (Regresi Linier) Periode 2017-2023
        </h3>
      </div>
      <div class="box-body">
        <div style="height:340px"><canvas id="regTrend"></canvas></div>
        <!-- Baris ini DIHAPUS supaya teks persamaan tidak muncul lagi -->
        <!-- <div style="margin-top:10px"><%= regStatsHtml %></div> -->
      </div>

      <div class="row stats-table">
        <!-- Tabel ringkasan model -->
        <div class="col-md-6">
          <table class="table table-bordered table-condensed">
            <tbody>
              <tr><td>Persamaan</td><td><code><%= regEqText %></code></td></tr>
              <tr><td>R&sup2;</td><td><%= regR2Text %></td></tr>
              <tr><td>MAE</td><td><%= regMAEText %></td></tr>
              <tr><td>MAPE</td><td><%= regMAPEText %></td></tr>
              <tr><td>RMSE</td><td><%= regRMSEText %></td></tr>
            </tbody>
          </table>
        </div>

        <!-- Tabel prediksi -->
        <div class="col-md-6">
          <table class="table table-bordered table-condensed">
            <thead>
              <tr><th>Tahun</th><th>Prediksi pendaftar</th></tr>
            </thead>
            <tbody id="tblPredBody"></tbody>
          </table>
        </div>
      </div>
    </div>
  </div>
</div>
  </div>
</section>

<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<script>
/* ──────────────────────────────
   Plugin 1: Label persen di pie/doughnut (khusus #pieGender)
─────────────────────────────── */
const PiePercentLabels = {
  id: 'piePercentLabels',
  afterDatasetsDraw(chart, args, cfg) {
    if (!['pie','doughnut'].includes(chart.config.type)) return;
    if (chart.canvas && chart.canvas.id !== 'pieGender') return;

    const { ctx, data } = chart;
    const ds = data.datasets?.[0];
    if (!ds) return;

    const opt = Object.assign({
      minPct: 3,
      font: { size: 12, weight: '600' },
      color: '#fff',
      outline: '#000',
      outlineWidth: 2,
      formatter: (pct) => pct.toLocaleString('id-ID',{ maximumFractionDigits:1 }) + '%'
    }, cfg || {});

    const total = (ds.data || []).reduce((a,b)=>a + Number(b||0), 0);
    if (!total) return;

    ctx.save();
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.font = `${opt.font.weight} ${opt.font.size}px sans-serif`;

    const meta = chart.getDatasetMeta(0);
    meta.data.forEach((arc, i) => {
      const val = Number(ds.data?.[i] || 0);
      if (val <= 0) return;

      const pct = (val * 100) / total;
      if (pct < opt.minPct) return;

      const p = arc.getProps(
        ['x','y','startAngle','endAngle','innerRadius','outerRadius'], true
      );
      const angle = (p.startAngle + p.endAngle) / 2;
      const r = (p.innerRadius + p.outerRadius) / 2;
      const x = p.x + Math.cos(angle) * r;
      const y = p.y + Math.sin(angle) * r;

      const label = opt.formatter(pct, val);
      if (opt.outline && opt.outlineWidth > 0) {
        ctx.strokeStyle = opt.outline;
        ctx.lineWidth   = opt.outlineWidth;
        ctx.strokeText(label, x, y);
      }
      ctx.fillStyle = opt.color;
      ctx.fillText(label, x, y);
    });

    ctx.restore();
  }
};
Chart.register(PiePercentLabels);

/* ──────────────────────────────
   Plugin 2: Label angka di atas batang (bar)
─────────────────────────────── */
const ValueLabels = {
  id: 'valueLabels',
  afterDatasetsDraw(chart, args, pluginOpts) {
    const { ctx, chartArea } = chart;
    const isH = (chart.config?.options?.indexAxis === 'y'); // horizontal?
    const opt = Object.assign({
      font: { size: 11, weight: '600' },
      color: '#111',
      offset: 4,
      showZero: false,
      formatter: v => Number(v).toLocaleString('id-ID')
    }, pluginOpts || {});

    ctx.save();
    ctx.font = `${opt.font.weight} ${opt.font.size}px sans-serif`;
    ctx.textAlign = isH ? 'left' : 'center';
    ctx.textBaseline = isH ? 'middle' : 'bottom';
    ctx.fillStyle = opt.color;

    chart.data.datasets.forEach((ds, di) => {
      const meta = chart.getDatasetMeta(di);
      if (!meta || meta.type !== 'bar' || ds.hidden) return;

      meta.data.forEach((bar, i) => {
        const v = ds.data?.[i];
        if (v == null) return;
        if (!opt.showZero && Number(v) === 0) return;

        const p = bar.getProps(['x','y','base'], true);
        let x, y;
        if (isH) {
          x = Math.max(p.x, p.base) + opt.offset;      // ke kanan ujung bar
          y = p.y;
          x = Math.min(x, chartArea.right - 2);        // jangan keluar canvas
        } else {
          x = p.x;
          y = Math.min(p.y, p.base) - opt.offset;      // di atas batang
        }
        ctx.fillText(opt.formatter(v), x, y);
      });
    });

    ctx.restore();
  }
};
Chart.register(ValueLabels);

/* ──────────────────────────────
   Render semua chart
─────────────────────────────── */
document.addEventListener('DOMContentLoaded', function () {
  // 1) Gauge
  try {
    var g = <%= gaugeConfigJson %> || null;
    if (g && g.id) {
      var el = document.getElementById(g.id);
      if (el) new Chart(el, {
        type: g.type,
        data: g.data,
        options: {
          responsive: true,
          maintainAspectRatio: false,
          circumference: 180,
          rotation: 270,
          cutout: "70%",
          plugins: { legend: { display: true }, tooltip: { enabled: false } }
        }
      });
    }
  } catch (e) { console.error('Gauge error:', e); }

  // 2) Bar / Pie / Top-10
  try {
    var cfgs = <%= chartConfigJson %> || [];
    cfgs.forEach(function(c){
      var el2 = document.getElementById(c.id);
      if (!el2) return;

      // siapkan options & inject plugin sesuai tipe
      var opt = c.options || {};
      opt.plugins = opt.plugins || {};

      if (c.type === 'bar') {
        opt.plugins.valueLabels = {
          font: { size: 11, weight: '600' },
          color: '#111',
          offset: 4,
          showZero: false,
          formatter: function(v){ return Number(v).toLocaleString('id-ID'); }
        };
      }
      if (c.id === 'pieGender') {
        opt.plugins.piePercentLabels = {
          minPct: 2.5,
          color: '#fff',
          outline: '#000',
          outlineWidth: 2
          // formatter: (pct, val) => `${pct.toFixed(1)}% (${val.toLocaleString('id-ID')})`
        };
      }

      new Chart(el2, { type: c.type, data: c.data, options: opt });
    });
  } catch (e) { console.error('Charts error:', e); }

// 3) K-Means + legend custom (FINAL REVISI)
try {
  var kOpt = Number(<%= clusterKOptimal %>) || 0;
  var km   = <%= clusterChartJson %> || null;
  if (typeof km === 'string') { try { km = JSON.parse(km); } catch(e){ km = null; } }

  // palet golden-angle
  function kmColor(i){ var h=(i*137.508)%360; return 'hsl(' + h + ' 70% 45%)'; }

  // legend kustom
  function renderKmLegend(datasets, containerId){
    var box = document.getElementById(containerId);
    if (!box) return;
    box.innerHTML = datasets.map(function(ds, i){
      var col = ds.borderColor || ds.backgroundColor || kmColor(i);
      var n   = Array.isArray(ds.data) ? ds.data.length : 0;
      return '<span class="legend-item">'
           +   '<span class="legend-swatch" style="background:'+col+'"></span>'
           +   (ds.label || ('Klaster ' + (i+1))) + ' (' + n + ' wilayah)'
           + '</span>';
    }).join('');
  }

  // build datasets dari skema baru "scatter"; fallback skema lama
  var datasets = [];
  if (km && Array.isArray(km.scatter) && km.scatter.length){
    datasets = km.scatter.map(function(s, i){
      var color = kmColor(i);
      return {
        label: 'Klaster ' + (i+1),
        data: (s.data || []).map(function(p){
          return {
            x: +p.x,
            y: +p.y,
            label: p.label,
            totalCnt: p.totalCnt,
            femaleShare: p.femaleShare,
            // <<< tambahan penting >>>
            uniqSchool: (p.uniqSchool != null ? p.uniqSchool : null),
            avgPerSchool: (p.avgPerSchool != null ? p.avgPerSchool : null)
          };
        }),
        showLine: false,
        pointRadius: 3,
        pointHoverRadius: 5,
        pointBackgroundColor: color,
        pointBorderColor: color,
        borderColor: color,
        borderWidth: 1
      };
    });
  } else if (km && Array.isArray(km.datasets)) {
    datasets = km.datasets;
  }

  // bersih & batasi ke K optimal jika ada
  datasets = datasets.filter(function(ds){ return Array.isArray(ds.data) && ds.data.length>0; });
  if (kOpt > 0 && datasets.length > kOpt) datasets = datasets.slice(0, kOpt);

  // render chart
  var el = document.getElementById('scKMeansWilayah');
  if (!el || !datasets.length){
    console.warn('KMeans: dataset kosong / canvas tidak ada', km);
  } else {
    // autoscale + padding
    var xs=[], ys=[];
    datasets.forEach(function(ds){ (ds.data||[]).forEach(function(p){ xs.push(+p.x); ys.push(+p.y); }); });
    var xmin=Math.min.apply(null,xs), xmax=Math.max.apply(null,xs);
    var ymin=Math.min.apply(null,ys), ymax=Math.max.apply(null,ys);
    if (!isFinite(xmin) || !isFinite(xmax)) { xmin=0; xmax=1; }
    if (!isFinite(ymin) || !isFinite(ymax)) { ymin=0; ymax=1; }
    // --- hitung padding axis (KURANGI dari 8% -> 3%)
    var padX = ((xmax - xmin) || 1) * 0.03;
    var padY = ((ymax - ymin) || 1) * 0.03;

    renderKmLegend(datasets, 'kmLegend');

  new Chart(el, {
    type: 'scatter',
    data: { datasets: datasets },
    options: {
      maintainAspectRatio: false,
      plugins: {
        legend: { display: false },
        tooltip: {
              callbacks: {
                label: function(ctx){
                  var d = ctx.raw || {};
                  var fmt = function(v, f){
                    if (v==null) return '-';
                    var n = Number(v);
                    return isFinite(n)
                      ? n.toLocaleString('id-ID',{ maximumFractionDigits:(f||0) })
                      : '-';
                  };
                  return (d.label || 'Wilayah')
                      + ' | Total: ' + fmt(d.totalCnt)
                      + ' | Sekolah: ' + fmt(d.uniqSchool)
                      + ' | Rata" MABA/Sekolah: ' + fmt(d.avgPerSchool, 1);
                }
              }
            }
          },
      scales: {
        x: {
          title: { display: true, text: 'Jumlah Mahasiswa' },
          min: xmin - padX, max: xmax + padX,
          grace: 0,          // jangan tambah ruang otomatis
          ticks: { padding: 0 }
        },
        y: {
          title: { display: true, text: 'Jumlah Sekolah' },
          min: ymin - padY, max: ymax + padY,
          grace: 0,
          ticks: { padding: 0 }
        }
      }
    }
  });
    }
  } catch(e) { console.error('KMeans error:', e); }


  // 4) Regresi: aktifkan hover titik di Target + isi tabel prediksi dari dataset "Titik Prediksi"
  try{
    var regCfg = <%= regChartJson %> || null;
    var regEl  = document.getElementById('regTrend');

    if (regEl && regCfg) {
      // titik hover untuk garis Target
      var tgt = (regCfg.data?.datasets || []).find(d => (String(d.label||'').trim().toLowerCase() === 'target'));
      if (tgt) {
        tgt.pointRadius = 2;
        tgt.pointHoverRadius = 6;
        tgt.pointHitRadius = 12;
        tgt.pointBackgroundColor = tgt.borderColor || '#6b7280';
      }

      regCfg.options = regCfg.options || {};
      regCfg.options.interaction = { mode: 'index', intersect: false };
      regCfg.options.plugins = regCfg.options.plugins || {};
      regCfg.options.plugins.tooltip = {
        callbacks: {
          label: (ctx) => (ctx.dataset.label || 'Data') + ': ' + Number(ctx.parsed.y).toLocaleString('id-ID')
        }
      };

      var chart = new Chart(regEl, regCfg);

      // === render tabel prediksi ===
      var labels = (regCfg.data && regCfg.data.labels) || [];
      var predDs = (regCfg.data?.datasets || []).find(d => (d.label||'').toLowerCase().includes('titik prediksi'));
      var tb = document.getElementById('tblPredBody');
      if (tb && predDs && Array.isArray(predDs.data)) {
        var rows = '';
        predDs.data.forEach(function(v, i){
          if (v == null || isNaN(v)) return;          // hanya titik yang ada nilainya
          var th = labels[i] != null ? labels[i] : '';
          rows += '<tr><td>'+ th +'</td><td>'+ Math.round(Number(v)).toLocaleString('id-ID', {maximumFractionDigits:0}) +' pendaftar</td></tr>';
        });
        tb.innerHTML = rows || '<tr><td colspan="2"><em>Tidak ada data prediksi.</em></td></tr>';
      }
    }
  } catch(e){ console.error('Regresi chart error:', e); }
  });
</script>


<style>
  /* Grid KPI di header statistik */
  .kpi-grid{display:flex;flex-wrap:wrap;gap:12px;margin-bottom:8px}
  .kpi-grid .small-box{flex:1 1 220px;margin:0;border-radius:10px}
  .kpi-grid .small-box .inner{padding:14px}
  .kpi-grid .small-box h3{margin:0 0 4px;font-size:28px;line-height:1}

  @media (max-width:767px){
    .kpi-grid .small-box{flex:1 1 calc(50% - 12px)}
  }

.legend-list{display:flex;flex-wrap:wrap;gap:22px;margin:6px 0 12px}
.legend-item{display:flex;align-items:center;font-weight:500;color:#333}
.legend-swatch{width:22px;height:12px;border-radius:2px;margin-right:8px}
/* Legend K-Means di atas chart */
#kmLegend{
  display: flex;
  justify-content: center;   /* <— center */
  align-items: center;
  flex-wrap: wrap;           /* biar rapi saat sempit */
  gap: 14px 22px;            /* row x column gap */
  padding: 6px 0 10px;
}
#kmLegend .legend-item{
  display: inline-flex;
  align-items: center;
  font-weight: 500;
  color: #333;
}
#kmLegend .legend-swatch{
  width: 22px; height: 12px; border-radius: 3px; margin-right: 8px;
}

.stats-table{ margin-top:6px; }
.stats-table td:first-child{ width:140px; color:#555; font-weight:500; }
.stats-table .label{ font-size:12px; padding:4px 6px; border-radius:4px; }

.filter-range .form-control{ min-width:110px; }
@media (max-width:576px){ .filter-range{ display:flex; flex-wrap:wrap; gap:8px 16px; } }
.filter-range{ position:relative; z-index:50; }

/* Kartu angka */
.small-box.plain{
  position:relative; overflow:hidden;
  background:#f5f7fb; border:1px solid #e8edf5; border-radius:12px;
  padding:16px 120px 16px 16px;
}
.small-box.plain::before{ content:""; position:absolute; left:0; top:0; width:100%; height:10px;
  background:transparent; border-radius:12px 12px 0 0;
}
.small-box.plain .icon{ position:absolute; right:20px; top:50%; transform:translateY(-52%);
  width:88px; height:88px; display:flex; align-items:center; justify-content:center; }
.small-box .icon i{ font-size:68px; line-height:1; opacity:.9; }
.small-box .inner h3{ margin:2px 0 8px; font-weight:800; line-height:1; letter-spacing:.2px; }
.small-box .inner p{ margin:6px 0 0; font-size:18px; font-weight:600; line-height:1.35; color:#0f172a; }

/* Warna sesuai gambar */
.small-box.plain.tile-sky::before{ background:#38bdf8; }
.small-box.plain.tile-sky .inner h3, .small-box.plain.tile-sky .icon i{ color:#38bdf8; }

.small-box.plain.tile-red::before{ background:#ef4444; }
.small-box.plain.tile-red .inner h3, .small-box.plain.tile-red .icon i{ color:#ef4444; }

@media (max-width:991px){
  .small-box.plain{ padding-right:100px; }
  .small-box.plain .icon{ width:72px; height:72px; right:16px; }
  .small-box .icon i{ font-size:56px; }
}
@media (max-width:600px){
  .small-box.plain{ padding-right:76px; }
  .small-box.plain .icon{ width:56px; height:56px; }
  .small-box .icon i{ font-size:44px; }
}

.kpi-grid .small-box:nth-child(3),
.kpi-grid .small-box:nth-child(4){ display:none !important; }
</style>

