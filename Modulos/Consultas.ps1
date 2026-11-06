param([Parameter(Mandatory)][string]$Id, [hashtable]$Opcoes=@{})
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Recursos.ps1')
. (Join-Path $PSScriptRoot 'Rede.ps1')
. (Join-Path $PSScriptRoot 'Discos.ps1')
. (Join-Path $PSScriptRoot 'Logon.ps1')
. (Join-Path $PSScriptRoot 'Falhas.ps1')
$largura = if ($Opcoes.ContainsKey('Largura')) { [Math]::Max(40,[int]$Opcoes.Largura) } else { 79 }

function Format-Section {
    param([string]$Title,[scriptblock]$Query)
    "`r`n--- $Title ---"
    try { & $Query | Out-String -Width $largura | ForEach-Object { $_.TrimEnd() } }
    catch {
        if ($_.Exception -is [UnauthorizedAccessException] -or $_.Exception.Message -match 'denied|negado') { '[ACESSO NEGADO] ' + $Title }
        elseif ($_.FullyQualifiedErrorId -match 'NoMatchingEventsFound') { 'Nenhum evento correspondente no periodo consultado.' }
        else { '[INDISPONIVEL] ' + $Title + ': ' + $_.Exception.Message }
    }
}

function Get-SuporteExplicacaoAutomatica {
    param([string]$Entrada)
    $codigo = [uint32]0
    $negativo = 0
    if ($Entrada -match '^0x([0-9a-f]{1,8})$') {
        $codigo = [Convert]::ToUInt32($Matches[1],16)
    } elseif ($Entrada -match '^-[0-9]{1,10}$' -and [int]::TryParse($Entrada,[ref]$negativo) -and $negativo -lt 0) {
        $codigo = [uint32]([long]$negativo + 4294967296)
    } elseif ($Entrada -notmatch '^\d{1,10}$' -or -not [uint32]::TryParse($Entrada,[ref]$codigo)) {
        throw 'Informe um numero decimal de 32 bits ou hexadecimal com prefixo 0x.'
    }
    $catalogo = $null
    try { $catalogo = Read-SuporteCatalogoFalhas }
    catch { '[INDISPONIVEL] Catalogo offline. A busca usa as mensagens do Windows quando disponiveis.' }

    $correspondencias = @(foreach ($familia in 'Win32','HRESULT','Excecoes','Paradas') {
        if ($familia -eq 'Win32' -and $codigo -gt 65535) { continue }
        $descricao = Find-SuporteCodigoFalha $catalogo $familia $codigo
        if ($descricao) { @{ Familia=$familia; Descricao=$descricao } }
    })
    if (-not $correspondencias.Count) {
        '0x{0:X8}: codigo sem correspondencia no catalogo ou nas mensagens do Windows.' -f $codigo
        return
    }
    if ($correspondencias.Count -gt 1) {
        'O mesmo codigo tem mais de um significado. Confira a origem do erro.'
    }
    foreach ($item in $correspondencias) {
        ''
        Format-SuporteExplicacaoCodigo $item.Familia $codigo $item.Descricao
    }
}

function Invoke-LocalNative {
    param([string]$Name,[string]$Arguments,[int]$Seconds=10)
    $exe=Join-Path $env:SystemRoot ('System32\'+$Name)
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$exe; $psi.Arguments=$Arguments; $psi.UseShellExecute=$false
    $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true; $psi.CreateNoWindow=$true
    $proc=New-Object Diagnostics.Process
    $proc.StartInfo=$psi
    try {
        [void]$proc.Start()
        $out=$proc.StandardOutput.ReadToEndAsync(); $err=$proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit($Seconds*1000)) { $proc.Kill(); throw 'Consulta nativa excedeu o limite.' }
        $proc.WaitForExit()
        $out.Result; if ($err.Result) { $err.Result }
        if ($proc.ExitCode -ne 0) { throw ('Codigo de saida: '+$proc.ExitCode) }
    } finally { $proc.Dispose() }
}
function Get-RecentEvents {
    param([string]$Log,[int[]]$Levels=@(1,2,3),[int]$Count=30)
    Get-WinEvent -FilterHashtable @{LogName=$Log;StartTime=(Get-Date).AddHours(-24);Level=$Levels} -MaxEvents $Count -ErrorAction Stop |
        Select-Object TimeCreated,Id,LevelDisplayName,ProviderName,@{n='Mensagem';e={ if ($_.Message) { ($_.Message -replace '\s+',' ').Substring(0,[Math]::Min(700,($_.Message -replace '\s+',' ').Length)) } }} | Format-List
}

