function Get-SuporteSmartClassificacao {
    param([Parameter(Mandatory)]$Dados)
    $reasons=New-Object 'System.Collections.Generic.List[string]'
    $state='Inconclusivo'
    $status=$Dados.PSObject.Properties['smart_status']
    if ($status -and $status.Value.PSObject.Properties['passed']) {
        if ($status.Value.passed -eq $true) { $state='Sem alertas detectados'; $reasons.Add('SMART global aprovado pelo dispositivo.') }
        elseif ($status.Value.passed -eq $false) { $state='Critico/degradado'; $reasons.Add('O dispositivo informa falha na avaliacao SMART.') }
    }
    $nvme=$Dados.PSObject.Properties['nvme_smart_health_information_log']
    if ($nvme) {
        $log=$nvme.Value
        if ($log.PSObject.Properties['critical_warning'] -and [int]$log.critical_warning -ne 0) { $state='Critico/degradado'; $reasons.Add('NVMe informa alerta critico: '+$log.critical_warning) }
        if ($log.PSObject.Properties['percentage_used'] -and [double]$log.percentage_used -ge 100) {
            if ($state -ne 'Critico/degradado') { $state='Atencao' }; $reasons.Add('Limite estimado de desgaste NVMe atingido; nao e percentual de vida restante.')
        }
        if ($log.PSObject.Properties['media_errors'] -and [double]$log.media_errors -gt 0) {
            if ($state -ne 'Critico/degradado') { $state='Atencao' }; $reasons.Add('Erros de integridade de midia acumulados; verificar evolucao.')
        }
    }
    $ata=$Dados.PSObject.Properties['ata_smart_attributes']
    if ($ata -and $ata.Value.PSObject.Properties['table']) {
        foreach ($attr in $ata.Value.table) {
            if ($attr.id -in @(5,197,198) -and $attr.PSObject.Properties['raw'] -and $attr.raw.PSObject.Properties['value'] -and [double]$attr.raw.value -gt 0) {
                if ($state -ne 'Critico/degradado') { $state='Atencao' }
                $reasons.Add('Atributo ATA '+$attr.id+' ('+$attr.name+'): '+$attr.raw.value+'. Avaliar conforme modelo/fabricante.')
            }
        }
    }
    if ($reasons.Count -eq 0) { $reasons.Add('SMART completo nao disponivel. Nao presumir saude normal.') }
    [pscustomobject]@{Estado=$state;Motivos=($reasons -join ' ')}
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
        # Bits 0..2 indicam erro de comando/abertura/leitura; bits altos podem representar alertas de saude.
        if (($process.ExitCode -band 7) -ne 0) { throw ('Leitura SMART indisponivel ou incompleta (codigo '+$process.ExitCode+'). Pode requerer administrador ou outra controladora.') }
        $data
    } finally { $process.Dispose() }
}

function Get-SuporteSmartResumo {
    $scan=Invoke-SuporteSmartJson @('--scan','-j') 5
    if (-not $scan.PSObject.Properties['devices'] -or @($scan.devices).Count -eq 0) { throw 'Nenhum dispositivo SMART detectado.' }
    $devices=@($scan.devices)
    if ($devices.Count -gt 4) { 'Consulta rapida limitada aos primeiros quatro dispositivos.' }
    foreach ($device in ($devices | Select-Object -First 4)) {
        try {
            $argsList=@('-a','-j','-n','standby','-d',[string]$device.type,[string]$device.name)
            $data=Invoke-SuporteSmartJson $argsList 6
            $class=Get-SuporteSmartClassificacao $data
            $model='Nao informado'; if ($data.PSObject.Properties['model_name']) { $model=$data.model_name }
            $temp='Indisponivel'; if ($data.PSObject.Properties['temperature'] -and $data.temperature.PSObject.Properties['current']) { $temp=$data.temperature.current }
            [pscustomobject]@{Dispositivo=$device.name;Modelo=$model;Resultado=$class.Estado;Motivo=$class.Motivos;Temperatura_C=$temp;Recomendacao=$(if($class.Estado -eq 'Critico/degradado'){'Priorizar backup e avaliar substituicao.'}elseif($class.Estado -eq 'Atencao'){'Conferir backup e avaliar indicadores e evolucao.'}else{'Leitura pontual; nao garante ausencia de defeito.'})} | Format-List | Out-String -Width 140
        } catch { '[INDISPONIVEL] '+$device.name+': '+$_.Exception.Message }
    }
}
