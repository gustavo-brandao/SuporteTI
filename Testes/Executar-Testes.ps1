#requires -Version 5.1
[CmdletBinding()]
param([switch]$IncluirConsultasReais)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$manifest=Join-Path $root 'Modulos\SuporteTI.psd1'
Import-Module $manifest -Force
$module=Get-Module SuporteTI
$results=New-Object 'System.Collections.Generic.List[object]'
$testRoot=Join-Path $root ('work\testes_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)

function Test-Case {
    param([string]$Option,[string]$Name,[scriptblock]$Body)
    $script:TestDetail=''
    try { & $Body; $results.Add([pscustomobject]@{Opcao=$Option;Teste=$Name;Resultado='PASSOU';Detalhe=$script:TestDetail}) }
    catch { $results.Add([pscustomobject]@{Opcao=$Option;Teste=$Name;Resultado='FALHOU';Detalhe=$_.Exception.Message}) }
}
function Assert-True { param($Condition,[string]$Message) if (-not $Condition) { throw $Message } }

# Stubs locais: os testes de alteracoes nao executam comandos administrativos reais.
& $module {
    $script:TestCalls=New-Object 'System.Collections.Generic.List[string]'
    $script:TestFailure=$false
    $script:TestStates=@{Spooler='Running';bits='Running';wuauserv='Stopped'}
    function script:Test-SuporteAdmin { $true }
    function script:Invoke-SuporteNativeAction {
        param($Programa,$Argumentos)
        $script:TestCalls.Add($Programa+' '+($Argumentos -join ' '))
        if ($script:TestFailure) { throw 'Falha nativa simulada.' }
        'Comando simulado encerrado.'
    }
    function script:Get-Service {
        param([string[]]$Name)
        if ($script:TestFailure) { throw 'Acesso negado simulado.' }
        foreach ($n in $Name) {
            $state='Running'; if ($script:TestStates.ContainsKey($n)) { $state=$script:TestStates[$n] }
            $obj=[pscustomobject]@{Name=$n;Status=$state;DisplayName=$n;StartType='Manual'}
            $obj | Add-Member -MemberType ScriptMethod -Name WaitForStatus -Value { param($status,$timeout) }
            $obj
        }
    }
    function script:Restart-Service { param($Name) $script:TestCalls.Add('restart '+$Name); if ($script:TestFailure) {throw 'Falha simulada'} }
    function script:Start-Service { param($Name) $script:TestCalls.Add('start '+$Name); $script:TestStates[$Name]='Running' }
    function script:Stop-Service { param($Name) $script:TestCalls.Add('stop '+$Name); $script:TestStates[$Name]='Stopped' }
    function script:Get-CimInstance {
        [pscustomobject]@{DeviceID='C:';VolumeName='Windows simulado';FileSystem='NTFS'}
        [pscustomobject]@{DeviceID='D:';VolumeName='Dados simulados';FileSystem='exFAT'}
    }
    function script:Read-Host { '2' }
}

$actions=@{spooler=@('spooler');cache=@('cache');gpupdateuser=@('gpuser');gpupdatecomputer=@('gpcomputer');sfc=@('sfcverify','sfcrepair');dism=@('dismcheck','dismscan','dismrestore');chkdsk=@('chkdskread','chkdskfull')}
foreach ($option in $actions.Keys) {
    foreach ($action in $actions[$option]) {
        Test-Case $option "$action - cancelar nao executa" {
            $count=& $module { $script:TestCalls.Clear(); Invoke-SuporteOperacao -Acao $args[0] -WhatIf | Out-Null; $script:TestCalls.Count } $action
            Assert-True ($count -eq 0) 'Cancelamento executou operacao.'
        }
        if ($action -ne 'cache') {
            Test-Case $option "$action - despacho autorizado" {
                $calls=& $module { $script:TestCalls.Clear(); $script:TestFailure=$false; Invoke-SuporteOperacao -Acao $args[0] -Confirm:$false | Out-Null; $script:TestCalls.ToArray() } $action
                Assert-True (@($calls).Count -gt 0) 'Nenhum comando encaminhado.'
                $joined=$calls -join ' '
                Assert-True ($joined -notmatch '/boot|/logoff|Remove-|Clear-') 'Operacao contem acao nao aprovada.'
                switch ($action) {
                    'sfcrepair' { Assert-True ($joined -match '/scannow') 'SFC sem scannow.' }
                    'sfcverify' { Assert-True ($joined -match '/verifyonly') 'SFC sem verifyonly.' }
                    'dismrestore' { Assert-True ($joined -match '/RestoreHealth' -and $joined -match '/NoRestart') 'DISM sem RestoreHealth/NoRestart.' }
                    'dismscan' { Assert-True ($joined -match '/ScanHealth') 'DISM sem ScanHealth.' }
                    'dismcheck' { Assert-True ($joined -match '/CheckHealth') 'DISM sem CheckHealth.' }
                    'chkdskread' { Assert-True ($joined -eq 'chkdsk.exe D:') 'CHKDSK de consulta alterou o volume ou as opcoes.' }
                    'chkdskfull' { Assert-True ($joined -eq 'chkdsk.exe D: /f /r') 'CHKDSK completo alterou o volume ou as opcoes.' }
                    'gpuser' { Assert-True ($joined -match '/target:user') 'Escopo do usuario incorreto.' }
                    'gpcomputer' { Assert-True ($joined -match '/target:computer') 'Escopo do computador incorreto.' }
                }
            }
            Test-Case $option "$action - falha nao vira sucesso" {
                $caught=& $module {
                    $script:TestFailure=$true
                    try { Invoke-SuporteOperacao -Acao $args[0] -Confirm:$false | Out-Null; $false } catch { $true } finally { $script:TestFailure=$false }
                } $action
                Assert-True $caught 'Falha nao foi propagada.'
            }
        }
    }
}

# Cache simulado em arvore temporaria; nao usa a pasta Windows.
Test-Case cache 'renomeia somente Download e restaura estados anteriores' {
    $fake=Join-Path $testRoot 'Windows'; [void][IO.Directory]::CreateDirectory((Join-Path $fake 'SoftwareDistribution\Download'))
    [IO.File]::WriteAllText((Join-Path $fake 'SoftwareDistribution\Download\payload.bin'),'preservar')
    $check=& $module {
        param($fake)
        $original=$env:SystemRoot; $env:SystemRoot=$fake
        function Get-Process { @() }
        function Test-Path { param($LiteralPath) if($LiteralPath -like 'HKLM:*'){$false}else{Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath} }
        try {
            $script:TestCalls.Clear(); $script:TestStates=@{bits='Running';wuauserv='Stopped';Spooler='Running'}
            Invoke-SuporteOperacao cache -Confirm:$false | Out-Null
            @((Get-ChildItem -LiteralPath (Join-Path $fake 'SoftwareDistribution') -Directory).Name,$script:TestCalls.ToArray(),$script:TestStates.bits,$script:TestStates.wuauserv)
        } finally { $env:SystemRoot=$original }
    } $fake
    Assert-True (($check -join ' ') -match 'Download.anterior_') 'Backup do cache nao criado.'
    Assert-True (-not (Microsoft.PowerShell.Management\Test-Path -LiteralPath (Join-Path $fake 'SoftwareDistribution\Download'))) 'Cache antigo nao foi renomeado.'
    Assert-True (($check -join ' ') -notmatch 'start wuauserv') 'Servico antes parado foi iniciado indevidamente.'
    $files=@(Get-ChildItem -LiteralPath $fake -Recurse -File)
    Assert-True ($files.Count -eq 1 -and [IO.File]::ReadAllText($files[0].FullName) -eq 'preservar') 'Download anterior nao foi preservado.'
}
Test-Case cache 'manutencao ativa bloqueia sem parar servicos' {
    $check=& $module {
        function Get-Process { [pscustomobject]@{Name='TiWorker'} }
        $script:TestCalls.Clear()
        try { Invoke-SuporteOperacao cache -Confirm:$false | Out-Null; $false } catch { $script:TestCalls.Count -eq 0 }
    }
    Assert-True $check 'Cache nao bloqueou manutencao concorrente.'
}
Test-Case gpupdateuser 'force explicito mantem escopo do usuario' {
    $call=& $module { $script:TestCalls.Clear(); Invoke-SuporteOperacao gpuser -Forcar -Confirm:$false | Out-Null; $script:TestCalls.ToArray() }
    Assert-True ($call -match '/force' -and $call -match '/target:user') 'Force ou escopo incorreto.'
}

# Recarregar remove todos os stubs administrativos.
Remove-Module SuporteTI -Force
Import-Module $manifest -Force
$module=Get-Module SuporteTI
$collector=Join-Path $root 'Modulos\Consultas.ps1'
$queries=@('sistema','desempenho','discos','dispositivos','servicos','programas','falhas','rede','dominio','update','gpusuario','gpcomputador','eventos')

function Invoke-FixtureConsulta {
    param([string]$Id,[bool]$Failure)
    & $module {
        param($collector,$id,$failure)
        $global:SuporteFixtureFailure=$failure
        function Get-CimInstance {
            if ($global:SuporteFixtureFailure) { throw 'Acesso negado simulado.' }
            [pscustomobject]@{Name='TEST-PC';Manufacturer='Fixture';Model='Teste';Domain='WORKGROUP';PartOfDomain=$false;Workgroup='WORKGROUP';TotalPhysicalMemory=8GB;Caption='Windows Teste';Version='10.0';BuildNumber='19045';OSArchitecture='64 bits';LastBootUpTime=(Get-Date);SMBIOSBIOSVersion='1';ReleaseDate=(Get-Date);TotalVisibleMemorySize=8MB;FreePhysicalMemory=4MB;LoadPercentage=10;DeviceID='C:';FileSystem='NTFS';Size=100GB;FreeSpace=50GB;Description='Rede teste';DHCPEnabled=$true;DHCPServer='192.0.2.1';DHCPLeaseExpires=(Get-Date);ConfigManagerErrorCode=0;PNPClass='System';Status='OK'}
        }
        function Get-Process { if($global:SuporteFixtureFailure){throw 'Falha simulada'}; foreach($n in 1..8){[pscustomobject]@{Id=$n;ProcessName=('ProcessoTeste'+$n);WorkingSet64=($n*1MB);CPU=1}} }
        function Get-Service { param($Name); if($global:SuporteFixtureFailure){throw 'Acesso negado simulado'}; [pscustomobject]@{Name='bits';Status='Running';StartType='Manual'} }
        function Get-PhysicalDisk { if($global:SuporteFixtureFailure){throw 'Falha simulada'}; [pscustomobject]@{DeviceId=0;FriendlyName='SSD Fixture';MediaType='SSD';HealthStatus='Healthy'} }
        function Get-StorageReliabilityCounter { [CmdletBinding()]param([Parameter(ValueFromPipeline)]$InputObject); process{if($global:SuporteFixtureFailure){throw 'Falha simulada'}; [pscustomobject]@{Wear=10;ReadErrorsUncorrected=0;WriteErrorsUncorrected=0;Temperature=35;PowerOnHours=100}} }
        function Get-NetAdapter { if($global:SuporteFixtureFailure){throw 'Falha simulada'}; [pscustomobject]@{Name='Ethernet';InterfaceDescription='Fixture';Status='Up';LinkSpeed='1 Gbps'} }
        function Get-NetIPConfiguration { if($global:SuporteFixtureFailure){throw 'Falha simulada'}; [pscustomobject]@{InterfaceAlias='Ethernet';IPv4Address='192.0.2.2';DNSServer='192.0.2.1'} }
        function Get-NetRoute { if($global:SuporteFixtureFailure){throw 'Falha simulada'}; [pscustomobject]@{DestinationPrefix='0.0.0.0/0';InterfaceAlias='Ethernet';NextHop='192.0.2.1';RouteMetric=10} }
        function Get-WinEvent { if($global:SuporteFixtureFailure){throw 'Acesso negado simulado'}; [pscustomobject]@{TimeCreated=(Get-Date);Id=100;LevelDisplayName='Warning';ProviderName='Fixture';Message='Evento de teste'} }
        function Get-ItemProperty { if($global:SuporteFixtureFailure){throw 'Falha simulada'}; [pscustomobject]@{DisplayName='Programa teste';DisplayVersion='1';Publisher='Fixture';ProxyEnable=0;ProxyServer='';AutoConfigURL=''} }
        # Consulta SMART real e limitada, caso presente. Nao altera discos.
        $options=@{}
        $originalRoot=$env:SystemRoot
        try {
            if($id -eq 'rede' -and $failure){$env:SystemRoot='C:\Caminho-Inexistente-Teste-Suporte'}
            & $collector -Id $id -Opcoes $options | Out-String
        }finally{$env:SystemRoot=$originalRoot}
    } $collector $Id $Failure
}

foreach ($query in $queries) {
    Test-Case $query 'consulta retorna secoes e texto com dados controlados' {
        $text=Invoke-FixtureConsulta $query $false
        Assert-True ($text.Length -gt 20 -and $text -match '---') 'Consulta nao retornou secoes.'
        Assert-True ($text -notmatch 'The property .* cannot be found|propriedade .* encontrada|cannot bind|nao pode ser associado') 'Erro de contrato na consulta.'
        $markers=@{sistema='TEST-PC';desempenho='RAM:';discos='SSD Fixture';dispositivos='TEST-PC';servicos='bits';programas='Programa teste';falhas='Evento de teste';rede='ipconfig /all';dominio='PartOfDomain';update='bits';eventos='Evento de teste'}
        if($markers.ContainsKey($query)){Assert-True ($text.Contains($markers[$query])) ('Dados controlados nao apareceram na consulta '+$query)}
    }
    Test-Case $query 'falha ou acesso negado fica explicito e nao interrompe interface' {
        if ($query -in @('gpusuario','gpcomputador')) {
            # gpresult e somente leitura: a maquina de teste pode nao ter RSoP.
            $text=Invoke-FixtureConsulta $query $true
            Assert-True ($text -match '---') 'Falha do gpresult encerrou o fluxo.'
        } else {
            $text=Invoke-FixtureConsulta $query $true
            if ($query -eq 'programas') {
                Assert-True ($text -match 'Inventario|INDISPONIVEL') 'Inventario nao informa cobertura.'
            } else { Assert-True ($text -match 'INDISPONIVEL|ACESSO NEGADO') 'Falha nao identificada.' }
        }
    }
}

Test-Case rede 'menu exibe consultas e mudancas IPv4 separadas' {
    $ids=@(Get-SuporteCatalogo | Where-Object Grupo -eq Rede | Select-Object -ExpandProperty Id)
    Assert-True (($ids -join ',') -eq 'rede,dominio,ping,velocidade,netdhcp,netstatic') 'Opcoes de rede incorretas.'
}
Test-Case rede 'opcoes removidas nao podem ser invocadas pela API' {
    foreach($id in @('conectividade','proxy')){
        $blocked=$false;try{Invoke-SuporteConsulta $id|Out-Null}catch{$blocked=$true}
        Assert-True $blocked ('Opcao removida continua disponivel: '+$id)
    }
}
Test-Case desempenho 'resumo limita a cinco processos e remove CPU acumulada' {
    $text=Invoke-FixtureConsulta desempenho $false
    Assert-True ($text -match 'RAM:' -and $text -match 'CPU:' -and $text -match 'ProcessoTeste8' -and $text -match 'ProcessoTeste4') ('Resumo de recursos incompleto: '+$text)
    Assert-True ($text -notmatch 'ProcessoTeste3|ProcessoTeste2|ProcessoTeste1|CPU_seg_acumulados') 'Resumo exibe processos excedentes ou CPU acumulada.'
}
Test-Case dominio 'exibe somente nome, ingresso e dominio' {
    $text = & $module {
        param($arquivo)
        function Get-CimInstance { [pscustomobject]@{Name='LAB-PC01';PartOfDomain=$true;Domain='acad.exemplo.edu';Workgroup='omitido'} }
        & $arquivo -Id dominio | Out-String
    } $collector
    Assert-True ($text -match 'Name\s+: LAB-PC01' -and $text -match 'PartOfDomain\s+: True' -and $text -match 'Domain\s+: acad\.exemplo\.edu') 'Vinculo do dominio nao aparece corretamente.'
    Assert-True ($text -notmatch 'Workgroup|Controlador|Horario|Sincronizacao') 'Consulta trouxe campos alem dos solicitados.'
}
Test-Case dispositivos 'oculta codigo 24 somente quando a ausencia esta confirmada' {
    $text = & $module {
        param($arquivo)
        function Get-CimInstance {
            [pscustomobject]@{Name='PS2 Ausente';PNPClass='Keyboard';ConfigManagerErrorCode=24;Status='Error';Present=$false}
            [pscustomobject]@{Name='PS2 Presente';PNPClass='Keyboard';ConfigManagerErrorCode=24;Status='Error';Present=$true}
            [pscustomobject]@{Name='USB Driver';PNPClass='USB';ConfigManagerErrorCode=28;Status='Error';Present=$true}
        }
        & $arquivo -Id dispositivos | Out-String
    } $collector
    Assert-True ($text -notmatch 'PS2 Ausente' -and $text -match 'PS2 Presente' -and $text -match 'USB Driver') 'Filtro ocultou ou exibiu o dispositivo errado.'
}
Test-Case ultimo 'Enter no primeiro prompt nao salva nem escolhe destino' {
    $salvos = & $module {
        $script:TotalSalvosTeste=0
        function Read-Host { '' }
        function Save-SuporteResultado { $script:TotalSalvosTeste++ }
        Request-SuporteSalvar ([pscustomobject]@{}) 'C:\Documentos'
        $script:TotalSalvosTeste
    }
    Assert-True ($salvos -eq 0) 'Enter iniciou o salvamento.'
}
Test-Case ping 'sucesso, perda parcial e falta de resposta recebem cores distintas' {
    $cores = & $module {
        function Write-Host {}
        function Write-SuporteLinha { param($Texto,$Cor,[switch]$SemCores); if ($Texto -like '[[]PING*') { $Cor } }
        $resultado=[pscustomobject]@{Status='Concluido';Texto="[PING OK] respondeu`n[PING PARCIAL] perda`n[PING SEM RESPOSTA] falha"}
        Show-SuporteResultado $resultado
    }
    Assert-True (($cores -join ',') -eq 'Green,Yellow,Red') 'Cores de ping incorretas.'
}
Test-Case sistema 'inventario inclui CPU e RAM atuais' {
    $text=Invoke-FixtureConsulta sistema $false
    Assert-True ($text -match 'CPU: 10%' -and $text -match 'RAM:') 'Indicadores ausentes do resumo do Windows.'
}
Test-Case monitor 'leituras da barra correspondem aos valores do sistema' {
    $leitura = & $module {
        function Get-CimInstance {
            [pscustomobject]@{LoadPercentage=30;TotalVisibleMemorySize=8MB;FreePhysicalMemory=2MB}
        }
        [pscustomobject]@{CPU=(Get-SuporteCpuPercentual);RAM=(Get-SuporteMemoria).Percentual}
    }
    Assert-True ($leitura.CPU -eq 30 -and $leitura.RAM -eq 75) 'Percentuais incorretos.'
}
Test-Case ping 'aceita URL e consulta apenas o host' {
    $destino = & $module { Get-SuporteDestinoPing 'https://exemplo.edu.br/aula?pagina=1' }
    Assert-True ($destino -eq 'exemplo.edu.br') 'O ping deve receber somente o host.'
}
Test-Case ping 'recusa destino com argumentos' {
    $bloqueado = & $module { try { Get-SuporteDestinoPing '127.0.0.1 -t' | Out-Null; $false } catch { $true } }
    Assert-True $bloqueado 'Argumentos foram aceitos como destino.'
}
Test-Case velocidade 'mede amostra completa e recusa amostra incompleta' {
    $resultado = & $module {
        $criar = {
            param($uri)
            $request = [pscustomobject]@{ Uri=$uri; AllowAutoRedirect=$true; Timeout=0; ReadWriteTimeout=0; CachePolicy=$null; Credentials=$null; Proxy=$null }
            $request | Add-Member ScriptMethod Abort {}
            $request | Add-Member ScriptMethod GetResponse {
                $response = [pscustomobject]@{StatusCode=200}
                $response | Add-Member ScriptMethod Dispose {}
                $response | Add-Member ScriptMethod GetResponseStream { New-Object IO.MemoryStream(,(New-Object byte[] $global:SuporteAmostraTeste)) }
                $response
            }
            $request
        }
        try {
            $global:SuporteAmostraTeste=8MB
            $ok=Measure-SuporteVelocidade Download $criar
            $global:SuporteAmostraTeste=1024
            $falhou=try{Measure-SuporteVelocidade Download $criar|Out-Null;$false}catch{$_.Exception.Message -match 'incompleta'}
            [pscustomobject]@{Ok=$ok;Falhou=$falhou}
        } finally { Remove-Variable SuporteAmostraTeste -Scope Global }
    }
    Assert-True ($resultado.Ok -match 'Mbps' -and $resultado.Falhou) 'A medicao nao distinguiu amostras completas e incompletas.'
}
Test-Case velocidade 'upload envia somente a amostra de 4 MiB e aceita HTTP 204' {
    $resultado = & $module {
        $request = [pscustomobject]@{
            AllowAutoRedirect=$true; Timeout=0; ReadWriteTimeout=0; CachePolicy=$null; Credentials=$null; Proxy=$null
            Method='GET'; ContentType=''; ContentLength=0; Envio=(New-Object IO.MemoryStream)
        }
        $request | Add-Member ScriptMethod Abort {}
        $request | Add-Member ScriptMethod GetRequestStream { $this.Envio }
        $request | Add-Member ScriptMethod GetResponse {
            if ($this.Method -ne 'POST' -or $this.Envio.ToArray().Length -ne 4MB) { throw 'Amostra de upload incorreta.' }
            $response = [pscustomobject]@{StatusCode=204}
            $response | Add-Member ScriptMethod Dispose {}
            $response
        }
        $criar = { param($uri) if ($uri -notmatch '/__up$') { throw 'Destino de upload incorreto.' }; $request }.GetNewClosure()
        Measure-SuporteVelocidade Upload $criar
    }
    Assert-True ($resultado -match 'Upload:.*Mbps') 'O upload nao produziu uma medicao.'
}
foreach ($acao in @('netdhcp','netstatic')) {
    Test-Case $acao 'configura somente o adaptador escolhido (simulado)' {
        $comandos = & $module {
            param($acao)
            $script:ComandosRede = New-Object 'System.Collections.Generic.List[string]'
            $script:EntradasRede = New-Object 'System.Collections.Generic.Queue[string]'
            foreach ($entrada in @('1','192.0.2.25','255.255.255.0','192.0.2.1','192.0.2.53','192.0.2.54')) { $script:EntradasRede.Enqueue($entrada) }
            function Read-Host { $script:EntradasRede.Dequeue() }
            function Test-SuporteAdmin { $true }
            function Get-NetAdapter { [pscustomobject]@{ifIndex=9;Name='Lab';Status='Up';InterfaceGuid='lab'} }
            function Get-NetIPInterface { [pscustomobject]@{Dhcp=$(if($acao -eq 'netdhcp'){'Enabled'}else{'Disabled'})} }
            function Get-NetIPAddress { [pscustomobject]@{InterfaceIndex=9;IPAddress='192.0.2.25';PrefixLength=24;PrefixOrigin='Dhcp';AddressState='Preferred'} }
            function Get-DnsClientServerAddress { [pscustomobject]@{ServerAddresses=@('192.0.2.53','192.0.2.54')} }
            function Invoke-SuporteNativeAction { param($Programa,$Argumentos); $script:ComandosRede.Add($Programa+' '+($Argumentos -join ' ')) }
            Invoke-SuporteOperacao $acao -Confirm:$false | Out-Null
            $script:ComandosRede.ToArray()
        } $acao
        if ($acao -eq 'netdhcp') {
            Assert-True (($comandos -join '|') -eq 'netsh.exe interface ipv4 set address name=9 source=dhcp|netsh.exe interface ipv4 set dnsservers name=9 source=dhcp') 'DHCP ou DNS automatico incorreto.'
        } else {
            Assert-True (($comandos -join '|') -match 'name=9 source=static address=192\.0\.2\.25 mask=255\.255\.255\.0 gateway=192\.0\.2\.1') 'Parametros do IPv4 fixo incorretos.'
            Assert-True ($comandos.Count -eq 3 -and $comandos[1] -match 'set dnsservers name=9 source=static address=192\.0\.2\.53' -and $comandos[2] -match 'add dnsservers name=9 address=192\.0\.2\.54 index=2') 'DNS IPv4 foi aplicado em ordem ou adaptador incorreto.'
        }
    }
}
Test-Case netstatic 'rejeita gateway fora da sub-rede e enderecos reservados' {
    $erros = & $module {
        foreach ($valores in @(@('192.0.2.25','24','192.0.3.1'),@('192.0.2.255','24','192.0.2.1'))) {
            try { Get-SuporteIPv4Estatico @valores | Out-Null; $false } catch { $true }
        }
    }
    Assert-True ($erros.Count -eq 2 -and $false -notin $erros) 'Configuracao IPv4 invalida foi aceita.'
}
Test-Case discos 'sem dados e inconclusivo' { Assert-True ((Get-SuporteDiscoClassificacao).Estado -eq 'Inconclusivo') 'Ausencia de dados virou saudavel.' }
Test-Case discos 'ocupacao exibe espaco usado e percentual' {
    $text = Invoke-FixtureConsulta discos $false
    Assert-True ($text -match 'Usado_GiB' -and $text -match 'Uso_%' -and $text -match 'C:\s+NTFS\s+100\s+50\s+50\s+50') ('Ocupacao incorreta: ' + $text)
}
Test-Case chromecache 'remove arquivos de cache e preserva dados dos perfis em pasta de teste' {
    $dados = Join-Path $testRoot 'ChromeTeste'
    $cache = Join-Path $dados 'Default\Cache\Cache_Data'
    $perfil = Join-Path $dados 'Profile 1\Cache'
    [void][IO.Directory]::CreateDirectory($cache)
    [void][IO.Directory]::CreateDirectory($perfil)
    $arquivos = @((Join-Path $cache 'f_001'),(Join-Path $perfil 'f_002'))
    $preservados = @((Join-Path $dados 'Default\History'),(Join-Path $dados 'Default\Cookies'),(Join-Path $dados 'Default\Login Data'))
    foreach ($arquivo in ($arquivos + $preservados)) { [IO.File]::WriteAllText($arquivo,'exemplo de teste') }
    $resultado = & $module {
        param($dados)
        function Test-SuporteAdmin { $false }
        function Get-Process { @() }
        Invoke-SuporteCacheChrome -DadosChrome $dados
    } $dados
    Assert-True ($resultado -match '2 arquivos removidos') 'Resumo incorreto.'
    foreach ($arquivo in $arquivos) { Assert-True (-not [IO.File]::Exists($arquivo)) 'Arquivo de cache permaneceu.' }
    foreach ($arquivo in $preservados) { Assert-True ([IO.File]::Exists($arquivo)) 'Dado do perfil foi alterado.' }
}
Test-Case chromecache 'bloqueia a limpeza enquanto o Chrome estiver aberto' {
    $bloqueado = & $module {
        function Test-SuporteAdmin { $false }
        function Get-Process { [pscustomobject]@{Name='chrome'} }
        try { Invoke-SuporteCacheChrome -DadosChrome 'C:\ChromeTesteAusente' | Out-Null; $false }
        catch { $_.Exception.Message -match 'Feche o Chrome' }
    }
    Assert-True $bloqueado 'A limpeza deveria aguardar o fechamento do navegador.'
}
Test-Case chromecache 'preserva pasta externa apontada por juncao no cache' {
    $dados = Join-Path $testRoot 'ChromeJuncao'
    $cache = Join-Path $dados 'Default\Cache'
    $externa = Join-Path $testRoot 'PastaPreservada'
    [void][IO.Directory]::CreateDirectory($cache)
    [void][IO.Directory]::CreateDirectory($externa)
    $arquivo = Join-Path $externa 'preservar.txt'
    [IO.File]::WriteAllText($arquivo,'preservar')
    New-Item -ItemType Junction -Path (Join-Path $cache 'redirecionado') -Target $externa | Out-Null
    $resultado = & $module {
        param($dados)
        function Test-SuporteAdmin { $false }
        function Get-Process { @() }
        Invoke-SuporteCacheChrome -DadosChrome $dados
    } $dados
    Assert-True ([IO.File]::Exists($arquivo) -and $resultado -match '1 itens ignorados') 'O cache seguiu uma juncao para fora do perfil.'
}
Test-Case discos 'Unhealthy prevalece sobre desgaste e erros' { Assert-True ((Get-SuporteDiscoClassificacao Unhealthy 100 1 1).Estado -eq 'Critico/degradado') 'Falha critica perdeu prioridade.' }
Test-Case discos 'desgaste 100 requer atencao' { Assert-True ((Get-SuporteDiscoClassificacao Healthy 100 0 0).Estado -eq 'Atencao') 'Desgaste nao sinalizado.' }
foreach ($sample in @(
    @{Nome='SMART aprovado';Json='{"smart_status":{"passed":true}}';Expected='Sem alertas detectados'},
    @{Nome='SMART falhou';Json='{"smart_status":{"passed":false}}';Expected='Critico/degradado'},
    @{Nome='NVMe critico';Json='{"smart_status":{"passed":true},"nvme_smart_health_information_log":{"critical_warning":4,"percentage_used":1,"media_errors":0}}';Expected='Critico/degradado'},
    @{Nome='ATA setores pendentes';Json='{"smart_status":{"passed":true},"ata_smart_attributes":{"table":[{"id":197,"name":"Pending","raw":{"value":1}}]}}';Expected='Atencao'},
    @{Nome='dados ausentes';Json='{}';Expected='Inconclusivo'}
)) {
    Test-Case diskhealth $sample.Nome {
        $state=& $module { (Get-SuporteSmartClassificacao ($args[0] | ConvertFrom-Json)).Estado } $sample.Json
        Assert-True ($state -eq $sample.Expected) ('Classificacao incorreta: '+$state)
    }
}
Test-Case diskhealth 'nao admin nao executa leitura elevada' {
    $caught=& $module { function Test-SuporteAdmin { $false }; try { Invoke-SuporteOperacao diskhealth -Confirm:$false | Out-Null; $false } catch { $true } }
    Assert-True $caught 'Permissao administrativa nao verificada.'
}

$resultFixture=[pscustomobject]@{Computador='TEST-PC';Consulta='Fixture';Inicio=(Get-Date).ToString('o');Fim=(Get-Date).ToString('o');Status='Teste';Texto='Dado original'}
Test-Case ultimo 'salvamentos repetidos nao sobrescrevem' {
    $p1=Save-SuporteResultado $resultFixture $testRoot; $p2=Save-SuporteResultado $resultFixture $testRoot
    Assert-True ($p1 -ne $p2 -and [IO.File]::ReadAllText($p1).Contains('Dado original') -and [IO.File]::ReadAllText($p2).Contains('Dado original')) 'Arquivos sobrescritos.'
}
Test-Case ultimo 'caminho relativo recusado' { $caught=$false;try{Save-SuporteResultado $resultFixture 'relativo'|Out-Null}catch{$caught=$true};Assert-True $caught 'Caminho relativo aceito.' }

foreach ($kind in @('gphtml','evtx')) {
    Test-Case $kind 'exportacao gera arquivos e manifesto sem sobrescrever (simulado)' {
        $paths=& $module {
            param($kind,$dest)
            function Invoke-SuporteExportNative {
                param($Programa,$Argumentos)
                $path=if($Programa -eq 'gpresult.exe'){$Argumentos[3]}else{$Argumentos[2]}
                [IO.File]::WriteAllText($path,'Arquivo exportado simulado')
            }
            function Test-SuporteEvtx { param($Path) if(-not [IO.File]::Exists($Path)){throw 'Arquivo ausente'} }
            Export-SuporteArquivo $kind $dest
            Export-SuporteArquivo $kind $dest
        } $kind (Join-Path $testRoot $kind)
        $manifests=@(Get-ChildItem -LiteralPath (Join-Path $testRoot $kind) -Recurse -Filter manifesto.json)
        Assert-True ($manifests.Count -eq 2) 'Exportacoes se sobrescreveram ou nao geraram manifesto.'
        foreach($entry in $manifests){
            $m=Get-Content -LiteralPath $entry.FullName -Raw | ConvertFrom-Json
            Assert-True (@($m.Arquivos).Count -ge 1) 'Manifesto sem arquivos.'
            foreach($file in $m.Arquivos){Assert-True ($file.SHA256 -eq (Get-FileHash -LiteralPath (Join-Path $entry.DirectoryName $file.Arquivo) -Algorithm SHA256).Hash) 'Hash incorreto.'}
        }
    }
    Test-Case $kind 'cancelar exportacao nao chama gravacao' {
        $value=& $module {
            param($kind)
            $script:ExportCalled=$false
            function Read-Host { 'n' }
            function Export-SuporteArquivo { $script:ExportCalled=$true }
            Request-SuporteExportar $kind 'C:\Teste' -Escopo User
            $script:ExportCalled
        } $kind
        Assert-True (-not $value) 'Cancelamento tentou gravar.'
    }
    Test-Case $kind 'destino relativo bloqueado antes do processo nativo' {
        $value=& $module { try { Export-SuporteArquivo -Tipo $args[0] -PastaBase relativo | Out-Null; $false } catch { $true } } $kind
        Assert-True $value 'Destino relativo aceito.'
    }
}

Test-Case seguranca 'operacao arbitraria recusada' { $caught=& $module { try { Invoke-SuporteOperacao arbitraria -Confirm:$false; $false } catch { $true } };Assert-True $caught 'Comando livre aceito.' }
Test-Case seguranca 'consulta arbitraria recusada' { $caught=$false;try{Invoke-SuporteConsulta arbitraria|Out-Null}catch{$caught=$true};Assert-True $caught 'Consulta livre aceita.' }
Test-Case seguranca 'forcar fora de GPO recusado' { $caught=& $module {try{Invoke-SuporteOperacao spooler -Forcar -Confirm:$false;$false}catch{$true}};Assert-True $caught 'Force indevido aceito.' }
Test-Case perfillocal 'relaciona .bak e perfil numerado pelo mesmo SID' {
    $plano = & $module {
        function Get-SuporteContaPerfil { 'DOMINIO\aluna' }
        $sid='S-1-5-21-11-22-33-1234'
        $inventario=[pscustomobject]@{
            Raiz='C:\Users'
            Chaves=@([pscustomobject]@{SID=$sid;Nome=$sid;Caminho='C:\Users\aluna.DOMINIO.001'},[pscustomobject]@{SID=$sid;Nome="$sid.bak";Caminho='C:\Users\aluna'})
            Pastas=@([pscustomobject]@{Name='aluna.DOMINIO.001';FullName='C:\Users\aluna.DOMINIO.001'},[pscustomobject]@{Name='aluna';FullName='C:\Users\aluna'})
            Perfis=@([pscustomobject]@{SID=$sid;Special=$false;Loaded=$false;Status=1;LocalPath='C:\Users\aluna.DOMINIO.001'})
        }
        Get-SuportePlanosPerfil $inventario
    }
    Assert-True ($plano.Conta -eq 'DOMINIO\aluna' -and $plano.Temporario -and $plano.Pastas.Count -eq 2 -and $plano.Bloqueios.Count -eq 0) 'Perfil duplicado nao identificado corretamente.'
}
foreach ($modo in @('cancelar','falhar','concluir')) {
    Test-Case perfillocal "procedimento simulado: $modo" {
        $estado = & $module {
            param($modo)
            $script:PerfilTesteModo=$modo
            $script:PerfilTesteChamadas=New-Object 'System.Collections.Generic.List[string]'
            $script:PerfilTesteEntradas=New-Object 'System.Collections.Generic.Queue[string]'
            $script:PerfilTesteEntradas.Enqueue('1')
            if ($modo -eq 'cancelar') { $script:PerfilTesteEntradas.Enqueue('n') }
            else { $script:PerfilTesteEntradas.Enqueue('s'); $script:PerfilTesteEntradas.Enqueue('s') }
            function Read-Host { $script:PerfilTesteEntradas.Dequeue() }
            function Write-Host {}
            function Get-SuporteInventarioPerfis { [pscustomobject]@{Raiz='C:\Users';Registro='HKLM:\Teste'} }
            function Get-SuportePlanosPerfil {
                $sid='S-1-5-21-11-22-33-1234'
                [pscustomobject]@{
                    Conta='DOMINIO\aluna';SID=$sid;Temporario=$true;Bloqueios=@();Incertas=@();Perfil='CIM simulado'
                    Pastas=@('C:\Users\aluna.DOMINIO.001');Chaves=@([pscustomobject]@{Nome=$sid;Caminho='C:\Users\aluna.DOMINIO.001'})
                }
            }
            function Test-SuportePerfilCarregado { $false }
            function Get-SuporteItensPerfil {}
            function Test-Path { $false }
            function Remove-CimInstance {
                $script:PerfilTesteChamadas.Add('excluir')
                if ($script:PerfilTesteModo -eq 'falhar') { throw 'Falha simulada' }
            }
            function Restart-Computer { $script:PerfilTesteChamadas.Add('reiniciar') }
            $falhou=$false
            try { Invoke-SuporteLimpezaPerfil | Out-Null } catch { $falhou=$true }
            [pscustomobject]@{Chamadas=($script:PerfilTesteChamadas -join ',');Falhou=$falhou}
        } $modo
        switch ($modo) {
            'cancelar' { Assert-True (-not $estado.Falhou -and -not $estado.Chamadas) 'Cancelamento alterou o perfil.' }
            'falhar' { Assert-True ($estado.Falhou -and $estado.Chamadas -eq 'excluir') 'A falha nao impediu o reinicio.' }
            'concluir' { Assert-True (-not $estado.Falhou -and $estado.Chamadas -eq 'excluir,reiniciar') 'Reinicio fora da ordem prevista.' }
        }
    }
}
foreach($action in @('spooler','cache','gpcomputer','sfcverify','sfcrepair','dismcheck','dismscan','dismrestore','diskhealth','gpcomputerquery')){
    Test-Case seguranca "$action - usuario comum bloqueado antes do comando" {
        $blocked=& $module {
            param($action)
            function Test-SuporteAdmin {$false}
            try{Invoke-SuporteOperacao $action -Confirm:$false|Out-Null;$false}catch{$_.Exception.Message -match 'elevacao'}
        } $action
        Assert-True $blocked 'Operacao privilegiada nao bloqueou usuario comum.'
    }
}
Test-Case seguranca 'selecao de acao solicita UAC sem confirmacao textual extra' {
    $count=& $module {
        $script:UacCalls=0
        function Read-Host {throw 'Nao deve pedir confirmacao textual'}
        function Test-SuporteAdmin {$false}
        function Start-Process {$script:UacCalls++}
        Request-SuporteOperacao spooler 'C:\Documentos originais'
        $script:UacCalls
    }
    Assert-True ($count -eq 1) 'Acao nao encaminhada ao UAC.'
}
Test-Case seguranca 'elevacao negada nao executa comando e preserva destino original' {
    $check=& $module {
        $script:UacArguments='';$script:OperationCalls=0
        function Test-SuporteAdmin {$false}
        function Read-Host {throw 'Nao deve pedir confirmacao textual'}
        function Start-Process {param($FilePath,$ArgumentList,$Verb,[switch]$PassThru,[switch]$Wait);$script:UacArguments=$ArgumentList;throw 'UAC cancelado simulado'}
        function Invoke-SuporteOperacao {$script:OperationCalls++}
        Request-SuporteOperacao spooler 'C:\Documentos originais'
        [pscustomobject]@{Calls=$script:OperationCalls;Arguments=$script:UacArguments}
    }
    Assert-True ($check.Calls -eq 0) 'UAC negado executou operacao.'
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('C:\Documentos originais'))
    Assert-True ($check.Arguments.Contains($encoded) -and $check.Arguments -match '-ExecutionPolicy RemoteSigned' -and $check.Arguments -notmatch 'Bypass|EncodedCommand|Set-ExecutionPolicy') 'Destino original ou elevacao incorretos.'
}
Test-Case iniciador 'politica temporaria RemoteSigned no iniciador' {
    $launcher=Get-Content -LiteralPath (Join-Path $root 'Iniciar.cmd') -Raw
    Assert-True ($launcher -match '-ExecutionPolicy RemoteSigned -File' -and $launcher -match '%~dp0Iniciar.ps1') 'Iniciador nao configura corretamente o processo local.'
}
Test-Case iniciador 'sem mudanca persistente ou desbloqueio automatico' {
    foreach($file in @('Iniciar.cmd','Iniciar.ps1','Modulos\Operacoes.ps1','Modulos\Elevado.ps1')){
        $code=Get-Content -LiteralPath (Join-Path $root $file) -Raw
        Assert-True ($code -notmatch 'Set-ExecutionPolicy|Unblock-File|-ExecutionPolicy\s+Bypass') ('Alteracao indevida em '+$file)
    }
}
Test-Case diskhealth 'integridade divergente bloqueia smartctl' {
    $blocked=& $module {
        function Get-FileHash { [pscustomobject]@{Hash='HASH_DIVERGENTE'} }
        try{Invoke-SuporteSmartJson @('--scan','-j')|Out-Null;$false}catch{$_.Exception.Message -match 'Integridade'}
    }
    Assert-True $blocked 'Executavel divergente nao foi recusado.'
}

