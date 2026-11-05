function Get-SuporteDestinoPing {
    param([string]$Entrada)
    $destino = $Entrada.Trim()
    if ($destino -match '^https?://') {
        $uri = $null
        if (-not [uri]::TryCreate($destino,[UriKind]::Absolute,[ref]$uri) -or $uri.UserInfo) { throw 'Endereco invalido.' }
        $destino = $uri.DnsSafeHost
    }
    if ([uri]::CheckHostName($destino) -eq [UriHostNameType]::Unknown) { throw 'Informe um site, nome de host ou endereco IP valido.' }
    $destino
}

function Invoke-SuportePing {
    param([string]$Destino)
    $destino = Get-SuporteDestinoPing $Destino
    $endereco = $null
    if (-not [Net.IPAddress]::TryParse($destino,[ref]$endereco)) {
        $endereco = [Net.Dns]::GetHostAddresses($destino) | Select-Object -First 1
    }
    if ($null -eq $endereco) { throw 'Nenhum endereco encontrado para o destino.' }
    "Destino: $destino ($endereco)"
    $ping = New-Object Net.NetworkInformation.Ping
    try {
        $tempos = @(for ($tentativa=1; $tentativa -le 4; $tentativa++) {
            $resposta = $ping.Send($endereco,1000)
            if ($resposta.Status -eq 'Success') { $resposta.RoundtripTime }
        })
        'Respostas: {0}/4 | Perda ICMP: {1}%' -f $tempos.Count,((4-$tempos.Count)*25)
        if ($tempos.Count) {
            $medidas = $tempos | Measure-Object -Minimum -Average -Maximum
            'Latencia (ms): minima {0:N0} | media {1:N1} | maxima {2:N0}' -f $medidas.Minimum,$medidas.Average,$medidas.Maximum
            if ($tempos.Count -eq 4) { '[PING OK] Destino respondeu a todas as tentativas.' }
            else { '[PING PARCIAL] Destino respondeu com perda de pacotes.' }
        } else { '[PING SEM RESPOSTA] Nenhuma resposta ICMP. O destino pode filtrar ping.' }
    } finally { $ping.Dispose() }
}

function Measure-SuporteVelocidade {
    param([ValidateSet('Download','Upload')][string]$Modo,
        [scriptblock]$CriarRequisicao = { param($Uri) [Net.HttpWebRequest]::Create($Uri) })
    $bytes = if ($Modo -eq 'Download') { 8MB } else { 4MB }
    $destino = if ($Modo -eq 'Download') { "https://speed.cloudflare.com/__down?bytes=$bytes" } else { 'https://speed.cloudflare.com/__up' }
    $requisicao = & $CriarRequisicao $destino
    $requisicao.AllowAutoRedirect = $false
    $requisicao.Timeout = 8000
    $requisicao.ReadWriteTimeout = 3000
    $requisicao.CachePolicy = New-Object Net.Cache.RequestCachePolicy([Net.Cache.RequestCacheLevel]::NoCacheNoStore)
    $requisicao.Credentials = $null
    if ($requisicao.Proxy) { $requisicao.Proxy.Credentials = $null }
    $cronometro = [Diagnostics.Stopwatch]::StartNew()
    $resposta = $null
    try {
        if ($Modo -eq 'Upload') {
            $requisicao.Method = 'POST'
            $requisicao.ContentType = 'application/octet-stream'
            $requisicao.ContentLength = $bytes
            $dados = New-Object byte[] $bytes
            $envio = $requisicao.GetRequestStream()
            try { $envio.Write($dados,0,$bytes) } finally { $envio.Dispose() }
        }
        $resposta = $requisicao.GetResponse()
        $codigoHttp = [int]$resposta.StatusCode
        if ($codigoHttp -lt 200 -or $codigoHttp -ge 300) { throw ('Resposta HTTP inesperada: ' + $codigoHttp) }
        if ($Modo -eq 'Download') {
            $cronometro.Restart()
            $buffer = New-Object byte[] 65536
            $recebido = 0
            $leitura = $resposta.GetResponseStream()
            try {
                while ($recebido -lt $bytes -and $cronometro.Elapsed.TotalSeconds -lt 8) {
                    $quantidade = $leitura.Read($buffer,0,[Math]::Min($buffer.Length,$bytes-$recebido))
                    if ($quantidade -eq 0) { break }
                    $recebido += $quantidade
                }
            } finally { $leitura.Dispose() }
            if ($recebido -ne $bytes) { throw 'Amostra incompleta. Velocidade inconclusiva.' }
        }
        '{0}: {1:N1} Mbps (amostra de {2:N0} MiB)' -f $Modo,(8*$bytes/[Math]::Max($cronometro.Elapsed.TotalSeconds,0.001)/1e6),($bytes/1MB)
    } finally {
        if ($resposta) { $resposta.Dispose() }
        $requisicao.Abort()
    }
}

