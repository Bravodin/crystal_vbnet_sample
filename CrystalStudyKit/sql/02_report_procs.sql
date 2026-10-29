/* =====================================================================
   Stored procedures dos relatórios (fonte de dados dos .rpt)
   ===================================================================== */
USE StudyERP;
GO

/* ---------------------------------------------------------------------
   1) Fatura - relatório principal
   Uma linha por item (desnormalizado), que é o formato mais fácil de
   agrupar no Crystal: Group 1 = InvoiceNo, Details = itens.
   Aceita uma fatura (@InvoiceID) ou um lote por data (impressão em massa).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.rpt_Invoice
    @InvoiceID  int  = NULL,
    @FromDate   date = NULL,
    @ToDate     date = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        -- Empresa (cabeçalho)
        co.CompanyName, co.AddressLine1 AS CompanyAddress, co.City AS CompanyCity,
        co.StateCode AS CompanyState, co.PostalCode AS CompanyZip, co.Phone AS CompanyPhone,

        -- Cabeçalho da fatura
        h.InvoiceID, h.InvoiceNo, h.InvoiceDate, h.DueDate, h.CustomerPO,
        h.Freight, h.Notes, h.Status,
        r.RepName,

        -- Cliente
        c.CustomerID, c.CustomerCode, c.CustomerName,
        c.BillAddress1, c.BillAddress2, c.BillCity, c.BillState, c.BillZip,
        c.ShipAddress1, c.ShipCity, c.ShipState, c.ShipZip,
        c.PaymentTerms, c.TaxRate,

        -- Itens
        l.LineNum, i.ItemCode, i.Description, i.UOM, l.LotNumber,
        l.Qty, l.UnitPrice, l.DiscountPct,
        x.ExtAmount,

        -- Totais calculados no SQL com window functions
        -- (alternativa a Summary/Running Total no Crystal - bom tema de conversa)
        SUM(x.ExtAmount) OVER (PARTITION BY h.InvoiceID)                       AS InvoiceSubtotal,
        ROUND(SUM(x.ExtAmount) OVER (PARTITION BY h.InvoiceID) * c.TaxRate, 2) AS InvoiceTax,
        COUNT(*)         OVER (PARTITION BY h.InvoiceID)                       AS LineCount
    FROM dbo.InvoiceHeader h
    JOIN dbo.Customer      c  ON c.CustomerID = h.CustomerID
    JOIN dbo.SalesRep      r  ON r.SalesRepID = h.SalesRepID
    JOIN dbo.InvoiceLine   l  ON l.InvoiceID  = h.InvoiceID
    JOIN dbo.Item          i  ON i.ItemID     = l.ItemID
    CROSS JOIN (SELECT TOP (1) * FROM dbo.Company ORDER BY CompanyID) co
    CROSS APPLY (SELECT CAST(ROUND(l.Qty * l.UnitPrice * (1 - l.DiscountPct), 2) AS decimal(18,2)) AS ExtAmount) x
    WHERE (@InvoiceID IS NULL OR h.InvoiceID = @InvoiceID)
      AND (@FromDate  IS NULL OR h.InvoiceDate >= @FromDate)
      AND (@ToDate    IS NULL OR h.InvoiceDate <  DATEADD(DAY, 1, @ToDate))
      AND h.Status = 'P'
    ORDER BY h.InvoiceNo, l.LineNum
    OPTION (RECOMPILE);  -- "catch-all" com parâmetros opcionais: evita plano ruim por parameter sniffing
END
GO

/* ---------------------------------------------------------------------
   2) Subreport: resumo de conta / aging do cliente
   Linkado ao principal por CustomerID (e data de referência = InvoiceDate).
   Usa temp table de propósito (a vaga pede temp tables).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.rpt_CustomerAging
    @CustomerID int,
    @AsOfDate   date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @AsOfDate = COALESCE(@AsOfDate, CAST(GETDATE() AS date));

    CREATE TABLE #Open (
        InvoiceID   int PRIMARY KEY,
        DueDate     date,
        Amount      decimal(18,2),
        DaysPastDue int
    );

    INSERT #Open (InvoiceID, DueDate, Amount, DaysPastDue)
    SELECT h.InvoiceID, h.DueDate,
           SUM(CAST(ROUND(l.Qty * l.UnitPrice * (1 - l.DiscountPct), 2) AS decimal(18,2))) + MAX(h.Freight),
           DATEDIFF(DAY, h.DueDate, @AsOfDate)
    FROM dbo.InvoiceHeader h
    JOIN dbo.InvoiceLine l ON l.InvoiceID = h.InvoiceID
    WHERE h.CustomerID = @CustomerID
      AND h.Status = 'P'
      AND h.InvoiceDate <= @AsOfDate
      AND h.InvoiceDate >  DATEADD(DAY, -120, @AsOfDate)   -- "em aberto" simplificado: últimos 120 dias
    GROUP BY h.InvoiceID, h.DueDate;

    SELECT
        SUM(CASE WHEN DaysPastDue <= 0              THEN Amount ELSE 0 END) AS [Current],
        SUM(CASE WHEN DaysPastDue BETWEEN 1  AND 30 THEN Amount ELSE 0 END) AS Days1to30,
        SUM(CASE WHEN DaysPastDue BETWEEN 31 AND 60 THEN Amount ELSE 0 END) AS Days31to60,
        SUM(CASE WHEN DaysPastDue > 60              THEN Amount ELSE 0 END) AS Over60,
        SUM(Amount)                                                         AS TotalOpen
    FROM #Open;
END
GO

/* ---------------------------------------------------------------------
   3) Resumo de vendas por vendedor/mês - vitrine de window functions
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.rpt_SalesSummary
    @StartDate date,
    @EndDate   date
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  h.SalesRepID,
            DATEFROMPARTS(YEAR(h.InvoiceDate), MONTH(h.InvoiceDate), 1) AS MonthStart,
            SUM(CAST(ROUND(l.Qty * l.UnitPrice * (1 - l.DiscountPct), 2) AS decimal(18,2))) AS Sales,
            COUNT(DISTINCT h.InvoiceID) AS Invoices
    INTO #RepMonth
    FROM dbo.InvoiceHeader h
    JOIN dbo.InvoiceLine   l ON l.InvoiceID = h.InvoiceID
    WHERE h.InvoiceDate >= @StartDate
      AND h.InvoiceDate <  DATEADD(DAY, 1, @EndDate)     -- SARGable: sem função na coluna
      AND h.Status = 'P'
    GROUP BY h.SalesRepID, DATEFROMPARTS(YEAR(h.InvoiceDate), MONTH(h.InvoiceDate), 1);

    CREATE CLUSTERED INDEX CX ON #RepMonth (SalesRepID, MonthStart);

    SELECT  r.RepName,
            m.MonthStart,
            m.Sales,
            m.Invoices,
            LAG(m.Sales) OVER (PARTITION BY m.SalesRepID ORDER BY m.MonthStart)               AS PrevMonthSales,
            SUM(m.Sales) OVER (PARTITION BY m.SalesRepID ORDER BY m.MonthStart
                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)              AS RunningTotal,
            AVG(m.Sales) OVER (PARTITION BY m.SalesRepID ORDER BY m.MonthStart
                               ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)                      AS Moving3MoAvg,
            RANK()       OVER (PARTITION BY m.MonthStart ORDER BY m.Sales DESC)               AS RankInMonth,
            CAST(100.0 * m.Sales / NULLIF(SUM(m.Sales) OVER (PARTITION BY m.MonthStart), 0)
                 AS decimal(5,2))                                                             AS PctOfMonth
    FROM #RepMonth m
    JOIN dbo.SalesRep r ON r.SalesRepID = m.SalesRepID
    ORDER BY r.RepName, m.MonthStart;
END
GO

/* ---------------------------------------------------------------------
   4) Procs "da aplicação": menu de relatórios e layout por cliente
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.app_ListReports
AS
BEGIN
    SET NOCOUNT ON;
    SELECT rd.ReportID, rd.ReportCode, rd.ReportName, rd.RptFileName, rd.MenuPath
    FROM dbo.ReportDefinition rd
    WHERE rd.IsActive = 1
    ORDER BY rd.MenuPath, rd.ReportName;

    SELECT rp.ReportID, rp.ParamName, rp.PromptText, rp.DataType, rp.DefaultValue, rp.SortOrder
    FROM dbo.ReportParameter rp
    JOIN dbo.ReportDefinition rd ON rd.ReportID = rp.ReportID AND rd.IsActive = 1
    ORDER BY rp.ReportID, rp.SortOrder;
END
GO

/* Qual .rpt de fatura usar para esta fatura (customer-specific layout) */
CREATE OR ALTER PROCEDURE dbo.app_ResolveInvoiceReport
    @InvoiceID int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (1) rd.ReportCode, rd.RptFileName
    FROM dbo.InvoiceHeader h
    JOIN dbo.ReportAssignment ra ON ra.CustomerID = h.CustomerID OR ra.CustomerID IS NULL
    JOIN dbo.ReportDefinition rd ON rd.ReportID = ra.ReportID AND rd.IsActive = 1
    WHERE h.InvoiceID = @InvoiceID
      AND rd.ReportCode LIKE 'INVOICE%'
    ORDER BY ra.Priority;
END
GO

/* Lista para o combo do app de estudo */
CREATE OR ALTER PROCEDURE dbo.app_ListInvoices
    @Top int = 300
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@Top) h.InvoiceID,
           h.InvoiceNo + '  |  ' + CONVERT(varchar(10), h.InvoiceDate, 23) + '  |  ' + c.CustomerName
             + CASE WHEN c.InvoiceFormat = 'CUSTOM' THEN '  [CUSTOM]' ELSE '' END AS Display
    FROM dbo.InvoiceHeader h
    JOIN dbo.Customer c ON c.CustomerID = h.CustomerID
    WHERE h.Status = 'P'
    ORDER BY h.InvoiceDate DESC, h.InvoiceNo DESC;
END
GO

-- Testes rápidos
EXEC dbo.rpt_Invoice @InvoiceID = 10;
EXEC dbo.rpt_CustomerAging @CustomerID = 1;
DECLARE @s date = DATEADD(MONTH, -6, CAST(GETDATE() AS date)), @e date = CAST(GETDATE() AS date);
EXEC dbo.rpt_SalesSummary @StartDate = @s, @EndDate = @e;
EXEC dbo.app_ResolveInvoiceReport @InvoiceID = 10;
