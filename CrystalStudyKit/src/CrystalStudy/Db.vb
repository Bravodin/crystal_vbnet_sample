Imports System.Data.SqlClient

''' <summary>Acesso a dados mínimo (ADO.NET puro, como em muito ERP legado).</summary>
Public NotInheritable Class Db

    Private Sub New()
    End Sub

    Public Shared ReadOnly Property ConnectionString As String
        Get
            Dim b As New SqlConnectionStringBuilder() With {
                .DataSource = AppSettings.SqlServer,
                .InitialCatalog = AppSettings.Database,
                .IntegratedSecurity = AppSettings.IntegratedSecurity,
                .ApplicationName = "CrystalStudy"
            }
            If Not AppSettings.IntegratedSecurity Then
                b.UserID = AppSettings.SqlUser
                b.Password = AppSettings.SqlPassword
            End If
            Return b.ConnectionString
        End Get
    End Property

    ''' <summary>Executa uma stored procedure e devolve o primeiro result set.</summary>
    Public Shared Function ExecProc(procName As String, ParamArray params As SqlParameter()) As DataTable
        Using cn As New SqlConnection(ConnectionString),
              cmd As New SqlCommand(procName, cn) With {.CommandType = CommandType.StoredProcedure, .CommandTimeout = 120},
              da As New SqlDataAdapter(cmd)
            If params IsNot Nothing Then cmd.Parameters.AddRange(params)
            Dim dt As New DataTable(procName)
            da.Fill(dt)
            Return dt
        End Using
    End Function

    Public Shared Function P(name As String, dbType As SqlDbType, value As Object) As SqlParameter
        Return New SqlParameter(name, dbType) With {.Value = If(value, DBNull.Value)}
    End Function

End Class