# Navegacao real do menu com entradas controladas: cada opcao e acessada sem executar alteracoes.
foreach($menuItem in Get-SuporteCatalogo){
    Test-Case $menuItem.Id 'navegacao do menu despacha a opcao correta' {
        $check=& $module {
            param($id,$docs)
            $groups=@('Computador','Rede','Windows Update','GPO','Impressao','Relatorios e eventos','Reparos do Windows')
            $catalog=@(Get-SuporteCatalogo);$selected=$catalog | Where-Object Id -eq $id
            $groupIndex=[array]::IndexOf($groups,$selected.Grupo)+1
            $peers=@($catalog | Where-Object Grupo -eq $selected.Grupo)
            $optionIndex=[array]::IndexOf($peers,$selected)+1
            $script:MenuQueue=New-Object 'System.Collections.Generic.Queue[string]'
            foreach($key in @([string]$groupIndex,[string]$optionIndex)){$script:MenuQueue.Enqueue($key)}
            if($id -in @('gpupdateuser','gpupdatecomputer')){$script:MenuQueue.Enqueue('n')}
            if($id -in @('sfc','dism','chkdsk')){$script:MenuQueue.Enqueue('1')}
            if($id -eq 'ping'){$script:MenuQueue.Enqueue('127.0.0.1')}
            foreach($key in @('','0','0')){$script:MenuQueue.Enqueue($key)}
            $script:MenuCalls=New-Object 'System.Collections.Generic.List[string]'
            function Read-Host { if($script:MenuQueue.Count -eq 0){throw 'Menu solicitou entrada inesperada.'};$script:MenuQueue.Dequeue() }
            function Clear-Host {}
            function Write-Host {}
            function Write-SuporteTela {}
            function Show-SuporteResultado {}
            function Show-SuporteMonitor { $script:MenuCalls.Add('monitor') }
            function Request-SuporteSalvar {}
            function Request-SuporteOperacao {param($Acao,$Documentos,[switch]$Forcar);$script:MenuCalls.Add($Acao)}
            function Request-SuporteExportar {param($Tipo,$Documentos);$script:MenuCalls.Add($Tipo)}
            function Invoke-SuporteConsulta {param($Id,$Opcoes,$TimeoutSeconds);$script:MenuCalls.Add($Id);[pscustomobject]@{Status='Teste';Texto='Simulado'}}
            Start-SuporteMenu -ModuleRoot $docs -SemCores
            [pscustomobject]@{Calls=$script:MenuCalls.ToArray();Restantes=$script:MenuQueue.Count}
        } $menuItem.Id $root
        Assert-True ($check.Restantes -eq 0) 'Navegacao nao consumiu as entradas previstas.'
        $expected=switch($menuItem.Id){'gpcomputador'{'gpcomputerquery'};'gpupdateuser'{'gpuser'};'gpupdatecomputer'{'gpcomputer'};'sfc'{'sfcverify'};'dism'{'dismcheck'};'chkdsk'{'chkdskread'};'ultimo'{''};default{$menuItem.Id}}
        if($expected){Assert-True ($check.Calls -contains $expected) ('Despacho incorreto: '+($check.Calls -join ','))}
    }
}

