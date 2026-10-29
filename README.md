# Crystal Study Kit 

Mini-ERP de distribuição (SQL Server) + app VB.NET WinForms (.NET Framework 4.8)
com Crystal Reports, cobrindo exatamente o que a vaga pede.

Tempo total: **cerca de 3 horas**. Se faltar tempo, faça só os blocos marcados com ⭐.

---

## 0. Instalar (30-40 min, em paralelo)

| O quê | Observação |
|---|---|
| Visual Studio 2022 Community | Workload **.NET desktop development** |
| SAP Crystal Reports for Visual Studio (SP mais recente, 39/40) | Baixe **o instalador do IDE** e os **runtimes MSI 32-bit e 64-bit** |
| SQL Server 2022 Developer + SSMS | Instância padrão `localhost` |
| Microsoft OLE DB Driver for SQL Server (MSOLEDBSQL) | Provider recomendado para o .rpt. O instalador traz 32 e 64-bit |

> O designer do Crystal dentro do VS 2022 roda em processo 64-bit. Por isso o
> provider usado no Database Expert precisa existir em 64-bit. Já o seu app
> roda na bitness que você compilar (x86/x64) e precisa do runtime Crystal e
> dos providers **na mesma bitness**.

## 1. Banco ⭐ (10 min)

No SSMS, rode em ordem:

1. `sql/01_create_studyerp.sql`: cria o `StudyERP` com 60 clientes, 200 itens, cerca de 2.000 faturas e as tabelas de integração (`ReportDefinition`, `ReportParameter`, `ReportAssignment`).
2. `sql/02_report_procs.sql`: procs dos relatórios (`rpt_Invoice`, `rpt_CustomerAging`, `rpt_SalesSummary`) e da aplicação (`app_ResolveInvoiceReport`...).
3. `sql/03_performance_lab.sql`: deixe para o bloco 5.

## 2. Abrir o projeto ⭐ (5 min)

Abra `src/CrystalStudy.sln`, plataforma **x86**, e faça o Build.
- Se aparecer referência quebrada no `CrystalDecisions.*`: remova e adicione de novo em
  *Add Reference > Assemblies > Extensions*. Repare na versão (13.0.xxxx), que é a mesma
  conversa do upgrade.
- Ajuste servidor/autenticação em `App.config` se não for `localhost` com Windows auth.

Rode o app. Ele lista as faturas. A barra de status mostra **bitness do processo
e versão do runtime Crystal carregado**.

## 3. Desenhar a fatura ⭐ (60 min): `Reports/Invoice.rpt`

*Add > New Item > Crystal Reports > Blank report* dentro da pasta `Reports`.
Em seguida, nas propriedades do arquivo: Build Action **None**, Copy to Output **Copy if newer**, Custom Tool **vazio**.

1. **Fonte de dados:** Database Expert > Create New Connection > **OLE DB (ADO)** >
   *Microsoft OLE DB Driver for SQL Server* > `localhost` / `StudyERP` > Stored Procedures >
   `rpt_Invoice`. O Crystal cria os parâmetros `@InvoiceID`, `@FromDate` e `@ToDate`.
   Marque *Set to Null value* nos dois de data.
2. **Grupo:** Insert > Group > `InvoiceNo`. Em Section Expert, no Group Header 1,
   ative *New Page Before* (exceto no 1º registro: fórmula `Not OnFirstRecord`) e
   *Repeat Group Header On Each Page*.
3. **Cabeçalho (GH1):** empresa, Bill To / Ship To, nº da fatura, data, vencimento, PO, termos.
   - `BillAddress2` é NULL na maioria: coloque numa seção própria e use
     *Suppress Blank Section*, ou junte num text object com *Suppress Embedded Field Blank Lines*.
   - `CustomerPO` NULL: fórmula `If IsNull({rpt_Invoice;1.CustomerPO}) Then "-" Else {rpt_Invoice;1.CustomerPO}`.
