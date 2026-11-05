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
    Write-Host 'CPU e RAM ao vivo. Pressione Q, Esc ou Enter para voltar. Limite de 60 segundos.'
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
                if ([Console]::KeyAvailable -and [Console]::ReadKey($true).Key -in @('Q','Escape','Enter')) { return }
                Start-Sleep -Milliseconds 100
            }
        }
    } catch { Write-Host ('Monitor indisponivel: ' + $_.Exception.Message) }
    finally {
        Write-Progress -Id 51 -Activity 'CPU' -Completed
        Write-Progress -Id 52 -Activity 'Memoria RAM' -Completed
    }
}
