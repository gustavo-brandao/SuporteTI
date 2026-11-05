function Get-SuporteTipoFalha {
    param($Evento)
    switch -Regex ('{0}/{1}/{2}' -f $Evento.LogName,$Evento.ProviderName,$Evento.Id) {
        '^System/(Microsoft-Windows-WER-SystemErrorReporting|BugCheck)/1001$' { 'Parada' }
        '^System/Microsoft-Windows-Kernel-Power/41$' { 'Reinicio' }
        '^System/EventLog/6008$' { 'Reinicio' }
        '^System/(User32|Microsoft-Windows-User32)/1074$' { 'Solicitado' }
        '^System/Microsoft-Windows-Kernel-General/12$' { 'Inicio' }
        '^Application/Application Error/1000$' { 'Aplicativo' }
        '^Application/Application Hang/1002$' { 'Travamento' }
        '^System/Microsoft-Windows-WHEA-Logger/' { 'Hardware' }
        '^System/disk/(7|51|153|157)$' { 'Disco' }
        '^System/(storahci|stornvme|storport|Microsoft-Windows-StorPort|iaStor[A-Z]*)/129$' { 'Disco' }
        '^System/Display/4101$' { 'Video' }
    }
}

function Get-SuporteDadosEvento {
    param($Evento)
    $dados = @{}
    if ($Evento.PSObject.Methods['ToXml']) {
        try {
            $xml = [xml]$Evento.ToXml()
            foreach ($campo in $xml.SelectNodes("/*[local-name()='Event']/*[local-name()='EventData']/*[local-name()='Data']")) {
                $nome = $campo.GetAttribute('Name')
                if ($nome) { $dados[$nome] = $campo.InnerText }
            }
        } catch { return @{} }
    }
    $dados
}

function Read-SuporteCatalogoFalhas {
    $arquivo = Join-Path $PSScriptRoot 'CatalogoFalhas.json'
    $catalogo = Get-Content -LiteralPath $arquivo -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($catalogo.Versao -ne 2 -or $catalogo.Paradas -isnot [pscustomobject] -or $catalogo.Excecoes -isnot [pscustomobject] -or
        $catalogo.Win32 -isnot [pscustomobject] -or $catalogo.HRESULT -isnot [pscustomobject]) {
        throw 'Formato de catalogo invalido.'
    }
    $catalogo
}

function Find-SuporteCodigoFalha {
    param($Catalogo,[string]$Familia,[uint32]$Codigo)
    $hex = '{0:X8}' -f $Codigo
    $entrada = if ($Catalogo) { $Catalogo.$Familia.PSObject.Properties[$hex] }
    $regra = if ($entrada) { $entrada.Value }
    $resumo = if ($regra -and $regra.PSObject.Properties['Resumo']) { $regra.Resumo }
    $podeLerMensagem = $regra -or $Familia -eq 'Win32' -or ($Familia -eq 'HRESULT' -and $hex.StartsWith('8007'))
    if (-not $resumo -and $Familia -ne 'Paradas' -and $podeLerMensagem) {
        try {
            Import-SuporteWindows
            $resumo = [SuporteTI.MensagensWindows]::Ler($Codigo, $Familia -eq 'Excecoes')
        } catch { $resumo = $null }
    }
    if (-not $resumo -and -not $regra) { return }
    $fonte = if ($regra) { $Catalogo.Fontes.($regra.Fonte) }
    if ($regra -and $regra.PSObject.Properties['Referencia']) {
        $fonte = 'https://learn.microsoft.com/pt-br/windows-hardware/drivers/debugger/' + $regra.Referencia
    }
    [pscustomobject]@{
        Nome = $(if ($regra) { $regra.Nome })
        Resumo = $resumo
        Investigar = $(if ($regra -and $regra.PSObject.Properties['Investigar']) { $regra.Investigar })
        Fonte = $fonte
    }
}