4. **Detalhe:** LineNum, ItemCode, Description, UOM, Qty, UnitPrice, ExtAmount.
   - `Description` é longa em alguns itens: ative **Can Grow** e veja a linha crescer sem cortar.
   - Lot: rótulo "Lot:" + campo, com suppress condicional `IsNull({rpt_Invoice;1.LotNumber})`.
5. **Totais (GF1):** faça **das duas formas** e compare:
   - Summary do Crystal: `Sum({ExtAmount}, {InvoiceNo})`.
   - Campos vindos do SQL: `InvoiceSubtotal` e `InvoiceTax` (window functions).
   - Total = subtotal + tax + `Freight`. Use fórmula com `Round(x, 2)`.
6. **Running total:** contador de linhas por fatura (Reset on change of group), comparado com `LineCount` do SQL.
7. **Subreport de aging:** Insert > Subreport > nova, sobre `rpt_CustomerAging`.
   Em *Change Subreport Links*, ligue `@CustomerID` a `rpt_Invoice;1.CustomerID` e
   `@AsOfDate` a `InvoiceDate`. Coloque no GF1.
   - Teste **shared variable**: no subreport, `WhilePrintingRecords; Shared CurrencyVar Over60 := {rpt_CustomerAging;1.Over60}`.
     Na seção **abaixo** do subreport, mostre um aviso "Account past due" se `Over60 > 0`.
     Repare que a seção precisa vir depois: é o timing de avaliação.
8. **Página:** Page Footer com "Page N of M". Teste `Page N of M` com faturas de 25 linhas.
9. **Status Void:** marca d'água "VOID" via suppress condicional. A proc já filtra 'P', então altere a proc para testar.

Rode **Fatura (pull)**, depois **Exportar PDF** e **Imprimir...** (use "Microsoft Print to PDF").

## 4. Outros relatórios (30 min)

- **Invoice_Custom.rpt:** *Save As* da fatura com layout diferente (logo à direita, colunas
  trocadas). Clientes marcados `[CUSTOM]` no combo passam a abrir esse layout:
  `app_ResolveInvoiceReport` + `ReportAssignment` (= "customer visibility through application tables").
- **Invoice_Push.rpt:** clique **Gerar XSD (push)**. No designer: Create New Connection >
  **ADO.NET (XML)** > `Output/InvoicePush.xsd`. Monte um layout simples e rode **Fatura (push)**.
  - Se der `FileNotFoundException crdb_adoplus.dll`, confira o `useLegacyV2RuntimeActivationPolicy` no App.config.
  - `.ttx` é o equivalente antigo (Field Definitions Only): um arquivo-texto com nome, tipo e tamanho dos campos.
- **SalesSummary.rpt:** sobre `rpt_SalesSummary`. Agrupe por `RepName`, coloque um gráfico de
  linha de `Sales` por `MonthStart` e use `RunningTotal`, `PrevMonthSales` e `RankInMonth` vindos do SQL.

## 5. Laboratório de upgrade (30 min)

1. **Inventário:** botão **Inventário .rpt**. Abre um CSV com tabelas, parâmetros, subreports,
   fórmulas, papel e fórmula de seleção de cada .rpt. É o primeiro passo para planejar o upgrade
   de uma biblioteca grande. (Bom exemplo de onde usar GenAI: classificar risco por relatório
   a partir desse CSV.)
2. **Baseline:** **Exportar lote PDF** com rótulo `antes_x86`.
3. **Troque a bitness:** mude a plataforma para **x64**, build, rode e exporte com rótulo `depois_x64`.
   - Se não instalou o runtime 64-bit, veja o erro de carregar `CrystalDecisions...` /
     "Could not load file or assembly" e entenda **por quê**: o runtime é por bitness.
   - Compare as pastas: tamanhos, páginas, abra lado a lado. Ferramentas como `diff-pdf` ajudam.
4. **Binding redirect:** leia o bloco comentado em `App.config` e saiba explicar quando ele é necessário
   (um assembly de terceiros compilado contra um SP antigo, com só o runtime novo na máquina).
5. `sql/03_performance_lab.sql` com plano de execução ligado (Ctrl+M).

