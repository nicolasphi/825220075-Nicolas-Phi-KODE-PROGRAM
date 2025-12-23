<%@ Page Language="VB" MasterPageFile="Site.master" %> <%@ Register
TagPrefix="uc" TagName="Section" Src="ascx/dashboard.ascx" %>

<asp:Content
  ID="TitleContent"
  ContentPlaceHolderID="TitleContent"
  runat="server"
>
  Dashboard Penerimaan Mahasiswa Baru | Universitas Tarumanagara
</asp:Content>

<asp:Content ID="MainContent" ContentPlaceHolderID="MainContent" runat="server">
  <uc:Section ID="Section1" runat="server" />
</asp:Content>