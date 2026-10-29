Imports System.Diagnostics
Imports CrystalDecisions.CrystalReports.Engine
Imports CrystalDecisions.Shared

''' <summary>
''' Tudo que a aplicação faz com um .rpt: carregar, apontar para o banco certo,
''' passar parâmetros, exportar e imprimir. É o tipo de código que você vai
''' ler/alterar no ERP da vaga.
''' </summary>
Public NotInheritable Class ReportService

    Private Sub New()
    End Sub

    ' ------------------------------------------------------------------
    ' Carregar
    ' ------------------------------------------------------------------

    ''' <summary>
    ''' Carrega um .rpt do disco. Quem chama é responsável por Close()/Dispose():
    ''' ReportDocument não liberado gera o famoso erro de "maximum report
    ''' processing jobs limit" (padrão 75, configurado no registro).
    ''' </summary>
    Public Shared Function Load(rptPath As String) As ReportDocument
        If Not File.Exists(rptPath) Then
            Throw New FileNotFoundException("Relatório não encontrado: " & rptPath, rptPath)
        End If
        Dim rd As New ReportDocument()
        rd.Load(rptPath, OpenReportMethod.OpenReportByTempCopy)
        Return rd
    End Function

    Public Shared Function PathOf(rptFileName As String) As String
        Return IO.Path.Combine(AppSettings.ReportsFolder, rptFileName)
    End Function

    ' ------------------------------------------------------------------
    ' Modelo PULL: o relatório conecta no banco sozinho.
    ' O .rpt guarda servidor/banco de quando foi desenhado; em runtime
    ' trocamos para o ambiente do cliente - em TODAS as tabelas, inclusive
    ' as dos subreports (esquecer os subreports é bug clássico).
    ' ------------------------------------------------------------------
    Public Shared Sub ApplyLogon(rd As ReportDocument)
        Dim ci As New ConnectionInfo() With {
            .ServerName = AppSettings.SqlServer,
            .DatabaseName = AppSettings.Database,
            .IntegratedSecurity = AppSettings.IntegratedSecurity
        }
        If Not AppSettings.IntegratedSecurity Then
            ci.UserID = AppSettings.SqlUser
            ci.Password = AppSettings.SqlPassword
        End If

        ApplyToTables(rd.Database.Tables, ci)
        For Each subRpt As ReportDocument In rd.Subreports
            ApplyToTables(subRpt.Database.Tables, ci)
        Next

        ' Atalho equivalente (menos controle):
        ' rd.SetDatabaseLogon(user, password, server, database)
    End Sub

    Private Shared Sub ApplyToTables(tables As Tables, ci As ConnectionInfo)
        For Each t As Table In tables
            Dim li As TableLogOnInfo = t.LogOnInfo
            li.ConnectionInfo = ci
            t.ApplyLogOnInfo(li)
            ' Se o .rpt foi desenhado com o nome do banco "chumbado" em Location
            ' (ex.: OutroBanco.dbo.rpt_Invoice;1) é preciso ajustar t.Location também.
        Next
    End Sub

    ' ------------------------------------------------------------------
    ' Modelo PUSH: a aplicação busca os dados e entrega pronto.
    ' O .rpt é desenhado sobre um schema (XSD/DataSet ou, nos antigos, .ttx).
    ' ------------------------------------------------------------------
    ''' <remarks>
    ''' Os nomes de tabela/colunas do DataSet precisam bater com o schema usado no
    ''' desenho do .rpt. Subreports em modo push recebem os próprios dados:
    ''' rd.Subreports("Nome").SetDataSource(...)
    ''' </remarks>
    Public Shared Sub PushData(rd As ReportDocument, data As DataSet)
        rd.SetDataSource(data)
    End Sub

    ' ------------------------------------------------------------------
    ' Parâmetros
    ' Com stored procedure como fonte, o parâmetro no Crystal se chama "@InvoiceID".
    ' Parâmetro criado à mão no Field Explorer se chama "InvoiceID".
    ' Parâmetro sem valor => o viewer abre o prompt (ou o export falha).
    ' ------------------------------------------------------------------
    Public Shared Sub SetParameters(rd As ReportDocument, values As IDictionary(Of String, Object))
        For Each pf As ParameterFieldDefinition In rd.DataDefinition.ParameterFields
            If pf.IsLinked() Then Continue For                 ' vem do link do subreport
            If Not String.IsNullOrEmpty(pf.ReportName) Then Continue For ' parâmetro de subreport
            Dim key = FindKey(values, pf.Name)
            If key Is Nothing Then Continue For
            rd.SetParameterValue(pf.Name, If(values(key), DBNull.Value))
        Next
    End Sub

    ''' <summary>Aceita "InvoiceID" ou "@InvoiceID" no dicionário.</summary>
    Private Shared Function FindKey(values As IDictionary(Of String, Object), paramName As String) As String
        Dim bare = paramName.TrimStart("@"c)
        Return values.Keys.FirstOrDefault(Function(k) String.Equals(k.TrimStart("@"c), bare, StringComparison.OrdinalIgnoreCase))
    End Function

    ''' <summary>Parâmetros do relatório principal ainda sem valor (o que viraria prompt).</summary>
    Public Shared Function MissingParameters(rd As ReportDocument) As List(Of String)
        Dim missing As New List(Of String)
        For Each pf As ParameterFieldDefinition In rd.DataDefinition.ParameterFields
            If pf.IsLinked() OrElse Not String.IsNullOrEmpty(pf.ReportName) Then Continue For
            If pf.CurrentValues.Count = 0 AndAlso Not pf.HasCurrentValue Then missing.Add(pf.Name)
        Next
        Return missing
    End Function

    ' ------------------------------------------------------------------
    ' Saída
    ' ------------------------------------------------------------------
    Public Shared Function ExportPdf(rd As ReportDocument, fileName As String) As String
        Dim path = IO.Path.Combine(AppSettings.OutputFolder, fileName)
        rd.ExportToDisk(ExportFormatType.PortableDocFormat, path)
        Return path
    End Function

    ''' <summary>
    ''' Impressão direta. Problemas comuns: o .rpt guarda a impressora/papel de quem
    ''' desenhou ("No Printer" desmarcado), margens não imprimíveis do driver,
    ''' fontes ausentes na máquina do cliente => truncamento/alinhamento diferente.
    ''' </summary>
    Public Shared Sub Print(rd As ReportDocument, Optional printerName As String = Nothing, Optional copies As Integer = 1)
        If Not String.IsNullOrEmpty(printerName) Then rd.PrintOptions.PrinterName = printerName
        rd.PrintToPrinter(copies, False, 0, 0)  ' (nCopies, collated, startPage, endPage) - 0,0 = todas
    End Sub

    Public Shared Sub Dispose(rd As ReportDocument)
        If rd Is Nothing Then Return
        Try
            rd.Close()
        Finally
            rd.Dispose()
        End Try
    End Sub

    ' ------------------------------------------------------------------
    ' Diagnóstico do runtime (útil no upgrade: qual SP e qual bitness?)
    ' ------------------------------------------------------------------
    Public Shared Function RuntimeInfo() As String
        Dim asm = GetType(ReportDocument).Assembly
        Dim fvi = FileVersionInfo.GetVersionInfo(asm.Location)
        Return String.Format("Processo {0} | CrystalDecisions assembly {1} | file {2} | {3}",
                             If(Environment.Is64BitProcess, "64-bit", "32-bit"),
                             asm.GetName().Version,
                             fvi.FileVersion,
                             asm.Location)
    End Function

End Class