function Get-SuporteExplicacaoCodigo {
    param([string]$Familia,[string]$Entrada)
    if ($Familia -notin 'Paradas','Excecoes','Win32','HRESULT') { throw 'Selecione uma familia de codigo valida.' }
    $codigo = [uint32]0
    if ($Entrada -match '^0x([0-9a-f]{1,8})$') { $codigo = [Convert]::ToUInt32($Matches[1],16) }
    elseif ($Familia -in 'HRESULT','Excecoes' -and $Entrada -match '^-[0-9]{1,10}$' -and [long]$Entrada -ge [int]::MinValue) {
        $codigo = [uint32]([long]$Entrada + 4294967296)
    }
    elseif ($Entrada -notmatch '^\d{1,10}$' -or -not [uint32]::TryParse($Entrada,[ref]$codigo)) {
        throw 'Informe um numero decimal ou hexadecimal com prefixo 0x.'
    }
    if ($Familia -eq 'Win32' -and $codigo -gt 65535) { throw 'Informe um codigo Win32 de ate 16 bits. Para valores como 0x80070005, selecione HRESULT.' }
    if ($Familia -in 'HRESULT','Excecoes' -and $codigo -lt 2147483648) { throw 'A familia selecionada requer um codigo de erro ou aviso de 32 bits.' }
    $catalogo = $null
    try { $catalogo = Read-SuporteCatalogoFalhas }
    catch { '[INDISPONIVEL] Catalogo offline. O Windows ainda pode fornecer uma mensagem para esta familia.' }
    $resultado = Find-SuporteCodigoFalha $catalogo $Familia $codigo
    '{0} | {1} (0x{1:X8})' -f $Familia,$codigo
    if ($resultado -and $resultado.Resumo) { $resultado.Resumo }
    else { 'Descricao em portugues indisponivel para este codigo.' }
    if (-not $resultado) { return }
    if ($resultado.Nome) { 'Nome tecnico: ' + $resultado.Nome }
    if ($resultado.Investigar) { 'O que investigar: ' + $resultado.Investigar }
    if ($resultado.Fonte) { 'Referencia: ' + $resultado.Fonte }
}

