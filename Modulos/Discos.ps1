function Get-SuporteSmartValor {
    param($Objeto,[string]$Nome)
    if ($null -ne $Objeto) {
        $propriedade = $Objeto.PSObject.Properties[$Nome]
        if ($propriedade) { $propriedade.Value }
    }
}

function Test-SuporteKingstonA400 {
    param($Dados)
    (Get-SuporteSmartValor $Dados 'model_name') -match '^KINGSTON +SA400(M8|S37)(120|240|480|960)G$'
}

function Get-SuporteSmartDesgaste {
    param($Dados,$Nvme,$Atributos)
    if ((Get-SuporteSmartValor $Dados 'rotation_rate') -gt 0) { return }
    if (Test-SuporteKingstonA400 $Dados) {
        $firmware = Get-SuporteSmartValor $Dados 'firmware_version'
        $atributo = $Atributos | Where-Object id -eq 231 | Select-Object -First 1
        # No A400 SBFK, o E7 bruto e a resistencia restante. O smartctl 7.5 calcula o agregado pelo valor normalizado.
        $restante = if ($firmware -like 'SBFK*') {
            Get-SuporteSmartValor (Get-SuporteSmartValor $atributo 'raw') 'value'
        } elseif ($firmware -like '03070009*') {
            Get-SuporteSmartValor $atributo 'value'
        }
        if ("$restante" -match '^\d{1,3}$' -and [int]$restante -le 100) { return (100 - [int]$restante) }
        return
    }
    $valor = Get-SuporteSmartValor $Nvme 'percentage_used'
    if ($null -eq $valor) {
        $valor = Get-SuporteSmartValor (Get-SuporteSmartValor $Dados 'endurance_used') 'current_percent'
    }
    if ($null -ne $valor -and "$valor" -match '^\d{1,3}$' -and [int]$valor -le 255) { return [int]$valor }

    # Crucial MX500: CAh e percentual restante na coluna normalizada, usado na coluna bruta.
    # O modelo e a concordancia das duas colunas evitam generalizar a regra para outros SSDs.
    if ((Get-SuporteSmartValor $Dados 'model_name') -match '^CT(250|500|[124]000)MX500SSD[14]$') {
        $atributo = $Atributos | Where-Object { $_.id -eq 202 } | Select-Object -First 1
        $restante = Get-SuporteSmartValor $atributo 'value'
        $usado = Get-SuporteSmartValor (Get-SuporteSmartValor $atributo 'raw') 'value'
        if ("$restante" -match '^\d{1,3}$' -and "$usado" -match '^\d{1,3}$' -and
            [int]$usado -le 255 -and [int]$restante -eq [Math]::Max(100 - [int]$usado,0)) { return [int]$usado }
    }
}

