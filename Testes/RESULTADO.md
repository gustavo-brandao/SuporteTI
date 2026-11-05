# Resultado da verificacao

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
