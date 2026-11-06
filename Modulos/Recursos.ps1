function Import-SuporteWindows {
    if (-not ('SuporteTI.LogonNativo' -as [type])) {
        # Carregar pelos bytes evita bloquear o arquivo, permitindo remover a copia temporaria da janela elevada.
        [void][Reflection.Assembly]::Load([IO.File]::ReadAllBytes((Join-Path (Split-Path $PSScriptRoot -Parent) 'Recursos\SuporteTI.Windows.dll')))
    }
}

function Show-SuporteMapaOcupacao {
    if (-not [Environment]::UserInteractive) { throw 'O mapa precisa de uma sessao grafica do Windows.' }
    Import-SuporteWindows
    $janela = New-Object SuporteTI.MapaOcupacao
    try { [void]$janela.ShowDialog() } finally { $janela.Dispose() }
}

function Get-SuporteCpuPercentual {
    $loads = @(Get-CimInstance Win32_Processor -OperationTimeoutSec 3 -ErrorAction Stop |
        Where-Object { $null -ne $_.LoadPercentage } | Select-Object -ExpandProperty LoadPercentage)
    if ($loads.Count -eq 0) { throw 'Carga de CPU indisponivel.' }
    [int][Math]::Round(($loads | Measure-Object -Average).Average)
}

function Get-SuporteMemoria {
    $os = Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 3 -ErrorAction Stop
    $total = [double]$os.TotalVisibleMemorySize
    $livre = [double]$os.FreePhysicalMemory
    if ($total -le 0 -or $livre -lt 0 -or $livre -gt $total) { throw 'Dados de memoria indisponiveis.' }
    $usado = $total - $livre
    [pscustomobject]@{
        Percentual = [int][Math]::Round(100 * $usado / $total)
        Resumo = 'RAM: {0:N1} GB usados de {1:N1} GB ({2:N0}%) | Livre: {3:N1} GB' -f ($usado/1MB),($total/1MB),(100*$usado/$total),($livre/1MB)
    }
}

function Show-SuporteMonitor {
    if ([Console]::IsInputRedirected) {
        Write-Host 'O monitor ao vivo precisa de uma janela interativa. Use o resumo de desempenho nesta sessao.'
        return
    }
    Write-SuporteLinha 'CPU e RAM ao vivo | 0, Enter, Q ou Esc para voltar | Limite: 60 s' -SemCores
    $tempo = [Diagnostics.Stopwatch]::StartNew()
    try {
        while ($tempo.Elapsed.TotalSeconds -lt 60) {
            try {
                $cpu = Get-SuporteCpuPercentual
                Write-Progress -Id 51 -Activity 'CPU' -Status "$cpu%" -PercentComplete $cpu
            } catch { Write-Progress -Id 51 -Activity 'CPU' -Status 'Leitura indisponivel' }
            try {
                $memoria = Get-SuporteMemoria
                Write-Progress -Id 52 -Activity 'Memoria RAM' -Status $memoria.Resumo -PercentComplete $memoria.Percentual
            } catch { Write-Progress -Id 52 -Activity 'Memoria RAM' -Status 'Leitura indisponivel' }
            for ($passo = 0; $passo -lt 10; $passo++) {
                if ([Console]::KeyAvailable -and [Console]::ReadKey($true).Key -in @('Q','Escape','Enter','D0','NumPad0')) { return }
                Start-Sleep -Milliseconds 100
            }
        }
    } catch { Write-Host ('Monitor indisponivel: ' + $_.Exception.Message) }
    finally {
        Write-Progress -Id 51 -Activity 'CPU' -Completed
        Write-Progress -Id 52 -Activity 'Memoria RAM' -Completed
    }
}

function Test-SuporteNotebook {
    try {
        $gabinetes = Get-CimInstance Win32_SystemEnclosure -OperationTimeoutSec 3 -ErrorAction Stop
        foreach ($gabinete in $gabinetes) {
            if (@($gabinete.ChassisTypes | Where-Object { $_ -in @(8,9,10,11,14,30,31,32) }).Count) { return $true }
        }
    } catch {}
    try {
        $baterias = Get-CimInstance Win32_Battery -OperationTimeoutSec 3 -ErrorAction Stop
        return @($baterias | Where-Object { $_.PNPDeviceID -like 'ACPI\*' }).Count -gt 0
    } catch { return $null }
}
function Get-SuporteBateriaResumo {
    param([Parameter(Mandatory)][string]$Caminho)

    $config = New-Object System.Xml.XmlReaderSettings
    $config.DtdProcessing = 'Prohibit'
    $config.XmlResolver = $null
    $config.MaxCharactersInDocument = 32MB
    $xml = New-Object System.Xml.XmlDocument
    $xml.XmlResolver = $null
    $leitor = [System.Xml.XmlReader]::Create($Caminho,$config)
    try { $xml.Load($leitor) } finally { $leitor.Dispose() }

    $instaladas = $xml.SelectSingleNode('/*[local-name()="BatteryReport"]/*[local-name()="Batteries" or local-name()="InstalledBatteries"]')
    if (-not $instaladas) { throw 'O relatorio do Windows nao informou as baterias instaladas.' }
    $baterias = $instaladas.SelectNodes('./*[local-name()="Battery"]')
    if ($baterias.Count -eq 0) { 'Nenhuma bateria detectada. Esta consulta so se aplica a computadores com bateria interna.'; return }
    $indice = 0
    foreach ($bateria in $baterias) {
        $indice++
        $projeto = $bateria.SelectSingleNode('./*[local-name()="DesignCapacity"]')
        $cargaCompleta = $bateria.SelectSingleNode('./*[local-name()="FullChargeCapacity"]')
        $original = 0L; $atual = 0L
        if (-not ($projeto -and $cargaCompleta -and
            [long]::TryParse($projeto.InnerText,[ref]$original) -and [long]::TryParse($cargaCompleta.InnerText,[ref]$atual) -and
            $original -gt 0 -and $original -lt [uint32]::MaxValue -and $atual -gt 0 -and $atual -lt [uint32]::MaxValue)) {
            "[INDISPONIVEL] Bateria ${indice}: Capacidade nao informada."
            continue
        }
        'Bateria {0}: {1:0.#}% da capacidade original ({2:0.##} Wh de {3:0.##} Wh).' -f $indice,(100.0*$atual/$original),($atual/1000.0),($original/1000.0)
    }
}