function ConvertTo-SuporteIPv4 {
    param([string]$Valor)
    $ip = $null
    if (-not [Net.IPAddress]::TryParse($Valor,[ref]$ip) -or $ip.AddressFamily -ne 'InterNetwork' -or $ip.ToString() -cne $Valor) {
        throw 'Use um IPv4 no formato decimal, por exemplo 192.0.2.10.'
    }
    $octetos = $ip.GetAddressBytes()
    if ($octetos[0] -eq 0 -or $octetos[0] -eq 127 -or $octetos[0] -ge 224 -or ($octetos[0] -eq 169 -and $octetos[1] -eq 254)) {
        throw 'Endereco reservado ou inadequado para configuracao manual da estacao.'
    }
    $ip
}

function Get-SuporteIPv4Estatico {
    param([string]$Endereco,[string]$Prefixo,[string]$Gateway)
    $ip = ConvertTo-SuporteIPv4 $Endereco
    $bits = 0
    if ($Prefixo -match '\.') {
        $ipMascara = $null
        if (-not [Net.IPAddress]::TryParse($Prefixo,[ref]$ipMascara) -or $ipMascara.AddressFamily -ne 'InterNetwork' -or $ipMascara.ToString() -ne $Prefixo) {
            throw 'Mascara invalida. Exemplo: 255.255.255.0.'
        }
        $binario = ($ipMascara.GetAddressBytes() | ForEach-Object { [Convert]::ToString($_,2).PadLeft(8,'0') }) -join ''
        if ($binario -notmatch '^(1{1,30})0+$') { throw 'Mascara invalida para uma estacao. Use bits consecutivos.' }
        $bits = $Matches[1].Length
    } elseif (-not [int]::TryParse($Prefixo.TrimStart('/'),[ref]$bits) -or $bits -lt 1 -or $bits -gt 30) {
        throw 'Informe uma mascara como 255.255.255.0 ou um prefixo de 1 a 30.'
    }
    $ipBytes = $ip.GetAddressBytes()
    $gatewayIp = if ($Gateway) { ConvertTo-SuporteIPv4 $Gateway } else { $null }
    if ($gatewayIp -and $gatewayIp.Equals($ip)) { throw 'Gateway e IPv4 da estacao precisam ser diferentes.' }
    $gatewayBytes = if ($gatewayIp) { $gatewayIp.GetAddressBytes() } else { $null }
    $rede = $true
    $broadcast = $true
    $gatewayRede = $true
    $gatewayBroadcast = $true
    $mascara = @(for ($octeto=0; $octeto -lt 4; $octeto++) {
        $contagem = [Math]::Max(0,[Math]::Min(8,$bits-8*$octeto))
        $mask = 256 - (1 -shl (8-$contagem))
        $hostMask = 255 - $mask
        $hostBits = $ipBytes[$octeto] -band $hostMask
        if ($hostBits -ne 0) { $rede = $false }
        if ($hostBits -ne $hostMask) { $broadcast = $false }
        if ($gatewayIp) {
            if (($gatewayBytes[$octeto] -band $mask) -ne ($ipBytes[$octeto] -band $mask)) { throw 'Gateway fora da sub-rede informada.' }
            $gatewayHost = $gatewayBytes[$octeto] -band $hostMask
            if ($gatewayHost -ne 0) { $gatewayRede = $false }
            if ($gatewayHost -ne $hostMask) { $gatewayBroadcast = $false }
        }
        $mask
    })
    if ($rede -or $broadcast -or ($gatewayIp -and ($gatewayRede -or $gatewayBroadcast))) { throw 'Endereco de rede ou broadcast nao pode ser usado como host.' }
    [pscustomobject]@{ Endereco=$ip.ToString(); Prefixo=$bits; Mascara=($mascara -join '.'); Gateway=$(if($gatewayIp){$gatewayIp.ToString()}else{'none'}) }
}