function Get-SuporteSmartClassificacao {
    param($Dados,[int]$Codigo)
    $estado = 'Inconclusivo'
    $motivo = 'Indicadores SMART insuficientes.'
    $smart = Get-SuporteSmartValor $Dados 'smart_status'
    $status = Get-SuporteSmartValor $smart 'passed'
    $nvme = Get-SuporteSmartValor $Dados 'nvme_smart_health_information_log'
    $ata = @(Get-SuporteSmartValor (Get-SuporteSmartValor $Dados 'ata_smart_attributes') 'table')
    $desgaste = Get-SuporteSmartDesgaste $Dados $nvme $ata
    # O smartctl marca passed=false para qualquer aviso NVMe, inclusive temperatura.
    $statusNvme = Get-SuporteSmartValor $smart 'nvme'
    $protocolo = Get-SuporteSmartValor (Get-SuporteSmartValor $Dados 'device') 'protocol'
    $ehNvme = $null -ne $nvme -or $null -ne $statusNvme -or $protocolo -eq 'NVMe'
    $avisoNvme = [int](Get-SuporteSmartValor $nvme 'critical_warning') -bor [int](Get-SuporteSmartValor $statusNvme 'value')
    $smartFalhou = $status -is [bool] -and -not $status
    $setores = $ata | Where-Object {
        (($_.id -eq 5 -and $_.name -eq 'Reallocated_Sector_Ct') -or
         ($_.id -eq 197 -and $_.name -eq 'Current_Pending_Sector') -or
         ($_.id -eq 198 -and $_.name -eq 'Offline_Uncorrectable')) -and
        (Get-SuporteSmartValor (Get-SuporteSmartValor $_ 'raw') 'value') -gt 0
    } | Select-Object -First 1

    # Bits 2, 3 e 5 indicam perda de confiabilidade ou modo somente leitura.
    if ($avisoNvme -band 0x2C) {
        $estado = 'Critico/degradado'
        $motivo = if ($avisoNvme -band 8) { 'A midia do SSD NVMe entrou em modo somente leitura.' }
            else { 'O SSD NVMe informa perda de confiabilidade.' }
    } elseif (-not $ehNvme -and ($smartFalhou -or ($protocolo -eq 'ATA' -and ($Codigo -band 8)))) {
        $estado = 'Critico/degradado'
        $motivo = 'O disco informa falha SMART.'
    } elseif ($avisoNvme -band 1) {
        $estado = 'Atencao'
        $motivo = 'A reserva do SSD NVMe caiu abaixo do limite informado pelo disco.'
    } elseif ((Get-SuporteSmartValor $nvme 'media_errors') -gt 0) {
        $estado = 'Atencao'
        $motivo = 'O SSD NVMe registra erros de integridade da midia.'
    } elseif ($avisoNvme -band 2) {
        $estado = 'Atencao'
        $motivo = 'A temperatura do SSD NVMe esta fora do limite informado pelo disco.'
    } elseif ($avisoNvme -or ($ehNvme -and $smartFalhou)) {
        $estado = 'Atencao'
        $motivo = 'O SSD NVMe informa outro alerta de saude.'
    } elseif ($setores) {
        $estado = 'Atencao'
        $motivo = switch ($setores.id) {
            197 { 'O disco tem setores pendentes.' }
            198 { 'O disco tem setores incorrigiveis.' }
            5 { 'O disco tem setores realocados.' }
        }
    } elseif ($protocolo -eq 'ATA' -and ($Codigo -band 144)) {
        $estado = 'Atencao'
        $motivo = 'O disco tem atributo SMART fora do limite ou registro de autoteste com erro.'
    } elseif ($Codigo -band 4) {
        $motivo = 'Leitura SMART parcial; indicadores insuficientes para concluir.'
    } elseif ($status -eq $true) {
        $estado = 'Sem alertas detectados'
        $motivo = 'Nenhum alerta nos indicadores verificados.'
    }
    [pscustomobject]@{Estado=$estado;Motivos=$motivo;Desgaste=$desgaste}
}

function Invoke-SuporteSmartJson {
    param([string[]]$Argumentos,[int]$TimeoutSeconds=6)
    $base=Join-Path (Split-Path $PSScriptRoot -Parent) 'Ferramentas\smartmontools'
    $exe=Join-Path $base 'bin\smartctl.exe'
    $manifestPath=Join-Path $base 'integridade.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'Manifesto do smartctl ausente; usando apenas diagnostico nativo.' }
    $manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    foreach ($file in @('smartctl.exe','drivedb.h')) {
        $path=Join-Path $base ('bin\'+$file)
        $expected=$manifest.PSObject.Properties[$file].Value
        if (-not $expected -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $expected) { throw ('Integridade divergente: '+$file) }
    }
    # Argumentos sao definidos pelo coletor, nunca texto livre do menu.
    foreach ($arg in $Argumentos) { if ($arg -notmatch '^[a-zA-Z0-9_./,:=+\-]+$') { throw 'Parametro smartctl invalido.' } }
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$exe; $psi.Arguments=$Argumentos -join ' '; $psi.UseShellExecute=$false
    $psi.CreateNoWindow=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    $process=New-Object Diagnostics.Process; $process.StartInfo=$psi
    try {
        [void]$process.Start()
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds*1000)) { $process.Kill(); throw 'Consulta SMART excedeu o limite; resultado inconclusivo.' }
        $process.WaitForExit()
        $data=$stdout.Result | ConvertFrom-Json -ErrorAction Stop
        # O bit 2 pode coexistir com dados validos e alertas. Os bits 0 e 1 impedem a leitura do disco.
        if ($process.ExitCode -band 3) { throw 'SMART indisponivel. O disco pode estar em repouso ou exigir acesso administrativo.' }
        [pscustomobject]@{Dados=$data;Codigo=$process.ExitCode}
    } finally { $process.Dispose() }
}

