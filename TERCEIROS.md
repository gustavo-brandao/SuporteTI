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
