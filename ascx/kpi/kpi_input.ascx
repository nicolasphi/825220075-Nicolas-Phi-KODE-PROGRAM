<%@ Control Language="VB" ClassName="KpiMabaInputSimple" %>
<%@ Import Namespace="System.Data" %>
<%@ Import Namespace="System.Data.OleDb" %>

<script runat="server">
    ' === helper tampil/sembunyi panel ===
    Private Sub ShowList()
        pnlList.Visible = True
        pnlForm.Visible = False
        BindGrid() ' refresh tabel list KPI
    End Sub

    Private Sub ShowForm()
        pnlList.Visible = False
        pnlForm.Visible = True
        ' siapkan dropdown/cbl/grid form
        LoadFakultas()
        LoadJurusan()
    End Sub

    Protected Sub btnInputKPI_Click(sender As Object, e As EventArgs)
        hfEditMode.Value = "0" : hfEditTahun.Value = "" : hfEditKdFak.Value = "" : hfEditKdJur.Value = ""
        btnSimpan.Text = "Simpan KPI"
        ' reset form jika perlu
        ShowForm()
    End Sub

    Protected Sub btnBatal_Click(sender As Object, e As EventArgs)
        ShowList()
    End Sub

  ' === KONFIG (pindahkan ke Web.config untuk produksi) ===
  Private Const CONN As String =
    "Provider=sqloledb;Data Source=10.200.120.83,1433;Network Library=DBMSSOCN;" &
    "Initial Catalog=Pmbregol;User ID=sa;Password=dbTesting2023;connect timeout=200;pooling=false;max pool size=200"

    Private Shared ReadOnly FakJurMap As Dictionary(Of String, String()) = CreateFakJurMap()

    Private Shared Function CreateFakJurMap() As Dictionary(Of String, String())
        Dim d As New Dictionary(Of String, String())()
        d("111") = New String() {"115"}
        d("121") = New String() {"125"}
        d("201") = New String() {"205"}
        d("310") = New String() {"315"}
        d("320") = New String() {"325"}
        d("340") = New String() {"345"}
        d("400") = New String() {"405"}
        d("510") = New String() {"515"}
        d("520") = New String() {"525"}
        d("540") = New String() {"545"}
        d("530") = New String() {"535"}    
        d("820") = New String() {"825"}
        d("610") = New String() {"615"}
        d("620") = New String() {"625"}
        d("700") = New String() {"705"}
        d("910") = New String() {"915"}
        d("217") = New String() {"217"}
        d("406") = New String() {"406"}
        Return d
    End Function

    Private Function GetAllowedJurusanFor(kdFak As String) As HashSet(Of String)
        If FakJurMap.ContainsKey(kdFak) Then
            Return New HashSet(Of String)(FakJurMap(kdFak), StringComparer.OrdinalIgnoreCase)
        End If
        Return New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
    End Function

    Private Function GetAllowedJurusanUnion(kdFaks As IEnumerable(Of String)) As HashSet(Of String)
        Dim h As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
        For Each f In kdFaks
            If FakJurMap.ContainsKey(f) Then
                For Each j In FakJurMap(f) : h.Add(j) : Next
            End If
        Next
        Return h
    End Function

    Protected Sub Page_Load(sender As Object, e As EventArgs) Handles Me.Load
        If Not IsPostBack Then
        ' === Tahun untuk LIST ===
        ddlTahunList.Items.Clear()
        For th As Integer = 2017 To 2023
            ddlTahunList.Items.Add(New ListItem(th.ToString(), th.ToString()))
        Next
        If ddlTahunList.Items.Count > 0 Then ddlTahunList.SelectedIndex = ddlTahunList.Items.Count - 1

        ' === Tahun untuk FORM ===
        ddlTahunForm.Items.Clear()
        For th As Integer = 2017 To 2023
            ddlTahunForm.Items.Add(New ListItem(th.ToString(), th.ToString()))
        Next
        If ddlTahunForm.Items.Count > 0 Then ddlTahunForm.SelectedIndex = ddlTahunForm.Items.Count - 1

        ShowList()   ' Halaman awal = panel list
    End If
    End Sub


    Private Sub LoadFakultas()
        Using cn As New OleDb.OleDbConnection(CONN)
            cn.Open()
            ' kd_fak = tjurus.kd_jur (sesuai logika baru)
            Dim sql As String =
            "SELECT DISTINCT CAST(tj.kd_jur AS varchar(10)) AS kd_fak, tj.nm_fak " &
            "FROM dbo.tjurus tj " &
            "WHERE tj.kd_jur IS NOT NULL AND LTRIM(RTRIM(tj.nm_fak)) <> '' " &
            "ORDER BY tj.nm_fak, CAST(tj.kd_jur AS varchar(10))"

            Using cmd As New OleDb.OleDbCommand(sql, cn)
                Using rd = cmd.ExecuteReader()
                    cblFakultas.Items.Clear()
                    While rd.Read()
                        Dim kode = rd("kd_fak").ToString().Trim()
                        Dim nama = rd("nm_fak").ToString().Trim()
                        ' tampilkan "111 - EKONOMI DAN BISNIS"
                        Dim tampil As String = String.Format("{0} - {1}", kode, nama)
                        cblFakultas.Items.Add(New ListItem(tampil, kode))
                    End While
                End Using
            End Using
        End Using
    End Sub


    Protected Sub cblFakultas_SelectedIndexChanged(sender As Object, e As EventArgs)
        Dim faks = (From it As ListItem In cblFakultas.Items
                    Where it.Selected
                    Select it.Value).ToList()
        LoadJurusan(faks)
    End Sub

    Private Sub LoadJurusan(Optional selectedFaks As List(Of String) = Nothing)
        Using cn As New OleDb.OleDbConnection(CONN)
            cn.Open()
            Dim sql As String =
                "SELECT CAST(tj.kode_jurnim AS varchar(10)) AS kode_jurnim, " &
                "       CAST(tj.kd_jur     AS varchar(10)) AS kd_fak_ref, " &
                "       tj.nm_jur " &
                "FROM dbo.tjurus tj " &
                "WHERE tj.kode_jurnim IS NOT NULL " &
                "ORDER BY tj.nm_jur"

            Using cmd As New OleDb.OleDbCommand(sql, cn)
            Using da As New OleDb.OleDbDataAdapter(cmd)
            Dim dt As New DataTable() : da.Fill(dt)

    ' Filter jurusan pakai mapping dari fakultas terpilih
    If selectedFaks IsNot Nothing AndAlso selectedFaks.Count > 0 Then
        Dim allowed As HashSet(Of String) = GetAllowedJurusanUnion(selectedFaks)
        Dim filtered As DataTable = dt.Clone()
        For Each r As DataRow In dt.Rows
            If allowed.Contains(r("kode_jurnim").ToString()) Then
                filtered.ImportRow(r)
            End If
        Next
        dt = filtered
    End If

    dt.Columns.Add("NamaJurusan", GetType(String))
        For Each row As DataRow In dt.Rows
            row("NamaJurusan") = row("kode_jurnim").ToString() & " - " & row("nm_jur").ToString()
        Next
                gvJurusan.DataSource = dt
                gvJurusan.DataBind()
                End Using
            End Using
        End Using
    End Sub

