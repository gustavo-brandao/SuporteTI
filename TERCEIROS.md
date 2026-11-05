# Componentes de terceiros

A [licença MIT](LICENSE) cobre o código próprio do Suporte TI. Os componentes abaixo mantêm suas respectivas licenças.

## smartmontools / smartctl 7.5

- Projeto oficial: https://github.com/smartmontools/smartmontools
- Release fixada: https://github.com/smartmontools/smartmontools/releases/tag/RELEASE_7_5
- Copyright: Bruce Allen, Christian Franke e demais contribuidores, conforme os arquivos originais.
- Licenca: GNU GPL versao 2 ou posterior, conforme os avisos do executavel e o codigo-fonte.
- Licenca incluida: `Ferramentas/smartmontools/doc/COPYING.txt`.
- Codigo-fonte original incluido: `Ferramentas/smartmontools/smartmontools-7.5.tar.gz`.
- Instalador de origem: `smartmontools-7.5.win32-setup.exe`, obtido dos assets oficiais da release.
- A assinatura Authenticode do instalador foi verificada como valida antes da extracao (SignPath Foundation).
- Extracao limitada a smartctl x64, base de discos e documentacao, sem servico smartd, PATH, atalhos ou registro de desinstalacao.
- Binario e base sem modificacoes locais. SHA256 em `Ferramentas/smartmontools/integridade.json`.
- Interface invoca o programa separado e le sua saida JSON. Nao inclui sua interface grafica nem executa comandos de configuracao/reparo de discos.

Para redistribuir, preserve os avisos e a fonte correspondente. A assinatura do pacote e o manifesto nao substituem a revisao da cadeia de distribuicao do projeto inteiro.

## Referências do catálogo de falhas

Os identificadores numéricos e nomes técnicos vieram do índice de códigos de parada e dos cabeçalhos oficiais `ntstatus.h` e `winerror.h`. O catálogo reúne esses dados e explicações próprias. Para códigos com mensagem nativa, a consulta lê o texto dos recursos instalados no Windows. O pacote inclui somente os dados do catálogo e a implementação da consulta. [Índice de códigos de parada](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/bug-check-code-reference2) · [ntstatus.h](https://github.com/microsoft/win32metadata/blob/main/generation/WinSDK/RecompiledIdlHeaders/shared/ntstatus.h) · [winerror.h](https://github.com/microsoft/win32metadata/blob/main/generation/WinSDK/RecompiledIdlHeaders/shared/winerror.h) · [Mensagens NTSTATUS](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/devprop-type-ntstatus)

## Referência técnica de interpretação SMART

Para o Kingston A400, a prévia 0.1.12 usa o valor bruto do E7 nos firmwares SBFK e o valor normalizado no firmware `03070009`. O valor escolhido é a resistência restante. A regra foi conferida com a documentação da [Kingston sobre o atributo E7](https://media.kingston.com/kingston/pdf/SMART-attribute.pdf) e com a [distinção por firmware do CrystalDiskInfo](https://github.com/hiyohiyo/CrystalDiskInfo/blob/master/AtaSmart.cpp). A leitura do firmware SBFK61F1 foi confirmada no equipamento. Nos casos sem leitura interpretável, o percentual é omitido.

A prévia 0.1.8 usa a documentação de saúde do [CrystalDiskInfo](https://crystalmark.info/en/software/crystaldiskinfo/crystaldiskinfo-health-status/) como referência para interpretação de atributos por modelo. Para o Crucial MX500, o atributo 202 (`CAh`) segue a [referência SMART da Micron](https://www.smartmontools.org/raw-attachment/ticket/812/tnfd22_client_ssd_smart_attributes.pdf) e a entrada da família MX500 na base `drivedb.h` já distribuída com o smartctl. A regra exige concordância entre o percentual restante normalizado e o percentual usado bruto. O pacote utiliza o smartctl para coletar os dados e não inclui executável nem código-fonte do CrystalDiskInfo.