function Get-SuporteFilasImpressao {
    $spooler = Get-Service -Name Spooler -ErrorAction Stop
    if ($spooler.Status -ne 'Running') {
        '[IMPRESSAO PROBLEMA] Spooler local: ' + $spooler.Status + '. As filas nao puderam ser avaliadas.'
        return
    }
    'Spooler local: em execucao.'
    $impressoras = @(Get-Printer -ErrorAction Stop | Sort-Object Name)
    if (-not $impressoras.Count) { 'Nenhuma fila de impressao visivel nesta sessao.'; return }
    foreach ($impressora in $impressoras) {
        ''
        $estado = [string]$impressora.PrinterStatus
        $problema = $estado -match '\b(Error|Offline|PaperJam|PaperOut|PaperProblem|OutputBinFull|NotAvailable|NoToner|UserIntervention|DoorOpen|OutOfMemory)\b'
        $atencao = $estado -match '\b(Paused|TonerLow|ManualFeed)\b'
        $trabalhos = @()
        $leituraFila = $true
        try { $trabalhos = @(Get-PrintJob -PrinterObject $impressora -ErrorAction Stop) }
        catch { $leituraFila = $false }
        $falhas = @($trabalhos | Where-Object { [string]$_.JobStatus -match '\b(Error|Offline|PaperOut|Blocked|BlockedDeviceQueue|UserIntervention)\b' })
        $pausados = @($trabalhos | Where-Object { [string]$_.JobStatus -match '\bPaused\b' })
        $rotulo = if ($problema -or $falhas.Count) { '[IMPRESSAO PROBLEMA] ' }
            elseif ($atencao -or $pausados.Count) { '[IMPRESSAO ATENCAO] ' }
            else { '' }
        $rotulo + 'Impressora: ' + $impressora.Name
        '  Porta: ' + $impressora.PortName
        '  Estado informado pelo Windows: ' + $(if ($estado) { $estado } else { 'Indisponivel' })
        if ($leituraFila) {
            '  Trabalhos na fila: {0} | Com problema: {1} | Pausados: {2}' -f $trabalhos.Count,$falhas.Count,$pausados.Count
        } else {
            '[INDISPONIVEL] Trabalhos da fila: ' + $impressora.Name
        }
    }
}