Protected Sub btnSimpan_Click(sender As Object, e As EventArgs)
    lblMsg.CssClass = "text-danger" : lblMsg.Text = ""

    ' --- Tambahkan ini: tentukan mode INSERT/UPDATE lebih dulu ---
    Dim isUpdate As Boolean = (hfEditMode.Value = "1")

    Dim tahun As Integer
    If Not Integer.TryParse(ddlTahunForm.SelectedValue, tahun) Then
        lblMsg.Text = "Tahun tidak valid." : Exit Sub
    End If
    If cblFakultas.SelectedItem Is Nothing Then
        lblMsg.Text = "Pilih fakultas terlebih dahulu." : Exit Sub
    End If

    Try
        Using cn As New OleDb.OleDbConnection(CONN)
            cn.Open()

            If hfEditMode.Value = "1" Then
                ' === UPDATE satu baris ===
                Dim kdFak As String = hfEditKdFak.Value
                Dim kdJur As String = hfEditKdJur.Value
                Dim target As Integer = 0

                ' cari nilai target dari grid (jurusan yang sama dengan kdJur)
                For Each row As GridViewRow In gvJurusan.Rows
                    Dim dk As DataKey = gvJurusan.DataKeys(row.RowIndex)
                    Dim kodeRow As String = Convert.ToString(dk("kode_jurnim"))

                    If String.Equals(kodeRow, kdJur, StringComparison.OrdinalIgnoreCase) Then
                        Dim txt As TextBox = TryCast(row.FindControl("txtTargetRow"), TextBox)
                        If txt IsNot Nothing Then Integer.TryParse(txt.Text.Trim(), target)
                        Exit For
                    End If
                Next


                Dim sqlU As String =
                    "UPDATE dbo.kpi_maba SET target_total=?, update_at=GETDATE() " &
                    "WHERE tahun=? AND kd_fak=? AND kd_jur=?"

                Using cmd As New OleDb.OleDbCommand(sqlU, cn)
                    cmd.Parameters.AddWithValue("@p1", target)
                    cmd.Parameters.AddWithValue("@p2", tahun)
                    cmd.Parameters.AddWithValue("@p3", kdFak)
                    cmd.Parameters.AddWithValue("@p4", kdJur)
                    cmd.ExecuteNonQuery()
                End Using

                ' reset mode
                hfEditMode.Value = "0" : hfEditTahun.Value = "" : hfEditKdFak.Value = "" : hfEditKdJur.Value = ""
                btnSimpan.Text = "Simpan KPI"

            Else
              ' === INSERT: satu baris per jurusan yang dicentang ===
              For Each row As GridViewRow In gvJurusan.Rows
                  Dim chk As CheckBox = TryCast(row.FindControl("chkPilih"), CheckBox)
                  Dim txt As TextBox = TryCast(row.FindControl("txtTargetRow"), TextBox)
                  If chk Is Nothing OrElse txt Is Nothing OrElse Not chk.Checked Then Continue For

                  Dim target As Integer : Integer.TryParse(txt.Text.Trim(), target)

                  Dim dk As DataKey = gvJurusan.DataKeys(row.RowIndex)
                  Dim kdJur As String = Convert.ToString(dk("kode_jurnim"))
                  Dim kdFak As String = Convert.ToString(dk("kd_fak_ref"))

                  If String.IsNullOrEmpty(kdJur) OrElse String.IsNullOrEmpty(kdFak) Then Continue For

                  Dim sqlI As String =
                    "INSERT INTO dbo.kpi_maba (tahun, kd_fak, kd_jur, target_total, created_at, update_at) " &
                    "VALUES (?,?,?, ?, GETDATE(), GETDATE())"

                  Using cmd As New OleDb.OleDbCommand(sqlI, cn)
                      cmd.Parameters.AddWithValue("@p1", tahun)
                      cmd.Parameters.AddWithValue("@p2", kdFak)
                      cmd.Parameters.AddWithValue("@p3", kdJur)
                      cmd.Parameters.AddWithValue("@p4", target)
                      cmd.ExecuteNonQuery()
                  End Using
              Next
          End If
        End Using

        lblMsg.CssClass = "text-success"
        lblMsg.Text = If(isUpdate, "KPI berhasil diupdate.", "KPI berhasil disimpan.")


        ' Tambahkan toast:
        Dim toastScript As String = If(isUpdate,
            "showToast('KPI berhasil diupdate.', 'success', 'Berhasil', 'middle');",
            "showToast('KPI berhasil disimpan.', 'success', 'Berhasil', 'middle');")

        ScriptManager.RegisterStartupScript(Me, Me.GetType(), "toastSaveUpdate", toastScript, True)
        ShowList()

    Catch ex As Exception
        lblMsg.CssClass = "text-danger"
        lblMsg.Text = "Gagal menyimpan: " & Server.HtmlEncode(ex.Message)
    End Try
