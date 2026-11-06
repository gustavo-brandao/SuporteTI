Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'Operacoes.ps1')
. (Join-Path $PSScriptRoot 'Discos.ps1')
. (Join-Path $PSScriptRoot 'Recursos.ps1')
. (Join-Path $PSScriptRoot 'Rede.ps1')
. (Join-Path $PSScriptRoot 'Manutencao.ps1')
. (Join-Path $PSScriptRoot 'Perfis.ps1')
. (Join-Path $PSScriptRoot 'Logon.ps1')

# Impressao dos arquivos na abertura. A janela elevada recusa executar se o pacote mudar depois disso.
$script:SuporteDigestPacote = $null
try { $script:SuporteDigestPacote = Get-SuporteDigestPacote (Split-Path $PSScriptRoot -Parent) } catch {}

function Get-SuporteCatalogo {
    $catalogo = @(
        @{ Id='sistema'; Grupo='Computador'; Nome='Informacoes do computador' }
        @{ Id='desempenho'; Grupo='Computador'; Nome='CPU, memoria e processos' }
        @{ Id='monitor'; Grupo='Computador'; Nome='Monitor de CPU e RAM ao vivo'; Especial=$true }
        @{ Id='discos'; Grupo='Computador'; Nome='Uso e saude dos discos internos' }
        @{ Id='diskhealth'; Grupo='Computador'; Nome='Saude dos discos com acesso administrativo'; Admin=$true; Especial=$true }
        @{ Id='dispositivos'; Grupo='Computador'; Nome='Dispositivos e drivers com problemas' }
        @{ Id='servicos'; Grupo='Computador'; Nome='Estado dos servicos' }
        @{ Id='programas'; Grupo='Computador'; Nome='Programas instalados' }
        @{ Id='falhas'; Grupo='Computador'; Nome='Falhas recentes e codigos de erro' }
        @{ Id='codigofalha'; Grupo='Computador'; Nome='Consultar codigo de erro do Windows'; Pai='falhas' }
        @{ Id='chromecache'; Grupo='Computador'; Nome='Limpar cache de paginas do Google Chrome'; Especial=$true }
        @{ Id='mapaocupacao'; Grupo='Computador'; Nome='Mapa de ocupacao do disco'; Especial=$true }
        @{ Id='autologon'; Grupo='Computador'; Nome='Login automatico (Autologon)'; Especial=$true }
        @{ Id='bateria'; Grupo='Computador'; Nome='Saude da bateria' }
        @{ Id='rede'; Grupo='Rede'; Nome='Configuracao de rede (ipconfig /all)' }
        @{ Id='dominio'; Grupo='Rede'; Nome='Dominio' }
        @{ Id='ping'; Grupo='Rede'; Nome='Ping em site ou endereco IP' }
        @{ Id='velocidade'; Grupo='Rede'; Nome='Medir download e upload (Cloudflare, 12 MiB)' }
        @{ Id='netdhcp'; Grupo='Rede'; Nome='Trocar IPv4 fixo por DHCP'; Especial=$true; Admin=$true }
        @{ Id='netstatic'; Grupo='Rede'; Nome='Configurar IPv4 fixo'; Especial=$true; Admin=$true }
        @{ Id='update'; Grupo='Windows Update'; Nome='Diagnosticar Windows Update' }
        @{ Id='cache'; Grupo='Windows Update'; Nome='Recriar cache de download'; Especial=$true; Admin=$true }
        @{ Id='gpusuario'; Grupo='GPO'; Nome='Politicas do usuario (gpresult)' }
        @{ Id='gpcomputador'; Grupo='GPO'; Nome='Politicas do computador (gpresult)'; Admin=$true; Especial=$true }
        @{ Id='gphtml'; Grupo='GPO'; Nome='Exportar gpresult em HTML (escolher escopo)'; Especial=$true }
        @{ Id='gpupdateuser'; Grupo='GPO'; Nome='Atualizar politicas do usuario'; Especial=$true }
        @{ Id='gpupdatecomputer'; Grupo='GPO'; Nome='Atualizar politicas do computador'; Especial=$true; Admin=$true }
        @{ Id='filaimpressao'; Grupo='Impressao'; Nome='Diagnosticar filas de impressao' }
        @{ Id='spooler'; Grupo='Impressao'; Nome='Reiniciar spooler local'; Especial=$true; Admin=$true }
        @{ Id='eventos'; Grupo='Relatorios e eventos'; Nome='Eventos recentes de System e Application' }
        @{ Id='ultimo'; Grupo='Relatorios e eventos'; Nome='Rever e salvar ultimo resultado'; Especial=$true }
        @{ Id='evtx'; Grupo='Relatorios e eventos'; Nome='Exportar Application, System e Setup (24h)'; Especial=$true }
        @{ Id='sfc'; Grupo='Reparos do Windows'; Nome='SFC: verificar ou reparar'; Especial=$true; Admin=$true }
        @{ Id='dism'; Grupo='Reparos do Windows'; Nome='DISM: verificar ou RestoreHealth'; Especial=$true; Admin=$true }
        @{ Id='chkdsk'; Grupo='Reparos do Windows'; Nome='CHKDSK: consultar ou verificar por completo'; Especial=$true; Admin=$true }
        @{ Id='perfillocal'; Grupo='Reparos do Windows'; Nome='Verificar e remover perfil local duplicado'; Especial=$true; Admin=$true }
    ) | ForEach-Object {
        [pscustomobject]@{ Id=$_['Id']; Grupo=$_['Grupo']; Nome=$_['Nome']; Pai=$_['Pai']; Admin=($_['Admin'] -eq $true); Pendente=$false; Especial=($_['Especial'] -eq $true) }
    }
    $catalogo | Where-Object { -not $_.Admin -and $_.Id -ne 'bateria' }
    $catalogo | Where-Object Admin
    $catalogo | Where-Object Id -eq 'bateria'
}

