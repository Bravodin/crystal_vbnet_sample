Imports System.Data.SqlClient
Imports System.Diagnostics
Imports CrystalDecisions.CrystalReports.Engine
Imports CrystalDecisions.Windows.Forms

''' <summary>
''' Tela única de estudo. Montada em código (sem .Designer.vb) para ficar fácil de ler.
''' </summary>
Public Class MainForm
    Inherits Form

    Private ReadOnly cboInvoice As New ComboBox() With {.DropDownStyle = ComboBoxStyle.DropDownList, .Width = 480}
    Private ReadOnly viewer As New CrystalReportViewer() With {.Dock = DockStyle.Fill, .ToolPanelView = ToolPanelViewType.None}
    Private ReadOnly lblStatus As New ToolStripStatusLabel() With {.Spring = True, .TextAlign = ContentAlignment.MiddleLeft}

    Private current As ReportDocument
    Private currentName As String = "report"

    Public Sub New()
        Text = "Crystal Study - StudyERP"
        Width = 1400
        Height = 900
        StartPosition = FormStartPosition.CenterScreen

        Dim topBar As New FlowLayoutPanel() With {.Dock = DockStyle.Top, .AutoSize = True, .Padding = New Padding(6), .WrapContents = True}
        topBar.Controls.Add(New Label() With {.Text = "Fatura:", .AutoSize = True, .Margin = New Padding(3, 8, 3, 3)})
        topBar.Controls.Add(cboInvoice)
        topBar.Controls.Add(MakeButton("Fatura (pull)", AddressOf OnInvoicePull))
        topBar.Controls.Add(MakeButton("Fatura (push)", AddressOf OnInvoicePush))
        topBar.Controls.Add(MakeButton("Resumo vendas 6m", AddressOf OnSalesSummary))
        topBar.Controls.Add(MakeButton("Exportar PDF", AddressOf OnExportPdf))
        topBar.Controls.Add(MakeButton("Imprimir...", AddressOf OnPrint))
        topBar.Controls.Add(MakeButton("Gerar XSD (push)", AddressOf OnWriteXsd))
        topBar.Controls.Add(MakeButton("Inventário .rpt", AddressOf OnInventory))
        topBar.Controls.Add(MakeButton("Exportar lote PDF", AddressOf OnBatchExport))

        Dim status As New StatusStrip()
        status.Items.Add(lblStatus)

        Controls.Add(viewer)
        Controls.Add(topBar)
        Controls.Add(status)
    End Sub

    Private Function MakeButton(caption As String, handler As EventHandler) As Button
        Dim b As New Button() With {.Text = caption, .AutoSize = True}
        AddHandler b.Click, Sub(s, e) Run(caption, Sub() handler(s, e))
        Return b
    End Function

    ''' <summary>Cursor de espera + mensagem de erro amigável para qualquer ação.</summary>
    Private Sub Run(actionName As String, action As Action)
        Cursor = Cursors.WaitCursor
        Try
            action()
        Catch ex As Exception
            MessageBox.Show(Me, ex.GetType().Name & ": " & ex.Message & vbCrLf & vbCrLf &
                            If(ex.InnerException IsNot Nothing, "Inner: " & ex.InnerException.Message, ""),
                            actionName, MessageBoxButtons.OK, MessageBoxIcon.Error)
        Finally
            Cursor = Cursors.Default
        End Try
    End Sub

    Protected Overrides Sub OnLoad(e As EventArgs)
        MyBase.OnLoad(e)
        SetStatus("")
        Run("Carregar faturas",
            Sub()
                Dim dt = Db.ExecProc("dbo.app_ListInvoices")
                cboInvoice.DisplayMember = "Display"
                cboInvoice.ValueMember = "InvoiceID"
                cboInvoice.DataSource = dt
            End Sub)
    End Sub

    Protected Overrides Sub OnFormClosed(e As FormClosedEventArgs)
        ShowReport(Nothing, Nothing)
        MyBase.OnFormClosed(e)
    End Sub

    ' ------------------------------------------------------------------
    ' Ações
    ' ------------------------------------------------------------------

    ''' <summary>PULL: o .rpt busca os dados chamando dbo.rpt_Invoice.
    ''' O layout é escolhido por cliente via ReportAssignment.</summary>
    Private Sub OnInvoicePull(sender As Object, e As EventArgs)
        Dim id = SelectedInvoiceId()

        Dim resolved = Db.ExecProc("dbo.app_ResolveInvoiceReport", Db.P("@InvoiceID", SqlDbType.Int, id))
        Dim rptFile = If(resolved.Rows.Count > 0, CStr(resolved.Rows(0)("RptFileName")), "Invoice.rpt")
        Dim note = ""
        If Not File.Exists(ReportService.PathOf(rptFile)) AndAlso rptFile <> "Invoice.rpt" Then
            note = " (layout " & rptFile & " não existe; usando Invoice.rpt)"
            rptFile = "Invoice.rpt"
        End If

        Dim rd = ReportService.Load(ReportService.PathOf(rptFile))
        ReportService.ApplyLogon(rd)
        ReportService.SetParameters(rd, New Dictionary(Of String, Object) From {{"InvoiceID", id}})
        ShowReport(rd, IO.Path.GetFileNameWithoutExtension(rptFile) & "_" & id)
        SetStatus(rptFile & note)
    End Sub

    ''' <summary>PUSH: a aplicação executa a proc e entrega o DataSet ao .rpt.</summary>
    Private Sub OnInvoicePush(sender As Object, e As EventArgs)
        Dim id = SelectedInvoiceId()
        Dim rd = ReportService.Load(ReportService.PathOf("Invoice_Push.rpt"))
        ReportService.PushData(rd, BuildInvoiceDataSet(id))
        ShowReport(rd, "Invoice_Push_" & id)
        SetStatus("Invoice_Push.rpt (push / SetDataSource)")
    End Sub

    Private Sub OnSalesSummary(sender As Object, e As EventArgs)
        Dim rd = ReportService.Load(ReportService.PathOf("SalesSummary.rpt"))
        ReportService.ApplyLogon(rd)
        ReportService.SetParameters(rd, New Dictionary(Of String, Object) From {
            {"StartDate", Date.Today.AddMonths(-6)},
            {"EndDate", Date.Today}})
        ShowReport(rd, "SalesSummary")
        SetStatus("SalesSummary.rpt")
    End Sub

    Private Sub OnExportPdf(sender As Object, e As EventArgs)
        EnsureReport()
        Dim path = ReportService.ExportPdf(current, currentName & "_" & Date.Now.ToString("yyyyMMdd_HHmmss") & ".pdf")
        Process.Start("explorer.exe", "/select,""" & path & """")
    End Sub

    Private Sub OnPrint(sender As Object, e As EventArgs)
        EnsureReport()
        Using dlg As New PrintDialog()
            If dlg.ShowDialog(Me) <> DialogResult.OK Then Return
            ReportService.Print(current, dlg.PrinterSettings.PrinterName, dlg.PrinterSettings.Copies)
        End Using
    End Sub

    ''' <summary>
    ''' Gera o schema para desenhar o relatório push:
    ''' Database Expert > Create New Connection > ADO.NET (XML) > escolha o .xsd.
    ''' (O .ttx é o "avô" disso: Field Definitions Only.)
    ''' </summary>
    Private Sub OnWriteXsd(sender As Object, e As EventArgs)
        Dim ds = BuildInvoiceDataSet(SelectedInvoiceId())
        Dim path = IO.Path.Combine(AppSettings.OutputFolder, "InvoicePush.xsd")
        ds.WriteXmlSchema(path)
        Process.Start("explorer.exe", "/select,""" & path & """")
    End Sub

    Private Sub OnInventory(sender As Object, e As EventArgs)
        Dim csv = ReportInventory.BuildCsv(AppSettings.ReportsFolder)
        Dim path = IO.Path.Combine(AppSettings.OutputFolder, "inventory_" & Date.Now.ToString("yyyyMMdd_HHmmss") & ".csv")
        File.WriteAllText(path, csv, System.Text.Encoding.UTF8)
        Process.Start("explorer.exe", "/select,""" & path & """")
    End Sub

    ''' <summary>Exercício de upgrade: rode com o SP antigo ("antes") e com o novo ("depois").</summary>
    Private Sub OnBatchExport(sender As Object, e As EventArgs)
        Dim runLabel = InputBox("Rótulo da execução (vira nome de pasta em Output):", "Exportar lote",
                             "run_" & Date.Now.ToString("yyyyMMdd_HHmmss") & If(Environment.Is64BitProcess, "_x64", "_x86"))
        If String.IsNullOrWhiteSpace(runLabel) Then Return

        Dim values As New Dictionary(Of String, Object) From {
            {"InvoiceID", SelectedInvoiceId()},
            {"FromDate", DBNull.Value},
            {"ToDate", DBNull.Value},
            {"StartDate", Date.Today.AddMonths(-6)},
            {"EndDate", Date.Today}}

        Dim outDir = ReportInventory.ExportAll(AppSettings.ReportsFolder, runLabel, values)
        Process.Start("explorer.exe", """" & outDir & """")
    End Sub

    ' ------------------------------------------------------------------
    ' Apoio
    ' ------------------------------------------------------------------
    Private Function SelectedInvoiceId() As Integer
        If cboInvoice.SelectedValue Is Nothing Then Throw New InvalidOperationException("Selecione uma fatura (o banco StudyERP foi criado?).")
        Return CInt(cboInvoice.SelectedValue)
    End Function

    Private Function BuildInvoiceDataSet(invoiceId As Integer) As DataSet
        Dim dt = Db.ExecProc("dbo.rpt_Invoice", Db.P("@InvoiceID", SqlDbType.Int, invoiceId))
        dt.TableName = "Invoice"
        Dim ds As New DataSet("InvoicePushDS")
        ds.Tables.Add(dt)
        Return ds
    End Function

    Private Sub ShowReport(rd As ReportDocument, name As String)
        viewer.ReportSource = Nothing
        ReportService.Dispose(current)   ' sempre liberar o anterior
        current = rd
        If name IsNot Nothing Then currentName = name
        If rd IsNot Nothing Then viewer.ReportSource = rd
    End Sub

    Private Sub EnsureReport()
        If current Is Nothing Then Throw New InvalidOperationException("Abra um relatório primeiro.")
    End Sub

    Private Sub SetStatus(extra As String)
        lblStatus.Text = ReportService.RuntimeInfo() & "  ||  Reports: " & AppSettings.ReportsFolder &
                         If(String.IsNullOrEmpty(extra), "", "  ||  " & extra)
    End Sub

End Class