End Sub

    ' === Bind data ke Grid ===
Private Sub BindGrid()
    Dim tahun As Integer
    Dim filterByYear As Boolean = Integer.TryParse(ddlTahunList.SelectedValue, tahun)

    Using cn As New OleDbConnection(CONN)
        cn.Open()
        Dim sql As String =
            "SELECT km.tahun, km.kd_fak, f.nm_fak, km.kd_jur, j.nm_jur, km.target_total " &
            "FROM dbo.kpi_maba AS km " &
            "LEFT JOIN dbo.tjurus AS f ON CAST(f.kd_jur AS varchar(10)) = km.kd_fak " &
            "LEFT JOIN dbo.tjurus AS j ON CAST(j.kode_jurnim AS varchar(10)) = km.kd_jur " &
            If(filterByYear, "WHERE km.tahun = ? ", "") &
            "ORDER BY km.tahun DESC, km.kd_fak, km.kd_jur"

        Using cmd As New OleDbCommand(sql, cn)
            If filterByYear Then cmd.Parameters.AddWithValue("@p1", tahun)
            Using da As New OleDbDataAdapter(cmd)
                Dim dt As New DataTable()
                da.Fill(dt)
                lvKpi.DataSource = dt
                lvKpi.DataBind()
            End Using
        End Using
    End Using
End Sub

Protected Sub lvKpi_ItemCommand(sender As Object, e As ListViewCommandEventArgs)
    Dim arg As String = If(e.CommandArgument, "").ToString()
    Dim p() As String = arg.Split("|"c)
    If p.Length <> 3 Then Exit Sub

    Dim tahun As Integer
    If Not Integer.TryParse(p(0), tahun) Then
        lblMsg.CssClass = "text-danger"
        lblMsg.Text = "Argumen tahun tidak valid."
        Exit Sub
    End If

    Dim kdFak As String = p(1).Trim()
    Dim kdJur As String = p(2).Trim()

    Select Case e.CommandName
        Case "EditRow"
            LoadEdit(tahun, kdFak, kdJur)
            ShowForm()
        Case "DeleteRow"
            Try
                Using cn As New OleDbConnection(CONN)
                    cn.Open()
                    Using cmd As New OleDbCommand(
                        "DELETE FROM dbo.kpi_maba WHERE tahun=? AND kd_fak=? AND kd_jur=?", cn)
                        cmd.Parameters.AddWithValue("@p1", tahun)
                        cmd.Parameters.AddWithValue("@p2", kdFak)
                        cmd.Parameters.AddWithValue("@p3", kdJur)
                        cmd.ExecuteNonQuery()
                    End Using
                End Using
                lblMsg.CssClass = "text-success"
                lblMsg.Text = String.Format("Data KPI {0} / {1} / {2} berhasil dihapus.", tahun, kdFak, kdJur)
                BindGrid()
            Catch ex As Exception
                lblMsg.CssClass = "text-danger"
                lblMsg.Text = "Gagal hapus: " & Server.HtmlEncode(ex.Message)
            End Try
    End Select