Test-Case seguranca 'menu ignora selecoes invalidas sem executar consulta' {
    $calls=& $module {
        $script:MenuQueue=New-Object 'System.Collections.Generic.Queue[string]'
        foreach($key in @('invalido','99','1','999','-1','0','0')){$script:MenuQueue.Enqueue($key)}
        $script:CallCount=0
        function Read-Host {if($script:MenuQueue.Count -eq 0){throw 'Entrada inesperada'};$script:MenuQueue.Dequeue()}
        function Write-Host {}; function Clear-Host {}; function Write-SuporteTela {}
        function Invoke-SuporteConsulta {$script:CallCount++}
        Start-SuporteMenu -ModuleRoot 'C:\Teste'
        $script:CallCount
    }
    Assert-True ($calls -eq 0) 'Selecao invalida executou consulta.'
}

if ($IncluirConsultasReais) {
    foreach ($query in $queries) {
        Test-Case $query 'smoke real somente leitura, com limite de tempo' {
            $options=@{}
            $answer=Invoke-SuporteConsulta $query -Opcoes $options -TimeoutSeconds 40
            Assert-True ($null -ne $answer -and $answer.Status -and $answer.Texto) 'Contrato de resultado invalido.'
            $script:TestDetail=$answer.Status+'; '+($answer.Texto.Length)+' caracteres; limitacoes: '+(($answer.Texto -split "`n" | Where-Object {$_ -match '^\[INDISPONIVEL\]|^\[ACESSO NEGADO\]'}) -join '; ')
        }
    }
}

# Garantia explicita: pelo menos dois testes para cada opcao do menu.
$coverage=foreach($item in Get-SuporteCatalogo){
    $count=@($results | Where-Object Opcao -eq $item.Id).Count
    [pscustomobject]@{Opcao=$item.Id;Testes=$count;Cobertura=($count -ge 2)}
}
foreach($row in $coverage){if(-not $row.Cobertura){$results.Add([pscustomobject]@{Opcao=$row.Opcao;Teste='Cobertura minima';Resultado='FALHOU';Detalhe='Menos de dois testes.'})}}
$report=Join-Path $root 'Testes\resultado-testes.json'
[pscustomobject]@{Data=(Get-Date).ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();Tipo='Simulacoes controladas; consultas reais apenas com switch';Testes=$results.ToArray();Cobertura=@($coverage)} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $report -Encoding UTF8
$results | Format-Table Opcao,Teste,Resultado,Detalhe -AutoSize
$failed=@($results | Where-Object Resultado -eq 'FALHOU')
Write-Host ('Total: '+$results.Count+' | Falhas: '+$failed.Count+' | Relatorio: '+$report)
if($failed.Count -gt 0){exit 1}