function Get-SuporteDiscoClassificacao {
    [CmdletBinding()]
    param([AllowNull()][string]$HealthStatus, [AllowNull()][object]$Wear,
        [AllowNull()][object]$ReadErrorsUncorrected, [AllowNull()][object]$WriteErrorsUncorrected)
    $motivos = New-Object 'System.Collections.Generic.List[string]'
    $estado = 'Inconclusivo'
    if ($HealthStatus -eq 'Healthy') { $estado = 'Sem alertas detectados'; $motivos.Add('Estado nativo informado como Healthy; cobertura limitada.') }
    if ($HealthStatus -eq 'Warning') { $estado = 'Atencao'; $motivos.Add('O Windows informa estado de advertencia.') }
    if ($null -ne $Wear -and [double]$Wear -ge 100) { $estado = 'Atencao'; $motivos.Add('Desgaste informado atingiu ou ultrapassou o limite estimado.') }
    if (($null -ne $ReadErrorsUncorrected -and [double]$ReadErrorsUncorrected -gt 0) -or
        ($null -ne $WriteErrorsUncorrected -and [double]$WriteErrorsUncorrected -gt 0)) {
        $estado = 'Atencao'; $motivos.Add('Ha erros nao corrigidos acumulados; correlacionar com eventos e evolucao.')
    }
    if ($HealthStatus -eq 'Unhealthy') { $estado = 'Critico/degradado'; $motivos.Add('O Windows informa estado Unhealthy. Priorizar protecao dos dados.') }
    if ($motivos.Count -eq 0) { $motivos.Add('Indicadores insuficientes para classificar a saude.') }
    [pscustomobject]@{ Estado=$estado; Motivos=($motivos -join ' '); Limite='Nao e teste de superficie nem garantia de ausencia de defeitos.' }
}