End Sub



    Private Sub LoadEdit(th As Integer, kdFak As String, kdJur As String)
    ' simpan mode edit
    hfEditMode.Value = "1"
    hfEditTahun.Value = th.ToString()
    hfEditKdFak.Value = kdFak
    hfEditKdJur.Value = kdJur
    btnSimpan.Text = "Update"

    ' set dropdown tahun
    If ddlTahunForm.Items.FindByValue(th.ToString()) IsNot Nothing Then
        ddlTahunForm.ClearSelection()
        ddlTahunForm.Items.FindByValue(th.ToString()).Selected = True
    End If

    ' muat fakultas dan tandai fakultas terkait
    LoadFakultas()
    For Each li As ListItem In cblFakultas.Items
        li.Selected = (String.Equals(li.Value, kdFak, StringComparison.OrdinalIgnoreCase))
    Next

    ' muat jurusan untuk fak tersebut
    LoadJurusan(New List(Of String) From { kdFak })

    ' set nilai target utk jurusan tsb
    Dim targetVal As Integer = 0
    Using cn As New OleDb.OleDbConnection(CONN)
        cn.Open()
        Dim sql As String = "SELECT target_total FROM dbo.kpi_maba WHERE tahun=? AND kd_fak=? AND kd_jur=?"
        Using cmd As New OleDb.OleDbCommand(sql, cn)
            cmd.Parameters.AddWithValue("@p1", th)
            cmd.Parameters.AddWithValue("@p2", kdFak)
            cmd.Parameters.AddWithValue("@p3", kdJur)
            Dim o = cmd.ExecuteScalar()
            If o IsNot Nothing AndAlso o IsNot DBNull.Value Then
                targetVal = Convert.ToInt32(o)
            End If
        End Using
    End Using

    ' centang baris jurusan dan isi textbox target
    For Each row As GridViewRow In gvJurusan.Rows
        Dim dk As DataKey = gvJurusan.DataKeys(row.RowIndex)
        Dim key As String = Convert.ToString(dk("kode_jurnim"))
        If String.Equals(key, kdJur, StringComparison.OrdinalIgnoreCase) Then
            Dim chk As CheckBox = TryCast(row.FindControl("chkPilih"), CheckBox)
            Dim txt As TextBox = TryCast(row.FindControl("txtTargetRow"), TextBox)
            If chk IsNot Nothing Then chk.Checked = True
            If txt IsNot Nothing Then txt.Text = targetVal.ToString()
        End If
    Next
End Sub

' Paging ListView
Protected Sub lvKpi_PagePropertiesChanging(sender As Object, e As PagePropertiesChangingEventArgs)
    dpKpi.SetPageProperties(e.StartRowIndex, e.MaximumRows, False)
    BindGrid()
End Sub

' Ganti tahun (dropdown di panel list)
Protected Sub ddlTahunList_SelectedIndexChanged(sender As Object, e As EventArgs)
    dpKpi.SetPageProperties(0, dpKpi.PageSize, False) ' reset ke halaman 1
    BindGrid()
End Sub

</script>