function Invoke-SuporteConfiguracaoIPv4 {
    param([ValidateSet('Dhcp','Estatico')][string]$Modo)
    $adaptadores = @(Get-NetAdapter -Physical -ErrorAction Stop | Sort-Object ifIndex)
    if (-not $adaptadores.Count) { throw 'Nenhum adaptador fisico disponivel.' }
    Write-SuporteLinha '  Escolha o adaptador de rede' -SemCores
    Write-Host ''
    $enderecosAtuais = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue)
    for ($i=0; $i -lt $adaptadores.Count; $i++) {
        $adaptador = $adaptadores[$i]
        $status = switch ($adaptador.Status) { 'Up' {'Conectado'} 'Disconnected' {'Desconectado'} 'Disabled' {'Desativado'} default {$adaptador.Status} }
        $ipv4 = ($enderecosAtuais | Where-Object InterfaceIndex -eq $adaptador.ifIndex | ForEach-Object IPAddress) -join ', '
        if (-not $ipv4) { $ipv4 = 'sem IPv4' }
        Write-SuporteLinha ('  [{0}] {1} | {2} | {3}' -f ($i+1),$adaptador.Name,$status,$ipv4) -SemCores
    }
    Write-Host ''
    $escolha = 0
    $entrada = Read-Host 'Adaptador (Enter ou 0 volta)'
    if (-not $entrada -or $entrada -eq '0') { return 'Selecao cancelada.' }
    if (-not [int]::TryParse($entrada,[ref]$escolha) -or $escolha -lt 1 -or $escolha -gt $adaptadores.Count) { throw 'Adaptador invalido.' }
    $adaptador = $adaptadores[$escolha-1]
    $indice = [int]$adaptador.ifIndex
    $antes = Get-NetIPInterface -InterfaceIndex $indice -AddressFamily IPv4 -ErrorAction Stop
    $enderecoAntes = @(Get-NetIPAddress -InterfaceIndex $indice -AddressFamily IPv4 -ErrorAction SilentlyContinue)
    $resumoAntes = 'Antes: {0} | DHCP: {1} | IPv4: {2}' -f $adaptador.Name,$antes.Dhcp,(($enderecoAntes | ForEach-Object IPAddress) -join ', ')
    Write-Host $resumoAntes
    $resumoAntes
    Write-Host 'A mudanca pode interromper a rede e o atendimento remoto.'
    if ($Modo -eq 'Estatico') {
        Write-Host ("`n  Configuracao manual de " + $adaptador.Name)
        $ip = ([string](Read-Host '  Endereco IPv4 (0 ou Enter volta)')).Trim()
        if ($ip -in @('','0')) { return 'Selecao cancelada.' }
        $prefixo = ([string](Read-Host '  Mascara ou prefixo (0 ou Enter volta)')).Trim()
        if ($prefixo -in @('','0')) { return 'Selecao cancelada.' }
        $gateway = ([string](Read-Host '  Gateway (0 volta, Enter deixa vazio)')).Trim()
        if ($gateway -eq '0') { return 'Selecao cancelada.' }
        $config = Get-SuporteIPv4Estatico $ip $prefixo $gateway
        $dns1 = ([string](Read-Host '  DNS primario IPv4 (0 ou Enter volta)')).Trim()
        if ($dns1 -in @('','0')) { return 'Selecao cancelada.' }
        $dns1 = (ConvertTo-SuporteIPv4 $dns1).ToString()
        $dns2 = ([string](Read-Host '  DNS secundario (0 volta, Enter deixa vazio)')).Trim()
        if ($dns2 -eq '0') { return 'Selecao cancelada.' }
        if ($dns2) {
            $dns2 = (ConvertTo-SuporteIPv4 $dns2).ToString()
            if ($dns2 -eq $dns1) { throw 'Use enderecos diferentes para o DNS primario e secundario.' }
        }
        Write-Host ('  Aplicando {0} / {1} | Gateway: {2} | DNS: {3}' -f $ip,$config.Mascara,$config.Gateway,((@($dns1,$dns2) | Where-Object {$_}) -join ', '))
        $argumentos = @('interface','ipv4','set','address',"name=$indice",'source=static',"address=$($config.Endereco)","mask=$($config.Mascara)","gateway=$($config.Gateway)",'store=persistent')
    } else {
        $argumentos = @('interface','ipv4','set','address',"name=$indice",'source=dhcp')
    }
    $atual = Get-NetAdapter -InterfaceIndex $indice -ErrorAction Stop
    if ($atual.InterfaceGuid -ne $adaptador.InterfaceGuid) { throw 'Adaptador mudou durante a selecao. Abra a opcao novamente.' }
    Invoke-SuporteNativeAction 'netsh.exe' $argumentos | Out-Null
    if ($Modo -eq 'Dhcp') {
        try { Invoke-SuporteNativeAction 'netsh.exe' @('interface','ipv4','set','dnsservers',"name=$indice",'source=dhcp') | Out-Null }
        catch { throw ('IPv4 alterado. DNS automatico falhou: ' + $_.Exception.Message) }
    } else {
        try {
            Invoke-SuporteNativeAction 'netsh.exe' @('interface','ipv4','set','dnsservers',"name=$indice",'source=static',"address=$dns1",'validate=no') | Out-Null
            if ($dns2) { Invoke-SuporteNativeAction 'netsh.exe' @('interface','ipv4','add','dnsservers',"name=$indice", "address=$dns2",'index=2','validate=no') | Out-Null }
        } catch { throw ('IPv4 alterado. Configuracao de DNS incompleta: ' + $_.Exception.Message) }
        $dnsAplicado = @((Get-DnsClientServerAddress -InterfaceIndex $indice -AddressFamily IPv4 -ErrorAction Stop).ServerAddresses)
        if (($dnsAplicado -join ',') -ne ((@($dns1,$dns2) | Where-Object {$_}) -join ',')) { throw 'IPv4 alterado. O Windows nao confirmou os DNS solicitados.' }
        'DNS IPv4 configurado: ' + ($dnsAplicado -join ', ')
    }
    $depois = Get-NetIPInterface -InterfaceIndex $indice -AddressFamily IPv4 -ErrorAction Stop
    $enderecos = @(Get-NetIPAddress -InterfaceIndex $indice -AddressFamily IPv4 -ErrorAction SilentlyContinue)
    $esperado = if ($Modo -eq 'Dhcp') { 'Enabled' } else { 'Disabled' }
    if ($depois.Dhcp -ne $esperado) { throw 'O Windows nao confirmou o modo IPv4 solicitado.' }
    $listaIPv4 = @($enderecos | ForEach-Object IPAddress)
    if ($Modo -eq 'Estatico' -and -not ($enderecos | Where-Object {$_.IPAddress -eq $config.Endereco -and $_.PrefixLength -eq $config.Prefixo})) { throw 'O Windows nao confirmou o IPv4 e o prefixo solicitados.' }
    'Depois: {0} | DHCP: {1} | IPv4: {2}' -f $adaptador.Name,$depois.Dhcp,($listaIPv4 -join ', ')
    if ($Modo -eq 'Dhcp' -and -not ($enderecos | Where-Object {$_.PrefixOrigin -eq 'Dhcp' -and $_.AddressState -eq 'Preferred'})) {
        'DHCP configurado. O Windows ainda nao confirmou um endereco concedido.'
    }
    if ($enderecos | Where-Object AddressState -eq Duplicate) { throw 'O Windows detectou IPv4 duplicado. Revise a configuracao.' }
    if ($Modo -eq 'Estatico' -and ($enderecos | Where-Object {$_.IPAddress -eq $config.Endereco -and $_.AddressState -ne 'Preferred'})) {
        'IPv4 configurado. O Windows ainda esta verificando se o endereco pode ser usado.'
    }
}