function Invoke-SuporteConsulta {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id, [hashtable]$Opcoes=@{},
        [ValidateRange(1,120)][int]$TimeoutSeconds=25)
    $item = Get-SuporteCatalogo | Where-Object Id -eq $Id | Select-Object -First 1
    if ($null -eq $item -or ($item.Especial -and $Id -notin @('gpcomputador','autologon'))) { throw 'Consulta indisponivel neste fluxo.' }
    $modulePath = Join-Path $PSScriptRoot 'SuporteTI.psd1'
    $collectorPath = Join-Path $PSScriptRoot 'Consultas.ps1'
    $Opcoes = $Opcoes.Clone()
    $Opcoes.Largura = Get-SuporteLargura
    $inicio = Get-Date
    $job = $null
    $status = 'Concluido'
    $lines = @(); $queryErrors=@()
    $incluirCodigos = $Id -eq 'falhas' -and $Opcoes['IncluirCodigos'] -eq $true
    $codigos = @()
    try {
        $job = Start-Job -ScriptBlock {
            param($manifest, $collector, $queryId, $options)
            $ErrorActionPreference = 'Stop'
            Import-Module $manifest
            & $collector -Id $queryId -Opcoes $options
        } -ArgumentList $modulePath,$collectorPath,$Id,$Opcoes
        $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
        if ($null -eq $completed) { $status = 'Parcial: limite de tempo atingido'; Stop-Job -Job $job }
        elseif ($job.State -eq 'Failed') { $status = 'Falha' }
        $dados = @(Receive-Job -Job $job -ErrorAction SilentlyContinue -ErrorVariable queryErrors)
        if ($incluirCodigos) {
            $codigos = @($dados | Where-Object { $_ -isnot [string] })
            $dados = @($dados | Where-Object { $_ -is [string] })
        }
        $lines = @($dados | ForEach-Object { [string]$_ })
        if ($queryErrors) { $status='Parcial ou falha'; $lines += @($queryErrors | ForEach-Object { 'ERRO: ' + $_.ToString() }) }
        if (@($lines | Where-Object { $_ -match '(?m)^\[(INDISPONIVEL|ACESSO NEGADO)\]' }).Count -gt 0 -and $status -eq 'Concluido') { $status='Parcial: ver limitacoes' }
    } catch {
        $status='Falha'; $lines += 'ERRO: ' + $_.Exception.Message
    } finally {
        if ($null -ne $job) {
            if ($job.State -in @('Running','NotStarted')) { Stop-Job -Job $job }
            Remove-Job -Job $job -Force
        }
    }
    if ($lines.Count -eq 0) { $lines=@('Nenhum dado foi retornado. Nao interpretar como ausencia de problemas.') }
    $resultado = [pscustomobject]@{
        Id=[guid]::NewGuid().ToString('N'); Consulta=$item.Nome; Computador=$env:COMPUTERNAME
        Inicio=$inicio.ToString('o'); Fim=(Get-Date).ToString('o'); Status=$status
        Texto=($lines -join [Environment]::NewLine)
    }
    if ($incluirCodigos) { $resultado | Add-Member -NotePropertyName Codigos -NotePropertyValue $codigos }
    $resultado
}

function Save-SuporteResultado {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Resultado, [Parameter(Mandatory)][string]$PastaBase)
    $computer = [regex]::Replace([string]$Resultado.Computador, '[^a-zA-Z0-9_.-]', '_')
    if ([string]::IsNullOrWhiteSpace($computer)) { $computer='Computador' }
    if (-not [IO.Path]::IsPathRooted($PastaBase)) { throw 'Informe um caminho absoluto.' }
    $root = [IO.Path]::GetFullPath($PastaBase)
    $folder = Join-Path (Join-Path $root $computer) ((Get-Date -Format 'yyyy-MM-dd_HHmmss') + '_' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($folder)
    $path = Join-Path $folder 'resultado.txt'
    $text = "SUPORTE TI - v$($ExecutionContext.SessionState.Module.Version)`r`n" + 'Computador: ' + $Resultado.Computador + "`r`n" +
        'Consulta: ' + $Resultado.Consulta + "`r`n" + 'Inicio: ' + $Resultado.Inicio + "`r`n" +
        'Fim: ' + $Resultado.Fim + "`r`n" + 'Resultado: ' + $Resultado.Status + "`r`n`r`n" + $Resultado.Texto
    $stream = $null; $writer = $null
    try {
        $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $writer = New-Object IO.StreamWriter($stream, (New-Object Text.UTF8Encoding($true)))
        $writer.Write($text)
    } finally {
        if ($null -ne $writer) { $writer.Dispose() } elseif ($null -ne $stream) { $stream.Dispose() }
    }
    $path
}