switch ($Id) {
    'sistema' {
        Format-Section 'Computador' { Get-CimInstance Win32_ComputerSystem -OperationTimeoutSec 5 | Select-Object Name,Manufacturer,Model,Domain,PartOfDomain,@{n='RAM_GB';e={[Math]::Round($_.TotalPhysicalMemory/1GB,1)}} | Format-List }
        Format-Section 'Windows' { Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5 | Select-Object Caption,Version,BuildNumber,OSArchitecture,LastBootUpTime | Format-List }
        Format-Section 'BIOS' { Get-CimInstance Win32_BIOS -OperationTimeoutSec 5 | Select-Object Manufacturer,SMBIOSBIOSVersion,ReleaseDate | Format-List }
        Format-Section 'Uso atual' {
            'CPU: {0}%' -f (Get-SuporteCpuPercentual)
            (Get-SuporteMemoria).Resumo
        }
    }
    'desempenho' {
        Format-Section 'Resumo de uso' { (Get-SuporteMemoria).Resumo }
        Format-Section 'CPU - amostra atual' { 'CPU: {0}%' -f (Get-SuporteCpuPercentual) }
        Format-Section '5 processos com maior uso de memoria' { Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 @{n='Processo';e={$_.ProcessName}},Id,@{n='RAM_MB';e={[Math]::Round($_.WorkingSet64/1MB,1)}} | Format-Table -AutoSize -Wrap }
        'Leitura pontual. Nenhum processo e encerrado.'
    }
    'discos' {
        Format-Section 'Ocupacao por volume local' {
            foreach ($volume in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -OperationTimeoutSec 5 | Sort-Object DeviceID)) {
                if ($volume.Size -le 0 -or $null -eq $volume.FreeSpace) {
                    '[INDISPONIVEL] Volume ' + $volume.DeviceID + ': ocupacao indisponivel.'
                    continue
                }
                $usado = $volume.Size - $volume.FreeSpace
                $percentual = [Math]::Round(100*$usado/$volume.Size)
                $cheios = [int][Math]::Max(0,[Math]::Min(10,[Math]::Round($percentual/10)))
                $barra = '[' + ('#' * $cheios) + ('-' * (10-$cheios)) + ']'
                'Volume {0} ({1})  {2} {3}% usado' -f $volume.DeviceID,$volume.FileSystem,$barra,$percentual
                '  Total: {0:0.#} GiB | Usado: {1:0.#} GiB | Livre: {2:0.#} GiB' -f ($volume.Size/1GB),($usado/1GB),($volume.FreeSpace/1GB)
            }
        }
        Format-Section 'Saude dos discos internos' { Get-SuporteSmartResumo }
    }
    'bateria' {
        Format-Section 'Notebook - saude da bateria' {
            if ((Test-SuporteNotebook) -eq $false) {
                'Consulta nao se aplica a desktop ou computador sem bateria interna detectada.'
                return
            }
            $relatorio = Join-Path ([IO.Path]::GetTempPath()) ('SuporteTI-' + [guid]::NewGuid().ToString('N') + '.xml')
            try {
                Invoke-LocalNative 'powercfg.exe' ('/batteryreport /xml /output "' + $relatorio + '"') | Out-Null
                Get-SuporteBateriaResumo $relatorio
            } finally { [IO.File]::Delete($relatorio) }
        }
    }
    'filaimpressao' { Format-Section 'Diagnostico das filas de impressao' { Get-SuporteFilasImpressao } }
    'autologon' { Format-Section 'Login automatico desta estacao' { Get-SuporteResumoLogon } }
    'dispositivos' {
        Format-Section 'Dispositivos com codigo de problema' {
            $devices=@(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' -OperationTimeoutSec 8 |
                Where-Object { $_.ConfigManagerErrorCode -ne 24 -or $_.Present -ne $false })
            if ($devices.Count -eq 0) { 'Nenhum problema listado em dispositivos presentes ou de presenca desconhecida.' }
            $devices | Select-Object Name,PNPClass,@{n='Codigo';e={$_.ConfigManagerErrorCode}},Status | Format-Table -AutoSize -Wrap
            if ($devices | Where-Object ConfigManagerErrorCode -eq 24) { 'Codigo 24: o Windows indica ausencia, mau funcionamento ou driver incompleto.' }
        }
    }
    'servicos' { Format-Section 'Servicos locais (inclui parados)' { Get-Service | Select-Object Name,DisplayName,Status | Sort-Object Name | Format-Table -AutoSize -Wrap } }
    'programas' {
        Format-Section 'Programas registrados (sem Win32_Product)' {
            $paths=@('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')
            Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue | Where-Object DisplayName | Select-Object DisplayName,DisplayVersion,Publisher | Sort-Object DisplayName,DisplayVersion -Unique | Format-Table -AutoSize -Wrap
            'Inventario de programas registrados. Pode nao incluir aplicativos portateis e todos os pacotes da Store.'
        }
    }
    'falhas' {
        $codigos = New-Object 'System.Collections.Generic.List[object]'
        Format-Section 'Diagnostico de travamentos e reinicios (24h)' {
            Get-SuporteDiagnosticoFalhas -IncluirCodigos:($Opcoes['IncluirCodigos'] -eq $true) | ForEach-Object {
                if ($_ -is [string]) { $_ } else { $codigos.Add($_) }
            }
        }
        $codigos.ToArray()
    }
    'codigofalha' {
        Format-Section 'Explicacao do codigo de erro' {
            if ($Opcoes['Familia']) { Get-SuporteExplicacaoCodigo $Opcoes['Familia'] $Opcoes['Codigo'] }
            else { Get-SuporteExplicacaoAutomatica $Opcoes['Codigo'] }
        }
    }
    'eventos' {
        foreach ($log in @('System','Application')) {
            "Comando: Get-WinEvent -FilterHashtable @{LogName='$log'; StartTime=(Get-Date).AddHours(-24); Level=1,2,3} -MaxEvents 30"
            Format-Section "$log - ate 30 avisos/erros, ultimas 24h" { Get-RecentEvents $log }
        }
        'Resultados limitados por periodo e quantidade; sem apagar eventos.'
    }
    'rede' {
        Format-Section 'Configuracao de rede - ipconfig /all' { Invoke-LocalNative 'ipconfig.exe' '/all' }
    }
    'ping' { Format-Section 'Ping ICMP - quatro tentativas' { Invoke-SuportePing $Opcoes['Destino'] } }
    'velocidade' {
        'Estimativa de transferencia HTTPS ate a Cloudflare.'
        Format-Section 'Download' { Measure-SuporteVelocidade Download }
        Format-Section 'Upload' { Measure-SuporteVelocidade Upload }
    }
    'dominio' {
        Format-Section 'Dominio' {
            Get-CimInstance Win32_ComputerSystem -OperationTimeoutSec 5 |
                Select-Object Name,PartOfDomain,@{n='Domain';e={if ($_.PartOfDomain) {$_.Domain} else {'-'}}} |
                Format-List
        }
    }
    'update' {
        Format-Section 'Servicos de atualizacao' { Get-Service -Name wuauserv,bits,cryptsvc -ErrorAction Stop | Select-Object Name,Status,StartType | Format-Table -AutoSize -Wrap }
        Format-Section 'Politicas de atualizacao' {
            foreach ($path in @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate','HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU')) {
                if (Test-Path $path) { Get-ItemProperty $path | Select-Object WUServer,WUStatusServer,UseWUServer,DoNotConnectToWindowsUpdateInternetLocations,NoAutoUpdate | Format-List }
                else { 'Sem valores nesta chave: '+$path }
            }
            'Ausencia de WSUS nesta consulta nao exclui outras fontes/politicas, como MDM.'
        }
        Format-Section 'Reinicializacao pendente (indicadores)' {
            foreach ($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) { $key+': '+(Test-Path $key) }
            'Indicadores parciais; nao cobrem todos os instaladores.'
        }
        Format-Section 'Espaco do volume Windows' { Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='"+$env:SystemDrive+"'") -OperationTimeoutSec 5 | Select-Object DeviceID,@{n='Livre_GB';e={[Math]::Round($_.FreeSpace/1GB,1)}} | Format-Table }
        Format-Section 'Windows Update - ultimos 30 eventos (24h)' { Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-WindowsUpdateClient/Operational';StartTime=(Get-Date).AddHours(-24)} -MaxEvents 30 | Select-Object TimeCreated,Id,LevelDisplayName,Message | Format-List }
        Format-Section 'Proxy de servicos' { Invoke-LocalNative 'netsh.exe' 'winhttp show proxy' }
        'Nao inicia busca/download nem altera servicos. Teste a origem identificada no grupo Rede.'
    }
    'gpusuario' { Format-Section 'Resultado de politica do usuario atual' { Invoke-LocalNative 'gpresult.exe' '/Scope User /R' 15 } }
    'gpcomputador' { Format-Section 'Resultado de politica do computador' { Invoke-LocalNative 'gpresult.exe' '/Scope Computer /R' 15 } }
    default { throw 'Identificador de consulta nao autorizado.' }
}
