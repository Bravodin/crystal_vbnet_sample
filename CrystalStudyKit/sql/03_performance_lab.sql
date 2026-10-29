/* =====================================================================
   Laboratório de performance (15 min)
   Ligue "Include Actual Execution Plan" (Ctrl+M) no SSMS e rode cada bloco.
   ===================================================================== */
USE StudyERP;
GO
SET STATISTICS IO, TIME ON;
GO

/* ---------- 1) SARGability ----------
   Função na coluna impede seek no índice IX_InvoiceHeader_Date.          */
-- RUIM: scan
SELECT COUNT(*) FROM dbo.InvoiceHeader WHERE YEAR(InvoiceDate) = YEAR(GETDATE());
-- BOM: seek
DECLARE @y0 date = DATEFROMPARTS(YEAR(GETDATE()), 1, 1);
SELECT COUNT(*) FROM dbo.InvoiceHeader WHERE InvoiceDate >= @y0 AND InvoiceDate < DATEADD(YEAR, 1, @y0);
GO

/* ---------- 2) Conversão implícita ----------
   InvoiceNo é varchar; comparar com N'...' (nvarchar) converte a coluna.  */
SELECT * FROM dbo.InvoiceHeader WHERE InvoiceNo = N'INV100010';  -- veja o warning no plano
SELECT * FROM dbo.InvoiceHeader WHERE InvoiceNo = 'INV100010';   -- seek limpo
GO

/* ---------- 3) Parameter sniffing ----------
   Proc "catch-all" sem RECOMPILE compila o plano pro 1º valor e reusa.    */
CREATE OR ALTER PROCEDURE dbo.lab_InvoicesSniff @CustomerID int = NULL, @FromDate date = NULL
AS
SELECT h.InvoiceNo, h.InvoiceDate, h.Freight
FROM dbo.InvoiceHeader h
WHERE (@CustomerID IS NULL OR h.CustomerID = @CustomerID)
  AND (@FromDate   IS NULL OR h.InvoiceDate >= @FromDate);
GO
EXEC dbo.lab_InvoicesSniff @CustomerID = 5;          -- plano compilado aqui
EXEC dbo.lab_InvoicesSniff @FromDate = '2000-01-01'; -- reusa plano inadequado
/* Correções possíveis (saber explicar os trade-offs):
   - OPTION (RECOMPILE)  -> plano ótimo por execução, custo de compilação
   - SQL dinâmico com sp_executesql, só com os filtros informados
   - OPTIMIZE FOR / variáveis locais (média estatística)
   - Separar em procs específicas                                          */
GO

/* ---------- 4) Temp table x table variable ----------
   #temp: tem estatísticas e aceita índices -> bom para volume.
   @table: sem estatísticas (estimativa baixa, melhorou no SQL 2019 com
   deferred compilation) -> bom para poucas linhas.                        */
DECLARE @t TABLE (InvoiceID int PRIMARY KEY);
INSERT @t SELECT InvoiceID FROM dbo.InvoiceHeader;
SELECT COUNT(*) FROM @t t JOIN dbo.InvoiceLine l ON l.InvoiceID = t.InvoiceID;

SELECT InvoiceID INTO #t FROM dbo.InvoiceHeader;
SELECT COUNT(*) FROM #t t JOIN dbo.InvoiceLine l ON l.InvoiceID = t.InvoiceID;
DROP TABLE #t;
GO

/* ---------- 5) Window function x subquery correlacionada ---------- */
-- RUIM: subquery por linha
SELECT h.InvoiceID,
       (SELECT SUM(l2.Qty * l2.UnitPrice) FROM dbo.InvoiceLine l2 WHERE l2.InvoiceID = h.InvoiceID) AS Total
FROM dbo.InvoiceHeader h;
-- BOM: uma passada
SELECT DISTINCT l.InvoiceID, SUM(l.Qty * l.UnitPrice) OVER (PARTITION BY l.InvoiceID) AS Total
FROM dbo.InvoiceLine l;
-- (ou simplesmente GROUP BY - saber dizer quando cada um faz sentido)
GO

/* ---------- 6) Desafio ----------
   Escreva uma query que traga, para cada cliente, as 3 maiores faturas
   dos últimos 90 dias com o % que cada uma representa no total do cliente.
   Dica: CTE + ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY total DESC)
   + SUM() OVER (PARTITION BY CustomerID).                                  */
