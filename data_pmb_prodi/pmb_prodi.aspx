<%@ Page Language="VB" MasterPageFile="../Site.master" %> <%@ Register
TagPrefix="uc" TagName="DashboardMABA"
Src="../ascx/data_pmb_prodi/pmb_prodi.ascx" %>

<asp:Content
  ID="TitleContent"
  ContentPlaceHolderID="TitleContent"
  runat="server"
>
  Dashboard Penerimaan Mahasiswa Baru Fakultas | Universitas Tarumanagara
</asp:Content>

<asp:Content ID="MainContent" ContentPlaceHolderID="MainContent" runat="server">
  <uc:DashboardMABA
    ID="DashboardMABA2"
    runat="server"
  />
</asp:Content>