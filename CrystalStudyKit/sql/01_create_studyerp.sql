/* =====================================================================
   StudyERP - mini-ERP de distribuição para estudar Crystal Reports
   Rode no SSMS conectado ao seu SQL Server local (Developer/Express).
   Cria o banco, as tabelas e ~2.000 faturas com itens.
   ===================================================================== */
USE master;
GO
IF DB_ID('StudyERP') IS NOT NULL
BEGIN
    ALTER DATABASE StudyERP SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE StudyERP;
END
GO
CREATE DATABASE StudyERP;
GO
USE StudyERP;
GO

/* ---------- Cadastros ---------- */
CREATE TABLE dbo.Company (
    CompanyID     int IDENTITY PRIMARY KEY,
    CompanyName   nvarchar(100) NOT NULL,
    AddressLine1  nvarchar(100) NOT NULL,
    City          nvarchar(60)  NOT NULL,
    StateCode     char(2)       NOT NULL,
    PostalCode    varchar(10)   NOT NULL,
    Phone         varchar(20)   NULL,
    LogoPath      nvarchar(260) NULL
);

CREATE TABLE dbo.Customer (
    CustomerID    int IDENTITY PRIMARY KEY,
    CustomerCode  varchar(10)   NOT NULL UNIQUE,
    CustomerName  nvarchar(100) NOT NULL,
    BillAddress1  nvarchar(100) NOT NULL,
    BillAddress2  nvarchar(100) NULL,
    BillCity      nvarchar(60)  NOT NULL,
    BillState     char(2)       NOT NULL,
    BillZip       varchar(10)   NOT NULL,
    ShipAddress1  nvarchar(100) NOT NULL,
    ShipCity      nvarchar(60)  NOT NULL,
    ShipState     char(2)       NOT NULL,
    ShipZip       varchar(10)   NOT NULL,
    PaymentTerms  varchar(20)   NOT NULL,   -- NET30, NET60, COD
    TaxRate       decimal(5,4)  NOT NULL,
    InvoiceFormat varchar(20)   NOT NULL DEFAULT 'STANDARD' -- usado em ReportAssignment
);

CREATE TABLE dbo.Item (
    ItemID        int IDENTITY PRIMARY KEY,
    ItemCode      varchar(20)   NOT NULL UNIQUE,
    Description   nvarchar(200) NOT NULL,   -- descrições longas p/ testar Can Grow / truncamento
    UOM           varchar(5)    NOT NULL,
    UnitPrice     decimal(18,4) NOT NULL,
    ProductLine   varchar(20)   NOT NULL
);

CREATE TABLE dbo.SalesRep (
    SalesRepID    int IDENTITY PRIMARY KEY,
    RepName       nvarchar(60) NOT NULL
);

/* ---------- Movimento ---------- */
CREATE TABLE dbo.InvoiceHeader (
    InvoiceID     int IDENTITY PRIMARY KEY,
    InvoiceNo     varchar(12)   NOT NULL UNIQUE,
    CustomerID    int           NOT NULL REFERENCES dbo.Customer(CustomerID),
    SalesRepID    int           NOT NULL REFERENCES dbo.SalesRep(SalesRepID),
    InvoiceDate   date          NOT NULL,
    DueDate       date          NOT NULL,
    CustomerPO    varchar(30)   NULL,
    Freight       decimal(18,2) NOT NULL DEFAULT 0,
    Notes         nvarchar(500) NULL,
    Status        char(1)       NOT NULL DEFAULT 'P'  -- P=Posted, V=Void
);
CREATE INDEX IX_InvoiceHeader_Customer_Date ON dbo.InvoiceHeader(CustomerID, InvoiceDate);
CREATE INDEX IX_InvoiceHeader_Date ON dbo.InvoiceHeader(InvoiceDate) INCLUDE (CustomerID, Status, Freight);

CREATE TABLE dbo.InvoiceLine (
    InvoiceLineID int IDENTITY PRIMARY KEY,
    InvoiceID     int           NOT NULL REFERENCES dbo.InvoiceHeader(InvoiceID),
    LineNum        int           NOT NULL,
    ItemID        int           NOT NULL REFERENCES dbo.Item(ItemID),
    Qty           decimal(18,4) NOT NULL,
    UnitPrice     decimal(18,4) NOT NULL,
    DiscountPct   decimal(5,4)  NOT NULL DEFAULT 0,
    LotNumber     varchar(20)   NULL
);
CREATE INDEX IX_InvoiceLine_Invoice ON dbo.InvoiceLine(InvoiceID) INCLUDE (ItemID, Qty, UnitPrice, DiscountPct);

/* ---------- Tabelas de "integração" de relatórios (como no ERP da vaga) ----------
   A vaga cita: report definitions, parameters, prompts, menus e customer visibility
   através de tabelas da aplicação. Este é um modelo simples disso.            */