<asp:Panel ID="pnlList" runat="server" Visible="true">
  <div class="kpi-topbar">
    <h1>KPI MAHASISWA BARU</h1>
    <ol class="kpi-breadcrumb">
      <li><a href="/dashboard_pmb/index.aspx"><i class="fa fa-dashboard"></i> Dashboard</a></li>
        <li class="active">List KPI</li>
    </ol>
  </div>
  <div class="kpi-list"> 
  <div class="box box-primary">
    <div class="box-header with-border">
      <h3 class="box-title">List KPI Mahasiswa Baru</h3>

      <div class="box-tools pull-right" style="display:flex; gap:8px; align-items:center;">
        <!-- Dropdown filter tahun -->
        <asp:DropDownList ID="ddlTahunList" runat="server"
            CssClass="form-control input-sm"
            AutoPostBack="true"
            OnSelectedIndexChanged="ddlTahunList_SelectedIndexChanged"
            ToolTip="Filter berdasarkan tahun" />
        <!-- Tombol Input KPI -->
        <asp:Button ID="btnInputKPI" runat="server"
                    Text="Input KPI"
                    CssClass="btn btn-success btn-sm"
                    OnClick="btnInputKPI_Click" />
      </div>
    </div>

 <div class="box-body">
  <div class="kpi-wrap">
    <div class="table-responsive">
      <asp:ListView ID="lvKpi" runat="server"
        OnItemCommand="lvKpi_ItemCommand"
        OnPagePropertiesChanging="lvKpi_PagePropertiesChanging">

        <LayoutTemplate>
          <div class="kpi-grid">
            <div class="kpi-row kpi-head">
              <div>Tahun</div><div>Nama Fakultas</div><div>Nama Jurusan</div>
              <div class="num">Target MABA</div><div class="aksi">Aksi</div>
            </div>
            <div id="itemPlaceholder" runat="server"></div>
          </div>
        </LayoutTemplate>

        <ItemTemplate>
          <div class="kpi-row">
            <div><%# Eval("tahun") %></div>
            <div><%# Eval("nm_fak") %></div>
            <div><%# Eval("nm_jur") %></div>
            <div class="num"><%# String.Format("{0:N0}", Eval("target_total")) %></div>
            <div class="aksi">
              <asp:LinkButton ID="btnEdit" runat="server" CommandName="EditRow"
                CommandArgument='<%# Eval("tahun") & "|" & Eval("kd_fak") & "|" & Eval("kd_jur") %>'
                CssClass="btn btn-warning btn-xs"><i class="fa fa-pencil"></i> Edit</asp:LinkButton>
              <asp:LinkButton ID="btnDel" runat="server" CommandName="DeleteRow"
                OnClientClick="return confirm('Yakin hapus data KPI ini?');"
                CommandArgument='<%# Eval("tahun") & "|" & Eval("kd_fak") & "|" & Eval("kd_jur") %>'
                CssClass="btn btn-danger btn-xs"><i class="fa fa-trash"></i> Hapus</asp:LinkButton>
            </div>
          </div>
        </ItemTemplate>

        <EmptyDataTemplate>
          <div class="kpi-grid">
            <div class="kpi-row kpi-head">
              <div>Tahun</div><div>Nama Fakultas</div><div>Nama Jurusan</div>
              <div class="num">Target MABA</div><div class="aksi">Aksi</div>
            </div>
            <div class="kpi-empty text-muted">Belum ada data KPI pada tahun yang dipilih.</div>
          </div>
        </EmptyDataTemplate>

      </asp:ListView>
    </div>

    <!-- PAGER dipindah ke bawah dan “nempel” -->
    <div class="kpi-pager">
      <!-- UBAH PageSize jika mau tampil >10 baris per halaman -->
      <asp:DataPager ID="dpKpi" runat="server" PagedControlID="lvKpi" PageSize="15">
        <Fields>
          <asp:NextPreviousPagerField ShowFirstPageButton="true" ShowPreviousPageButton="true"
              ShowNextPageButton="false" ShowLastPageButton="false" ButtonCssClass="btn btn-default btn-xs" />
          <asp:NumericPagerField ButtonCount="10" NumericButtonCssClass="btn btn-default btn-xs"
              CurrentPageLabelCssClass="btn btn-primary btn-xs disabled" />
          <asp:NextPreviousPagerField ShowFirstPageButton="false" ShowPreviousPageButton="false"
              ShowNextPageButton="true" ShowLastPageButton="true" ButtonCssClass="btn btn-default btn-xs" />
        </Fields>
      </asp:DataPager>
    </div>
  </div>
</div>
</div>
</asp:Panel>


<asp:Panel ID="pnlForm" runat="server" Visible="false">
<div class="kpi-topbar">
    <h1>INPUT KPI MAHASISWA BARU</h1>
    <ol class="kpi-breadcrumb">
      <li><a href="/dashboard_pmb/index.aspx"><i class="fa fa-dashboard"></i> Dashboard</a></li>
      <li class="active">Input KPI</li>
    </ol>
  </div>

  <!-- Bungkus form dengan .kpi-form agar CSS-nya spesifik -->
  <div class="kpi-form">
  <div class="box box-primary">
    <div class="box-header with-border">
      <h3 class="box-title">Input KPI Mahasiswa Baru</h3>
      <div class="box-tools pull-right">
        <asp:Button ID="btnBatal" runat="server" Text="Batal"
            CssClass="btn btn-default btn-sm" OnClick="btnBatal_Click" />
      </div>
    </div>

    <div class="box-body">
      <asp:HiddenField ID="hfEditMode" runat="server" Value="0" />
      <asp:HiddenField ID="hfEditTahun" runat="server" />
      <asp:HiddenField ID="hfEditKdFak" runat="server" />
      <asp:HiddenField ID="hfEditKdJur" runat="server" />

      <table class="table table-bordered table-striped" style="max-width:720px;">
        <tbody>
          <tr>
            <th style="width:220px;">Tahun</th>
            <td>
              <asp:DropDownList ID="ddlTahunForm" runat="server"
                  CssClass="form-control" />
            </td>
          </tr>
          <tr>
  <th>Fakultas</th>
  <td style="vertical-align:top;">
    <asp:CheckBoxList ID="cblFakultas" runat="server"
      CssClass="cbl-fakultas"
      RepeatLayout="Table" RepeatDirection="Vertical" RepeatColumns="2"
      AutoPostBack="true" OnSelectedIndexChanged="cblFakultas_SelectedIndexChanged" />
    <small class="text-muted">Pilih satu atau lebih fakultas.</small>
  </td>
