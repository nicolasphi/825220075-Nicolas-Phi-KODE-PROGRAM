<!-- #INCLUDE file = "/path/to/your/page_or_master.aspx" --> 'NOTE: include file tergantung modul / layout aplikasi (internal).

<section class="content-header" style="margin-top:20px;">
    <h1>
        DASHBOARD PENERIMAAN MAHASISWA BARU
        <small> &nbsp;</small>
    </h1>
    <ol class="breadcrumb">
        <li><a href="/dashboard_pmb/index.aspx"><i class="fa fa-dashboard"></i> Dashboard</a></li>
    </ol>
</section>

<section class= "content">
    <div class="row" style="margin-top:30px;">
        <div class="col-md-3 col-sm-6 col-xs-12">
        <div class="card text-center" style="background:#fff; border-radius:8px; box-shadow:0 2px 5px rgba(0,0,0,0.1); padding:20px;">
            <div style="font-size:50px; color:#00c0ef; margin-bottom:10px;">
                <i class="fa-solid fa-users"></i>
            </div>
            <h4>Penerimaan Mahasiswa Baru (Universitas)</h4>
            <a href="/dashboard_pmb/data_maba/biodata.aspx" class="btn btn-primary">Lihat Dashboard</a>
        </div>
    </div>
    <div class="col-md-3 col-sm-6 col-xs-12">
        <div class="card text-center" style="background:#fff; border-radius:8px; box-shadow:0 2px 5px rgba(0,0,0,0.1); padding:20px;">
            <div style="font-size:50px; color:#1C6EA4; margin-bottom:10px;">
                <i class="fa-solid fa-university"></i>
            </div>
            <h4>Penerimaan Mahasiswa Baru (Fakultas)</h4>
            <a href="/dashboard_pmb/data_pmb_fakultas/pmb_fakultas.aspx" class="btn btn-primary">Lihat Dashboard</a>
        </div>
    </div>
    <div class="col-md-3 col-sm-6 col-xs-12">
        <div class="card text-center" style="background:#fff; border-radius:8px; box-shadow:0 2px 5px rgba(0,0,0,0.1); padding:20px;">
            <div style="font-size:50px; color:red; margin-bottom:10px;">
                <i class="fa-solid fa-school"></i>
            </div>
            <h4>Penerimaan Mahasiswa Baru (Prodi)</h4>
            <a href="/dashboard_pmb/data_pmb_prodi/pmb_prodi.aspx" class="btn btn-primary">Lihat Dashboard</a>
        </div>
    </div>
</div>
</section>

<script runat="server">
    Sub Page_Load(sender As Object, e As EventArgs)
        If Not Page.IsPostBack Then
            ' Initialization code for dashboard
        End If
    End Sub
</script>

<!-- Menampilkan Icon Font Awesome Pro/Premium -->
<link rel="stylesheet" href="https://site-assets.fontawesome.com/releases/v6.4.2/css/all.css">