CREATE TABLE dbo.ReportDefinition (
    ReportID      int IDENTITY PRIMARY KEY,
    ReportCode    varchar(30)   NOT NULL UNIQUE,  -- ex.: INVOICE_STD
    ReportName    nvarchar(100) NOT NULL,
    RptFileName   nvarchar(260) NOT NULL,         -- relativo à pasta de relatórios
    MenuPath      nvarchar(200) NOT NULL,         -- ex.: Sales > Invoices
    IsActive      bit           NOT NULL DEFAULT 1
);

CREATE TABLE dbo.ReportParameter (
    ReportParameterID int IDENTITY PRIMARY KEY,
    ReportID      int           NOT NULL REFERENCES dbo.ReportDefinition(ReportID),
    ParamName     varchar(50)   NOT NULL,         -- nome EXATO do parâmetro no .rpt (sem o ?)
    PromptText    nvarchar(100) NOT NULL,
    DataType      varchar(10)   NOT NULL,         -- INT, DATE, STRING, BOOL
    DefaultValue  nvarchar(100) NULL,
    SortOrder     int           NOT NULL
);

/* Qual layout cada cliente usa (customer-specific invoice) */
CREATE TABLE dbo.ReportAssignment (
    ReportAssignmentID int IDENTITY PRIMARY KEY,
    ReportID      int NOT NULL REFERENCES dbo.ReportDefinition(ReportID),
    CustomerID    int NULL REFERENCES dbo.Customer(CustomerID), -- NULL = padrão p/ todos
    Priority      int NOT NULL DEFAULT 100
);
GO

/* =====================================================================
   SEED
   ===================================================================== */
INSERT dbo.Company (CompanyName, AddressLine1, City, StateCode, PostalCode, Phone)
VALUES (N'Acme Industrial Supply, Inc.', N'1200 Commerce Blvd', N'Columbus', 'OH', '43215', '(614) 555-0100');

INSERT dbo.SalesRep (RepName) VALUES (N'Linda Park'),(N'Carlos Mendes'),(N'Tom Becker'),(N'Aisha Khan');

/* Clientes */
;WITH n AS (SELECT TOP (60) CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS int) AS i FROM sys.all_objects)
INSERT dbo.Customer (CustomerCode, CustomerName, BillAddress1, BillAddress2, BillCity, BillState, BillZip,
                     ShipAddress1, ShipCity, ShipState, ShipZip, PaymentTerms, TaxRate, InvoiceFormat)
SELECT  'C' + RIGHT('0000' + CAST(i AS varchar(4)), 4),
        CHOOSE(i % 6 + 1, N'Midwest Fabrication', N'Great Lakes Machining', N'Summit Tool & Die',
               N'Riverbend Plastics Manufacturing Company of North America', N'Delta Hydraulics', N'Prairie Metalworks')
            + N' #' + CAST(i AS nvarchar(4)),
        CAST(100 + i * 7 AS nvarchar(10)) + N' Industrial Pkwy',
        CASE WHEN i % 4 = 0 THEN N'Suite ' + CAST(i AS nvarchar(5)) END,   -- NULL em 3/4 -> teste de linha suprimida
        CHOOSE(i % 5 + 1, N'Detroit', N'Cleveland', N'Indianapolis', N'Milwaukee', N'Chicago'),
        CHOOSE(i % 5 + 1, 'MI', 'OH', 'IN', 'WI', 'IL'),
        RIGHT('00000' + CAST(40000 + i * 13 AS varchar(6)), 5),
        CAST(500 + i * 3 AS nvarchar(10)) + N' Warehouse Rd',
        CHOOSE(i % 5 + 1, N'Detroit', N'Cleveland', N'Indianapolis', N'Milwaukee', N'Chicago'),
        CHOOSE(i % 5 + 1, 'MI', 'OH', 'IN', 'WI', 'IL'),
        RIGHT('00000' + CAST(40000 + i * 13 AS varchar(6)), 5),
        CHOOSE(i % 3 + 1, 'NET30', 'NET60', 'COD'),
        CHOOSE(i % 4 + 1, 0.0600, 0.0575, 0.0700, 0.0000),
        CASE WHEN i % 10 = 0 THEN 'CUSTOM' ELSE 'STANDARD' END
FROM n;

/* Itens */
;WITH n AS (SELECT TOP (200) CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS int) AS i FROM sys.all_objects)
INSERT dbo.Item (ItemCode, Description, UOM, UnitPrice, ProductLine)
SELECT  'IT-' + RIGHT('00000' + CAST(i AS varchar(5)), 5),
        CHOOSE(i % 5 + 1,
            N'Hex Bolt Grade 8, 1/2-13 x 2"',
            N'Hydraulic Hose Assembly 3/8" ID, 3000 PSI, JIC female swivel both ends, 48" overall length',
            N'Bearing 6205-2RS',
            N'Steel Plate A36 1/4" x 48" x 96"',
            N'Cutting Fluid Semi-Synthetic 5 gal pail - water-miscible concentrate for ferrous and non-ferrous machining operations'),
        CHOOSE(i % 4 + 1, 'EA', 'BX', 'FT', 'GAL'),
        CAST(1.25 + (i * 37 % 900) / 3.0 AS decimal(18,4)),
        CHOOSE(i % 4 + 1, 'FASTENERS', 'HYDRAULICS', 'BEARINGS', 'RAW')
