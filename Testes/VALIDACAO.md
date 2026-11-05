# Validacao da primeira versao

O script `Executar-Testes.ps1` verifica cada opcao do catalogo pelo menos duas vezes e falha se a cobertura minima nao for atingida. Inclui navegacao de todos os menus com entradas controladas.

## O que e testado

- Diagnosticos: retorno com dados controlados e erro/acesso negado, mais smoke real opcional.
- Falhas recentes: eventos simulados verificam agrupamento de reinicio e tela azul, interpretacao do codigo decimal de Kernel-Power, reinicio sem causa identificada, separacao entre falha de aplicativo e tela azul, traducao de excecao de aplicativo, codigo desconhecido e exclusao de pistas posteriores a inicializacao.
- Catalogo de falhas: valida formato, tamanho, nomes e referencias nas quatro familias, preservacao das explicacoes revisadas e exibicao da ocorrencia quando o catalogo fica indisponivel. A consulta manual cobre codigo Win32 decimal, HRESULT decimal com sinal e codigo de parada hexadecimal.
- Navegacao de falhas: o mesmo submenu despacha a analise automatica e a consulta manual. Zero e Enter voltam sem consultar, inclusive na escolha de familia e na entrada do codigo.
- Layout: verifica a sequencia de telas na consulta por codigo, opcoes e rotulos em 24 colunas, ausencia de cores forcadas com `-SemCores` e tons para fundos claro e escuro.
- Busca automatica: verifica que um evento de ID 0 sem codigo de falha nao oculta registros com codigo, que um numero no texto da mensagem nao e tratado como codigo e que codigos repetidos aparecem uma vez no resumo.
- Spooler, GPO, SFC e DISM: cancelamento, despacho dos argumentos e falhas, com comandos administrativos simulados.
- Cache do Update: renomeacao em arvore temporaria, preservacao do conteudo, restauracao dos estados de servicos simulados e bloqueio por manutencao ativa.
- SMART: saudavel, falha global, alerta NVMe, setores pendentes ATA, ausencia de dados e falta de privilegio.
- Relatorios: salvamento repetido em arquivos diferentes e recusa de caminho relativo.
- Exportacoes: cancelamento, destino invalido, criacao simulada dos arquivos e verificacao de hashes do manifesto.
- Seguranca: recusa de comandos arbitrarios, uso indevido de force e selecoes de menu invalidas.
- Rede e recursos: IPv4/DHCP com adaptadores simulados, validacao de enderecos, destino de ping, amostras HTTP simuladas e valores do monitor de CPU/RAM.
- Armazenamento: ocupacao por volume, parametros do CHKDSK em simulacao e limpeza de cache em perfil Chrome ficticio, incluindo juncao para pasta protegida.
- Mapa de ocupacao: arvore de teste com tamanhos conhecidos, juncao ignorada, limite de entradas e resultado parcial. A verificacao grafica cobre retangulos de cores diferentes, divisao em subpastas e navegacao.
- Login automatico: consulta sem leitura de senha legada, ordem de gravacao simulada, recuperacao apos falha, desativacao e uso do console ja elevado. A consulta real e somente leitura. Em VM com conta descartavel, valide o UAC em sessao padrao, o login apos reiniciar e o retorno ao login manual depois de desativar.
- Saude de discos internos: uma recomendacao por disco, alerta preservado em leitura SMART parcial, resultado inconclusivo quando faltam dados, desgaste NVMe acima de 100%, interpretacao do Crucial MX500 e exclusao de USB e RAID.
- Desgaste preventivo: HDD com `Wear=0` no Windows fica sem porcentagem. SSDs com 80% e 87% usados sinalizam atencao, enquanto um SSD com 79% sem outros alertas permanece azul.
- NVMe: alerta termico, reserva baixa, erros de midia e aviso sem causa detalhada recebem atencao. Perda de confiabilidade e modo somente leitura recebem recomendacao de troca, inclusive quando coexistem com um alerta termico.
- Kingston A400: o E7 bruto do firmware SBFK61F1 mostra 87% restantes e 13% usados, sem alerta preventivo. O firmware 03070009 usa o E7 normalizado. Firmware sem regra ou valor fora da faixa nao gera porcentagem.
- Apresentacao de discos: cores dos quatro resultados, barra com a mesma cor do status, desgaste zero e acima de 100%, resultado sem porcentagem e modo `-SemCores` com encaminhamento para a janela elevada.
- Notebook: navegacao pelo menu, opcao visivel e aviso em desktop com nobreak USB, relatorio XML com duas baterias, capacidade ausente e relatorio sem bateria. A barra e verificada com decimal local, percentual acima de 100%, capacidade ausente e modo `-SemCores`. Para validar em notebook real, compare as capacidades exibidas pelo menu com as capacidades do relatorio do Windows para o mesmo equipamento.
- Navegacao e largura: 0 e Enter retornam de escolhas sem executar a acao. O resultado dos discos preserva modelo, porcentagem e barra em 36 colunas simuladas.
- Impressao: nome da fila com erro, impressora offline, trabalho em processamento sem alerta, fila sem acesso e spooler parado. Nenhum trabalho de impressao e enviado ou removido pelos testes.
- Perfis locais: identificacao por SID, registro .bak e pastas numeradas. Exclusao e reinicio simulados, com verificacao de cancelamento e bloqueio de reinicio apos falha.
- Interface: cores de ping, Enter como recusa de salvamento, campos do dominio, filtro de dispositivos ausentes e configuracao simulada de mascara e DNS no adaptador escolhido.
- Portabilidade e autoria: executar `Suporte TI.exe` de uma copia do pacote extraido em outro local, conferir a abertura do menu, entrar em Sobre e voltar com Enter. Validar o credito no menu, em Sobre e nas propriedades do executavel, junto com o icone embutido.

## Limites dos resultados

As intervencoes de GPO, DISM, SFC, CHKDSK, spooler e cache de Update sao simuladas. A limpeza do Chrome roda em arquivos de teste. Consultas reais podem retornar parcialmente por falta de permissao ou dados. O teste verifica a resposta e o retorno ao menu.

Ainda requer homologacao em laboratorio: credenciais locais/AD pelo UAC, acesso ao projeto por UNC e unidade mapeada sob outra conta, Windows 10/11, servidor de impressao, WSUS/MDM e diferentes discos/controladoras. Os scripts da aplicacao ainda nao sao assinados.
