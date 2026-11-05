# Validacao da primeira versao

O script `Executar-Testes.ps1` verifica cada opcao do catalogo pelo menos duas vezes e falha se a cobertura minima nao for atingida. Inclui navegacao de todos os menus com entradas controladas.

## O que e testado

- Diagnosticos: retorno com dados controlados e erro/acesso negado, mais smoke real opcional.
- Spooler, GPO, SFC e DISM: cancelamento, despacho dos argumentos e falhas, com comandos administrativos simulados.
- Cache do Update: renomeacao em arvore temporaria, preservacao do conteudo, restauracao dos estados de servicos simulados e bloqueio por manutencao ativa.
- SMART: saudavel, falha global, alerta NVMe, setores pendentes ATA, ausencia de dados e falta de privilegio.
- Relatorios: salvamento repetido em arquivos diferentes e recusa de caminho relativo.
- Exportacoes: cancelamento, destino invalido, criacao simulada dos arquivos e verificacao de hashes do manifesto.
- Seguranca: recusa de comandos arbitrarios, uso indevido de force e selecoes de menu invalidas.
- Rede e recursos: IPv4/DHCP com adaptadores simulados, validacao de enderecos, destino de ping, amostras HTTP simuladas e valores do monitor de CPU/RAM.
- Armazenamento: ocupacao por volume, parametros do CHKDSK em simulacao e limpeza de cache em perfil Chrome ficticio, incluindo juncao para pasta protegida.
- Perfis locais: identificacao por SID, registro .bak e pastas numeradas. Exclusao e reinicio simulados, com verificacao de cancelamento e bloqueio de reinicio apos falha.
- Interface: cores de ping, Enter como recusa de salvamento, campos do dominio, filtro de dispositivos ausentes e configuracao simulada de mascara e DNS no adaptador escolhido.
- Portabilidade e autoria: executar `Suporte TI.exe` de uma copia do pacote extraido em outro local, conferir a abertura do menu, entrar em Sobre e voltar com Enter. Validar o credito no menu, em Sobre e nas propriedades do executavel, junto com o icone embutido.

## Limites dos resultados

As intervencoes de GPO, DISM, SFC, CHKDSK, spooler e cache de Update sao simuladas. A limpeza do Chrome roda em arquivos de teste. Consultas reais podem retornar parcialmente por falta de permissao ou dados. O teste verifica a resposta e o retorno ao menu.

Ainda requer homologacao em laboratorio: credenciais locais/AD pelo UAC, acesso ao projeto por UNC e unidade mapeada sob outra conta, Windows 10/11, servidor de impressao, WSUS/MDM e diferentes discos/controladoras. Os scripts da aplicacao ainda nao sao assinados.