function Get-SuporteResumoIncidente {
    param($Evento,[string]$Tipo,$Catalogo)
    $dados = Get-SuporteDadosEvento $Evento
    $codigo = [uint32]0
    $familia = $null
    if ($Tipo -eq 'Parada' -and $dados['param1'] -match '^\s*0x([0-9a-f]{1,8})(?:\s|\(|$)') {
        $codigo = [Convert]::ToUInt32($Matches[1],16)
    } elseif ($Tipo -eq 'Reinicio' -and $Evento.Id -eq 41) {
        [void][uint32]::TryParse([string]$dados['BugcheckCode'],[ref]$codigo)
    }
    $titulo = $null
    $pista = $null
    $detalhe = $null
    if ($Tipo -eq 'Parada' -or $codigo -gt 0) {
        $titulo = 'O Windows registrou uma tela azul.'
        if ($codigo -gt 0) {
            $familia = 'Paradas'
            $hex = '{0:X8}' -f $codigo
            $regra = Find-SuporteCodigoFalha $Catalogo 'Paradas' $codigo
            $detalhe = "Codigo de parada 0x$hex"
            if ($regra) {
                $detalhe += ' - ' + $regra.Nome
                if ($regra.Resumo) { $titulo = 'Tela azul. ' + $regra.Resumo }
                $pista = if ($regra.Investigar) { $regra.Investigar } else { 'O catalogo identificou o nome tecnico. Consulte a referencia para interpretar os parametros do codigo.' }
                if ($regra.Fonte -and -not $regra.Resumo) { $detalhe += ' | ' + $regra.Fonte }
            } else { $pista = 'O codigo ainda nao tem descricao no catalogo local. Use-o para investigar a falha.' }
        } else { $pista = 'O registro confirma a parada, mas o codigo nao estava disponivel.' }
        if ($dados['param2'] -match '\.dmp\s*$') { $detalhe = (@($detalhe,'O Windows informou ter gravado um arquivo de despejo (.dmp).') -ne $null) -join ' | ' }
    } else {
        switch ($Tipo) {
            'Reinicio' {
                $titulo = 'O computador reiniciou sem concluir o desligamento.'
                $pista = 'Os registros disponiveis nao identificam o motivo. Procure sinais proximos ao reinicio.'
            }
            'Solicitado' {
                $titulo = 'Um processo solicitou o desligamento ou reinicio.'
                if ($dados['param1']) { $detalhe = 'Processo: ' + $dados['param1'] }
            }
            { $_ -in 'Aplicativo','Travamento' } {
                $app = if ($dados['AppName']) { $dados['AppName'] } else { $dados['param1'] }
                if (-not $app) { $app = 'Um aplicativo' }
                $titulo = if ($Tipo -eq 'Aplicativo') { "$app fechou inesperadamente." } else { "$app parou de responder." }
                $pista = 'Verifique se a falha se repete com esse aplicativo.'
                if ($dados['ModuleName']) { $detalhe = 'Modulo registrado: ' + $dados['ModuleName'] }
            }
            'Hardware' {
                $titulo = 'O Windows registrou um alerta de hardware (WHEA).'
                $pista = 'Confira os detalhes do evento para identificar o componente. O alerta por si so nao comprova que uma peca precisa ser trocada.'
            }
            'Disco' {
                $titulo = switch ($Evento.Id) {
                    7 { 'O Windows relatou um bloco defeituoso no disco.' }
                    51 { 'O Windows registrou uma falha de entrada ou saida no armazenamento.' }
                    129 { 'O controlador de armazenamento reiniciou um dispositivo apos falta de resposta.' }
                    153 { 'Uma operacao de leitura ou gravacao no disco precisou ser repetida.' }
                    157 { 'O Windows detectou que um disco foi desconectado inesperadamente.' }
                }
                $pista = 'Verifique a saude do disco e se os alertas voltam a ocorrer.'
            }
            'Video' {
                $titulo = 'O driver de video parou de responder e o Windows conseguiu recupera-lo.'
                $pista = 'Se ocorrer novamente, investigue o driver e o subsistema grafico.'
            }
            default {
                $titulo = 'O Windows registrou um erro sem interpretacao no catalogo local.'
                $pista = 'Consulte a mensagem do Windows para investigar.'
            }
        }
        $rotulo = $null
        if ($Tipo -in 'Aplicativo','Travamento' -and ([string]$dados['ExceptionCode']).Trim() -match '^(?:0x)?([0-9a-f]{1,8})$') {
            $codigo = [Convert]::ToUInt32($Matches[1],16)
            $familia = 'Excecoes'
            $rotulo = 'Codigo de excecao'
        } else {
            foreach ($campo in 'HRESULT','NTStatus','Win32ErrorCode') {
                $valor = ([string]$dados[$campo]).Trim()
                if ($valor -match '^0x([0-9a-f]{1,8})$') { $codigo = [Convert]::ToUInt32($Matches[1],16) }
                elseif ($campo -ne 'Win32ErrorCode' -and $valor -match '^-[0-9]{1,10}$' -and [long]$valor -ge [int]::MinValue) {
                    $codigo = [uint32]([long]$valor + 4294967296)
                } elseif (-not [uint32]::TryParse($valor,[ref]$codigo)) { continue }
                if ($campo -eq 'Win32ErrorCode' -and $codigo -gt 0 -and $codigo -le 65535) {
                    $familia = 'Win32'
                    $rotulo = 'Codigo Win32'
                } elseif ($campo -ne 'Win32ErrorCode' -and $codigo -ge 2147483648) {
                    $familia = if ($campo -eq 'NTStatus') { 'Excecoes' } else { 'HRESULT' }
                    $rotulo = $campo
                } else { continue }
                break
            }
        }
        if ($familia -and $codigo -gt 0) {
            $regra = Find-SuporteCodigoFalha $Catalogo $familia $codigo
            if (-not $Tipo) { $titulo = 'O aplicativo ou servico registrou uma falha.' }
            if ($regra -and $regra.Resumo) {
                $titulo += ' ' + $regra.Resumo
                if ($regra.Investigar) { $pista = $regra.Investigar }
            } else { $pista += ' Descricao em portugues indisponivel para este codigo.' }
            $detalhe = (@($detalhe,('{0} 0x{1:X8}' -f $rotulo,$codigo)) -ne $null) -join ' | '
            if ($regra -and $regra.Nome) { $detalhe += ' - ' + $regra.Nome }
        }
    }
    [pscustomobject]@{ Titulo=$titulo; Pista=$pista; Detalhe=$detalhe; Codigo=$codigo; Familia=$familia }
}

