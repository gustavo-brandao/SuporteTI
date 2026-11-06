# Esboço — Caixa de ferramentas de suporte Windows

Data: 04/11/2026  
Status: referência do planejamento aprovado. A implementação e suas limitações estão descritas em README.md.

Na prévia 0.1.22, a janela elevada deixa de executar os scripts diretamente da pasta do pacote, que pode estar num pendrive ou compartilhamento gravável por contas comuns. A abertura registra uma impressão SHA256 dos módulos, da DLL e do smartctl. A janela elevada copia esses arquivos para uma pasta restrita a Administradores e SYSTEM, confere a cópia e só então executa a operação. A cópia temporária fica em `Windows\Temp` porque contas comuns não podem renomear nem substituir pastas criadas ali por outra conta; a pasta é removida ao final. Com todos os scripts assinados, a janela elevada exige AllSigned. A assinatura continua sendo a única proteção contra um pacote adulterado antes da abertura. Os binários passam a ser gerados por `Construcao\Compilar.ps1` a partir do código-fonte, e o GitHub Actions compila e executa a suíte a cada pull request.

Na prévia 0.1.21, grupos, escolhas, operações e consultas usam telas com títulos próprios. A consulta manual de código separa família, digitação e resultado. O resultado fica disponível para leitura ou salvamento antes de voltar. As opções de alteração recebem rótulos, e escolhas técnicas como DISM e CHKDSK trazem explicações curtas.

Na prévia 0.1.20, a triagem automática apresenta os códigos distintos encontrados nos registros consultados e suas explicações, inclusive quando a ocorrência principal não tem um código de falha identificado. A consulta por digitação continua no mesmo submenu.

Na prévia 0.1.19, **Computador > Falhas recentes e códigos de erro** reúne a triagem automática e a consulta manual por código. O submenu apresenta primeiro a análise dos logs. Após qualquer resultado, o técnico pode escolher outra consulta no mesmo lugar.

Na prévia 0.1.18, o catálogo público cresce até perto de 1 MB com identificadores de tela azul, NTSTATUS, Win32 e HRESULT. A triagem continua identificando a família pelo registro original. A consulta manual permite selecionar a família e buscar um código visto em outra tela ou relatório. Explicações revisadas têm prioridade e a mensagem nativa em português complementa a cobertura quando disponível.

Na prévia 0.1.17, o catálogo da triagem passa a ser um arquivo de dados versionado no pacote público. Reúne traduções curtas de códigos de parada e de exceção, pistas para investigação e referências oficiais. A lista prioriza os códigos úteis na triagem de bancada e pode crescer sem alteração no coletor.

Na prévia 0.1.16, **Computador > Falhas recentes** ganha triagem de incidentes em português. A edição pública usa os logs locais do Windows e um catálogo de códigos de parada. O resumo separa fatos registrados e pistas para investigação. A leitura do conteúdo de dumps fica para avaliação futura. A listagem bruta permanece em **Relatórios e eventos**.

