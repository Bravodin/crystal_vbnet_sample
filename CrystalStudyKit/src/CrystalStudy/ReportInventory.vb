Imports System.Diagnostics
Imports System.Text
Imports CrystalDecisions.CrystalReports.Engine
Imports CrystalDecisions.Shared

''' <summary>
''' Ferramentas para o upgrade do runtime numa biblioteca grande de relatórios:
''' 1) Inventário: lista, para cada .rpt, fontes de dados, parâmetros, subreports,
'''    papel/orientação, fórmula de seleção -> CSV para planejar e priorizar.
''' 2) Exportação em lote para PDF numa pasta rotulada (ex.: "antes-SP35",
'''    "depois-SP40") -> compare as duas pastas para validar antes do rollout.
''' </summary>
Public NotInheritable Class ReportInventory

    Private Sub New()
    End Sub

    Public Shared Function BuildCsv(folder As String) As String
        Dim sb As New StringBuilder()
        sb.AppendLine("Report;Status;Tables(Location|Server|Database);Parameters;Subreports;Formulas;Paper;Orientation;SelectionFormula")

        For Each rptPath In Directory.GetFiles(folder, "*.rpt", SearchOption.AllDirectories).OrderBy(Function(f) f)
            Dim rd As ReportDocument = Nothing
            Try
                rd = ReportService.Load(rptPath)

                Dim tables = String.Join(" / ", rd.Database.Tables.Cast(Of Table)().Select(
                    Function(t) t.Location & "|" & t.LogOnInfo.ConnectionInfo.ServerName & "|" & t.LogOnInfo.ConnectionInfo.DatabaseName))

                Dim params = String.Join(" / ", rd.DataDefinition.ParameterFields.Cast(Of ParameterFieldDefinition)().
                    Where(Function(p) String.IsNullOrEmpty(p.ReportName)).
                    Select(Function(p) p.Name & ":" & p.ValueType.ToString()))

                Dim subs = String.Join(" / ", rd.Subreports.Cast(Of ReportDocument)().Select(Function(s) s.Name))

                Dim formulas = rd.DataDefinition.FormulaFields.Count

                sb.AppendLine(String.Join(";", {
                    Csv(IO.Path.GetFileName(rptPath)), "OK", Csv(tables), Csv(params), Csv(subs),
                    formulas.ToString(),
                    rd.PrintOptions.PaperSize.ToString(),
                    rd.PrintOptions.PaperOrientation.ToString(),
                    Csv(rd.RecordSelectionFormula)}))
            Catch ex As Exception
                sb.AppendLine(String.Join(";", {Csv(IO.Path.GetFileName(rptPath)), Csv("ERRO: " & ex.Message), "", "", "", "", "", "", ""}))
            Finally
                ReportService.Dispose(rd)
            End Try
        Next
        Return sb.ToString()
    End Function

    ''' <summary>
    ''' Exporta todos os .rpt para PDF em Output\label\. Parâmetros conhecidos
    ''' (InvoiceID, StartDate, EndDate...) são preenchidos a partir de "values";
    ''' relatórios com parâmetro faltando são registrados no log, não travam o lote.
    ''' </summary>
    Public Shared Function ExportAll(folder As String, label As String, values As IDictionary(Of String, Object)) As String
        Dim outDir = IO.Path.Combine(AppSettings.OutputFolder, label)
        Directory.CreateDirectory(outDir)
        Dim log As New StringBuilder()
        log.AppendLine(ReportService.RuntimeInfo())

        For Each rptPath In Directory.GetFiles(folder, "*.rpt", SearchOption.AllDirectories).OrderBy(Function(f) f)
            Dim rd As ReportDocument = Nothing
            Dim sw = Stopwatch.StartNew()
            Try
                rd = ReportService.Load(rptPath)
                ReportService.ApplyLogon(rd)
                ReportService.SetParameters(rd, values)

                Dim missing = ReportService.MissingParameters(rd)
                If missing.Count > 0 Then
                    log.AppendLine("PULADO  " & IO.Path.GetFileName(rptPath) & " - parâmetros sem valor: " & String.Join(", ", missing))
                    Continue For
                End If

                Dim pdf = IO.Path.Combine(outDir, IO.Path.GetFileNameWithoutExtension(rptPath) & ".pdf")
                rd.ExportToDisk(ExportFormatType.PortableDocFormat, pdf)
                log.AppendLine(String.Format("OK      {0} ({1} ms)", IO.Path.GetFileName(rptPath), sw.ElapsedMilliseconds))
            Catch ex As Exception
                log.AppendLine("ERRO    " & IO.Path.GetFileName(rptPath) & " - " & ex.GetType().Name & ": " & ex.Message)
            Finally
                ReportService.Dispose(rd)
            End Try
        Next

        File.WriteAllText(IO.Path.Combine(outDir, "_export_log.txt"), log.ToString())
        Return outDir
    End Function

    Private Shared Function Csv(s As String) As String
        If s Is Nothing Then Return ""
        Return """" & s.Replace("""", """""").Replace(vbCr, " ").Replace(vbLf, " ") & """"
    End Function

End Class