function Get-SuporteSmartResumo {
    $discos = @(Get-Disk -ErrorAction Stop | Where-Object { $_.BusType -in @('ATA','SATA','NVMe','SAS') } | Sort-Object Number)
    if ($discos.Count -eq 0) { 'Nenhum disco interno compativel identificado.'; return }
    if ($discos.Count -gt 4) { '[INDISPONIVEL] Consulta limitada aos primeiros quatro discos internos.' }
    foreach ($disco in ($discos | Select-Object -First 4)) {
        $classe = Get-SuporteSmartClassificacao
        $parcial = $false
        $rotacao = $null
        $dados = $null
        try {
            if ($disco.Number -gt 255) { throw 'Numero de disco fora da faixa suportada pelo smartctl.' }
            $argumentos = @('-a','-j','-n','standby')
            if ($disco.BusType -eq 'NVMe') { $argumentos += @('-d','nvme') }
            $leitura = Invoke-SuporteSmartJson ($argumentos + ('/dev/pd' + [uint32]$disco.Number))
            $dados = $leitura.Dados
            $classe = Get-SuporteSmartClassificacao $dados $leitura.Codigo
            $parcial = ($leitura.Codigo -band 4) -ne 0
            $rotacao = Get-SuporteSmartValor $dados 'rotation_rate'
        } catch {
            $classe.Motivos = $_.Exception.Message
        }
        $contadores = $null
        try { $contadores = Get-StorageReliabilityCounter -Disk $disco -ErrorAction Stop } catch {}
        $desgaste = $classe.Desgaste
        # O Windows pode retornar zero em Wear mesmo para HDDs. Use esse contador so em SSD confirmado.
        if ($null -eq $desgaste -and -not (Test-SuporteKingstonA400 $dados) -and
            ($disco.BusType -eq 'NVMe' -or ($null -ne $rotacao -and $rotacao -eq 0))) {
            $desgaste = Get-SuporteSmartValor $contadores 'Wear'
        }
        $nativo = Get-SuporteDiscoClassificacao -HealthStatus ([string]$disco.HealthStatus) `
            -ReadErrorsUncorrected (Get-SuporteSmartValor $contadores 'ReadErrorsUncorrected') `
            -WriteErrorsUncorrected (Get-SuporteSmartValor $contadores 'WriteErrorsUncorrected')
        if ($classe.Estado -ne 'Critico/degradado' -and ($nativo.Estado -eq 'Critico/degradado' -or
            ($nativo.Estado -eq 'Atencao' -and $classe.Estado -ne 'Atencao'))) {
            $classe.Estado = $nativo.Estado
            $classe.Motivos = if ($nativo.Estado -eq 'Critico/degradado') { 'O Windows informa que o disco esta degradado.' }
                else { 'Os indicadores de armazenamento do Windows sinalizam atencao.' }
        }
        if ($desgaste -ge 80 -and $classe.Estado -in @('Sem alertas detectados','Inconclusivo')) {
            $classe.Estado = 'Atencao'
            $classe.Motivos = if ($desgaste -ge 100) { 'O SSD atingiu o limite de desgaste estimado.' }
                else { 'Desgaste elevado. Planeje uma troca preventiva.' }
        }
        $resultado = switch ($classe.Estado) {
            'Critico/degradado' { 'Troca recomendada'; break }
            'Atencao' { 'Atencao - avaliar troca'; break }
            default { $classe.Estado }
        }
        $resumo = 'Disco {0} ({1}): {2}. {3}' -f $disco.Number,$disco.FriendlyName,$resultado,$classe.Motivos
        if ($classe.Estado -eq 'Inconclusivo') { $resumo = '[INDISPONIVEL] ' + $resumo }
        if ($classe.Estado -eq 'Critico/degradado') { $resumo += ' Priorize o backup.' }
        if ($null -ne $desgaste) {
            $resumo += ' Desgaste estimado: {0}% usado. Resistencia restante: {1}%.' -f $desgaste,[Math]::Max(0,100 - $desgaste)
        }
        if ($parcial -and $classe.Estado -ne 'Inconclusivo') { $resumo += ' Leitura SMART parcial.' }
        $resumo
    }
}
