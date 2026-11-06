# Resultado da verificacao

## Previa 0.1.23

O iniciador e a DLL foram recompilados a partir do código da edição pública. A suíte do Windows PowerShell 5.1 passou com **204 testes e zero falhas** usando os binários recompilados. O pacote portátil inclui os dois fluxos de consulta sem escolha manual de família e acompanha um arquivo SHA-256 em Releases.

## Atalho da triagem na CLI

No Windows PowerShell 5.1, **203 testes passaram sem falhas**. A suíte conferiu a separação entre texto e códigos estruturados, a escolha entre códigos iguais de famílias diferentes, o atalho para salvar e a rejeição de uma opção fora da lista. Uma execução de `Iniciar.ps1` com um evento simulado do Kernel-Power exibiu `[1] Consultar 0x000000EF (Tela azul)`. Digitar **1** abriu diretamente a explicação de `CRITICAL_PROCESS_DIED`.

Com a pesquisa de códigos avulsos sem seleção de família, **204 testes passaram sem falhas**. No terminal, digitar `5` exibiu `ERROR_ACCESS_DENIED` e `INVALID_PROCESS_ATTACH_ATTEMPT` com o aviso de ambiguidade. A suíte também verificou HRESULT decimal negativo, código sem correspondência e entrada fora do intervalo de 32 bits.

## Previa 0.1.22

Duas rodadas no Windows PowerShell 5.1 passaram com **198 testes e zero falhas em cada rodada**. Os cinco testes novos executaram a entrada da janela elevada sem UAC sobre uma cópia do pacote: a operação rodou a partir da cópia protegida em `Windows\Temp`, com argumentos e código de saída preservados, e a cópia foi removida. Um `Elevado.ps1` alterado depois da abertura foi bloqueado sem executar. O comando elevado de produção tem cerca de 2.500 caracteres.

`Construcao\Compilar.ps1` gerou o executável e a DLL com as mesmas referências, tipos públicos e ícone dos binários anteriores. O executável compilado abriu o menu, exibiu a versão 0.1.22 em **Sobre** e encerrou com código 0.

Após a revisão da cópia elevada, **201 testes passaram sem falhas** no Windows PowerShell 5.1 com o executável e a DLL recém-compilados. Os testes confirmaram a limpeza da cópia mesmo com um arquivo de origem somente leitura, o bloqueio de um script marcado como baixado da Internet e a exigência de assinatura para a cópia de rede. As duas unidades de rede visíveis na estação foram classificadas corretamente. A sessão de teste não tinha certificado de assinatura de código com chave privada disponível. O UAC com outra conta e a operação pelo compartilhamento com pacote assinado continuam pendentes de homologação em VM.

## Previa 0.1.21

Duas rodadas no Windows PowerShell 5.1 passaram com **193 testes e zero falhas em cada rodada**. A verificação inclui navegação de todas as opções, sequência das telas da consulta de código, quebra de linhas em 24 colunas, rótulos sem cor e seleção de tons para fundos claro e escuro. O terminal interativo confirmou a limpeza da tela nas transições do fluxo de códigos.

## Previa 0.1.20

Duas rodadas no Windows PowerShell 5.1 passaram com **191 testes e zero falhas em cada rodada**. A triagem automática foi exercitada com um evento de ID 0 sem código, registros anteriores com códigos explicáveis, números no texto livre e um código repetido. A saída exibiu os códigos estruturados e as explicações sem pedir entrada manual.

## Previa 0.1.19

Duas rodadas no Windows PowerShell 5.1 passaram com **189 testes e zero falhas em cada rodada**. Os testes verificaram o despacho das duas consultas em **Computador > Falhas recentes e códigos de erro** e o retorno por 0 ou Enter sem iniciar uma consulta.

## Previa 0.1.18

Duas rodadas no Windows PowerShell 5.1 passaram com **188 testes e zero falhas em cada rodada**. O catálogo ocupa 954.570 bytes e reúne 9.608 entradas. Foram conferidos o tamanho e os campos do arquivo, as explicações revisadas, a leitura parcial sem catálogo e a consulta manual com valores em decimal, hexadecimal e decimal negativo. Os testes incluem a separação entre HRESULT e NTSTATUS.

## Previa 0.1.17

Duas rodadas no Windows PowerShell 5.1 passaram com **186 testes e zero falhas em cada rodada**. O catálogo JSON tem 35 entradas, com 23 códigos de parada e 12 de exceção, em 10.271 bytes. Os testes conferiram os campos e a referência oficial de cada entrada, a tradução de um código novo na triagem e a exibição do código e do incidente quando o arquivo fica indisponível.

