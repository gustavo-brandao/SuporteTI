# Ferramenta de Suporte Windows

Caixa de ferramentas local e portatil para Windows 10/11, escrita em Windows PowerShell 5.1. Menu textual, diagnosticos com limites de duracao e intervencoes selecionadas pelo tecnico.

## Abrir

1. Extraia todo o ZIP em uma pasta no pendrive ou no computador.
2. Abra **Suporte TI.exe**, identificado pelo nome e pelo icone de terminal. A ferramenta abre com as permissoes da sessao atual.
3. Escolha o grupo e a opcao pelo numero e pressione Enter. **0** sempre volta ou sai.

Para levar a ferramenta para outra unidade, copie a pasta inteira. O executavel encontra os modulos na pasta do pacote, independentemente da letra do pendrive. O pacote tambem inclui **Iniciar.cmd** para abertura direta pelo iniciador de linha de comando.

Tambem e possivel iniciar em um Windows PowerShell permitido pela instituicao:

```powershell
.\Iniciar.ps1
# Opcional: cores do terminal, sem destaque colorido
.\Iniciar.ps1 -SemCores
```

A distribuicao de desenvolvimento ainda nao esta assinada. O iniciador e a janela elevada usam **RemoteSigned somente no processo que abrem**, sem alterar a politica persistente do usuario ou computador. Nao usam Bypass nem desbloqueiam arquivos automaticamente. Restricoes de GPO continuam prevalecendo. Se a instituicao bloquear scripts, sera necessario homologar e assinar a distribuicao e autorizar sua execucao pelos mecanismos institucionais.

Se o Windows informar que um script nao esta assinado por ter vindo da internet, confira a procedencia do ZIP; nas propriedades do ZIP confiavel, use Desbloquear antes de extrair novamente. Isso remove a marcacao de origem do arquivo, nao uma restricao por GPO. Nao desbloqueie arquivos de procedencia desconhecida. Em redes que exigem AllSigned ou bloqueiam scripts, solicite a autorizacao institucional.

O smartctl incluido e x64. Em Windows de 32 bits ou controladoras nao compativeis, a consulta detalhada pode ficar indisponivel; os dados nativos continuam sendo apresentados quando acessiveis.

## Menu

| Grupo | Opcoes |
|---|---|
| Computador | Informacoes do Windows com CPU e RAM; resumo de cinco processos por memoria; monitor de CPU/RAM com barras ao vivo; ocupacao e saude dos discos; leitura de disco com elevacao; dispositivos com problema; servicos; programas instalados; falhas recentes; limpeza do cache HTTP do Chrome. |
| Rede | ipconfig /all; nome da maquina, ingresso e dominio; ping com resultado em destaque; estimativa de download e upload; troca de IPv4 para DHCP ou configuracao manual com mascara, gateway e um ou dois DNS. |
| Windows Update | Diagnostico de servicos, politicas, espaco, reinicio pendente e eventos; recriar somente o cache de download. |
| GPO | gpresult do usuario; gpresult do computador com elevacao; HTML por escopo usuario/computador; gpupdate separado por usuario/computador, com /force opcional. |
| Impressao | Reiniciar spooler local, sem remover trabalhos. |
| Relatorios e eventos | Eventos recentes de Application/System; rever e salvar ultimo resultado da sessao; exportar Application/System/Setup das ultimas 24h em EVTX com manifesto SHA256. |
| Reparos | SFC /verifyonly ou /scannow; DISM CheckHealth, ScanHealth ou RestoreHealth; CHKDSK de consulta e completo com /f /r. |

O menu principal usa letras de bloco em janelas com pelo menos 72 colunas. Em janelas estreitas ou com `-SemCores`, usa um titulo compacto.

**Desenvolvido por Gustavo Brandão Gimenez.** O credito aparece no menu inicial, na opcao **[8] Sobre o Suporte TI** e nas propriedades do executavel, em **Detalhes**.

As secoes administrativas e as acoes de alteracao aparecem em amarelo. Ping usa texto e cor para indicar resposta, perda parcial ou falta de resposta. Discos mostram uma barra de ocupacao por volume. GPO e Eventos exibem os comandos usados.