</tr>

<tr>
  <th>Jurusan</th>
  <td>
    <asp:GridView ID="gvJurusan" runat="server"
      CssClass="table table-bordered table-striped"
      AutoGenerateColumns="False"
      DataKeyNames="kode_jurnim,kd_fak_ref">
      <Columns>
        <asp:TemplateField HeaderText="Pilih">
          <ItemTemplate><asp:CheckBox ID="chkPilih" runat="server" /></ItemTemplate>
          <ItemStyle HorizontalAlign="Center" />
        </asp:TemplateField>
        <asp:BoundField DataField="NamaJurusan" HeaderText="Jurusan" />
        <asp:TemplateField HeaderText="Target Mahasiswa Baru">
          <ItemTemplate>
            <asp:TextBox ID="txtTargetRow" runat="server" CssClass="form-control" />
          </ItemTemplate>
        </asp:TemplateField>
      </Columns>
    </asp:GridView>
  </td>
</tr>
        </tbody>
      </table>

      <asp:Button ID="btnSimpan" runat="server" CssClass="btn btn-primary"
                  Text="Simpan KPI" OnClick="btnSimpan_Click" />
      &nbsp;<asp:Label ID="lblMsg" runat="server" />
    </div>
  </div>
  </div>
</asp:Panel>

<link rel="stylesheet"
      href="https://site-assets.fontawesome.com/releases/v6.4.2/css/all.css" />

<style>
/* ===========================
   GLOBAL LAYOUT (AdminLTE 2/3)
   Keep footer at the bottom
   =========================== */

/* AdminLTE 3 */
.content-wrapper{
  display:flex;
  flex-direction:column;
  min-height:100vh;
}
.content-wrapper > .content{
  flex:1 1 auto;
  min-height:0;
}
.main-footer{
  margin-top:auto;
}

/* AdminLTE 2 (safe to keep alongside the above) */
.right-side, .content-wrapper{
  display:flex;
  flex-direction:column;
  min-height:100vh;
}
.content{
  flex:1 1 auto;
  min-height:0;
}

/* ===========================
   KPI LIST AREA ONLY
   =========================== */

.kpi-list .box-body{
  display:flex;
  flex-direction:column;
  min-height:0;
  padding-bottom:16px;
}

.kpi-list .kpi-wrap{
  display:flex;
  flex-direction:column;
  flex:1 1 auto;
}

.kpi-list .kpi-wrap .table-responsive{
  flex:1 1 auto;
  overflow-x:auto;
}

.kpi-list .kpi-pager{
  position:static;
  margin-top:auto;
  padding-top:8px;
  background:transparent;
  border-top:0;
}

.kpi-pager .btn{
  margin:0 2px;
}

/* ===========================
   KPI GRID STYLE
   =========================== */

.table-responsive{ overflow-x:auto; }

.kpi-grid{
  display:block;
  border:1px solid #ddd;
  border-radius:4px;
  background:#fff;
  margin-top:8px;
}

.kpi-row{
  display:grid;
  grid-template-columns:110px 1.4fr 1.6fr 130px 170px; /* Tahun | Fakultas | Jurusan | Target | Aksi */
  gap:0;
  border-top:1px solid #eee;
}

.kpi-row > div{
  padding:12px 14px;
  align-self:center;
}

.kpi-row .num{ text-align:right; }
.kpi-row .aksi{ text-align:center; white-space:nowrap; }

.kpi-head{
  background:#f5f7fa;
  font-weight:600;
  border-top:none;
}

.kpi-grid .kpi-row:nth-child(even):not(.kpi-head){
  background:#fafafa;
}

.kpi-empty{
  padding:14px;
  color:#666;
}

/* ===========================
   TOPBAR TITLE + BREADCRUMB
   =========================== */

