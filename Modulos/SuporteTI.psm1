Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'Operacoes.ps1')
. (Join-Path $PSScriptRoot 'Discos.ps1')
. (Join-Path $PSScriptRoot 'Recursos.ps1')
. (Join-Path $PSScriptRoot 'Rede.ps1')
. (Join-Path $PSScriptRoot 'Manutencao.ps1')
. (Join-Path $PSScriptRoot 'Perfis.ps1')

function Get-SuporteCatalogo {
    @(
        @{ Id='sistema'; Grupo='Computador'; Nome='Informacoes do computador' }
        @{ Id='desempenho'; Grupo='Computador'; Nome='CPU, memoria e processos' }
        @{ Id='monitor'; Grupo='Computador'; Nome='Monitor de CPU e RAM ao vivo'; Especial=$true }
        @{ Id='discos'; Grupo='Computador'; Nome='Uso e saude dos discos (SMART e nativo)' }
        @{ Id='diskhealth'; Grupo='Computador'; Nome='Saude dos discos com acesso administrativo'; Admin=$true; Especial=$true }
        @{ Id='dispositivos'; Grupo='Computador'; Nome='Dispositivos e drivers com problemas' }
        @{ Id='servicos'; Grupo='Computador'; Nome='Estado dos servicos' }
        @{ Id='programas'; Grupo='Computador'; Nome='Programas instalados' }
        @{ Id='falhas'; Grupo='Computador'; Nome='Falhas recentes (ultimas 24 horas)' }
        @{ Id='chromecache'; Grupo='Computador'; Nome='Limpar cache de paginas do Google Chrome'; Especial=$true }
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
        @{ Id='spooler'; Grupo='Impressao'; Nome='Reiniciar spooler local'; Especial=$true; Admin=$true }
        @{ Id='eventos'; Grupo='Relatorios e eventos'; Nome='Eventos recentes de System e Application' }
        @{ Id='ultimo'; Grupo='Relatorios e eventos'; Nome='Rever e salvar ultimo resultado'; Especial=$true }
        @{ Id='evtx'; Grupo='Relatorios e eventos'; Nome='Exportar Application, System e Setup (24h)'; Especial=$true }
        @{ Id='sfc'; Grupo='Reparos do Windows'; Nome='SFC: verificar ou reparar'; Especial=$true; Admin=$true }
        @{ Id='dism'; Grupo='Reparos do Windows'; Nome='DISM: verificar ou RestoreHealth'; Especial=$true; Admin=$true }
        @{ Id='chkdsk'; Grupo='Reparos do Windows'; Nome='CHKDSK: consultar ou verificar por completo'; Especial=$true; Admin=$true }
        @{ Id='perfillocal'; Grupo='Reparos do Windows'; Nome='Verificar e remover perfil local duplicado'; Especial=$true; Admin=$true }
    ) | ForEach-Object {
        [pscustomobject]@{ Id=$_['Id']; Grupo=$_['Grupo']; Nome=$_['Nome']; Admin=($_['Admin'] -eq $true); Pendente=$false; Especial=($_['Especial'] -eq $true) }
    }
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
    if ($null -eq $item -or ($item.Especial -and $Id -notin @('gpcomputador'))) { throw 'Consulta indisponivel neste fluxo.' }
    $modulePath = Join-Path $PSScriptRoot 'SuporteTI.psd1'
    $collectorPath = Join-Path $PSScriptRoot 'Consultas.ps1'
    $inicio = Get-Date
    $job = $null
    $status = 'Concluido'
    $lines = @(); $queryErrors=@()
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
        $lines = @(Receive-Job -Job $job -ErrorAction SilentlyContinue -ErrorVariable queryErrors | ForEach-Object { [string]$_ })
        if ($queryErrors) { $status='Parcial ou falha'; $lines += @($queryErrors | ForEach-Object { 'ERRO: ' + $_.ToString() }) }
        if (@($lines | Where-Object { $_ -match '^\[(INDISPONIVEL|ACESSO NEGADO)\]' }).Count -gt 0 -and $status -eq 'Concluido') { $status='Parcial: ver limitacoes' }
    } catch {
        $status='Falha'; $lines += 'ERRO: ' + $_.Exception.Message
    } finally {
        if ($null -ne $job) {
            if ($job.State -in @('Running','NotStarted')) { Stop-Job -Job $job }
            Remove-Job -Job $job -Force
        }
    }
    if ($lines.Count -eq 0) { $lines=@('Nenhum dado foi retornado. Nao interpretar como ausencia de problemas.') }
    [pscustomobject]@{
        Id=[guid]::NewGuid().ToString('N'); Consulta=$item.Nome; Computador=$env:COMPUTERNAME
        Inicio=$inicio.ToString('o'); Fim=(Get-Date).ToString('o'); Status=$status
        Texto=($lines -join [Environment]::NewLine)
    }
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
    Clear-Host
    $color = if ($SemCores) { $Host.UI.RawUI.ForegroundColor } else { 'Cyan' }
    $largura = 0
    try { $largura = $Host.UI.RawUI.WindowSize.Width } catch {}
    if ($Titulo -eq 'Menu principal' -and $largura -ge 72 -and -not $SemCores) {
        $faixa = '01' * 35
        Write-Host $faixa -ForegroundColor $color
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
            Write-Host ($linha.Replace('#',[char]0x2588).Replace('.',[char]0x2591)) -ForegroundColor $color
        }
        Write-Host ''
        Write-Host '              CAIXA DE FERRAMENTAS WINDOWS' -ForegroundColor $color
        Write-Host $faixa -ForegroundColor $color
    } else {
        Write-Host ('=' * 44) -ForegroundColor $color
        Write-Host ('  SUPORTE TI  |  ' + $Titulo) -ForegroundColor $color
        Write-Host ('=' * 44) -ForegroundColor $color
    }
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $access = if ($isAdmin) { 'Administrador' } else { 'Padrao' }
    Write-Host ('  ' + $env:COMPUTERNAME + '  |  ' + $env:USERDOMAIN + '\' + $env:USERNAME + '  |  ' + $access)
    $identidade = $ExecutionContext.SessionState.Module
    Write-Host "  v$($identidade.Version) - Uso local | Resultados salvos somente por escolha"
    if ($Titulo -in @('Menu principal', 'Sobre')) {
        Write-Host ('  Desenvolvido por ' + $identidade.Author)
    }
    Write-Host ''
}