Em **Reparos**, a opcao **Verificar e remover perfil local duplicado** exibe a conta, o SID e os caminhos encontrados. A exclusao exige confirmacao apos o aviso de perda de arquivos e configuracoes locais. Antes de aceitar, confira o backup ou a pasta compartilhada. Perfis carregados e pastas de associacao duvidosa ficam bloqueados. O reinicio tem uma pergunta separada apos a verificacao da exclusao.

O pacote atual e a edicao publica e generica. Recursos exclusivos de redes da UCDB pertencem a uma futura edicao fechada.

Consultas de eventos cobrem as ultimas 24h, no maximo 30 eventos por canal. O relatorio de Update inclui as mensagens retornadas pelo Windows, que podem conter KB e codigos de erro. O monitor atualiza barras no console a cada leitura e volta com Q, Esc ou Enter. O resumo do Windows oferece uma amostra para salvar no relatorio.

## Seguranca e comportamento

- Atua somente na maquina aberta. Nao executa comandos livres ou em destinos remotos.
- A selecao da opcao autoriza a acao. Nao e necessario digitar palavras de confirmacao nem confirmar novamente na janela elevada. O impacto e apresentado, e o Windows solicita elevacao quando necessaria; a conta deve ter direitos nessa estacao.
- Usuario/GPO do usuario nao sao consultados sob outra conta. Consultas do computador e reparos usam um processo separado.
- GPO pode exigir credenciais, apenas consentimento, ou impedir elevacao. A ferramenta nao recebe nem armazena senhas.
- Nao limpa logs, nao esvazia lixeira, nao encerra programas para liberar RAM, nao altera proxy, antivirus ou permissoes.
- Nao instala servicos, nao cria auditoria propria nem pasta em ProgramData. Comandos do Windows produzem seus logs nativos normalmente.
- Cache do Update: bloqueia se detectar manutencao ativa ou reinicializacao pendente; para BITS/wuauserv quando necessario; renomeia apenas Download; restaura os estados de execucao anteriores. O cache anterior permanece no disco, sem exclusao automatica. Nao faz reset de DataStore/catroot2, nao desinstala atualizacoes e nao inicia download automaticamente.
- Consultas comuns: limite de 25s; discos: 40s no total, ate quatro dispositivos SMART. A consulta nativa pode fornecer resultados parciais. SFC, DISM, CHKDSK e gpupdate rodam ate o encerramento do comando nativo.
- O uso de disco mostra total, usado, livre e percentual de ocupacao por volume local. O CHKDSK permite escolher um volume local com letra. No modo completo, o proprio Windows pode oferecer agendamento para o proximo reinicio. O tecnico reinicia manualmente se tiver aceitado o agendamento.
- A limpeza do Chrome exige o navegador fechado e a sessao comum do usuario. O escopo e a pasta Cache dos perfis Default e Profile N na localizacao padrao do Chrome. Historico, cookies e senhas permanecem nos perfis. Pastas redirecionadas e arquivos inacessiveis sao ignorados.
- SMART: leitura pontual, sem testes de superficie ou autotestes. Discos ATA em standby nao sao despertados deliberadamente; podem aparecer como inconclusivos. Alertas devem ser avaliados com contexto e backup.
- Ping: quatro tentativas ICMP para o host ou IP informado. O teste de velocidade mede amostras HTTPS de 8 MiB de download e 4 MiB de upload para a Cloudflare. O resultado depende da rota e do servidor testado. A consulta de proxy WinHTTP fica no diagnostico do Windows Update.
- A troca para DHCP restaura IPv4 e DNS IPv4 automaticos no adaptador escolhido. A selecao mostra o nome, o estado e o endereco atual de cada adaptador. O modo fixo solicita IPv4, mascara ou prefixo, gateway opcional, DNS primario e DNS secundario opcional. Essas operacoes podem interromper a conexao, inclusive durante suporte remoto. O menu mostra o estado antes e apos a alteracao.
- Dispositivos com codigo 24 ficam ocultos quando o Windows confirma que estao ausentes. Os demais dispositivos com problema aparecem no diagnostico.
- A consulta Dominio exibe somente `Name`, `PartOfDomain` e `Domain`. O ingresso registrado e o nome do dominio podem ser verificados mesmo com o controlador indisponivel.