## Previa 0.1.16

Duas rodadas no Windows PowerShell 5.1 passaram com **184 testes e zero falhas em cada rodada**. A triagem foi verificada com registros simulados de tela azul, reinício sem código, travamento de aplicativo, exceção de aplicativo traduzida e código desconhecido. Os testes confirmaram que a descrição aparece junto ao código, que registros do mesmo reinício são agrupados e que um evento de vídeo posterior à inicialização fica fora das pistas anteriores.

A consulta de falhas foi executada duas vezes nos logs reais do Windows em modo somente leitura. Nenhuma falha foi provocada. A cobertura de telas azuis e travamentos específicos foi verificada com dados simulados.

## Previa 0.1.15

Duas rodadas no Windows PowerShell 5.1 passaram com **180 testes e zero falhas em cada rodada**. Cada rodada verificou os dois recursos no menu. Para o mapa, os testes conferiram soma de tamanhos, junção ignorada, limite de leitura, cores, retângulos de subpastas e navegação. Para o Autologon, conferiram gravação e desativação simuladas, recuperação após falha e encaminhamento para o console atual quando já elevado.

A janela do mapa abriu e fechou duas vezes com arquivos de teste e apresentou os dois retângulos esperados e a capacidade do volume local. A consulta de estado do Autologon passou duas vezes no Windows real, em modo somente leitura. A gravação do segredo LSA, a autenticação após reiniciar e a desativação real ainda requerem uma VM com conta descartável. O JSON desta prévia registra a segunda rodada da suíte.

## Previa 0.1.14

A opção **Sobre** foi conferida pelo executável em duas aberturas, com retorno por 0 e por Enter. Com dados de sessão fictícios, a tela apresentou apenas a versão 0.1.14, o ano 2026 e o crédito de Gustavo Brandão Gimenez. O JSON distribuído naquela prévia correspondia à suíte da versão 0.1.13.

## Previa 0.1.13

Duas rodadas no Windows PowerShell 5.1 passaram com **174 testes e zero falhas em cada rodada**. Os casos cobriram despacho das opções, retorno por 0 e Enter sem executar ações, opção de bateria em desktop, alinhamento de discos em 36 colunas e diagnóstico de impressão com fila bloqueada, fila inacessível e spooler parado. O JSON registra a segunda rodada desta prévia.

No desktop de teste, a consulta de bateria informou que não se aplicava. O diagnóstico real de impressão consultou 12 filas visíveis e identificou uma fila sinalizada pelo Windows. As condições de fila bloqueada e spooler parado foram simuladas. A consulta real não enviou trabalhos nem alterou filas.

## Previa 0.1.12

Duas rodadas no Windows PowerShell 5.1 passaram com **169 testes e zero falhas em cada rodada**. A regressão do Kingston A400 simulou o relatório SMART completo do firmware SBFK61F1 e confirmou **13% usados e 87% restantes**, sem alerta preventivo. Também foram testados o firmware que usa o valor normalizado, um firmware desconhecido e um valor fora da faixa. O JSON atual registra a segunda rodada desta prévia.

No equipamento real, o E7 do Kingston retornou valor bruto 87 e valor normalizado 13. A consulta corrigida mostrou 13% usados e 87% restantes. A avaliação geral do Kingston e do HDD ficou inconclusiva devido a leitura SMART parcial na sessão de teste. O NVMe mostrou 1% usado e 99% restantes, sem alertas. O HDD permaneceu sem porcentagem.

## Previa 0.1.11

Duas rodadas no Windows PowerShell 5.1 passaram com **167 testes e zero falhas em cada rodada**. Os testes simularam temperatura fora do limite, reserva baixa, erros de mídia, aviso genérico, perda de confiabilidade e modo somente leitura em NVMe. O relatório real manteve o HDD sem porcentagem e inconclusivo por SMART parcial, o Kingston SATA com atenção a 87% de desgaste e o WDC NVMe sem alertas a 1%. A prévia 0.1.12 corrigiu a interpretação invertida do Kingston nesse relatório. O JSON distribuído com a prévia 0.1.11 corresponde à segunda rodada daquela versão.

## Previa 0.1.10

