Coloque aqui os .rpt que você desenhar (o app procura esta pasta):

  Invoice.rpt         - fatura padrão (pull, proc dbo.rpt_Invoice) + subreport de aging
  Invoice_Custom.rpt  - layout alternativo p/ clientes [CUSTOM] (opcional)
  Invoice_Push.rpt    - fatura desenhada sobre Output\InvoicePush.xsd (push)
  SalesSummary.rpt    - resumo por vendedor (proc dbo.rpt_SalesSummary)

Ao adicionar um .rpt pelo Visual Studio (Add > New Item > Crystal Reports),
nas propriedades do arquivo deixe:
  Build Action = None
  Copy to Output Directory = Copy if newer
  Custom Tool = (vazio)
Assim ele é carregado do disco, como numa biblioteca de relatórios de ERP,
e não embutido no .exe como classe tipada.