.kpi-topbar{
  background:#ecf0f5;              /* warna abu-abu lembut AdminLTE */
  border-bottom:1px solid #d2d6de;
  padding:18px 24px;               /* isi bar */
  margin:0 -15px 24px;             /* biar full-width */
  display:flex;
  align-items:center;
  justify-content:space-between;
  gap:16px;
}
.kpi-topbar h1{
  font-size:22px;
  font-weight:600;
  color:#2c3e50;
  margin:0;
  letter-spacing:.2px;
}
.kpi-breadcrumb{
  list-style:none;
  display:flex;
  gap:8px;
  margin:0;
  padding:0;
  color:#6c757d;
}
.kpi-breadcrumb li{
  display:inline-flex;
  align-items:center;
  gap:6px;
  font-size:14px;
}
.kpi-breadcrumb li + li::before{
  content: ">";
  margin:0 6px; 
  color:#9aa0a6;
}
.kpi-breadcrumb .active{
  color:#495057;
  font-weight:600;
}

/* ===========================
   BOX HEADER (judul List KPI + filter kanan)
   =========================== */

.kpi-list .box{
  background:transparent;
  border:0;
  box-shadow:none;
}
.kpi-list .box-header{
  padding:12px 4px 10px;
  display:flex;
  align-items:center;
  gap:16px;
}
.kpi-list .box-header.with-border{
  border-bottom:0;
  background:transparent;
  padding-left:0;
  padding-right:0;
}
.kpi-list .box-header .box-title{ margin:0; font-weight:600; }
.kpi-list .box-header .box-tools{
  margin-left:auto;
  display:flex;
  align-items:center;
  gap:12px;
}

/* ===========================
   PAGER + TABLE SPACING
   =========================== */

.kpi-list .kpi-grid{ margin-top:8px; }
.kpi-list .kpi-pager{ padding-top:12px; }
.kpi-pager .btn{ margin:0 3px; }

/* ===========================
   RESPONSIVE TWEAKS
   =========================== */

@media (max-width: 992px){
  .kpi-row{
    grid-template-columns:90px 1fr 1fr 110px 150px;
  }
  .kpi-list .box-header{ flex-wrap:wrap; }
  .kpi-list .box-header .box-tools{ margin-left:0; }
}

@media (max-width: 720px){
  .kpi-topbar{
    margin:0 -10px 16px;
    padding:12px 16px;
    flex-direction:column;
    align-items:flex-start;
  }
  .kpi-breadcrumb{ flex-wrap:wrap; font-size:13px; }
  .kpi-row{
    grid-template-columns:1fr 1fr;
  }
  .kpi-head{ display:none; }
  .kpi-row > div:nth-child(1){ font-weight:600; }
  .kpi-row .num,
  .kpi-row .aksi{
    grid-column:1 / -1;
    text-align:left;
  }
}

/* =============== GLOBAL / WRAPPER =============== */
/* Pastikan footer tetap di bawah, sama seperti sebelumnya */
.content-wrapper{
  display:flex; flex-direction:column; min-height:100vh;
}
.content-wrapper > .content{ flex:1 1 auto; min-height:0; }
.main-footer{ margin-top:auto; }

