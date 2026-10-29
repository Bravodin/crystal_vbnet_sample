Imports System.Configuration

''' <summary>Leitura das configurações do App.config.</summary>
Public NotInheritable Class AppSettings

    Private Sub New()
    End Sub

    Public Shared ReadOnly Property SqlServer As String
        Get
            Return Value("SqlServer", "localhost")
        End Get
    End Property

    Public Shared ReadOnly Property Database As String
        Get
            Return Value("Database", "StudyERP")
        End Get
    End Property

    Public Shared ReadOnly Property IntegratedSecurity As Boolean
        Get
            Return String.Equals(Value("IntegratedSecurity", "true"), "true", StringComparison.OrdinalIgnoreCase)
        End Get
    End Property

    Public Shared ReadOnly Property SqlUser As String
        Get
            Return Value("SqlUser", "")
        End Get
    End Property

    Public Shared ReadOnly Property SqlPassword As String
        Get
            Return Value("SqlPassword", "")
        End Get
    End Property

    ''' <summary>
    ''' Pasta dos .rpt. Tenta relativo ao .exe; se não existir, sobe os diretórios
    ''' procurando uma pasta com esse nome (útil rodando de bin\x86\Debug).
    ''' </summary>
    Public Shared ReadOnly Property ReportsFolder As String
        Get
            Return ResolveFolder(Value("ReportsFolder", "Reports"), mustExist:=True)
        End Get
    End Property

    Public Shared ReadOnly Property OutputFolder As String
        Get
            Dim path = ResolveFolder(Value("OutputFolder", "Output"), mustExist:=False)
            Directory.CreateDirectory(path)
            Return path
        End Get
    End Property

    Private Shared Function Value(key As String, fallback As String) As String
        Dim v = ConfigurationManager.AppSettings(key)
        Return If(String.IsNullOrWhiteSpace(v), fallback, v)
    End Function

    Private Shared Function ResolveFolder(setting As String, mustExist As Boolean) As String
        If IO.Path.IsPathRooted(setting) Then Return setting

        Dim baseDir = AppDomain.CurrentDomain.BaseDirectory
        Dim candidate = IO.Path.GetFullPath(IO.Path.Combine(baseDir, setting))
        If Not mustExist OrElse Directory.Exists(candidate) Then Return candidate

        Dim dir = New DirectoryInfo(baseDir)
        While dir IsNot Nothing
            Dim probe = IO.Path.Combine(dir.FullName, setting)
            If Directory.Exists(probe) AndAlso Directory.GetFiles(probe, "*.rpt").Length > 0 Then Return probe
            dir = dir.Parent
        End While
        Return candidate
    End Function

End Class