function Write-SuporteTela {
    param([string]$Titulo, [switch]$SemCores)
    if ([Console]::IsOutputRedirected) { Write-Host '' }
    else { try { Clear-Host } catch { Write-Host '' } }
    $largura = Get-SuporteLargura
    if ($Titulo -eq 'Menu principal' -and $largura -ge 71 -and -not $SemCores) {
        $faixa = '01' * 35
        Write-SuporteLinha $faixa -Cor Cyan
        Write-Host ''
        $marca = @(
            '  #####  #   #  #####  #####  #####  #####  #####       #####  #####'
            '  #..... #.  #. #...#. #...#. #...#.  .#... #.....       .#...  .#...'
            '  #####  #.  #. #####. #.  #. #####.   #.   ####          #.     #.'
            '   ...#. #.  #. #..... #.  #. #.#...   #.   #....         #.     #.'
            '  #####. #####. #.     #####. #. ##    #.   #####         #.   #####'
            '   .....  .....  .      .....  .  ..    .    .....         .    .....'
        )
        foreach ($linha in $marca) {
            Write-SuporteLinha ($linha.Replace('#',[char]0x2588).Replace('.',[char]0x2591)) -Cor Cyan
        }
        Write-Host ''
        Write-SuporteLinha '              CAIXA DE FERRAMENTAS WINDOWS' -Cor Cyan
        Write-SuporteLinha $faixa -Cor Cyan
    } else {
        $separador = '=' * [Math]::Min(44,(Get-SuporteLargura))
        Write-SuporteLinha $separador -Cor Cyan -SemCores:$SemCores
        Write-SuporteLinha ('  SUPORTE TI  |  ' + $Titulo) -Cor Cyan -SemCores:$SemCores
        Write-SuporteLinha $separador -Cor Cyan -SemCores:$SemCores
    }
    Write-Host ''
    if ($Titulo -notin 'Menu principal','Sobre') { return }
    $identidade = $ExecutionContext.SessionState.Module
    if ($Titulo -eq 'Sobre') {
        Write-SuporteLinha ('  Versao ' + $identidade.Version) -SemCores
        Write-SuporteLinha '  Ano 2026' -SemCores
        Write-SuporteLinha ('  Desenvolvido por ' + $identidade.Author) -SemCores
        Write-Host ''
        return
    }
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $access = if ($isAdmin) { 'Administrador' } else { 'Padrao' }
    Write-SuporteLinha ('  ' + $env:COMPUTERNAME + '  |  ' + $env:USERDOMAIN + '\' + $env:USERNAME + '  |  ' + $access) -SemCores
    Write-SuporteLinha "  v$($identidade.Version) - Uso local | Resultados salvos somente por escolha" -SemCores
    if ($Titulo -eq 'Menu principal') {
        Write-Host ('  Desenvolvido por ' + $identidade.Author)
    }
    Write-Host ''
}

function Get-SuporteLargura {
    try {
        $largura = $Host.UI.RawUI.WindowSize.Width
        if ($largura -gt 0) { return [Math]::Max(1,$largura - 1) }
    } catch {}
    79
}

function Get-SuporteCorConsole {
    param([ConsoleColor]$Cor,[ConsoleColor]$Fundo)
    if ($Fundo -in 'Gray','White','Cyan','Yellow','Green','Magenta','Red') {
        $Cor = switch ($Cor) {
            'Cyan' { 'DarkCyan' }; 'Blue' { 'DarkBlue' }; 'Green' { 'DarkGreen' }
            'Yellow' { 'DarkYellow' }; 'Red' { 'DarkRed' }; 'Gray' { 'DarkGray' }
            default { $Cor }
        }
    }
    if ($Cor -eq $Fundo) {
        if ($Fundo -in 'White','Gray','Cyan','Yellow','Green','Magenta','Red') { return 'Black' }
        return 'White'
    }
    $Cor
}

function Write-SuporteLinha {
    param([string]$Texto,[ConsoleColor]$Cor='Gray',[switch]$SemCores)
    $largura = Get-SuporteLargura
    if (-not $SemCores) {
        try { $Cor = Get-SuporteCorConsole $Cor $Host.UI.RawUI.BackgroundColor } catch {}
    }
    foreach ($linha in ($Texto -split '\r?\n')) {
        $resto = $linha
        $recuo = ' ' * [Math]::Min([Math]::Max(0,[Math]::Min(8,$largura - 4)),($linha.Length - $linha.TrimStart().Length))
        while ($resto.Length -gt $largura) {
            $corte = $resto.LastIndexOf(' ',$largura)
            if ($corte -le $recuo.Length) { $corte = $largura }
            $parte = $resto.Substring(0,$corte).TrimEnd()
            if ($SemCores) { Write-Host $parte } else { Write-Host $parte -ForegroundColor $Cor }
            $resto = $recuo + $resto.Substring($corte).TrimStart()
        }
        if ($SemCores) { Write-Host $resto } else { Write-Host $resto -ForegroundColor $Cor }
    }
}

function Read-SuporteEscolha {
    param([string[]]$Opcoes=@(),[string]$Titulo,[int[]]$Alteracoes=@(),[switch]$SemCores)
    if ($Titulo) { Write-SuporteTela -Titulo $Titulo -SemCores:$SemCores }
    for ($i=0; $i -lt $Opcoes.Count; $i++) {
        $linha = '  ' + $Opcoes[$i]
        if (($i + 1) -in $Alteracoes) { Write-SuporteLinha ($linha + ' [ALTERACAO]') -Cor Yellow -SemCores:$SemCores }
        else { Write-SuporteLinha $linha -SemCores }
    }
    if ($Opcoes.Count) { Write-Host '' }
    Write-SuporteLinha '  [0 ou Enter] Voltar' -SemCores
    Write-Host ''
    $escolha = ([string](Read-Host 'Selecione')).Trim()
    if ($escolha) { $escolha } else { '0' }
}

function Show-SuporteResultado {
    param($Resultado,[switch]$SemCores)
    $cor = switch -Wildcard ($Resultado.Status) { 'Concluido' {'Green'} 'Falha*' {'Red'} default {'Yellow'} }
    if ($Resultado.Texto -match '(?m)^\[PING SEM RESPOSTA\]') { $cor = 'Red' }
    elseif ($Resultado.Texto -match '(?m)^\[PING PARCIAL\]') { $cor = 'Yellow' }
    Write-SuporteLinha "`n  RESULTADO | $($Resultado.Status)" -Cor $cor -SemCores:$SemCores
    foreach ($linha in ($Resultado.Texto -split '\r?\n')) {
        $percentual = $null
        if ($linha -match '^((?:\[INDISPONIVEL\] )?Disco \d+ \(.*\)): (Troca recomendada|Atencao - avaliar troca|Sem alertas detectados|Inconclusivo)\.\s*(.*)$') {
            $identificacao = $Matches[1]; $estadoDisco = $Matches[2]; $detalhes = $Matches[3]
            $destaque = switch ($estadoDisco) {
                'Troca recomendada' { 'Red' }
                'Atencao - avaliar troca' { 'Yellow' }
                'Sem alertas detectados' { 'Blue' }
                'Inconclusivo' { 'Gray' }
            }
            $linha = "${identificacao}: $estadoDisco."
            if ($detalhes -match '^(.*?)\s*(Desgaste estimado: (\d{1,3})% usado\..*)$') {
                $percentual = [int]$Matches[3]
                $detalhes = $Matches[1] + "`n  " + $Matches[2]
            }
            if ($detalhes) { $linha += "`n  " + $detalhes }
        } elseif ($linha -match '^Bateria \d+: (\d+(?:[.,]\d)?)% da capacidade original ') {
            $destaque = 'Blue'
            $percentual = [double]::Parse(($Matches[1] -replace ',','.'),[Globalization.CultureInfo]::InvariantCulture)
        } else {
            $destaque = switch -Regex ($linha) {
                '^\[PING OK\]' {'Green';break}
                '^\[PING SEM RESPOSTA\]' {'Red';break}
                '^\[IMPRESSAO PROBLEMA\]' {'Red';break}
                '^\[IMPRESSAO ATENCAO\]' {'Yellow';break}
                '^\[(PING PARCIAL|INDISPONIVEL|ACESSO NEGADO)\]' {'Yellow';break}
                '^Comando:' {'Cyan';break}
                '^(--- |Ocorrencia mais recente|Detalhes tecnicos|(?:Outros )?[Cc]odigos de falha encontrados|Registros proximos)' {'Cyan';break}
            }
        }
        if ($destaque) { Write-SuporteLinha $linha -Cor $destaque -SemCores:$SemCores }
        else { Write-SuporteLinha $linha -SemCores }
        if ($null -ne $percentual) {
            $tamanho = [Math]::Max(1,[Math]::Min(20,(Get-SuporteLargura) - 4))
            $cheios = [int][Math]::Floor([Math]::Min(100.0,[double]$percentual) * $tamanho / 100.0)
            $barra = '  [' + ('#' * $cheios) + ('-' * ($tamanho - $cheios)) + ']'
            Write-SuporteLinha $barra -Cor $destaque -SemCores:$SemCores
        }
    }
    Write-Host ''
}

function Request-SuporteSalvar {
    param($Resultado, [string]$Documentos, [switch]$Confirmado)
    if (-not $Confirmado -and ([string](Read-Host 'Salvar este resultado? [S] Sim | [Enter/N] Nao')).Trim() -ine 's') { return }
    $destino = if ($Documentos) { Join-Path $Documentos 'SuporteTI\Resultados' } else { '' }
    while ($true) {
        Write-Host ('Destino sugerido: ' + $(if ($destino) { $destino } else { 'Documentos indisponivel; escolha uma pasta.' }))
        $choice = Read-Host '[Enter] Usar destino | [2] Outro local | [0] Cancelar'
        if ($choice -eq '0') { return }
        if ($choice -eq '2') { $destino=(Read-Host 'Caminho completo da pasta (sem aspas)').Trim().Trim('"') }
        elseif ($choice -ne '') { Write-Host 'Opcao invalida.'; continue }
        if ([string]::IsNullOrWhiteSpace($destino)) { continue }
        try { $saved=Save-SuporteResultado -Resultado $Resultado -PastaBase $destino; Write-Host ('Salvo em: ' + $saved); return }
        catch { Write-Host ('Nao foi possivel salvar: ' + $_.Exception.Message); Write-Host 'Escolha outro local ou cancele.' }
    }
}

function Start-SuporteMenu {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ModuleRoot, [switch]$SemCores)
    $catalogo = @(Get-SuporteCatalogo)
    $grupos = @('Computador','Rede','Windows Update','GPO','Impressao','Relatorios e eventos','Reparos do Windows')
    $documentos = [Environment]::GetFolderPath('MyDocuments')
    $ultimo = $null
    while ($true) {
        Write-SuporteTela -Titulo 'Menu principal' -SemCores:$SemCores
        for ($i=0; $i -lt $grupos.Count; $i++) { Write-SuporteLinha ('  [{0}] {1}' -f ($i+1),$grupos[$i]) -SemCores }
        Write-SuporteLinha '  [8] Sobre o Suporte TI' -SemCores
        Write-SuporteLinha "`n  [0 ou Enter] Sair`n" -SemCores
        $entrada = ([string](Read-Host 'Selecione')).Trim()
        if (-not $entrada -or $entrada -eq '0') { return }
        if ($entrada -eq '8') {
            Write-SuporteTela -Titulo 'Sobre' -SemCores:$SemCores
            [void](Read-Host '0 ou Enter para voltar')
            continue
        }
        if ($entrada -notmatch '^[1-7]$') { continue }
        $grupo = $grupos[[int]$entrada-1]
        $items = @($catalogo | Where-Object { $_.Grupo -eq $grupo -and -not $_.Pai })
        :submenu while ($true) {
            Write-SuporteTela -Titulo $grupo -SemCores:$SemCores
            foreach ($admin in @($false,$true)) {
                $subset=@($items | Where-Object { $_.Admin -eq $admin -and $_.Id -ne 'bateria' })
                if ($subset.Count -eq 0) { continue }
                $secao = if ($admin) { '  ADMINISTRADOR | O Windows pode pedir elevacao' } else { '  SESSAO ATUAL' }
                $corSecao = if ($admin) { 'Yellow' } else { 'Cyan' }
                Write-SuporteLinha $secao -Cor $corSecao -SemCores:$SemCores
                foreach ($item in $subset) {
                    $number=[array]::IndexOf($items,$item)+1
                    $suffix=if ($item.Id -in @('cache','gpupdateuser','gpupdatecomputer','spooler','netdhcp','netstatic','chromecache','perfillocal')) { ' [ALTERACAO]' } elseif($item.Id -in @('sfc','dism','chkdsk')){' [Verificacao / reparo]'} else { '' }
                    if ($suffix) { Write-SuporteLinha ('  [{0}] {1}{2}' -f $number,$item.Nome,$suffix) -Cor Yellow -SemCores:$SemCores }
                    else { Write-SuporteLinha ('  [{0}] {1}' -f $number,$item.Nome) -SemCores }
                }
                Write-Host ''
            }
            $bateria = $items | Where-Object Id -eq 'bateria'
            if ($bateria) {
                Write-SuporteLinha '  NOTEBOOK' -Cor Cyan -SemCores:$SemCores
                Write-SuporteLinha ('  [{0}] {1}' -f ($items.Count),$bateria.Nome) -SemCores
                Write-Host ''
            }
            $entrada=Read-SuporteEscolha -SemCores:$SemCores
            if ($entrada -eq '0') { break }
            if ($entrada -notmatch '^[1-9][0-9]?$') { continue }
            $index=[int]$entrada-1
            if ($index -ge $items.Count) { continue }
            $item=$items[$index]
            if ($item.Especial) {
                switch ($item.Id) {
                    'monitor' { Write-SuporteTela -Titulo $item.Nome -SemCores:$SemCores; Show-SuporteMonitor }
                    'mapaocupacao' {
                        Write-SuporteTela -Titulo $item.Nome -SemCores:$SemCores
                        try { Show-SuporteMapaOcupacao; continue submenu }
                        catch { Write-SuporteLinha ('Falha ao abrir o mapa: ' + $_.Exception.Message) -Cor Red -SemCores:$SemCores }
                    }
                    'autologon' {
                        $choice = Read-SuporteEscolha @('[1] Consultar (ver se esta ativo)','[2] Configurar (administrador)','[3] Desativar (administrador)') -Titulo $item.Nome -Alteracoes 2,3 -SemCores:$SemCores
                        if ($choice -notin @('1','2','3')) { continue submenu }
                        switch ($choice) {
                            '1' {
                                Write-SuporteTela -Titulo 'Consultar login automatico' -SemCores:$SemCores
                                try { Show-SuporteResultado (Invoke-SuporteConsulta -Id autologon) -SemCores:$SemCores }
                                catch { Write-SuporteLinha ('Consulta falhou: ' + $_.Exception.Message) -Cor Red -SemCores:$SemCores }
                            }
                            '2' { Request-SuporteOperacao autologonenable $documentos -SemCores:$SemCores }
                            '3' { Request-SuporteOperacao autologondisable $documentos -SemCores:$SemCores }
                        }
                    }
                    'ultimo' {
                        Write-SuporteTela -Titulo $item.Nome -SemCores:$SemCores
                        if ($null -eq $ultimo) { Write-Host 'Nenhum resultado nesta sessao.' }
                        else { Show-SuporteResultado $ultimo -SemCores:$SemCores; Request-SuporteSalvar $ultimo $documentos }
                    }
                    'gphtml' {
                        $choice=Read-SuporteEscolha @('[1] HTML do usuario atual','[2] HTML do computador (administrador)') -Titulo $item.Nome -SemCores:$SemCores
                        if ($choice -notin @('1','2')) { continue submenu }
                        $escopo = if ($choice -eq '1') { 'User' } else { 'Computer' }
                        Request-SuporteExportar gphtml $documentos -Escopo $escopo -SemCores:$SemCores
                    }
                    'evtx' { Request-SuporteExportar evtx $documentos -SemCores:$SemCores }
                    'gpcomputador' { Request-SuporteOperacao gpcomputerquery $documentos -SemCores:$SemCores }
                    'diskhealth' { Request-SuporteOperacao diskhealth $documentos -SemCores:$SemCores }
                    {$_ -in @('gpupdateuser','gpupdatecomputer')} {
                        $choice=Read-SuporteEscolha @('[1] Atualizar politicas (processamento normal)','[2] Reaplicar todas (/force)') -Titulo $item.Nome -Alteracoes 1,2 -SemCores:$SemCores
                        if ($choice -notin @('1','2')) { continue submenu }
                        $force=$choice -eq '2'
                        $action=if ($item.Id -eq 'gpupdateuser') { 'gpuser' } else { 'gpcomputer' }
                        Request-SuporteOperacao $action $documentos -Forcar:$force -SemCores:$SemCores
                    }
                    'sfc' {
                        $choice=Read-SuporteEscolha @('[1] Verificar (arquivos protegidos do Windows)','[2] Verificar e reparar (/scannow)') -Titulo $item.Nome -Alteracoes 2 -SemCores:$SemCores
                        if ($choice -eq '0') { continue submenu }
                        if ($choice -eq '1') { Request-SuporteOperacao sfcverify $documentos -SemCores:$SemCores }
                        elseif ($choice -eq '2') { Request-SuporteOperacao sfcrepair $documentos -SemCores:$SemCores }
                    }
                    'dism' {
                        $choice=Read-SuporteEscolha @('[1] Consultar o estado registrado (CheckHealth)','[2] Examinar a imagem do Windows (ScanHealth)','[3] Reparar a imagem do Windows (RestoreHealth)') -Titulo $item.Nome -Alteracoes 3 -SemCores:$SemCores
                        if ($choice -eq '0') { continue submenu }
                        if ($choice -eq '1') { Request-SuporteOperacao dismcheck $documentos -SemCores:$SemCores }
                        elseif ($choice -eq '2') { Request-SuporteOperacao dismscan $documentos -SemCores:$SemCores }
                        elseif ($choice -eq '3') { Request-SuporteOperacao dismrestore $documentos -SemCores:$SemCores }
                    }
                    'chkdsk' {
                        $choice=Read-SuporteEscolha @('[1] Verificar o volume (somente leitura)','[2] Corrigir erros e procurar setores defeituosos (pode exigir reinicio)') -Titulo $item.Nome -Alteracoes 2 -SemCores:$SemCores
                        if ($choice -eq '0') { continue submenu }
                        if ($choice -eq '1') { Request-SuporteOperacao chkdskread $documentos -SemCores:$SemCores }
                        elseif ($choice -eq '2') { Request-SuporteOperacao chkdskfull $documentos -SemCores:$SemCores }
                    }
                    default { Request-SuporteOperacao $item.Id $documentos -SemCores:$SemCores }
                }
                [void](Read-Host '0 ou Enter para voltar'); continue
            }
            if ($item.Admin) {
                $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
                if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                    Write-Host 'Consulta requer administrador. Elevacao por operacao sera entregue na proxima fase.'
                    [void](Read-Host '0 ou Enter para voltar'); continue
                }
            }
            do {
                $consultaId = $item.Id
                $tituloConsulta = $item.Nome
                $opcoes = @{}
                if ($item.Id -eq 'falhas') {
                    $escolha = Read-SuporteEscolha @('[1] Analisar os ultimos erros e travamentos (ultimas 24h)','[2] Consultar um codigo de erro (digitar o numero)') -Titulo $item.Nome -SemCores:$SemCores
                    if ($escolha -eq '0') { continue submenu }
                    if ($escolha -notin '1','2') { continue }
                    if ($escolha -eq '2') {
                        $tituloConsulta = 'Consultar um codigo de erro'
                        Write-SuporteTela -Titulo $tituloConsulta -SemCores:$SemCores
                        $codigo = ([string](Read-Host 'Codigo decimal ou hexadecimal com 0x (0 ou Enter volta)')).Trim()
                        if ($codigo -in '','0') { continue }
                        $consultaId = 'codigofalha'
                        $opcoes = @{ Codigo=$codigo }
                    } else {
                        $tituloConsulta = 'Analisar os ultimos erros e travamentos (24h)'
                        $opcoes.IncluirCodigos = $true
                    }
                }
                if ($item.Id -eq 'ping') {
                    Write-SuporteTela -Titulo $tituloConsulta -SemCores:$SemCores
                    $destino = ([string](Read-Host 'Site ou IP (0 ou Enter volta)')).Trim()
                    if (-not $destino -or $destino -eq '0') { continue submenu }
                    try { $opcoes.Destino = Get-SuporteDestinoPing $destino }
                    catch { Write-SuporteLinha $_.Exception.Message -SemCores; [void](Read-Host '0 ou Enter para voltar'); continue submenu }
                }
                $limit = if ($item.Id -eq 'discos') { 40 } else { 25 }
                Write-SuporteTela -Titulo $tituloConsulta -SemCores:$SemCores
                Write-SuporteLinha ('Consultando... limite de '+$limit+' segundos; sem alteracoes corretivas.') -SemCores
                $codigos = @()
                try {
                    $ultimo = Invoke-SuporteConsulta -Id $consultaId -Opcoes $opcoes -TimeoutSeconds $limit
                    Show-SuporteResultado $ultimo -SemCores:$SemCores
                    if ($consultaId -eq 'falhas') { $codigos = $ultimo.Codigos }
                    if ($codigos.Count -gt 0) {
                        $rotulos = @{ Paradas='Tela azul'; Excecoes='NTSTATUS'; Win32='Win32'; HRESULT='HRESULT' }
                        $atalhos = @(for ($i=0; $i -lt $codigos.Count; $i++) {
                            '[{0}] Consultar {1} ({2})' -f ($i + 1),$codigos[$i].Codigo,$rotulos[$codigos[$i].Familia]
                        })
                        do {
                            $escolha = Read-SuporteEscolha ($atalhos + '[S] Salvar este resultado') -SemCores:$SemCores
                            if ($escolha -eq 's') { Request-SuporteSalvar $ultimo $documentos -Confirmado }
                        } until ($escolha -eq '0' -or ($escolha -match '^[1-9]$' -and [int]$escolha -le $codigos.Count))
                        if ($escolha -eq '0') { continue }
                        $selecionado = $codigos[[int]$escolha - 1]
                        Write-SuporteTela -Titulo ('Explicacao de ' + $selecionado.Codigo) -SemCores:$SemCores
                        $ultimo = Invoke-SuporteConsulta -Id codigofalha -Opcoes @{ Familia=$selecionado.Familia; Codigo=$selecionado.Codigo } -TimeoutSeconds $limit
                        Show-SuporteResultado $ultimo -SemCores:$SemCores
                    }
                    Request-SuporteSalvar $ultimo $documentos
                }
                catch { Write-Host ('Consulta falhou: ' + $_.Exception.Message) }
                [void](Read-Host '0 ou Enter para voltar')
            } while ($item.Id -eq 'falhas')
        }
    }
}

Export-ModuleMember -Function Start-SuporteMenu,Get-SuporteCatalogo,Invoke-SuporteConsulta,Save-SuporteResultado,Get-SuporteDiscoClassificacao