/* =============== TOPBAR (judul + breadcrumb) =============== */
.kpi-topbar{
  background:#ecf0f5;
  border-bottom:1px solid #d2d6de;
  /* ruang dari bar kuning (navbar) */
  margin:8px -15px 20px;          /* full-bleed + jarak bawah */
  padding:16px 24px;              /* tinggi bar */
  display:flex; align-items:center; justify-content:space-between; gap:16px;
}
.kpi-topbar h1{
  margin:0; font-size:22px; font-weight:600; color:#2c3e50; letter-spacing:.2px;
}
.kpi-breadcrumb{
  list-style:none; margin:0; padding:0; display:flex; align-items:center; gap:8px; color:#6c757d;
}
.kpi-breadcrumb li{ display:inline-flex; align-items:center; gap:6px; font-size:14px; }
.kpi-breadcrumb li + li::before{ content: ">"; margin:0 6px; color:#9aa0a6; }
.kpi-breadcrumb .active{ color:#495057; font-weight:600; }

/* =============== LIST PAGE (sudah bagus, tetap) =============== */
.kpi-list .box{ background:transparent; border:0; box-shadow:none; }
.kpi-list .box-header{ padding:12px 4px 10px; display:flex; align-items:center; gap:16px; }
.kpi-list .box-header.with-border{ border-bottom:0; background:transparent; padding-left:0; padding-right:0; }
.kpi-list .box-header .box-title{ margin:0; font-weight:600; }
.kpi-list .box-header .box-tools{ margin-left:auto; display:flex; align-items:center; gap:12px; }

.kpi-list .box-body{ display:flex; flex-direction:column; min-height:0; padding-bottom:16px; }
.kpi-list .kpi-wrap{ display:flex; flex-direction:column; flex:1 1 auto; }
.kpi-list .kpi-wrap .table-responsive{ flex:1 1 auto; overflow-x:auto; }

.kpi-list .kpi-pager{ position:static; margin-top:auto; padding-top:12px; background:transparent; border-top:0; }
.kpi-pager .btn{ margin:0 3px; }

/* Grid list */
.table-responsive{ overflow-x:auto; }
.kpi-grid{ display:block; border:1px solid #ddd; border-radius:4px; background:#fff; margin-top:8px; }
.kpi-row{
  display:grid;
  grid-template-columns:110px 1.4fr 1.6fr 130px 170px;
  gap:0; border-top:1px solid #eee;
}
.kpi-row > div{ padding:12px 14px; align-self:center; }
.kpi-row .num{ text-align:right; } .kpi-row .aksi{ text-align:center; white-space:nowrap; }
.kpi-head{ background:#f5f7fa; font-weight:600; border-top:none; }
.kpi-grid .kpi-row:nth-child(even):not(.kpi-head){ background:#fafafa; }

/* =============== FORM PAGE (Input KPI) =============== */
/* memberi ruang dari bar kuning (tambahan aman selain topbar) */
.kpi-form{ padding-top:6px; }

/* CheckBoxList WebForms biasanya table -> beri jarak antar sel */
.cbl-fakultas{
  /* biar dua kolom terlihat rapi */
  display:inline-table; border-collapse:separate; border-spacing:0 6px; /* jarak vertikal 6px */
  margin-top:4px;
}
.cbl-fakultas td{
  padding:4px 20px 4px 0;          /* ruang antar item & antar kolom */
  vertical-align:top;
  line-height:1.3;
  white-space:nowrap;
}
/* jarak antara checkbox dan teks */
.cbl-fakultas input[type="checkbox"]{ margin-right:8px; transform: translateY(1px); }

/* catatan kecil di bawah cbl */
small.text-muted{ display:inline-block; margin-top:4px; }

/* Grid jurusan di form (optional rapikan) */
#gvJurusan.table{ margin-top:8px; }

/* =============== RESPONSIVE =============== */
@media (max-width: 992px){
  .kpi-row{ grid-template-columns:90px 1fr 1fr 110px 150px; }
  .kpi-list .box-header{ flex-wrap:wrap; }
  .kpi-list .box-header .box-tools{ margin-left:0; }
}
@media (max-width: 720px){
  .kpi-topbar{ margin:8px -10px 14px; padding:12px 16px; flex-direction:column; align-items:flex-start; }
  .kpi-breadcrumb{ flex-wrap:wrap; font-size:13px; }
  .kpi-row{ grid-template-columns:1fr 1fr; }
  .kpi-head{ display:none; }
  .kpi-row > div:nth-child(1){ font-weight:600; }
  .kpi-row .num, .kpi-row .aksi{ grid-column:1 / -1; text-align:left; }
  .cbl-fakultas{ border-spacing:0 8px; }   /* sedikit lebih renggang di mobile */
  .cbl-fakultas td{ padding-right:14px; }
}

</style>

<style>
  /* ===== TOAST (popup) ===== */
  .toast-wrap{position:fixed;left:0;right:0;z-index:9999;pointer-events:none}
  .toast-wrap.pos-center{bottom:24px;display:flex;justify-content:center}
  .toast-wrap.pos-middle{top:50%;transform:translateY(-50%);display:flex;justify-content:center}
  .toast{
    min-width:260px; max-width:520px; padding:12px 14px; border-radius:10px;
    background:#2b2f36; color:#fff; box-shadow:0 10px 24px rgba(0,0,0,.25);
    opacity:0; transform:translateY(8px); transition:all .25s ease; pointer-events:auto
  }
  .toast.show{opacity:1; transform:translateY(0)}
  .toast .t-h{font-weight:700; margin-bottom:4px; font-size:14px; line-height:1.2}
  .toast .t-b{font-size:13px; line-height:1.35}
  /* warna */
  .toast.success{background:#2e7d32}
  .toast.info{background:#1565c0}
  .toast.error{background:#c62828}
</style>

<script>
  // showToast(message, type='info', title='', position='center'|'middle')
  function showToast(message, type, title, position){
    type = type || 'info';
    position = (position === 'middle') ? 'middle' : 'center';

    var wrap = document.getElementById('toast-wrap');
    if(!wrap){
      wrap = document.createElement('div');
      wrap.id = 'toast-wrap';
      document.body.appendChild(wrap);
    }
    wrap.className = 'toast-wrap ' + (position === 'middle' ? 'pos-middle' : 'pos-center');

    var el = document.createElement('div');
    el.className = 'toast ' + type;
    el.innerHTML = (title ? '<div class="t-h">'+title+'</div>' : '') +
                   '<div class="t-b">'+message+'</div>';
    wrap.appendChild(el);

    // animasi in
    setTimeout(function(){ el.classList.add('show'); }, 10);

    // auto close
    setTimeout(function(){
      el.classList.remove('show');
      el.addEventListener('transitionend', function(){ el.remove(); }, {once:true});
    }, 2800);
  }
</script>