function Get-SuporteDiagnosticoFalhas {
    $catalogo = $null
    try { $catalogo = Read-SuporteCatalogoFalhas }
    catch {
        '[INDISPONIVEL] Catalogo de codigos. Os eventos e codigos registrados continuam disponiveis.'
    }
    $inicio = (Get-Date).AddHours(-24)
    $filtros = @(
        @{ LogName='System'; Id=12,41,1001,1074,6008 }
        @{ LogName='System'; Id=7,51,129,153,157,4101 }
        @{ LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; Level=1,2,3 }
        @{ LogName='Application'; Id=1000,1002 }
        @{ LogName='System'; Level=1,2 }
        @{ LogName='Application'; Level=1,2 }
    )
    $chaves = @{}
    $registros = @(foreach ($filtro in $filtros) {
        $filtro.StartTime = $inicio
        try { $lote = @(Get-WinEvent -FilterHashtable $filtro -MaxEvents 80 -ErrorAction Stop) }
        catch {
            if ($_.FullyQualifiedErrorId -notmatch 'NoMatchingEventsFound') { Write-Output ('[INDISPONIVEL] Parte da consulta de ' + $filtro.LogName + '.') }
            continue
        }
        foreach ($evento in $lote) {
            if (-not $evento.TimeCreated) { continue }
            $chave = '{0}/{1}' -f $evento.LogName,$evento.RecordId
            if (-not $chaves.ContainsKey($chave)) {
                $chaves[$chave] = $true
                [pscustomobject]@{ Evento=$evento; Hora=$evento.TimeCreated; Tipo=(Get-SuporteTipoFalha $evento) }
            }
        }
    })
    $registros | Where-Object { $_ -is [string] } | Select-Object -Unique
    $ordenados = @($registros | Where-Object { $_ -isnot [string] } | Sort-Object Hora -Descending)
    $incidente = $ordenados | Where-Object Tipo -in 'Parada','Reinicio','Solicitado','Aplicativo','Travamento' | Select-Object -First 1
    if (-not $incidente) { $incidente = $ordenados | Where-Object Tipo -ne 'Inicio' | Select-Object -First 1 }
    if (-not $incidente) { 'Nenhum incidente encontrado nos registros consultados nas ultimas 24 horas.'; return }

    $relacionados = @($incidente)
    $referencia = $incidente.Hora
    if ($incidente.Tipo -in 'Reinicio','Parada') {
        $inicioWindows = $ordenados | Where-Object { $_.Tipo -eq 'Inicio' -and $_.Hora -le $incidente.Hora } | Select-Object -First 1
        $limite = $incidente.Hora.AddMinutes(-5)
        if ($inicioWindows -and $inicioWindows.Hora -gt $limite) {
            $limite = $inicioWindows.Hora
            $referencia = $inicioWindows.Hora
        }
        $relacionados = @($ordenados | Where-Object { $_.Tipo -in 'Reinicio','Parada' -and $_.Hora -ge $limite })
        $melhor = $relacionados | Where-Object Tipo -eq 'Parada' | Select-Object -First 1
        if (-not $melhor) { $melhor = $relacionados | Where-Object { $_.Evento.Id -eq 41 } | Select-Object -First 1 }
        if ($melhor) { $incidente = $melhor }
        $resumo = Get-SuporteResumoIncidente $incidente.Evento $incidente.Tipo $catalogo
        if ($resumo.Familia -ne 'Paradas') {
            foreach ($apoio in ($relacionados | Where-Object { $_.Evento.Id -eq 41 -and $_ -ne $incidente })) {
                $alternativo = Get-SuporteResumoIncidente $apoio.Evento $apoio.Tipo $catalogo
                if ($alternativo.Familia -eq 'Paradas') { $resumo = $alternativo; break }
            }
        }
    } else { $resumo = Get-SuporteResumoIncidente $incidente.Evento $incidente.Tipo $catalogo }

    'Ocorrencia mais recente identificada na triagem'
    $resumo.Titulo
    if ($resumo.Pista) { 'O que investigar: ' + $resumo.Pista }
    ''
    'Detalhes tecnicos'
    foreach ($registro in $relacionados) {
        '  {0:dd/MM/yyyy HH:mm:ss} | {1} | evento {2}' -f $registro.Hora,$registro.Evento.ProviderName,$registro.Evento.Id
    }
    if ($resumo.Detalhe) { '  ' + $resumo.Detalhe }
    if (-not $resumo.Familia) { '  O registro nao trouxe um codigo de falha identificado.' }
    if ($incidente.Tipo -in 'Reinicio','Parada') { '  Horario do registro no Windows. A falha pode ter ocorrido antes.' }
    if (-not $incidente.Tipo -or $incidente.Tipo -in 'Hardware','Solicitado') {
        try { $mensagem = ([string]$incidente.Evento.Message -replace '\s+',' ').Trim() } catch { $mensagem = '' }
        if ($mensagem) { '  Mensagem do Windows: ' + $mensagem.Substring(0,[Math]::Min(350,$mensagem.Length)) }
    }
    ''
    if ($resumo.Familia) { 'Outros codigos de falha encontrados (24h)' }
    else { 'Codigos de falha encontrados (24h)' }
    $vistos = @{}
    if ($resumo.Familia) { $vistos[('{0}/{1}' -f $resumo.Familia,$resumo.Codigo)] = $true }
    $exibidos = 0
    foreach ($registro in $ordenados) {
        if ($registro.Tipo -eq 'Inicio' -or $registro -in $relacionados) { continue }
        $outro = Get-SuporteResumoIncidente $registro.Evento $registro.Tipo $catalogo
        if (-not $outro.Familia) { continue }
        $chaveCodigo = '{0}/{1}' -f $outro.Familia,$outro.Codigo
        if ($vistos.ContainsKey($chaveCodigo)) { continue }
        $vistos[$chaveCodigo] = $true
        '  {0:dd/MM HH:mm:ss} | {1} | {2}' -f $registro.Hora,$registro.Evento.ProviderName,$outro.Detalhe
        '    ' + $outro.Titulo
        if ($outro.Pista) { '    O que investigar: ' + $outro.Pista }
        $exibidos++
        if ($exibidos -ge 6) { break }
    }
    if (-not $exibidos) { '  Nenhum codigo adicional identificado nos registros consultados.' }

    $anteriores = @($ordenados | Where-Object {
        $_.Hora -lt $referencia -and $_.Hora -ge $referencia.AddMinutes(-15) -and
        $_.Tipo -in 'Aplicativo','Travamento','Hardware','Disco','Video'
    } | Select-Object -First 4)
    if ($anteriores.Count) {
        ''
        'Registros proximos anteriores. Podem ajudar na investigacao.'
        foreach ($registro in $anteriores) {
            $pista = Get-SuporteResumoIncidente $registro.Evento $registro.Tipo $catalogo
            '  {0:HH:mm:ss} | {1} ({2}, evento {3})' -f $registro.Hora,$pista.Titulo,$registro.Evento.ProviderName,$registro.Evento.Id
        }
    }
}
