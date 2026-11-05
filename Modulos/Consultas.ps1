param([Parameter(Mandatory)][string]$Id, [hashtable]$Opcoes=@{})
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Recursos.ps1')
. (Join-Path $PSScriptRoot 'Rede.ps1')

function Format-Section {
    param([string]$Title,[scriptblock]$Query)
    "`r`n--- $Title ---"
    try { & $Query | Out-String -Width 160 | ForEach-Object { $_.TrimEnd() } }
    catch {
        if ($_.Exception -is [UnauthorizedAccessException] -or $_.Exception.Message -match 'denied|negado') { '[ACESSO NEGADO] ' + $Title }
        elseif ($_.FullyQualifiedErrorId -match 'NoMatchingEventsFound') { 'Nenhum evento correspondente no periodo consultado.' }
        else { '[INDISPONIVEL] ' + $Title + ': ' + $_.Exception.Message }
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
        Format-Section '5 processos com maior uso de memoria' { Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 @{n='Processo';e={$_.ProcessName}},Id,@{n='RAM_MB';e={[Math]::Round($_.WorkingSet64/1MB,1)}} | Format-Table -AutoSize }
        'Leitura pontual. Nenhum processo e encerrado.'
    }
    'discos' {
        Format-Section 'Ocupacao por volume local' {
            Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -OperationTimeoutSec 5 |
                Select-Object DeviceID,FileSystem,
                    @{n='Total_GiB';e={if ($null -ne $_.Size) {[Math]::Round($_.Size/1GB,1)}}},
                    @{n='Usado_GiB';e={if ($_.Size -gt 0 -and $null -ne $_.FreeSpace) {[Math]::Round(($_.Size-$_.FreeSpace)/1GB,1)}}},
                    @{n='Livre_GiB';e={if ($null -ne $_.FreeSpace) {[Math]::Round($_.FreeSpace/1GB,1)}}},
                    @{n='Uso_%';e={if ($_.Size -gt 0 -and $null -ne $_.FreeSpace) {[Math]::Round(100*($_.Size-$_.FreeSpace)/$_.Size)}}},
                    @{n='Ocupacao';e={if ($_.Size -gt 0 -and $null -ne $_.FreeSpace) {
                        $cheios = [int][Math]::Max(0,[Math]::Min(10,[Math]::Round(10*($_.Size-$_.FreeSpace)/$_.Size)))
                        '[' + ('#' * $cheios) + ('-' * (10-$cheios)) + ']'
                    }}} |
                Format-Table -AutoSize
        }
        Format-Section 'SMART/NVMe - consulta rapida' { & (Get-Module SuporteTI) { Get-SuporteSmartResumo } }
        Format-Section 'Saude nativa dos dispositivos' {
            $disks=@(Get-PhysicalDisk -ErrorAction Stop)
            if ($disks.Count -eq 0) { throw 'Nenhum dispositivo visivel pelo provedor.' }
            foreach ($disk in $disks) {
                $counter=$null; $limitation=''
                try { $counter=$disk | Get-StorageReliabilityCounter -ErrorAction Stop } catch { $limitation='Contadores indisponiveis: '+$_.Exception.Message }
                $wear=$null; $read=$null; $write=$null
                if ($counter) { $wear=$counter.Wear; $read=$counter.ReadErrorsUncorrected; $write=$counter.WriteErrorsUncorrected }
                $class=Get-SuporteDiscoClassificacao -HealthStatus ([string]$disk.HealthStatus) -Wear $wear -ReadErrorsUncorrected $read -WriteErrorsUncorrected $write
                [pscustomobject]@{Disco=$disk.DeviceId;Modelo=$disk.FriendlyName;Tipo=$disk.MediaType;Resultado=$class.Estado;Motivo=$class.Motivos;Temperatura_C=$(if($counter){$counter.Temperature}else{'Indisponivel'});Desgaste_percentual=$wear;Horas_ligado=$(if($counter){$counter.PowerOnHours}else{$null});Limitacoes=($class.Limite+' '+$limitation)} | Format-List
            }
        }
    }
    'dispositivos' {
        Format-Section 'Dispositivos com codigo de problema' {
            $devices=@(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' -OperationTimeoutSec 8 |
                Where-Object { $_.ConfigManagerErrorCode -ne 24 -or $_.Present -ne $false })
            if ($devices.Count -eq 0) { 'Nenhum problema listado em dispositivos presentes ou de presenca desconhecida.' }
            $devices | Select-Object Name,PNPClass,ConfigManagerErrorCode,Status | Format-Table -AutoSize
            if ($devices | Where-Object ConfigManagerErrorCode -eq 24) { 'Codigo 24: o Windows indica ausencia, mau funcionamento ou driver incompleto.' }
        }
    }
    'servicos' { Format-Section 'Servicos locais (inclui parados)' { Get-Service | Select-Object Name,DisplayName,Status | Sort-Object Name | Format-Table -AutoSize } }
    'programas' {
        Format-Section 'Programas registrados (sem Win32_Product)' {
            $paths=@('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')
            Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue | Where-Object DisplayName | Select-Object DisplayName,DisplayVersion,Publisher | Sort-Object DisplayName,DisplayVersion -Unique | Format-Table -AutoSize
            'Inventario de programas registrados. Pode nao incluir aplicativos portateis e todos os pacotes da Store.'
        }
    }
    {$_ -in @('falhas','eventos')} {
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
        Format-Section 'Servicos de atualizacao' { Get-Service -Name wuauserv,bits,cryptsvc -ErrorAction Stop | Select-Object Name,Status,StartType | Format-Table -AutoSize }
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