Os arquivos portateis devem vir de fonte confiavel. A confirmacao UAC nao autentica o conteudo de um script; o projeto ainda precisa de assinatura e homologacao institucional para distribuicao em producao. O manifesto SHA256 do smartctl detecta divergencias em relacao ao pacote, mas nao e fronteira de seguranca contra quem pode alterar todo o projeto.

## Resultados

Resultados de consultas ficam em memoria ate serem substituidos ou ate fechar o programa. No prompt de salvamento, Enter equivale a N. O destino sugerido e:

```text
Documentos\SuporteTI\Resultados\COMPUTADOR\DATA_HORA_IDENTIFICADOR\
```

E possivel selecionar outro caminho absoluto, inclusive pendrive ou compartilhamento. Cada salvamento cria uma pasta unica e nao sobrescreve resultados anteriores. Acesso negado permite escolher outro destino no salvamento textual. Exportacoes informam erros e podem deixar arquivos parciais identificaveis no destino.

No processo elevado, o destino sugerido e recebido da sessao original, evitando sugerir Documentos da conta administrativa. O Windows ainda pode negar acesso ao destino; escolha uma pasta autorizada. Nao ha alteracao automatica de ACLs. Relatorios podem conter informacoes internas: escolha o destino e as permissoes adequados.

Os reparos exibem a saida nativa ao vivo. O resultado textual opcional registra o resumo da operacao, sem transcrever automaticamente todo o console; detalhes permanecem nos logs nativos CBS/DISM. A interface principal nao recupera o resultado em memoria do processo elevado.

## Estrutura

```text
Suporte TI.exe                Iniciador portatil com icone embutido
Iniciar.cmd / Iniciar.ps1      Entrada do menu PowerShell
Modulos\SuporteTI.psm1         Menu, consultas limitadas e salvamento
Modulos\Consultas.ps1          Coletores de leitura
Modulos\Operacoes.ps1          Acoes restritas e exportacoes
Modulos\Elevado.ps1            Entrada UAC para acoes permitidas
Modulos\Discos.ps1             SMART/NVMe e classificacao
Ferramentas\smartmontools\     smartctl 7.5, base, licenca e fonte
Testes\Executar-Testes.ps1     Testes e cobertura por opcao
```

## Testes

Os testes simulam as intervencoes e nao reiniciam servicos nem executam reparos reais. Criam apenas arquivos de teste sob work e o relatorio em Testes. Em um Windows PowerShell com execucao autorizada:

```powershell
.\Testes\Executar-Testes.ps1
.\Testes\Executar-Testes.ps1 -IncluirConsultasReais
```

O segundo comando acrescenta consultas reais somente leitura. Acesso negado e falta de dominio/hardware sao resultados possiveis; um smoke test aprovado verifica o contrato de retorno e nao significa que todos os dados estavam disponiveis. Consulte **Testes/resultado-testes.json** e **Testes/VALIDACAO.md**.

Homologacao real de UAC com outra conta, Active Directory/GPO, dispositivos variados, impressao e reparos deve ocorrer em maquinas de teste. Testes simulados nao substituem essa etapa.

## Origem, licença e terceiros

Inspirado na proposta de [felipewehcode/Suporte_TI](https://github.com/felipewehcode/Suporte_TI), com implementacao independente.

O código próprio da edição pública é licenciado sob a [licença MIT](LICENSE). Copyright © 2026 Gustavo Brandão Gimenez.

O componente [smartmontools 7.5](https://github.com/smartmontools/smartmontools/releases/tag/RELEASE_7_5) e distribuido separadamente sob sua licenca GPL-2.0-ou-posterior. O pacote contem a licenca, avisos, documentacao e arquivo-fonte original correspondente. Consulte **TERCEIROS.md**. Nao redistribua somente o executavel sem os arquivos de licenca e fonte do pacote.