Para uma etapa futura, o BlueScreenView oferece exportação de minidumps por linha de comando. A licença freeware permite redistribuição gratuita do pacote completo, sem alterações. A documentação de requisitos cita Windows 10. A leitura em Windows 11 precisa ser verificada antes de qualquer integração. Para código reutilizável, EvtxECmd (MIT) é referência para mapas de eventos e importação de EVTX de outra máquina. kdmp-parser (MIT) é candidato para leitura de dumps de kernel, com cobertura de minidumps a verificar. WinDbg serve para comparar a leitura de códigos, parâmetros e pilhas em laboratório. A prévia usa os próprios recursos do Windows. [BlueScreenView](https://www.nirsoft.net/utils/blue_screen_view.html) · [EvtxECmd](https://github.com/EricZimmerman/evtx) · [kdmp-parser](https://github.com/0vercl0k/kdmp-parser) · [WinDbg](https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/read-small-memory-dump-file)

Na prévia 0.1.15, **Computador** ganha o mapa de ocupação para volumes locais fixos e a gestão de login automático do Windows. O mapa usa retângulos proporcionais em janela própria do Suporte TI. A consulta do login é somente leitura. Configurar ou desativar exige confirmação e elevação, com senha protegida pelo segredo LSA. A edição pública mantém funções genéricas de Windows. A edição fechada segue em projeto separado, com adoção após avaliação das mudanças na edição pública.

Na prévia 0.1.14, a opção **Sobre** reúne versão, ano de 2026 e crédito de desenvolvimento. Os dados da sessão ficam nas telas de trabalho.

Na prévia 0.1.13, os grupos mostram opções em ordem numérica, com **0 ou Enter** para voltar. As escolhas de GPO exigem selecionar a ação antes de atualizar. A bateria permanece visível em Computador e informa quando o equipamento não se aplica. Os resultados se ajustam à largura do console. O diagnóstico de filas é somente leitura e aparece antes da ação de reiniciar o spooler.

Na prévia 0.1.12, o Kingston A400 usa o atributo E7 conforme o firmware identificado. A apresentação distingue resistência usada e restante. A barra e o limiar preventivo continuam baseados no percentual usado.

Na prévia 0.1.11, a recomendação de saúde de SSDs NVMe passa a usar o motivo específico do aviso do dispositivo. Um alerta térmico isolado recebe atenção. Perda de confiabilidade e mídia somente leitura justificam recomendar troca.

Na prévia 0.1.10, a porcentagem de desgaste fica restrita a SSDs com indicador disponível. O Suporte TI usa 80% de desgaste estimado como limiar de atenção preventiva. Falhas críticas de saúde mantêm prioridade na recomendação.

Na prévia 0.1.9, a saúde dos discos ganhou cores por resultado e uma barra de desgaste com a mesma cor. A seção **Notebook** ganhou uma barra azul para a capacidade atual da bateria em relação à original. As barras acompanham os percentuais exibidos em texto e ficam disponíveis no modo sem cores.

Na versão 0.1.7, a abertura portátil usa `Suporte TI.exe`, com nome e ícone próprios. O executável encontra o menu PowerShell na mesma pasta do pacote.

A edição pública credita **Gustavo Brandão Gimenez** e usa a [licença MIT](LICENSE) para seu código próprio. A futura edição privada da UCDB terá repositório privado e o crédito **Suporte DTI - UCDB**.

Na prévia 0.1.8, a primeira prioridade foi a saúde da bateria na seção **Notebook**, usando apenas o relatório nativo do Windows. A segunda foi a saúde de HDDs e SSDs internos, com leitura SMART e contadores do Windows e uma recomendação por disco. A consulta usa o smartctl portátil. A interpretação de desgaste por modelo do CrystalDiskInfo serviu de referência para validar o atributo SMART 202 dos SSDs Crucial MX500, com conferência do valor normalizado e do valor bruto. USB, RAID, carregamento e consumo em suspensão ficam fora desta etapa. As mudanças genéricas são testadas na edição pública antes da homologação institucional da edição fechada.

Na versão 0.1.6, o menu ganhou destaques por cor e barra de ocupação de disco. Domínio exibe nome da máquina, ingresso e nome do domínio. A configuração manual de IPv4 inclui máscara, gateway e um ou dois DNS. GPO e Eventos exibem os comandos. Enter no prompt de salvamento equivale a Não.

Atualização aprovada durante os testes (versão 0.1.2): Rede foi reduzida a configuração com `ipconfig /all` e domínio/horário; testes interativos de destino e proxy foram retirados. A seleção da ação substitui a confirmação textual, mantendo a elevação do Windows. Desempenho exibe resumo de CPU/RAM e cinco processos por memória. As seções abaixo preservam o planejamento original; README.md descreve a versão atual.

Na revisão da 0.1.22, a cópia elevada preserva a marca de origem e confere o hash no destino. A elevação a partir de rede exige scripts assinados. O CI executa os testes com os binários recém-compilados.

## Objetivo e tecnologia

Facilitar o atendimento técnico com diagnósticos e intervenções selecionadas, sem exigir que o técnico memorize comandos.

- Projeto próprio, escrito do zero, inspirado na proposta do [Suporte_TI](https://github.com/felipewehcode/Suporte_TI), sem reaproveitar seu código.
- Windows PowerShell 5.1, com foco em Windows 10/11.
- Operação apenas na máquina onde o programa estiver aberto.
- Pasta portátil, acessível por servidor de arquivos ou pendrive.
- Interface inteiramente na janela do PowerShell.
- Uso genérico em diferentes redes, com ou sem domínio e proxy.

## Menu principal

```text
╔══════════════════════════════════════════╗
║          SUPORTE TÉCNICO WINDOWS         ║
╚══════════════════════════════════════════╝
 Computador: LAB-PC01    Acesso: padrão

 [1] Computador
 [2] Rede
 [3] Windows Update
 [4] Políticas de grupo — GPO
 [5] Impressão
 [6] Relatórios e eventos
 [7] Reparos do Windows
 [8] Sobre o Suporte TI

 [0] Sair
```

Menus interativos, bem formatados, com navegação consistente, entradas validadas, cores acompanhadas de texto, mensagens claras e indicação de progresso. Seleções inválidas não executam ações. Prever apresentação legível quando caracteres gráficos ou cores não estiverem disponíveis.

Dentro de cada grupo, separar consultas comuns, consultas privilegiadas e intervenções, conforme necessário:

```text
  WINDOWS UPDATE

  CONSULTAS
  [1] Diagnosticar falhas

  REQUER ADMINISTRADOR
  [2] Recriar cache de download

  [0] Voltar
```

## Funcionalidades

| Grupo | Opções previstas |
|---|---|
| Computador | Informações do computador; desempenho de CPU, memória e processos; espaço e saúde dos discos; dispositivos e drivers com problemas; estado dos serviços; programas instalados; falhas recentes. |
| Rede | Configuração de adaptadores, IP, DHCP, DNS e gateway; resolução de nomes, portas e rotas; latência e perda de pacotes com tentativas limitadas; diagnóstico de sites, aplicativos e proxy; identificação de domínio ou grupo de trabalho, disponibilidade de controlador e sincronização de horário. |
| Windows Update | Diagnóstico de falhas, KB e códigos de erro, tentativas recentes, serviços, espaço, reinicialização pendente, políticas, origem das atualizações e conectividade; recriação do cache de download como intervenção separada. |
| GPO | Consultar políticas aplicadas ao usuário e computador com gpresult; exportar HTML; atualizar políticas com gpupdate, oferecendo /force separadamente com aviso. |
| Impressão | Reiniciar somente o spooler local, com elevação e confirmação, sem excluir trabalhos de impressão. |
| Relatórios e eventos | Consultar e exportar eventos; reunir resultados do atendimento; preservar registros originais. |
| Reparos do Windows | Verificação e reparo separados com SFC e DISM, incluindo sfc /scannow e DISM /Online /Cleanup-Image /RestoreHealth. |

### Saúde dos discos

- Seleção simples: Computador → Discos → Verificar saúde.
- Consulta rápida dos indicadores disponíveis, sem varredura completa, reparo ou teste extenso.
- Resultado dentro do PowerShell: **sem alertas detectados**, **atenção**, **crítico/degradado** ou **inconclusivo**.
- Exibir motivos, dados disponíveis e recomendação compatível com as evidências.
- Não considerar ausência de dados como disco saudável nem inventar porcentagem de saúde.
- Não usar um limite único de temperatura para todos os modelos.
- Inclusão do smartctl aprovada condicionalmente: integração simples, consulta rápida e validação de licença, integridade, segurança e compatibilidade antes da distribuição.
- Componente incluído na pasta do projeto, sem exigir instalação, serviço permanente ou janela externa.
- Se indisponível ou incompatível, apresentar dados nativos e suas limitações.
- Rapidez esperada deverá ser confirmada em protótipo e dispositivos representativos; não garantir prazo universal.

### Rede e proxy

- Diagnóstico genérico, sem depender especificamente do Squid.
- Consultar proxy do usuário, WinHTTP e configuração automática PAC/WPAD.
- Não alterar configurações de proxy.
- Distinguir falhas de DNS, conexão, autenticação e HTTPS.
- Aplicativos podem ter configurações próprias; o teste da ferramenta não comprova o funcionamento de todos eles.
- Ausência de proxy explícito não comprova ausência de proxy transparente.
- Confirmar acesso aos destinos testados, sem declarar falta de internet apenas por falha de ping ou de um site.
- Relatórios podem reunir horário com fuso, origem, destino, proxy e erro para análise na infraestrutura, sem senhas, cookies ou tokens.

### Windows Update e reparos

- Preservar diagnósticos antes de recriar o cache.
- Recriar o cache de download não significa desinstalar atualizações ou retornar à atualização anterior.
- Reset completo de componentes fora da versão inicial.
- SFC e DISM ficam separados do diagnóstico rápido e podem demorar.
- A fonte de reparo do DISM deverá respeitar a configuração institucional.
- Não reiniciar a máquina nem encerrar a sessão automaticamente.

## Permissões e confirmações

- Menu inicia sem solicitar administrador.
- Consultas executadas com os direitos atuais do usuário.
- Opções privilegiadas claramente identificadas.
- Intervenções: apresentar ação e impacto → confirmar → solicitar elevação quando necessária → executar → apresentar resultado.
- Usar a janela oficial do Windows (UAC), sem tela própria de coleta de senha.
- Aceitar credenciais locais ou do domínio que tenham direitos administrativos na estação, conforme política do Windows/GPO.
- Exigir senha sempre, inclusive de administradores, depende da política institucional; não será garantido pela aplicação.
- Preservar o contexto do usuário original para consultas da sessão e sugestão de destino dos relatórios.
- Não contornar bloqueios institucionais de execução.

## Resultados e armazenamento

- Após cada consulta, perguntar se o técnico deseja salvar o resultado.
- Sugerir a pasta Documentos do usuário da sessão original, mesmo quando outra conta executar a operação elevada.
- Exibir o destino e permitir escolher outra pasta, inclusive pendrive ou compartilhamento.
- Verificar permissão de escrita; se falhar, informar e permitir outro destino.
- Nunca sobrescrever resultados anteriores.
- Organizar por computador e atendimento, com data, horário e identificador único:

```text
Documentos\SuporteTI\Resultados\
  NOME-DO-PC\
    DATA_HORA_ID\
```

Consultas sem opção de salvamento não criam arquivos de resultados pela ferramenta. Comandos do Windows podem produzir seus próprios registros operacionais.

**Sem auditoria própria obrigatória na versão inicial.** Não criar pasta em ProgramData nem modificar permissões para essa finalidade. Preservar os logs nativos do Windows.

## Tratamento de falhas e duração

- Consultas rápidas com tempo limitado e resultados parciais identificados quando necessário.
- Diferenciar sucesso, falha, cancelamento, acesso negado e informação indisponível.
- Não anunciar sucesso apenas porque um processo terminou.
- Reparos demorados devem ter aviso e acompanhamento, sem encerramento forçado por prazo genérico.
- Cancelamento e negativa de elevação não devem iniciar a intervenção.

## Fora do escopo inicial

- Apagar logs de eventos do Windows.
- Auditoria própria obrigatória de intervenções.
- Consultar estado genérico de antivírus.
- Diagnosticar compartilhamentos de rede.
- Alterar proxy.
- Executar comandos em outras máquinas ou em lote.
- Abrir shell arbitrário como recurso do programa.
- Otimizador de memória com encerramento de programas ou ações em sequência.
- Esvaziar lixeira, limpeza ampla de temporários e download livre de arquivos.
- Reset completo do Windows Update.
- CHKDSK completo ou reparos de disco dentro da consulta rápida de saúde.

## Próximas validações antes da implementação

1. Homologar edições e versões do Windows, considerando o ciclo de suporte e as políticas institucionais.
2. Validar em protótipo rapidez, cobertura e distribuição do smartctl.
3. Definir regras de classificação de saúde com evidências rastreáveis e estado inconclusivo.
4. Validar execução por compartilhamento e pendrive, incluindo proteção dos componentes usados com elevação.
5. Detalhar parâmetros e critérios de resultado de cada operação.
6. Testar usuário comum, elevação com outra conta, cancelamento, falhas, limites de duração e salvamento sem sobrescrita.
7. Implementar por fases, começando pelo menu e consultas somente leitura, após validação do planejamento.

## Referências técnicas consultadas

- [Windows PowerShell 5.1](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_windows_powershell_5.1)
- [UAC e elevação](https://learn.microsoft.com/windows/security/identity-protection/user-account-control/how-user-account-control-works)
- [Contadores de confiabilidade de armazenamento](https://learn.microsoft.com/en-us/powershell/module/storage/get-storagereliabilitycounter)
- [Saúde NVMe pelas APIs do Windows](https://learn.microsoft.com/en-us/windows/win32/fileio/working-with-nvme-devices)
- [Repositório oficial smartmontools](https://github.com/smartmontools/smartmontools)
- [Recuperação de componentes do Windows Update](https://learn.microsoft.com/en-us/troubleshoot/windows-client/installing-updates-features-roles/additional-resources-for-windows-update)
- [gpresult](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/gpresult)
- [gpupdate](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/gpupdate)
- [Reparo da imagem do Windows](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/repair-a-windows-image?view=windows-11)