function Write-SuporteLinha {
    param([string]$Texto,[ConsoleColor]$Cor='Gray',[switch]$SemCores)
    if ($SemCores) { Write-Host $Texto } else { Write-Host $Texto -ForegroundColor $Cor }
}

function Show-SuporteResultado {
    param($Resultado,[switch]$SemCores)
    $cor = switch -Wildcard ($Resultado.Status) { 'Concluido' {'Green'} 'Falha*' {'Red'} default {'Yellow'} }
    if ($Resultado.Texto -match '(?m)^\[PING SEM RESPOSTA\]') { $cor = 'Red' }
    elseif ($Resultado.Texto -match '(?m)^\[PING PARCIAL\]') { $cor = 'Yellow' }
    Write-SuporteLinha "`n  RESULTADO | $($Resultado.Status)" -Cor $cor -SemCores:$SemCores
    foreach ($linha in ($Resultado.Texto -split '\r?\n')) {
        $destaque = switch -Regex ($linha) {
            '^\[PING OK\]' {'Green';break}
            '^\[PING SEM RESPOSTA\]' {'Red';break}
            '^\[(PING PARCIAL|INDISPONIVEL|ACESSO NEGADO)\]' {'Yellow';break}
            '^Comando:' {'Cyan';break}
        }
        if ($destaque) { Write-SuporteLinha $linha -Cor $destaque -SemCores:$SemCores }
        else { Write-Host $linha }
    }
    Write-Host ''
}