Duas rodadas no Windows PowerShell 5.1 passaram com **162 testes e zero falhas em cada rodada**. O teste de regressão confirmou que o contador `Wear=0` do Windows não gera porcentagem em HDD e que o limiar preventivo sinaliza SSDs com 80% e 87% usados, mantendo um SSD com 79% sem outros alertas. O JSON desta prévia registra a segunda rodada.

Na consulta real, o HDD WDC WD10EZEX apareceu sem porcentagem e ficou inconclusivo por leitura SMART parcial. O SSD Kingston A400 apareceu com 87% de desgaste usado e recomendação de planejar a troca preventiva. O SSD NVMe WDC permaneceu sem alertas, com 1% usado.

## Previa 0.1.9

Duas rodadas completas no Windows PowerShell 5.1 passaram com **161 testes e zero falhas em cada rodada**. Os testes simularam os quatro estados dos discos, confirmaram a cor compartilhada entre resultado e barra e verificaram a proporção em 0%, 25% e 105%. Na bateria, verificaram a barra azul com decimal local, a saturação visual acima de 100% e a ausência de barra quando o Windows não informa a capacidade. O modo `-SemCores` preservou os textos e as barras. A preferência também foi encaminhada à janela elevada de discos em teste simulado. O JSON atual corresponde à segunda rodada desta prévia.

## Previa 0.1.8

Duas rodadas completas no Windows PowerShell 5.1 passaram com **158 testes e zero falhas em cada rodada**. Em cada rodada, quatro casos cobriram a bateria, sete cobriram a opção de discos e onze cobriram a opção de discos com acesso administrativo. Os casos incluem menu, XML com capacidades válidas e ausentes, exclusão de USB e RAID, regras de desgaste e leitura SMART parcial. O JSON distribuído com a prévia 0.1.8 corresponde à segunda rodada daquela versão.

As duas consultas novas também foram executadas duas vezes em um desktop. O relatório nativo confirmou ausência de bateria. O resumo listou três discos internos em cada rodada. O NVMe apresentou leitura completa. Nos dois SATA, o smartctl obteve atributos, mas não pôde ler os limites SMART com as permissões disponíveis. O resultado ficou inconclusivo e preservou o desgaste estimado onde disponível. O cálculo da capacidade em notebook e a interpretação específica do SSD Crucial MX500 foram verificados com dados simulados. A validação em notebook físico, a leitura SATA elevada e a homologação na edição fechada permanecem pendentes.

O ZIP portátil foi extraído em outra pasta. O iniciador abriu a versão 0.1.8 e exibiu a opção de saúde dos discos internos. O pacote inclui o smartctl, a base de discos, a licença e o código-fonte correspondente.

## Previa 0.1.7

O executavel foi testado a partir do ZIP extraido em outra pasta, com a pasta de trabalho fora do pacote. A abertura mostrou o credito no menu inicial. A opcao **[8] Sobre o Suporte TI** exibiu a versao e o mesmo credito, e Enter retornou ao menu. O nome do aplicativo e do autor foram conferidos nas propriedades do executavel, junto com o icone embutido.

Os 151 testes da suite completa correspondem a previa 0.1.6.

## Previa 0.1.6

151 testes passaram no Windows PowerShell 5.1, com pelo menos dois por opcao. Foram verificados o filtro do codigo 24, os tres campos de Dominio, as cores do Ping, o Enter sem salvamento e a configuracao de mascara e DNS com adaptador simulado. O iniciador abriu o menu atualizado. Um atalho real foi criado na pasta de testes e teve destino e icone conferidos.

O JSON corresponde a esta verificacao.

## Previa 0.1.5

147 testes passaram no Windows PowerShell 5.1, com pelo menos dois por opcao. A verificacao de perfis usou SIDs, registros e pastas ficticios. As chamadas de exclusao e reinicio foram simuladas. Cancelamento e falha interromperam o procedimento. O iniciador mostrou as letras de bloco no menu principal em uma janela larga.


## Previa 0.1.4

142 testes passaram no Windows PowerShell 5.1, com pelo menos dois por opcao. A ocupacao por volume foi verificada com valores conhecidos. Os dois modos de CHKDSK foram testados com volumes e comandos simulados. A limpeza do Chrome rodou em perfis ficticios, preservou os arquivos de sessao e ignorou a juncao para uma pasta externa ao cache.


## Ajustes 0.1.3

