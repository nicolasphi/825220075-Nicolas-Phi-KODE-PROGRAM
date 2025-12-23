<%@ Page Language="VB" MasterPageFile="~/dashboard_pmb/Site.master" %>
<%@ Register TagPrefix="uc" TagName="KpiMabaForm"
    Src="~/dashboard_pmb/ascx/kpi/kpi_input.ascx" %>

<asp:Content ID="TitleContent" ContentPlaceHolderID="TitleContent" runat="server">
  Input KPI | Universitas Tarumanagara
</asp:Content>

<asp:Content ID="MainContent" ContentPlaceHolderID="MainContent" runat="server">
  <uc:KpiMabaForm ID="KpiMabaForm1" runat="server" />
</asp:Content>