function Request-SuporteSalvar {
    param($Resultado, [string]$Documentos)
    if (([string](Read-Host 'Salvar este resultado? [S] Sim | [Enter/N] Nao')).Trim() -ine 's') { return }
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
        for ($i=0; $i -lt $grupos.Count; $i++) { Write-Host ('  [{0}] {1}' -f ($i+1),$grupos[$i]) }
        Write-Host '  [8] Sobre o Suporte TI'
        Write-Host "`n  [0] Sair`n"
        $entrada = Read-Host 'Selecione'
        if ($entrada -eq '0') { return }
        if ($entrada -eq '8') {
            Write-SuporteTela -Titulo 'Sobre' -SemCores:$SemCores
            Write-Host '  Caixa de ferramentas para suporte Windows'
            [void](Read-Host "`nPressione Enter para voltar")
            continue
        }
        if ($entrada -notmatch '^[1-7]$') { continue }
        $grupo = $grupos[[int]$entrada-1]
        $items = @($catalogo | Where-Object Grupo -eq $grupo)
        while ($true) {
            Write-SuporteTela -Titulo $grupo -SemCores:$SemCores
            foreach ($admin in @($false,$true)) {
                $subset=@($items | Where-Object Admin -eq $admin)
                if ($subset.Count -eq 0) { continue }
                $secao = if ($admin) { '  ADMINISTRADOR | O Windows pode pedir elevacao' } else { '  SESSAO ATUAL' }
                $corSecao = if ($admin) { 'Yellow' } else { 'Cyan' }
                Write-SuporteLinha $secao -Cor $corSecao -SemCores:$SemCores
                foreach ($item in $subset) {
                    $number=[array]::IndexOf($items,$item)+1
                    $suffix=if ($item.Id -in @('cache','gpupdateuser','gpupdatecomputer','spooler','netdhcp','netstatic','chromecache')) { ' [ALTERACAO]' } elseif($item.Id -in @('sfc','dism','chkdsk')){' [Verificacao / reparo]'} else { '' }
                    if ($suffix) { Write-SuporteLinha ('  [{0}] {1}{2}' -f $number,$item.Nome,$suffix) -Cor Yellow -SemCores:$SemCores }
                    else { Write-Host ('  [{0}] {1}' -f $number,$item.Nome) }
                    $referencia = switch ($item.Id) {
                        'gpupdateuser' { 'gpupdate.exe ' + ((Get-SuporteArgumentosGpupdate user) -join ' ') + '  (+ /force opcional)' }
                        'gpupdatecomputer' { 'gpupdate.exe ' + ((Get-SuporteArgumentosGpupdate computer) -join ' ') + '  (+ /force opcional)' }
                        'eventos' { 'Get-WinEvent -FilterHashtable ... -MaxEvents 30' }
                        'evtx' { 'wevtutil.exe epl' }
                    }
                    if ($referencia) { Write-SuporteLinha ('      ' + $referencia) -Cor Cyan -SemCores:$SemCores }
                }
                Write-Host ''
            }
            Write-Host '  [0] Voltar'
            $entrada=Read-Host 'Selecione'
            if ($entrada -eq '0') { break }
            if ($entrada -notmatch '^[1-9][0-9]?$') { continue }
            $index=[int]$entrada-1
            if ($index -ge $items.Count) { continue }
            $item=$items[$index]
            if ($item.Especial) {
                switch ($item.Id) {
                    'monitor' { Show-SuporteMonitor }
                    'ultimo' {
                        if ($null -eq $ultimo) { Write-Host 'Nenhum resultado nesta sessao.' }
                        else { Show-SuporteResultado $ultimo -SemCores:$SemCores; Request-SuporteSalvar $ultimo $documentos }
                    }
                    'gphtml' { Request-SuporteExportar gphtml $documentos }
                    'evtx' { Request-SuporteExportar evtx $documentos }
                    'gpcomputador' { Request-SuporteOperacao gpcomputerquery $documentos }
                    'diskhealth' { Request-SuporteOperacao diskhealth $documentos }
                    {$_ -in @('gpupdateuser','gpupdatecomputer')} {
                        $force=(Read-Host 'Reaplicar todas as politicas do escopo (/force)? [s/N]') -ieq 's'
                        $escopo=if ($item.Id -eq 'gpupdateuser') { 'user' } else { 'computer' }
                        Write-SuporteLinha ('Comando: gpupdate.exe ' + ((Get-SuporteArgumentosGpupdate $escopo -Forcar:$force) -join ' ')) -Cor Cyan -SemCores:$SemCores
                        $action=if ($item.Id -eq 'gpupdateuser') { 'gpuser' } else { 'gpcomputer' }
                        Request-SuporteOperacao $action $documentos -Forcar:$force
                    }
                    'sfc' {
                        $choice=Read-Host '[1] Verificar sem reparar | [2] Reparar /scannow | [0] Voltar'
                        if ($choice -eq '1') { Request-SuporteOperacao sfcverify $documentos }
                        elseif ($choice -eq '2') { Request-SuporteOperacao sfcrepair $documentos }
                    }
                    'dism' {
                        $choice=Read-Host '[1] CheckHealth | [2] ScanHealth | [3] RestoreHealth | [0] Voltar'
                        if ($choice -eq '1') { Request-SuporteOperacao dismcheck $documentos }
                        elseif ($choice -eq '2') { Request-SuporteOperacao dismscan $documentos }
                        elseif ($choice -eq '3') { Request-SuporteOperacao dismrestore $documentos }
                    }
                    'chkdsk' {
                        $choice=Read-Host '[1] Consultar sem reparar | [2] Completo /f /r (pode exigir reinicio) | [0] Voltar'
                        if ($choice -eq '1') { Request-SuporteOperacao chkdskread $documentos }
                        elseif ($choice -eq '2') { Request-SuporteOperacao chkdskfull $documentos }
                    }
                    default { Request-SuporteOperacao $item.Id $documentos }
                }
                [void](Read-Host 'Enter para voltar'); continue
            }
            if ($item.Admin) {
                $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
                if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                    Write-Host 'Consulta requer administrador. Elevacao por operacao sera entregue na proxima fase.'
                    [void](Read-Host 'Enter para voltar'); continue
                }
            }
            $opcoes=@{}
            if ($item.Id -eq 'ping') {
                $destino = Read-Host 'Site ou IP (Enter volta)'
                if (-not $destino) { continue }
                try { $opcoes.Destino = Get-SuporteDestinoPing $destino }
                catch { Write-Host $_.Exception.Message; [void](Read-Host 'Enter para voltar'); continue }
            }
            $limit=if ($item.Id -eq 'discos') { 40 } else { 25 }
            Write-Host ('Consultando... limite de '+$limit+' segundos; sem alteracoes corretivas.')
            try { $ultimo=Invoke-SuporteConsulta -Id $item.Id -Opcoes $opcoes -TimeoutSeconds $limit; Show-SuporteResultado $ultimo -SemCores:$SemCores; Request-SuporteSalvar $ultimo $documentos }
            catch { Write-Host ('Consulta falhou: ' + $_.Exception.Message) }
            [void](Read-Host 'Enter para voltar')
        }
    }
}

Export-ModuleMember -Function Start-SuporteMenu,Get-SuporteCatalogo,Invoke-SuporteConsulta,Save-SuporteResultado,Get-SuporteDiscoClassificacao