130 testes controlados passaram no Windows PowerShell 5.1, com pelo menos dois testes por opcao. O ping local recebeu quatro respostas sem perdas. O teste HTTPS real com a Cloudflare mediu 145,8 Mbps de download e 58,7 Mbps de upload nesta execucao. A troca de IPv4 e DNS foi verificada com adaptadores simulados. O teste do monitor verificou as leituras e a abertura pelo menu.


## Ajustes 0.1.2

129 verificacoes passaram, incluindo 13 consultas reais e pelo menos tres testes por opcao atual. Rede e desempenho retornaram resultados completos na consulta real. Os testes confirmaram o menu Rede com duas opcoes, o resumo de cinco processos e o encaminhamento ao UAC sem confirmacao textual extra. Intervencoes continuam simuladas.


## Correcao 0.1.1 — 04/11/2026

119 testes controlados passaram, incluindo politica temporaria no iniciador e na elevacao, ausencia de mudancas persistentes, navegacao e cobertura minima por opcao. O iniciador real foi aberto com entrada 0 para conferir abertura e saida. As consultas reais anteriores nao foram repetidas, pois os coletores nao mudaram. Restricoes de GPO e marcacao de arquivos baixados continuam sendo respeitadas. UAC com outra conta ainda exige homologacao interativa.

Os dados abaixo registram a verificacao anterior, que incluiu 15 consultas reais.

## Historico 0.1.0

Data: 11/04/2026 16:03:33
PowerShell: 5.1.26100.9818

Total: 132 verificacoes aprovadas.
Cobertura: pelo menos dois testes por opcao do menu.

| Opcao | Testes |
|---|---:|
| sistema | 4 |
| desempenho | 4 |
| discos | 7 |
| diskhealth | 8 |
| dispositivos | 4 |
| servicos | 4 |
| programas | 4 |
| falhas | 4 |
| rede | 4 |
| conectividade | 4 |
| proxy | 4 |
| dominio | 4 |
| update | 4 |
| cache | 4 |
| gpusuario | 4 |
| gpcomputador | 4 |
| gphtml | 4 |
| gpupdateuser | 5 |
| gpupdatecomputer | 4 |
| spooler | 4 |
| eventos | 4 |
| ultimo | 3 |
| evtx | 4 |
| sfc | 7 |
| dism | 10 |

## Consultas reais

- **sistema**: Concluido; 532 caracteres; limitacoes: 
- **desempenho**: Concluido; 1561 caracteres; limitacoes: 
- **discos**: Parcial: ver limitacoes; 2517 caracteres; limitacoes: [INDISPONIVEL] /dev/sda: Leitura SMART indisponivel ou incompleta (codigo 4). Pode requerer administrador ou outra controladora.; [INDISPONIVEL] /dev/sdb: Leitura SMART indisponivel ou incompleta (codigo 4). Pode requerer administrador ou outra controladora.
- **dispositivos**: Concluido; 290 caracteres; limitacoes: 
- **servicos**: Concluido; 50312 caracteres; limitacoes: 
- **programas**: Concluido; 48151 caracteres; limitacoes: 
- **falhas**: Concluido; 34194 caracteres; limitacoes: 
- **rede**: Concluido; 3858 caracteres; limitacoes: 
- **conectividade**: Parcial: ver limitacoes; 536 caracteres; limitacoes: [INDISPONIVEL] TCP 65534 - ate 3 segundos: Exceção ao chamar "Wait" com "1" argumento(s): "Um ou mais erros."
- **proxy**: Concluido; 477 caracteres; limitacoes: 
- **dominio**: Concluido; 1171 caracteres; limitacoes: 
- **update**: Concluido; 5285 caracteres; limitacoes: 
- **gpusuario**: Concluido; 2433 caracteres; limitacoes: 
- **gpcomputador**: Parcial: ver limitacoes; 117 caracteres; limitacoes: [INDISPONIVEL] Resultado de politica do computador: Codigo de saida: 1
- **eventos**: Concluido; 34194 caracteres; limitacoes: 

## Limites
Intervencoes foram simuladas: nenhum reparo, reset de cache ou reinicio de spooler real foi executado. Consultas reais foram executadas fora das restricoes do ambiente, com direitos da conta de teste. GPO do computador e SMART retornaram limitacoes de acesso/leitura; teste TCP usou porta local fechada intencionalmente. UAC interativo, outras contas, outras maquinas e alteracoes reais ainda exigem homologacao em laboratorio.
A politica de execucao RemoteSigned foi usada somente no processo de testes; nao foi alterada a politica persistente nem a GPO. O iniciador do programa nao usa essa substituicao.