FROM n;

/* Faturas: ~2000 nos últimos 18 meses */
;WITH n AS (SELECT TOP (2000) CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS int) AS i
            FROM sys.all_objects a CROSS JOIN sys.all_objects b)
INSERT dbo.InvoiceHeader (InvoiceNo, CustomerID, SalesRepID, InvoiceDate, DueDate, CustomerPO, Freight, Notes, Status)
SELECT  'INV' + RIGHT('000000' + CAST(100000 + i AS varchar(7)), 6),
        (i * 7) % 60 + 1,
        i % 4 + 1,
        d.InvDate,
        DATEADD(DAY, 30, d.InvDate),
        CASE WHEN i % 3 = 0 THEN NULL ELSE 'PO-' + CAST(50000 + i AS varchar(10)) END,
        CAST((i % 7) * 12.5 AS decimal(18,2)),
        CASE WHEN i % 25 = 0 THEN N'Deliver to dock 4 only. Call 30 minutes before arrival. Forklift required for pallets over 2,000 lb.' END,
        CASE WHEN i % 97 = 0 THEN 'V' ELSE 'P' END
FROM n
CROSS APPLY (SELECT DATEADD(DAY, -(i % 540), CAST(GETDATE() AS date)) AS InvDate) d;

/* Itens: 1 a 25 linhas por fatura (algumas longas p/ testar quebra de página) */
;WITH lines AS (SELECT TOP (25) CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS int) AS ln FROM sys.all_objects)
INSERT dbo.InvoiceLine (InvoiceID, LineNum, ItemID, Qty, UnitPrice, DiscountPct, LotNumber)
SELECT  h.InvoiceID,
        l.ln,
        (h.InvoiceID * 13 + l.ln * 17) % 200 + 1,
        CAST(1 + (h.InvoiceID + l.ln) % 50 AS decimal(18,4)),
        it.UnitPrice,
        CASE WHEN (h.InvoiceID + l.ln) % 9 = 0 THEN 0.1000 ELSE 0 END,
        CASE WHEN l.ln % 3 = 0 THEN 'LOT' + CAST(h.InvoiceID * 10 + l.ln AS varchar(12)) END
FROM dbo.InvoiceHeader h
JOIN lines l ON l.ln <= 1 + (h.InvoiceID * 7) % 25
JOIN dbo.Item it ON it.ItemID = (h.InvoiceID * 13 + l.ln * 17) % 200 + 1;

/* Definições de relatório */
INSERT dbo.ReportDefinition (ReportCode, ReportName, RptFileName, MenuPath)
VALUES ('INVOICE_STD',    N'Invoice (Standard)',       N'Invoice.rpt',        N'Sales > Invoices'),
       ('INVOICE_CUSTOM', N'Invoice (Custom layout)',  N'Invoice_Custom.rpt', N'Sales > Invoices'),
       ('SALES_SUMMARY',  N'Sales Summary by Rep',     N'SalesSummary.rpt',   N'Sales > Analysis');

INSERT dbo.ReportParameter (ReportID, ParamName, PromptText, DataType, DefaultValue, SortOrder)
SELECT ReportID, 'InvoiceID', N'Invoice', 'INT', NULL, 1 FROM dbo.ReportDefinition WHERE ReportCode LIKE 'INVOICE%'
UNION ALL
SELECT ReportID, 'StartDate', N'From date', 'DATE', NULL, 1 FROM dbo.ReportDefinition WHERE ReportCode = 'SALES_SUMMARY'
UNION ALL
SELECT ReportID, 'EndDate',   N'To date',   'DATE', NULL, 2 FROM dbo.ReportDefinition WHERE ReportCode = 'SALES_SUMMARY';

/* Padrão para todos + layout custom para clientes com InvoiceFormat = CUSTOM */
INSERT dbo.ReportAssignment (ReportID, CustomerID, Priority)
SELECT ReportID, NULL, 100 FROM dbo.ReportDefinition WHERE ReportCode = 'INVOICE_STD';

INSERT dbo.ReportAssignment (ReportID, CustomerID, Priority)
SELECT r.ReportID, c.CustomerID, 10
FROM dbo.ReportDefinition r CROSS JOIN dbo.Customer c
WHERE r.ReportCode = 'INVOICE_CUSTOM' AND c.InvoiceFormat = 'CUSTOM';
GO

SELECT (SELECT COUNT(*) FROM dbo.Customer)      AS Customers,
       (SELECT COUNT(*) FROM dbo.InvoiceHeader) AS Invoices,
       (SELECT COUNT(*) FROM dbo.InvoiceLine)   AS InvoiceLines;
