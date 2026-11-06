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
        function Get-Disk { if($global:SuporteFixtureFailure){throw 'Falha simulada'}; [pscustomobject]@{Number=0;FriendlyName='SSD Fixture';BusType='SATA';HealthStatus='Healthy'} }
        function Get-StorageReliabilityCounter { [CmdletBinding()]param($Disk); [pscustomobject]@{Wear=10;ReadErrorsUncorrected=0;WriteErrorsUncorrected=0} }
        function Get-NetAdapter { if($global:SuporteFixtureFailure){throw 'Falha simulada'}; [pscustomobject]@{Name='Ethernet';InterfaceDescription='Fixture';Status='Up';LinkSpeed='1 Gbps'} }
        function Get-NetIPConfiguration { if($global:SuporteFixtureFailure){throw 'Falha simulada'}; [pscustomobject]@{InterfaceAlias='Ethernet';IPv4Address='192.0.2.2';DNSServer='192.0.2.1'} }
        function Get-NetRoute { if($global:SuporteFixtureFailure){throw 'Falha simulada'}; [pscustomobject]@{DestinationPrefix='0.0.0.0/0';InterfaceAlias='Ethernet';NextHop='192.0.2.1';RouteMetric=10} }
        function Get-WinEvent {
            param($FilterHashtable,$MaxEvents,$ErrorAction)
            if($global:SuporteFixtureFailure){throw 'Acesso negado simulado'}
            [pscustomobject]@{TimeCreated=(Get-Date);Id=100;RecordId=1;LogName=$FilterHashtable.LogName;LevelDisplayName='Warning';ProviderName='Fixture';Message='Evento de teste'}
        }
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

function New-FixtureEventoFalha {
    param([string]$Canal,[string]$Provedor,[int]$Id,[int]$Registro,[datetime]$Hora,[string]$Dados='')
    $evento = [pscustomobject]@{ LogName=$Canal; ProviderName=$Provedor; Id=$Id; RecordId=$Registro; TimeCreated=$Hora; Message='Mensagem de teste'; Xml=$Dados }
    $evento | Add-Member ScriptMethod ToXml { '<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event"><EventData>' + $this.Xml + '</EventData></Event>' }
    $evento
}

function Invoke-FixtureFalhas {
    param([object[]]$Eventos,[switch]$IncluirCodigos)
    function Get-WinEvent {
        param($FilterHashtable,$MaxEvents,$ErrorAction)
        $Eventos | Where-Object {
            $_.LogName -eq $FilterHashtable.LogName -and
            (-not $FilterHashtable.Id -or $_.Id -in $FilterHashtable.Id) -and
            (-not $FilterHashtable.ProviderName -or $_.ProviderName -eq $FilterHashtable.ProviderName)
        }
    }
    if ($IncluirCodigos) { & $collector -Id falhas -Opcoes @{IncluirCodigos=$true} }
    else { & $collector -Id falhas | Out-String }
}

Test-Case falhas 'agrupa reinicio e tela azul com codigo explicado e contexto anterior' {
    $hora = Get-Date
    $eventos = @(
        New-FixtureEventoFalha System disk 153 1 ($hora.AddMinutes(-10))
        New-FixtureEventoFalha System Microsoft-Windows-Kernel-General 12 2 ($hora.AddMinutes(-3))
        New-FixtureEventoFalha System Microsoft-Windows-Kernel-Power 41 3 ($hora.AddMinutes(-2)) '<Data Name="BugcheckCode">278</Data>'
        New-FixtureEventoFalha System Microsoft-Windows-WER-SystemErrorReporting 1001 4 ($hora.AddMinutes(-1)) '<Data Name="param1">0x00000116 (0x0)</Data><Data Name="param2">C:\Windows\MEMORY.DMP</Data>'
        New-FixtureEventoFalha System EventLog 6008 5 ($hora.AddSeconds(-45))
        New-FixtureEventoFalha System Display 4101 6 ($hora.AddSeconds(-20))
    )
    $texto = Invoke-FixtureFalhas $eventos
    Assert-True ($texto -match 'Tela azul.*recuperacao falhou' -and $texto -match '0x00000116 - VIDEO_TDR_FAILURE' -and
        $texto -match 'evento 6008' -and $texto -match 'gravado um arquivo de despejo' -and $texto -match 'gravacao no disco precisou ser repetida' -and
        $texto -notmatch 'evento 4101' -and ([regex]::Matches($texto,'evento 41\b')).Count -eq 1) 'Incidente duplicado, sem traducao ou com pista posterior a inicializacao.'
}

Test-Case falhas 'interpreta codigo decimal e preserva incerteza no reinicio sem codigo' {
    $hora = Get-Date
    $comCodigo = New-FixtureEventoFalha System Microsoft-Windows-Kernel-Power 41 1 $hora '<Data Name="BugcheckCode">159</Data>'
    $semCodigo = New-FixtureEventoFalha System Microsoft-Windows-Kernel-Power 41 2 $hora '<Data Name="BugcheckCode">0</Data>'
    $texto = Invoke-FixtureFalhas @($comCodigo)
    Assert-True ($texto -match '0x0000009F - DRIVER_POWER_STATE_FAILURE' -and $texto -match 'transicao') 'Codigo decimal nao foi traduzido.'
    $texto = Invoke-FixtureFalhas @($semCodigo)
    Assert-True ($texto -match 'nao identificam o motivo' -and $texto -notmatch 'Tela azul|falha de energia') 'Reinicio sem codigo recebeu causa indevida.'
}

Test-Case falhas 'distingue travamento de aplicativo e codigo de parada desconhecido' {
    $hora = Get-Date
    $app = New-FixtureEventoFalha Application 'Application Hang' 1002 1 $hora '<Data Name="AppName">Editor.exe</Data>'
    $outro = New-FixtureEventoFalha Application 'Windows Error Reporting' 1001 2 $hora '<Data Name="param1">0x00000116</Data>'
    $texto = Invoke-FixtureFalhas @($app,$outro)
    Assert-True ($texto -match 'Editor.exe parou de responder' -and $texto -notmatch 'Tela azul') 'Evento de aplicativo confundido com tela azul.'
    $parada = New-FixtureEventoFalha System BugCheck 1001 3 $hora '<Data Name="param1">0x0000ABCD</Data>'
    $texto = Invoke-FixtureFalhas @($parada)
    Assert-True ($texto -match '0x0000ABCD' -and $texto -match 'nao tem descricao no catalogo') 'Codigo desconhecido foi omitido ou recebeu diagnostico indevido.'
}

Test-Case falhas 'traduz excecao de aplicativo e preserva o modulo nos detalhes' {
    $app = New-FixtureEventoFalha Application 'Application Error' 1000 1 (Get-Date) '<Data Name="AppName">Editor.exe</Data><Data Name="ExceptionCode">c0000005</Data><Data Name="ModuleName">ntdll.dll</Data>'
    $texto = Invoke-FixtureFalhas @($app)
    Assert-True ($texto -match 'Editor.exe fechou inesperadamente.*tentou acessar uma area de memoria' -and
        $texto -match 'Modulo registrado: ntdll.dll' -and $texto -match 'Codigo de excecao 0xC0000005') 'A excecao nao foi explicada ou perdeu os detalhes.'
}

Test-Case falhas 'erro sem codigo nao oculta codigos anteriores nem interpreta numeros do texto' {
    $hora = Get-Date
    $semCodigo = New-FixtureEventoFalha Application 'Provedor de teste' 0 10 $hora
    $semCodigo.Message = 'A pasta de teste nao foi encontrada. Registro de operacao 0x80070005.'
    $maisAntigo = New-FixtureEventoFalha Application 'Servico de teste' 9 9 ($hora.AddMinutes(-20)) '<Data Name="NTStatus">0xC0000135</Data>'
    $repetido = New-FixtureEventoFalha Application 'Servico de teste' 9 8 ($hora.AddMinutes(-30)) '<Data Name="NTStatus">0xC0000135</Data>'
    $texto = Invoke-FixtureFalhas @($semCodigo,$maisAntigo,$repetido)
    Assert-True ($texto -match 'evento 0' -and $texto -match 'nao trouxe um codigo' -and
        $texto -match 'NTStatus 0xC0000135' -and $texto -match 'nao encontrou uma biblioteca necessaria' -and
        ([regex]::Matches($texto,'0xC0000135')).Count -eq 1 -and $texto -notmatch 'HRESULT 0x80070005') 'A triagem ocultou codigo anterior, repetiu o codigo ou inferiu codigo pelo texto.'
}

Test-Case falhas 'lista codigos de ocorrencias anteriores sem entrada manual' {
    $hora = Get-Date
    $app = New-FixtureEventoFalha Application 'Application Error' 1000 10 $hora '<Data Name="AppName">Editor.exe</Data><Data Name="ExceptionCode">c0000005</Data>'
    $parada = New-FixtureEventoFalha System BugCheck 1001 9 ($hora.AddMinutes(-40)) '<Data Name="param1">0x00000116 (0x0)</Data>'
    $texto = Invoke-FixtureFalhas @($app,$parada)
    Assert-True ($texto -match 'Codigo de excecao 0xC0000005' -and $texto -match 'Outros codigos de falha encontrados' -and
        $texto -match 'Codigo de parada 0x00000116' -and $texto -match 'recuperacao falhou') 'Um codigo ou sua explicacao ficou de fora da triagem automatica.'
}

Test-Case falhas 'entrega codigos estruturados separadamente do relatorio' {
    $hora = Get-Date
    $win32 = New-FixtureEventoFalha Application 'Servico de teste' 9 10 $hora '<Data Name="Win32ErrorCode">5</Data>'
    $parada = New-FixtureEventoFalha System BugCheck 1001 9 ($hora.AddMinutes(-40)) '<Data Name="param1">0x00000005</Data>'
    $dados = @(Invoke-FixtureFalhas @($win32,$parada) -IncluirCodigos)
    $codigos = @($dados | Where-Object { $_ -isnot [string] })
    Assert-True ($codigos.Count -eq 2 -and ($codigos.Familia -join ',') -eq 'Paradas,Win32' -and
        ($codigos.Codigo -join ',') -eq '0x00000005,0x00000005') 'Codigos iguais de familias diferentes perderam a origem.'
    $texto = ($dados | Where-Object { $_ -is [string] }) -join "`n"
    Assert-True ($texto -match 'Detalhes tecnicos' -and $texto -notmatch 'Familia=|Codigo=') 'O relatorio perdeu os detalhes ou incluiu metadados.'
}

Test-Case falhas 'catalogo indexa as quatro familias e preserva as explicacoes revisadas' {
    $arquivo = Get-Item -LiteralPath (Join-Path $root 'Modulos\CatalogoFalhas.json')
    $dados = Get-Content -LiteralPath $arquivo.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($dados.Versao -eq 2 -and $arquivo.Length -ge 900000 -and $arquivo.Length -le 1000000) 'Versao ou tamanho do catalogo incorreto.'
    foreach ($familia in @($dados.Paradas,$dados.Excecoes,$dados.Win32,$dados.HRESULT)) {
        Assert-True (@($familia.PSObject.Properties).Count -gt 350) 'Familia sem a cobertura esperada.'
        foreach ($entrada in $familia.PSObject.Properties) {
            $regra = $entrada.Value
            Assert-True ($entrada.Name -cmatch '^[0-9A-F]{8}$' -and $regra.Nome -and
                $dados.Fontes.($regra.Fonte) -match '^https://learn\.microsoft\.com/') "Entrada incompleta para $($entrada.Name)."
        }
    }
    $app = New-FixtureEventoFalha Application 'Application Error' 1000 1 (Get-Date) '<Data Name="AppName">Editor.exe</Data><Data Name="ExceptionCode">C0000135</Data>'
    $texto = Invoke-FixtureFalhas @($app)
    Assert-True ($texto -match 'nao encontrou uma biblioteca necessaria' -and $texto -match 'requisitos de instalacao') 'O novo codigo nao foi traduzido pelo coletor.'
}

Test-Case codigofalha 'decodifica decimal, HRESULT negativo e parada com referencia' {
    $win32 = & $collector -Id codigofalha -Opcoes @{Familia='Win32';Codigo='5'} | Out-String
    $hresult = & $collector -Id codigofalha -Opcoes @{Familia='HRESULT';Codigo='-2147024891'} | Out-String
    $parada = & $collector -Id codigofalha -Opcoes @{Familia='Paradas';Codigo='0xC2'} | Out-String
    $familiaErrada = & $collector -Id codigofalha -Opcoes @{Familia='HRESULT';Codigo='0xC0000005'} | Out-String
    Assert-True ($win32 -match '0x00000005' -and $win32 -match 'ERROR_ACCESS_DENIED' -and
        $hresult -match '0x80070005' -and $hresult -match 'E_ACCESSDENIED' -and
        $parada -match 'BAD_POOL_CALLER' -and $parada -match 'learn.microsoft.com') 'O codigo foi interpretado na familia errada ou perdeu a referencia.'
    Assert-True ($familiaErrada -match 'Descricao em portugues indisponivel' -and $familiaErrada -notmatch 'STATUS_ACCESS_VIOLATION') 'A consulta misturou NTSTATUS e HRESULT.'
}

Test-Case codigofalha 'pesquisa sem familia mostra correspondencias e valida a entrada' {
    $ambiguo = & $collector -Id codigofalha -Opcoes @{Codigo='5'} | Out-String
    $hresult = & $collector -Id codigofalha -Opcoes @{Codigo='-2147024891'} | Out-String
    $desconhecido = & $collector -Id codigofalha -Opcoes @{Codigo='0xFFFFFFFF'} | Out-String
    $invalido = & $collector -Id codigofalha -Opcoes @{Codigo='4294967296'} | Out-String
    Assert-True ($ambiguo -match 'mais de um significado' -and $ambiguo -match 'ERROR_ACCESS_DENIED' -and
        $ambiguo -match 'INVALID_PROCESS_ATTACH_ATTEMPT') 'A pesquisa escondeu uma interpretacao do mesmo codigo.'
    Assert-True ($hresult -match '0x80070005' -and $hresult -match 'E_ACCESSDENIED' -and $hresult -notmatch 'Win32 \|') 'A pesquisa misturou o HRESULT com Win32.'
    Assert-True ($desconhecido -match '0xFFFFFFFF: codigo sem correspondencia' -and
        $invalido -match 'Informe um numero decimal de 32 bits') 'A pesquisa nao distinguiu codigo desconhecido de entrada invalida.'
}

Test-Case falhas 'catalogo indisponivel preserva o codigo de parada e a ocorrencia' {
    function Get-Content {
        param($LiteralPath,[switch]$Raw,$Encoding,$ErrorAction)
        throw 'Catalogo simulado indisponivel.'
    }
    $parada = New-FixtureEventoFalha System BugCheck 1001 1 (Get-Date) '<Data Name="param1">0x000000EF</Data>'
    $texto = Invoke-FixtureFalhas @($parada)
    Assert-True ($texto -match '\[INDISPONIVEL\] Catalogo' -and $texto -match 'registrou uma tela azul' -and $texto -match '0x000000EF') 'Falha no catalogo ocultou a ocorrencia.'
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
Test-Case discos 'status e barra de desgaste usam a mesma cor no console' {
    $linhas = & $module {
        function Get-SuporteLargura { 100 }
        function Write-Host {
            param($Object,$ForegroundColor)
            if ($Object -match '^(\[INDISPONIVEL\] )?Disco|^  (Desgaste estimado:|\[[#-]+\]$)') {
                [pscustomobject]@{Texto=$Object;Cor=$ForegroundColor}
            }
        }
        $texto = @(
            'Disco 0 (SSD): Sem alertas detectados. Desgaste estimado: 25% usado.'
            'Disco 1 (NVMe): Atencao - avaliar troca. Desgaste estimado: 105% usado.'
            'Disco 2 (HDD): Troca recomendada. Priorize o backup.'
            '[INDISPONIVEL] Disco 3 (SSD): Inconclusivo. Desgaste estimado: 0% usado.'
        ) -join "`n"
        $resultado = [pscustomobject]@{Status='Concluido';Texto=$texto}
        Show-SuporteResultado $resultado
        Show-SuporteResultado $resultado -SemCores
    }
    Assert-True ($linhas.Count -eq 20 -and ($linhas[0..9].Cor -join ',') -eq 'Blue,Blue,Blue,Yellow,Yellow,Yellow,Red,Gray,Gray,Gray') 'Cores dos discos ou barras incorretas.'
    Assert-True ($linhas[2].Texto -eq '  [#####---------------]' -and $linhas[4].Texto -match '105%' -and
        $linhas[5].Texto -eq '  [####################]' -and $linhas[9].Texto -eq '  [--------------------]') 'Proporcao da barra ou percentual de desgaste incorreto.'
    Assert-True (($linhas[10..19].Cor -join '') -eq '' -and ($linhas[10..19].Texto -join "`n") -eq ($linhas[0..9].Texto -join "`n")) 'SemCores alterou o conteudo ou manteve cores.'
}
Test-Case diskhealth 'encaminha SemCores para a janela elevada' {
    $argumentos = & $module {
        function Test-SuporteAdmin { $false }
        function Write-Host {}
        function Start-Process {
            param($FilePath,$ArgumentList,$Verb,[switch]$PassThru,[switch]$Wait)
            $script:ArgumentosDiscoTeste = $ArgumentList
            [pscustomobject]@{ExitCode=0}
        }
        Request-SuporteOperacao diskhealth 'C:\Documentos' -SemCores
        $script:ArgumentosDiscoTeste
    }
    Assert-True ($argumentos -match '-Acao diskhealth -Documentos64 \S+ -SemCores;') 'A preferencia de cores nao chegou a janela elevada.'
}
Test-Case bateria 'barra usa capacidade relativa com decimal local e omite dado ausente' {
    $linhas = & $module {
        function Get-SuporteLargura { 100 }
        function Write-Host {
            param($Object,$ForegroundColor)
            if ($Object -match '^  \[[#-]+\]$') {
                [pscustomobject]@{Texto=$Object;Cor=$ForegroundColor}
            }
        }
        $resultado = [pscustomobject]@{Status='Concluido';Texto=( @(
            'Bateria 1: 82,5% da capacidade original (41,25 Wh de 50 Wh).'
            'Bateria 2: 105% da capacidade original (21 Wh de 20 Wh).'
            '[INDISPONIVEL] Bateria 3: Capacidade nao informada.'
        ) -join "`n" )}
        Show-SuporteResultado $resultado
        Show-SuporteResultado $resultado -SemCores
    }
    Assert-True ($linhas.Count -eq 4 -and ($linhas[0..1].Cor -join ',') -eq 'Blue,Blue' -and
        $linhas[0].Texto -eq '  [################----]' -and $linhas[1].Texto -eq '  [####################]' -and
        ($linhas[2..3].Cor -join '') -eq '') 'Barras de capacidade incorretas.'
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
    Assert-True ($text -match 'Volume C: \(NTFS\)\s+\[#####-----\] 50% usado' -and $text -match 'Total: 100 GiB \| Usado: 50 GiB \| Livre: 50 GiB') ('Ocupacao incorreta: ' + $text)
}
Test-Case discos 'console estreito preserva texto e alinha barra de desgaste' {
    $linhas = & $module {
        function Get-SuporteLargura { 36 }
        function Write-Host { param($Object,$ForegroundColor); [string]$Object }
        $r = [pscustomobject]@{Status='Concluido';Texto='Disco 1 (KINGSTON SA400S37960G): Sem alertas detectados. Nenhum alerta nos indicadores verificados. Desgaste estimado: 13% usado. Resistencia restante: 87%.'}
        Show-SuporteResultado $r
    }
    Assert-True (@($linhas | Where-Object Length -gt 36).Count -eq 0 -and ($linhas -join ' ') -match 'KINGSTON SA400S37960G' -and
        ($linhas -join ' ') -match '87%' -and $linhas -contains '  [##------------------]') 'Console estreito perdeu texto ou desalinhou o grafico.'
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
    @{Nome='NVMe com confiabilidade degradada';Json='{"smart_status":{"passed":false},"nvme_smart_health_information_log":{"critical_warning":4,"percentage_used":1,"media_errors":0}}';Expected='Critico/degradado';Motivo='perda de confiabilidade'},
    @{Nome='NVMe com alerta apenas de temperatura';Json='{"smart_status":{"passed":false,"nvme":{"value":2}},"nvme_smart_health_information_log":{"critical_warning":2,"media_errors":0}}';Expected='Atencao';Motivo='temperatura'},
    @{Nome='NVMe com reserva baixa e log indisponivel';Json='{"smart_status":{"passed":false,"nvme":{"value":1}}}';Expected='Atencao';Motivo='reserva'},
    @{Nome='NVMe somente leitura prevalece sobre alerta termico';Json='{"smart_status":{"passed":false,"nvme":{"value":10}},"nvme_smart_health_information_log":{"critical_warning":10,"media_errors":0}}';Expected='Critico/degradado';Motivo='somente leitura'},
    @{Nome='NVMe com erros de midia e SMART global aprovado';Json='{"smart_status":{"passed":true},"nvme_smart_health_information_log":{"critical_warning":0,"media_errors":1}}';Expected='Atencao';Motivo='integridade'},
    @{Nome='NVMe com aviso global sem motivo especificado';Json='{"device":{"protocol":"NVMe"},"smart_status":{"passed":false}}';Expected='Atencao';Motivo='outro alerta'},
    @{Nome='ATA setores pendentes';Json='{"smart_status":{"passed":true},"ata_smart_attributes":{"table":[{"id":197,"name":"Current_Pending_Sector","raw":{"value":1}}]}}';Expected='Atencao'},
    @{Nome='dados ausentes';Json='{}';Expected='Inconclusivo'}
)) {
    Test-Case diskhealth $sample.Nome {
        $classificacao=& $module { Get-SuporteSmartClassificacao ($args[0] | ConvertFrom-Json) } $sample.Json
        Assert-True ($classificacao.Estado -eq $sample.Expected) ('Classificacao incorreta: '+$classificacao.Estado)
        if ($sample.Motivo) { Assert-True ($classificacao.Motivos -match $sample.Motivo) ('Motivo incorreto: '+$classificacao.Motivos) }
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

# Pacote de teste para a entrada elevada: copia real dos arquivos com Elevado.ps1 substituido.
function New-FixturePacoteElevado {
    param([string]$Nome)
    $pacote = Join-Path $testRoot $Nome
    foreach ($pasta in @('Modulos','Recursos','Ferramentas\smartmontools\bin')) { [void][IO.Directory]::CreateDirectory((Join-Path $pacote $pasta)) }
    foreach ($arquivo in [IO.Directory]::GetFiles((Join-Path $root 'Modulos'))) { [IO.File]::Copy($arquivo,(Join-Path $pacote ('Modulos\'+[IO.Path]::GetFileName($arquivo)))) }
    foreach ($relativo in @('Recursos\SuporteTI.Windows.dll','Ferramentas\smartmontools\integridade.json','Ferramentas\smartmontools\bin\smartctl.exe','Ferramentas\smartmontools\bin\drivedb.h')) {
        [IO.File]::Copy((Join-Path $root $relativo),(Join-Path $pacote $relativo))
    }
    $marca = Join-Path $testRoot ($Nome+'-marca.txt')
    $stub = "param([string]`$Acao,[string]`$Documentos64,[switch]`$Forcar,[switch]`$SemCores)`r`n" +
        "[IO.File]::WriteAllText('$marca',(`$PSScriptRoot+'|'+`$Acao+'|'+[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String(`$Documentos64))+'|'+`$SemCores))`r`nexit 7`r`n"
    [IO.File]::WriteAllText((Join-Path $pacote 'Modulos\Elevado.ps1'),$stub,[Text.Encoding]::ASCII)
    [pscustomobject]@{Pacote=$pacote;Marca=$marca}
}
function Invoke-FixtureEntradaElevada {
    # Executa a entrada elevada sem UAC. O SID atual entra na ACL somente neste teste.
    param([string]$Pacote,[string]$Digest,[switch]$ExigirAssinatura)
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $documentos = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('C:\Pasta com espaco'))
    $comando = & $module {
        param($p,$d,$a,$s,$assinatura)
        Get-SuporteComandoElevado -Raiz $p -Digest $d -Argumentos $a -SidsExtras $s -ExigirAssinatura:$assinatura
    } $Pacote $Digest ('-Acao spooler -Documentos64 '+$documentos+' -SemCores') $sid ([bool]$ExigirAssinatura)
    $entrada = Join-Path $testRoot ([guid]::NewGuid().ToString('N')+'-entrada.txt'); [IO.File]::WriteAllText($entrada,'')
    $saida = Join-Path $testRoot ([guid]::NewGuid().ToString('N')+'-saida.txt')
    $processo = Start-Process (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList ('-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command '+$comando) -RedirectStandardInput $entrada -RedirectStandardOutput $saida -PassThru -WindowStyle Hidden
    $null = $processo.Handle # Sem guardar o handle, o PowerShell 5.1 perde o ExitCode.
    if (-not $processo.WaitForExit(60000)) { $processo.Kill(); throw 'Entrada elevada excedeu 60 segundos.' }
    [pscustomobject]@{Codigo=$processo.ExitCode;Saida=[IO.File]::ReadAllText($saida)}
}
Test-Case seguranca 'janela elevada executa somente a copia conferida e remove a copia' {
    $fixture = New-FixturePacoteElevado 'pacote-elevado-ok'
    [IO.File]::SetAttributes((Join-Path $fixture.Pacote 'Modulos\Elevado.ps1'),[IO.FileAttributes]::ReadOnly)
    $digest = & $module { param($p) Get-SuporteDigestPacote $p } $fixture.Pacote
    $resultado = Invoke-FixtureEntradaElevada $fixture.Pacote $digest
    Assert-True ($resultado.Codigo -eq 7) ('Codigo de saida nao propagado: '+$resultado.Codigo+' '+$resultado.Saida)
    $campos = [IO.File]::ReadAllText($fixture.Marca).Split('|')
    $copia = Split-Path $campos[0] -Parent
    Assert-True ($copia.StartsWith((Join-Path $env:SystemRoot 'Temp\SuporteTI_'),[StringComparison]::OrdinalIgnoreCase)) ('Elevado.ps1 nao rodou da copia protegida: '+$campos[0])
    Assert-True ($campos[1] -eq 'spooler' -and $campos[2] -eq 'C:\Pasta com espaco' -and $campos[3] -eq 'True') 'Argumentos nao chegaram intactos.'
    Assert-True (-not [IO.Directory]::Exists($copia)) ('Copia temporaria permaneceu: '+$copia)
}
Test-Case seguranca 'RemoteSigned bloqueia na copia um script sem assinatura com marca da Internet' {
    $fixture = New-FixturePacoteElevado 'pacote-elevado-internet'
    $worker = Join-Path $fixture.Pacote 'Modulos\Elevado.ps1'
    Set-Content -LiteralPath $worker -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3"
    $digest = & $module { param($p) Get-SuporteDigestPacote $p } $fixture.Pacote
    $resultado = Invoke-FixtureEntradaElevada $fixture.Pacote $digest
    Assert-True ($resultado.Codigo -eq 1 -and -not [IO.File]::Exists($fixture.Marca)) 'A copia executou um script que RemoteSigned deveria bloquear.'
    Assert-True ($resultado.Saida -match 'Falha:') 'O bloqueio nao foi informado.'
}
Test-Case seguranca 'origem em rede e reconhecida antes de copiar o pacote' {
    $rede = & $module { Test-SuporteOrigemRede '\\servidor.invalid\compartilhamento\Suporte TI' }
    $local = & $module { param($p) Test-SuporteOrigemRede $p } $testRoot
    Assert-True ($rede -and -not $local) 'A classificacao de caminho UNC ou local esta incorreta.'
}
Test-Case seguranca 'origem em rede recusa script sem assinatura mesmo sob RemoteSigned' {
    $fixture = New-FixturePacoteElevado 'pacote-elevado-rede'
    $digest = & $module { param($p) Get-SuporteDigestPacote $p } $fixture.Pacote
    $resultado = Invoke-FixtureEntradaElevada $fixture.Pacote $digest -ExigirAssinatura
    Assert-True ($resultado.Codigo -eq 1 -and -not [IO.File]::Exists($fixture.Marca)) 'Um pacote sem assinatura passou pela verificacao de rede.'
    Assert-True ($resultado.Saida -match 'rede exige assinatura valida') 'A exigencia de assinatura nao foi informada.'
}
Test-Case seguranca 'pacote alterado depois da abertura bloqueia a janela elevada' {
    $fixture = New-FixturePacoteElevado 'pacote-elevado-alterado'
    $digest = & $module { param($p) Get-SuporteDigestPacote $p } $fixture.Pacote
    [IO.File]::AppendAllText((Join-Path $fixture.Pacote 'Modulos\Elevado.ps1'),"# alteracao posterior`r`n")
    $resultado = Invoke-FixtureEntradaElevada $fixture.Pacote $digest
    Assert-True ($resultado.Codigo -eq 1) ('Pacote alterado nao terminou com codigo 1: '+$resultado.Codigo)
    Assert-True (-not [IO.File]::Exists($fixture.Marca)) 'Elevado.ps1 alterado chegou a rodar.'
    Assert-True ($resultado.Saida -match 'mudaram depois da abertura') 'Motivo do bloqueio nao foi exibido.'
}
Test-Case seguranca 'impressao do pacote cobre modulos, DLL e smartctl' {
    $fixture = New-FixturePacoteElevado 'pacote-impressao'
    $inicial = & $module { param($p) Get-SuporteDigestPacote $p } $fixture.Pacote
    Assert-True ($inicial -match '^[0-9A-F]{64}$') 'Impressao em formato inesperado.'
    foreach ($relativo in @('Recursos\SuporteTI.Windows.dll','Ferramentas\smartmontools\bin\smartctl.exe','Modulos\CatalogoFalhas.json')) {
        $caminho = Join-Path $fixture.Pacote $relativo
        $original = [IO.File]::ReadAllBytes($caminho)
        [IO.File]::WriteAllBytes($caminho,$original + [byte]0)
        $alterada = & $module { param($p) Get-SuporteDigestPacote $p } $fixture.Pacote
        [IO.File]::WriteAllBytes($caminho,$original)
        Assert-True ($alterada -ne $inicial) ('Alteracao nao detectada em '+$relativo)
    }
    [IO.File]::WriteAllText((Join-Path $fixture.Pacote 'Modulos\Extra.ps1'),'# novo')
    Assert-True ((& $module { param($p) Get-SuporteDigestPacote $p } $fixture.Pacote) -ne $inicial) 'Arquivo novo em Modulos nao foi detectado.'
}
Test-Case seguranca 'comando elevado usa aspas simples, tamanho limitado e entradas validadas' {
    $check = & $module {
        $documentos = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('C:\Users\Teste\Documents'))
        $comando = Get-SuporteComandoElevado -Raiz (Split-Path $PSScriptRoot -Parent) -Digest $script:SuporteDigestPacote -Argumentos ('-Acao dismrestore -Documentos64 '+$documentos+' -Forcar -SemCores')
        $recusas = 0
        try { Get-SuporteComandoElevado -Raiz 'C:\' -Digest 'abc' -Argumentos '-Acao spooler' | Out-Null } catch { $recusas++ }
        try { Get-SuporteComandoElevado -Raiz 'C:\' -Digest ('A'*64) -Argumentos '-Acao spooler; Remove-Item C:\' | Out-Null } catch { $recusas++ }
        try { Get-SuporteComandoElevado -Raiz 'C:\' -Digest ('A'*64) -Argumentos '-Acao spooler' -SidsExtras 'Everyone' | Out-Null } catch { $recusas++ }
        [pscustomobject]@{Comando=$comando;Recusas=$recusas;Digest=$script:SuporteDigestPacote}
    }
    Assert-True ($check.Digest -match '^[0-9A-F]{64}$') 'Impressao do pacote nao registrada na abertura.'
    Assert-True (-not $check.Comando.Contains('"') -and $check.Comando -notmatch '[\r\n]') 'Comando elevado contem aspas duplas ou quebras de linha.'
    Assert-True ($check.Comando.Length -lt 6000) ('Comando elevado longo demais: '+$check.Comando.Length)
    Assert-True ($check.Comando -match "'S-1-5-32-544','S-1-5-18'\)" -and $check.Comando -match '-Acao dismrestore -Documentos64 \S+ -Forcar -SemCores;') 'ACL ou argumentos do comando elevado incorretos.'
    Assert-True ($check.Recusas -eq 3) 'Entradas invalidas foram aceitas no comando elevado.'
    $script:TestDetail = 'Tamanho do comando: '+$check.Comando.Length
}
Test-Case seguranca 'AllSigned somente quando todos os scripts tem assinatura valida' {
    $politicas = & $module {
        $raiz = Split-Path $PSScriptRoot -Parent
        function Get-AuthenticodeSignature { param($LiteralPath) [pscustomobject]@{Status='Valid'} }
        Get-SuportePoliticaElevacao $raiz
        function Get-AuthenticodeSignature { param($LiteralPath) [pscustomobject]@{Status=$(if($LiteralPath -like '*Elevado.ps1'){'NotSigned'}else{'Valid'})} }
        Get-SuportePoliticaElevacao $raiz
    }
    Assert-True (($politicas -join ',') -eq 'AllSigned,RemoteSigned') ('Politica incorreta: '+($politicas -join ','))
}
Test-Case diskhealth 'integridade divergente bloqueia smartctl' {
    $blocked=& $module {
        function Get-FileHash { [pscustomobject]@{Hash='HASH_DIVERGENTE'} }
        try{Invoke-SuporteSmartJson @('--scan','-j')|Out-Null;$false}catch{$_.Exception.Message -match 'Integridade'}
    }
    Assert-True $blocked 'Executavel divergente nao foi recusado.'
}

Test-Case diskhealth 'relatorio consolida discos internos e preserva alerta em leitura parcial' {
    $resumo = & $module {
        function Get-Disk {
            [pscustomobject]@{Number=0;FriendlyName='HDD teste';BusType='SATA';HealthStatus='Healthy'}
            [pscustomobject]@{Number=1;FriendlyName='SSD teste';BusType='NVMe';HealthStatus='Healthy'}
            [pscustomobject]@{Number=2;FriendlyName='USB teste';BusType='USB';HealthStatus='Unhealthy'}
            [pscustomobject]@{Number=3;FriendlyName='RAID teste';BusType='RAID';HealthStatus='Unhealthy'}
        }
        function Get-StorageReliabilityCounter { param($Disk); throw 'Contadores nativos indisponiveis.' }
        function Invoke-SuporteSmartJson {
            param($Argumentos)
            switch ($Argumentos[-1]) {
                '/dev/pd0' { [pscustomobject]@{Codigo=12;Dados=(' {"smart_status":{"passed":false}}' | ConvertFrom-Json)} }
                '/dev/pd1' {
                    if ($Argumentos -notcontains 'nvme') { throw 'Tipo de dispositivo incorreto.' }
                    [pscustomobject]@{Codigo=0;Dados=(' {"smart_status":{"passed":true},"nvme_smart_health_information_log":{"percentage_used":105}}' | ConvertFrom-Json)}
                }
                default { throw 'Dispositivo fora do escopo.' }
            }
        }
        @(Get-SuporteSmartResumo)
    }
    Assert-True ($resumo.Count -eq 2 -and $resumo[0] -match 'Disco 0.*Troca recomendada.*SMART parcial' -and
        $resumo[1] -match 'Disco 1.*Atencao.*105% usado') 'Resumo incorreto ou disco externo consultado.'
}

Test-Case diskhealth 'SMART parcial sem alertas permanece inconclusivo' {
    $estado = & $module { (Get-SuporteSmartClassificacao ('{"smart_status":{"passed":true}}' | ConvertFrom-Json) 4).Estado }
    Assert-True ($estado -eq 'Inconclusivo') 'O resumo aceitou leitura SMART parcial como suficiente.'
}

Test-Case diskhealth 'HDD omite Wear do Windows e SSD com desgaste elevado recebe atencao' {
    $resumo = & $module {
        function Get-Disk {
            foreach ($numero in 0..3) {
                [pscustomobject]@{Number=$numero;FriendlyName="Disco teste $numero";BusType='SATA';HealthStatus='Healthy'}
            }
        }
        function Get-StorageReliabilityCounter {
            param($Disk)
            [pscustomobject]@{Wear=$(if ($Disk.Number -eq 2) { 80 } else { 0 })}
        }
        function Invoke-SuporteSmartJson {
            param($Argumentos)
            $dados = switch ($Argumentos[-1]) {
                '/dev/pd0' { '{"smart_status":{"passed":true},"rotation_rate":7200}' }
                '/dev/pd1' { '{"smart_status":{"passed":true},"rotation_rate":0,"endurance_used":{"current_percent":87}}' }
                '/dev/pd2' { '{"smart_status":{"passed":true},"rotation_rate":0}' }
                '/dev/pd3' { '{"smart_status":{"passed":true},"rotation_rate":0,"endurance_used":{"current_percent":79}}' }
            }
            [pscustomobject]@{Codigo=0;Dados=($dados | ConvertFrom-Json)}
        }
        @(Get-SuporteSmartResumo)
    }
    Assert-True ($resumo.Count -eq 4 -and $resumo[0] -match 'Sem alertas' -and $resumo[0] -notmatch 'Desgaste estimado' -and
        $resumo[1] -match 'Atencao.*troca preventiva.*87% usado' -and $resumo[2] -match 'Atencao.*80% usado' -and
        $resumo[3] -match 'Sem alertas.*79% usado') 'Desgaste exibido para HDD ou limiar preventivo aplicado incorretamente.'
}

Test-Case diskhealth 'desgaste SATA usa formato confirmado e rejeita atributo ambiguo' {
    $valores = & $module {
        $dados = '{"model_name":"CT500MX500SSD1","ata_smart_attributes":{"table":[{"id":202,"name":"Percent_Lifetime_Remain","value":78,"raw":{"value":22}}]}}' | ConvertFrom-Json
        (Get-SuporteSmartClassificacao $dados).Desgaste
        $dados.ata_smart_attributes.table[0].raw.value = 78
        $null -eq (Get-SuporteSmartClassificacao $dados).Desgaste
        $dados.ata_smart_attributes.table[0].raw.value = 22
        $dados.model_name = 'SSD modelo desconhecido'
        $null -eq (Get-SuporteSmartClassificacao $dados).Desgaste
    }
    Assert-True ($valores[0] -eq 22 -and $valores[1] -and $valores[2]) 'A regra de desgaste foi aplicada fora do modelo ou do formato validado.'
}

Test-Case diskhealth 'A400 SBFK interpreta E7 bruto como restante e ignora agregado invertido' {
    $resumo = & $module {
        function Get-Disk { [pscustomobject]@{Number=1;FriendlyName='KINGSTON SA400S37960G';BusType='SATA';HealthStatus='Healthy'} }
        function Get-StorageReliabilityCounter { param($Disk); [pscustomobject]@{Wear=87} }
        function Invoke-SuporteSmartJson {
            $dados = '{"model_name":"KINGSTON SA400S37960G","firmware_version":"SBFK61F1","smart_status":{"passed":true},"endurance_used":{"current_percent":87},"ata_smart_attributes":{"table":[{"id":231,"value":13,"raw":{"value":87}}]}}' | ConvertFrom-Json
            [pscustomobject]@{Codigo=0;Dados=$dados}
        }
        Get-SuporteSmartResumo
    }
    Assert-True ($resumo -match 'Sem alertas detectados.*13% usado\. Resistencia restante: 87%\.') 'O Kingston teve o desgaste invertido ou recebeu alerta indevido.'
}

Test-Case diskhealth 'A400 seleciona E7 pelo firmware e omite desgaste ambiguo' {
    $valores = & $module {
        $dados = '{"model_name":"KINGSTON SA400S37960G","firmware_version":"03070009","endurance_used":{"current_percent":13},"ata_smart_attributes":{"table":[{"id":231,"value":87,"raw":{"value":13}}]}}' | ConvertFrom-Json
        (Get-SuporteSmartClassificacao $dados).Desgaste
        $dados.firmware_version = 'DESCONHECIDO'
        $null -eq (Get-SuporteSmartClassificacao $dados).Desgaste
        $dados.firmware_version = 'SBFK61F1'
        $dados.ata_smart_attributes.table[0].raw.value = 101
        $null -eq (Get-SuporteSmartClassificacao $dados).Desgaste
    }
    Assert-True ($valores[0] -eq 13 -and $valores[1] -and $valores[2]) 'Firmware ou valor fora da faixa produziram percentual incorreto.'
}

Test-Case bateria 'relatorio com namespace calcula capacidade de cada bateria' {
    $xml = Join-Path $testRoot 'baterias.xml'
    [IO.File]::WriteAllText($xml,'<BatteryReport xmlns="urn:schemas-microsoft-com:batteryreport"><Batteries><Battery><DesignCapacity>50000</DesignCapacity><FullChargeCapacity>40000</FullChargeCapacity></Battery><Battery><DesignCapacity>20000</DesignCapacity><FullChargeCapacity>21000</FullChargeCapacity></Battery></Batteries></BatteryReport>')
    $linhas = & $module { Get-SuporteBateriaResumo $args[0] } $xml
    Assert-True ($linhas.Count -eq 2 -and $linhas[0] -match 'Bateria 1: 80%.*40 Wh de 50 Wh' -and
        $linhas[1] -match 'Bateria 2: 105%.*21 Wh de 20 Wh') 'Resumo da capacidade incorreto.'
}

Test-Case bateria 'distingue capacidade ausente de nenhuma bateria' {
    $xml = Join-Path $testRoot 'bateria-ausente.xml'
    [IO.File]::WriteAllText($xml,'<BatteryReport><Batteries><Battery><DesignCapacity>4294967295</DesignCapacity><FullChargeCapacity>20000</FullChargeCapacity></Battery></Batteries></BatteryReport>')
    $indisponivel = & $module { Get-SuporteBateriaResumo $args[0] } $xml
    [IO.File]::WriteAllText($xml,'<BatteryReport><Batteries/></BatteryReport>')
    $vazio = & $module { Get-SuporteBateriaResumo $args[0] } $xml
    Assert-True ($indisponivel -match 'Capacidade nao informada' -and $vazio -match 'Nenhuma bateria detectada') 'Ausencia de dados foi confundida com ausencia de bateria.'
}

Test-Case bateria 'desktop com nobreak USB exibe a opcao e informa que nao se aplica' {
    $saida = & $module {
        function Get-CimInstance {
            param($ClassName,$OperationTimeoutSec)
            if ($ClassName -eq 'Win32_SystemEnclosure') { [pscustomobject]@{ChassisTypes=@(3)} }
            else { [pscustomobject]@{PNPDeviceID='USB\VID_0000'} }
        }
        $script:MenuQueue = New-Object 'System.Collections.Generic.Queue[string]'
        foreach ($entrada in @('1','13','n','0','','')) { $script:MenuQueue.Enqueue($entrada) }
        function Read-Host { $script:MenuQueue.Dequeue() }
        $script:SaidaMenuTeste = New-Object 'System.Collections.Generic.List[string]'
        function Write-Host { $script:SaidaMenuTeste.Add(($args -join ' ')) }
        function Write-SuporteTela {}
        function Invoke-SuporteConsulta {
            param($Id)
            $texto = & $argsCollector -Id $Id | Out-String
            [pscustomobject]@{Status='Concluido';Texto=$texto}
        }
        $argsCollector = $args[0]
        Start-SuporteMenu -ModuleRoot 'C:\Teste' -SemCores
        $script:SaidaMenuTeste.ToArray()
    } $collector
    Assert-True (($saida -join "`n") -match '\[13\] Saude da bateria' -and ($saida -join "`n") -match 'nao se aplica a desktop') 'Desktop nao apresentou opcao ou explicacao.'
}

Test-Case mapaocupacao 'varredura agrega tamanhos e para de forma segura ao atingir limite' {
    & $module { Import-SuporteWindows }
    $pasta = Join-Path $testRoot 'mapa'
    $dados = Join-Path $pasta 'Dados'
    [void][IO.Directory]::CreateDirectory($dados)
    [IO.File]::WriteAllBytes((Join-Path $dados 'maior.bin'),[byte[]]::new(3072))
    [IO.File]::WriteAllBytes((Join-Path $pasta 'menor.bin'),[byte[]]::new(1024))
    $outro = Join-Path $testRoot 'fora-do-mapa'
    [void][IO.Directory]::CreateDirectory($outro)
    [IO.File]::WriteAllBytes((Join-Path $outro 'externo.bin'),[byte[]]::new(8192))
    New-Item -ItemType Junction -Path (Join-Path $pasta 'atalho') -Target $outro | Out-Null
    $token = [Threading.CancellationToken]::None
    $completo = [SuporteTI.VarreduraOcupacao]::Ler($pasta,100,5,$token)
    $parcial = [SuporteTI.VarreduraOcupacao]::Ler($pasta,1,5,$token)
    Assert-True ($completo.Raiz.Bytes -eq 4096 -and $completo.Ignorados -eq 1 -and $completo.Raiz.Filhos[0].Nome -eq 'Dados' -and
        $parcial.Limite -match 'limite de itens' -and $parcial.Raiz.Bytes -lt 4096) 'Mapa contou a juncao ou errou a soma e o limite.'
}

Test-Case mapaocupacao 'janela desenha cores e permite navegar para a subpasta' {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $pasta = Join-Path $testRoot 'mapa'
    $r = [SuporteTI.VarreduraOcupacao]::Ler($pasta,100,5,[Threading.CancellationToken]::None)
    $form = New-Object SuporteTI.MapaOcupacao
    $flags = [Reflection.BindingFlags]'Instance,NonPublic'
    $tipo = $form.GetType()
    $painel = $tipo.GetField('desenho',$flags).GetValue($form)
    $bitmap = New-Object Drawing.Bitmap($painel.Width,$painel.Height)
    $tela = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $tipo.GetMethod('Exibir',$flags).Invoke($form,@($r.Raiz))
        $tipo.GetMethod('Desenhar',$flags).Invoke($form,@($tela))
        $blocos = $tipo.GetField('blocos',$flags).GetValue($form)
        $internos = $tipo.GetField('blocosInternos',$flags).GetValue($form)
        Assert-True ($blocos.Count -eq 2 -and $internos.Count -eq 1) 'A janela nao desenhou pastas e arquivos.'
        Assert-True ($bitmap.GetPixel(8,22).ToArgb() -ne $bitmap.GetPixel($painel.Width-8,22).ToArgb()) 'Os blocos nao apresentaram cores distintas.'
        $tipo.GetMethod('Entrar',$flags).Invoke($form,@($r.Raiz.Filhos[0]))
        $lista = $tipo.GetField('lista',$flags).GetValue($form)
        Assert-True ($lista.Items.Count -eq 1 -and $lista.Items[0].Text -eq 'maior.bin') 'A lista nao acompanhou a navegacao.'
    } finally { $tela.Dispose(); $bitmap.Dispose(); $form.Dispose() }
}

function New-FixtureWinlogon {
    $chave = [pscustomobject]@{ Valores=@{AutoAdminLogon='0';DefaultUserName='anterior'}; Falhar=$false }
    $chave | Add-Member ScriptMethod GetValue { param($nome); if($nome -eq 'DefaultPassword'){throw 'Senha legada foi lida.'}; $this.Valores[$nome] }
    $chave | Add-Member ScriptMethod GetValueNames { [string[]]@($this.Valores.Keys) }
    $chave | Add-Member ScriptMethod SetValue {
        param($nome,$valor,$tipo)
        if($this.Falhar -and $nome -eq 'AutoAdminLogon' -and $valor -eq '1'){throw 'Falha simulada de registro.'}
        $this.Valores[$nome]=$valor
    }
    $chave | Add-Member ScriptMethod DeleteValue { param($nome,$ausente); $this.Valores.Remove($nome) }
    $chave | Add-Member ScriptMethod Dispose {}
    $chave
}

Test-Case autologon 'configura segredo antes de habilitar e restaura metadados em falha' {
    foreach ($falhar in @($false,$true)) {
        $chave = New-FixtureWinlogon
        $chave.Falhar = $falhar
        $r = & $module {
            param($registro)
            $script:ChamadasLogon = New-Object 'System.Collections.Generic.List[string]'
            function Set-SuporteSegredoLogon {
                param([Security.SecureString]$Senha)
                if($registro.Valores.AutoAdminLogon -ne '0'){throw 'Segredo alterado enquanto o logon estava ativo.'}
                $script:ChamadasLogon.Add($(if($null -ne $Senha){'gravar'}else{'remover'}))
            }
            $senha = New-Object Security.SecureString
            $senha.AppendChar('x')
            $falha = $false
            try { Enable-SuporteLogon $registro 'conta' 'AD.EXEMPLO' $senha } catch { $falha = $true } finally { $senha.Dispose() }
            [pscustomobject]@{Falha=$falha;Chamadas=($script:ChamadasLogon -join ',')}
        } $chave
        if ($falhar) {
            Assert-True ($r.Falha -and $r.Chamadas -eq 'gravar,remover' -and $chave.Valores.AutoAdminLogon -eq '0' -and
                $chave.Valores.DefaultUserName -eq 'anterior' -and -not $chave.Valores.ContainsKey('DefaultDomainName')) 'Falha deixou o login ativo ou perdeu o estado anterior.'
        } else {
            Assert-True (-not $r.Falha -and $r.Chamadas -eq 'gravar' -and $chave.Valores.AutoAdminLogon -eq '1' -and
                $chave.Valores.DefaultDomainName -eq 'AD.EXEMPLO' -and -not $chave.Valores.ContainsKey('DefaultPassword')) 'Configuracao incorreta ou gravacao de senha legada.'
        }
    }
}

Test-Case autologon 'consulta omite senha e desativacao limpa configuracao na sessao elevada atual' {
    $chave = New-FixtureWinlogon
    $chave.Valores.AutoAdminLogon = '1'
    $chave.Valores.DefaultPassword = 'senha-ficticia'
    $chave.Valores.AutoLogonCount = '2'
    $texto = & $module {
        param($registro)
        function Open-SuporteWinlogon { $registro }
        function Test-SuporteAdmin { $true }
        function Start-Process { throw 'Janela elevada extra indevida.' }
        function Read-Host { 's' }
        function Set-SuporteSegredoLogon { if($registro.Valores.AutoAdminLogon -ne '0'){throw 'Ordem insegura.'} }
        function Write-Host { $args -join ' ' }
        Get-SuporteResumoLogon
        Request-SuporteOperacao autologondisable 'C:\Documentos'
    } $chave
    Assert-True (($texto -join ' ') -match 'Conta configurada: anterior' -and ($texto -join ' ') -match 'credencial removida' -and
        ($texto -join ' ') -notmatch 'senha-ficticia|extra indevida' -and $chave.Valores.AutoAdminLogon -eq '0' -and
        -not $chave.Valores.ContainsKey('DefaultPassword') -and -not $chave.Valores.ContainsKey('AutoLogonCount')) 'Falha na consulta, na desativacao ou no uso da janela atual.'
}

Test-Case filaimpressao 'identifica impressora com erro de fila e preserva filas normais' {
    $texto = & $module {
        param($arquivo)
        function Get-Service { [pscustomobject]@{Status='Running'} }
        function Get-Printer {
            [pscustomobject]@{Name='Recepcao';PortName='USB001';PrinterStatus='Normal'}
            [pscustomobject]@{Name='Sala de reuniao';PortName='IP_192.0.2.12';PrinterStatus='Normal'}
            [pscustomobject]@{Name='Secretaria';PortName='USB002';PrinterStatus='Offline'}
            [pscustomobject]@{Name='Somente proprietario';PortName='USB003';PrinterStatus='Normal'}
        }
        function Get-PrintJob {
            param($PrinterObject)
            switch ($PrinterObject.Name) {
                'Recepcao' { [pscustomobject]@{JobStatus='Spooling'} }
                'Sala de reuniao' { [pscustomobject]@{JobStatus='Printing, Blocked'} }
                'Somente proprietario' { throw 'Acesso negado simulado.' }
            }
        }
        & $arquivo -Id filaimpressao | Out-String
    } $collector
    Assert-True ($texto -match '\[IMPRESSAO PROBLEMA\] Impressora: Sala de reuniao' -and
        $texto -match '\[IMPRESSAO PROBLEMA\] Impressora: Secretaria' -and
        $texto -notmatch '\[IMPRESSAO PROBLEMA\] Impressora: Recepcao' -and
        $texto -match '\[INDISPONIVEL\] Trabalhos da fila: Somente proprietario') 'A consulta marcou a fila errada ou ocultou a falha de acesso.'
}

Test-Case filaimpressao 'spooler parado informa a causa sem consultar filas' {
    $texto = & $module {
        param($arquivo)
        function Get-Service { [pscustomobject]@{Status='Stopped'} }
        function Get-Printer { throw 'Nao deveria enumerar filas.' }
        & $arquivo -Id filaimpressao | Out-String
    } $collector
    Assert-True ($texto -match 'Spooler local: Stopped.*nao puderam ser avaliadas' -and $texto -notmatch 'Nao deveria') 'Spooler parado nao foi tratado corretamente.'
}

Test-Case seguranca 'Enter e zero voltam das escolhas de GPO sem executar operacoes' {
    $chamadas = & $module {
        $script:MenuQueue = New-Object 'System.Collections.Generic.Queue[string]'
        foreach ($entrada in @('4','3','','3','0','2','','0','')) { $script:MenuQueue.Enqueue($entrada) }
        function Read-Host { $script:MenuQueue.Dequeue() }
        function Write-Host {}
        function Write-SuporteTela {}
        function Request-SuporteOperacao { throw 'A navegacao executou uma operacao.' }
        function Request-SuporteExportar { throw 'A navegacao executou uma exportacao.' }
        Start-SuporteMenu -ModuleRoot 'C:\Teste' -SemCores
        $script:MenuQueue.Count
    }
    Assert-True ($chamadas -eq 0) 'As escolhas de voltar consumiram entradas incorretamente.'
}

# Navegacao real do menu com entradas controladas: cada opcao e acessada sem executar alteracoes.
foreach($menuItem in Get-SuporteCatalogo){
    Test-Case $menuItem.Id 'navegacao do menu despacha a opcao correta' {
        $check=& $module {
            param($id,$docs)
            $groups=@('Computador','Rede','Windows Update','GPO','Impressao','Relatorios e eventos','Reparos do Windows')
            $catalog=@(Get-SuporteCatalogo);$selected=$catalog | Where-Object Id -eq $id
            $groupIndex=[array]::IndexOf($groups,$selected.Grupo)+1
            $peers=@($catalog | Where-Object { $_.Grupo -eq $selected.Grupo -and -not $_.Pai })
            $visivel=if($selected.Pai){$peers | Where-Object Id -eq $selected.Pai}else{$selected}
            $optionIndex=[array]::IndexOf($peers,$visivel)+1
            $script:MenuQueue=New-Object 'System.Collections.Generic.Queue[string]'
            foreach($key in @([string]$groupIndex,[string]$optionIndex)){$script:MenuQueue.Enqueue($key)}
            if($id -in @('gpupdateuser','gpupdatecomputer','gphtml','sfc','dism','chkdsk','autologon')){$script:MenuQueue.Enqueue('1')}
            if($id -eq 'ping'){$script:MenuQueue.Enqueue('127.0.0.1')}
            if($id -eq 'falhas'){$script:MenuQueue.Enqueue('1')}
            if($id -eq 'codigofalha'){$script:MenuQueue.Enqueue('2');$script:MenuQueue.Enqueue('5')}
            if($id -ne 'mapaocupacao'){$script:MenuQueue.Enqueue('')}
            if($id -in 'falhas','codigofalha'){$script:MenuQueue.Enqueue('0')}
            foreach($key in @('0','0')){$script:MenuQueue.Enqueue($key)}
            $script:MenuCalls=New-Object 'System.Collections.Generic.List[string]'
            function Read-Host { if($script:MenuQueue.Count -eq 0){throw 'Menu solicitou entrada inesperada.'};$script:MenuQueue.Dequeue() }
            function Clear-Host {}
            function Write-Host {}
            function Write-SuporteTela {}
            function Show-SuporteResultado {}
            function Show-SuporteMonitor { $script:MenuCalls.Add('monitor') }
            function Show-SuporteMapaOcupacao { $script:MenuCalls.Add('mapaocupacao') }
            function Request-SuporteSalvar {}
            function Request-SuporteOperacao {param($Acao,$Documentos,[switch]$Forcar);$script:MenuCalls.Add($Acao)}
            function Request-SuporteExportar {param($Tipo,$Documentos);$script:MenuCalls.Add($Tipo)}
            function Invoke-SuporteConsulta {param($Id,$Opcoes,$TimeoutSeconds);$script:MenuCalls.Add($Id);[pscustomobject]@{Status='Teste';Texto='Simulado';Codigos=@()}}
            Start-SuporteMenu -ModuleRoot $docs -SemCores
            [pscustomobject]@{Calls=$script:MenuCalls.ToArray();Restantes=$script:MenuQueue.Count}
        } $menuItem.Id $root
        Assert-True ($check.Restantes -eq 0) 'Navegacao nao consumiu as entradas previstas.'
        $expected=switch($menuItem.Id){'gpcomputador'{'gpcomputerquery'};'gpupdateuser'{'gpuser'};'gpupdatecomputer'{'gpcomputer'};'sfc'{'sfcverify'};'dism'{'dismcheck'};'chkdsk'{'chkdskread'};'ultimo'{''};default{$menuItem.Id}}
        if($expected){Assert-True ($check.Calls -contains $expected) ('Despacho incorreto: '+($check.Calls -join ','))}
    }
}

Test-Case falhas '0 e Enter voltam no submenu de falhas sem consultar' {
    $calls = & $module {
        $script:MenuQueue = New-Object 'System.Collections.Generic.Queue[string]'
        foreach($key in @('1','8','2','','2','0','0','8','','0','0')){$script:MenuQueue.Enqueue($key)}
        $script:CallCount = 0
        function Read-Host { $script:MenuQueue.Dequeue() }
        function Write-Host {}; function Clear-Host {}; function Write-SuporteTela {}
        function Invoke-SuporteConsulta { $script:CallCount++ }
        Start-SuporteMenu -ModuleRoot 'C:\Teste' -SemCores
        [pscustomobject]@{ Calls=$script:CallCount; Restantes=$script:MenuQueue.Count }
    }
    Assert-True ($calls.Calls -eq 0 -and $calls.Restantes -eq 0) 'O retorno executou uma consulta ou voltou para o menu errado.'
}

Test-Case falhas 'atalho numerado consulta o codigo com a familia do evento' {
    $chamadas = & $module {
        $fila = New-Object 'System.Collections.Generic.Queue[string]'
        foreach ($key in @('1','8','1','s','3','2','0','0','0','0')) { $fila.Enqueue($key) }
        function Read-Host { $fila.Dequeue() }
        function Write-Host {}
        function Write-SuporteTela {}
        function Request-SuporteSalvar { param($Resultado,$Documentos,[switch]$Confirmado); if ($Confirmado) { 'Salvar ' + $Resultado.Texto } }
        function Show-SuporteResultado { param($Resultado); $Resultado.Texto }
        function Invoke-SuporteConsulta {
            param($Id,$Opcoes,$TimeoutSeconds)
            if ($Id -eq 'falhas' -and $Opcoes.IncluirCodigos) {
                return [pscustomobject]@{Texto='Triagem';Codigos=@(
                    [pscustomobject]@{Familia='Paradas';Codigo='0x00000005'}
                    [pscustomobject]@{Familia='Win32';Codigo='0x00000005'}
                )}
            }
            [pscustomobject]@{Texto=('{0}/{1}/{2}' -f $Id,$Opcoes.Familia,$Opcoes.Codigo)}
        }
        Start-SuporteMenu -ModuleRoot 'C:\Teste' -SemCores
        $fila.Count
    }
    Assert-True (($chamadas -join '|') -eq 'Triagem|Salvar Triagem|codigofalha/Win32/0x00000005|0') 'O atalho perdeu a opcao de salvar, consultou a origem errada ou nao ignorou a selecao invalida.'
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

Test-Case falhas 'consulta por codigo pede apenas o numero antes do resultado' {
    $telas = & $module {
        $script:MenuQueue = New-Object 'System.Collections.Generic.Queue[string]'
        $script:TelasTeste = New-Object 'System.Collections.Generic.List[string]'
        foreach ($key in @('1','8','2','5','0','0','0','0')) { $script:MenuQueue.Enqueue($key) }
        function Read-Host { $script:MenuQueue.Dequeue() }
        function Write-Host {}
        function Write-SuporteTela { param($Titulo,[switch]$SemCores); $script:TelasTeste.Add('Tela: ' + $Titulo) }
        function Invoke-SuporteConsulta {
            param($Id,$Opcoes,$TimeoutSeconds)
            if ($Id -ne 'codigofalha' -or $Opcoes.Codigo -ne '5' -or $Opcoes.ContainsKey('Familia')) { throw 'Consulta esperada somente pelo codigo.' }
            [pscustomobject]@{ Status='Concluido'; Texto='Simulado' }
        }
        function Show-SuporteResultado { $script:TelasTeste.Add('Resultado') }
        function Request-SuporteSalvar {}
        Start-SuporteMenu -ModuleRoot 'C:\Teste' -SemCores
        $script:TelasTeste.ToArray()
    }
    $esperado = @(
        'Tela: Menu principal','Tela: Computador','Tela: Falhas recentes e codigos de erro',
        'Tela: Consultar um codigo de erro','Tela: Consultar um codigo de erro','Resultado','Tela: Falhas recentes e codigos de erro',
        'Tela: Computador','Tela: Menu principal'
    )
    Assert-True (($telas -join '|') -eq ($esperado -join '|')) 'A consulta acumulou etapas ou retornou a uma tela incorreta.'
}

Test-Case seguranca 'layout estreito preserva opcoes e rotulos sem depender das cores' {
    $saida = & $module {
        function Get-SuporteLargura { 24 }
        function Write-Host { param($Object,$ForegroundColor); [pscustomobject]@{ Texto=[string]$Object; Cor=$ForegroundColor } }
        function Read-Host { '0' }
        Read-SuporteEscolha @('[1] Consultar o estado da imagem do Windows','[2] Reparar a imagem do Windows') -Titulo 'Opcoes DISM' -Alteracoes 2 -SemCores
    }
    $linhas = @($saida | Where-Object { $_ -isnot [string] })
    Assert-True (@($linhas | Where-Object { $_.Texto.Length -gt 24 -or $_.Cor }).Count -eq 0) 'O menu excedeu a largura ou aplicou cores no modo sem cores.'
    $texto = ($linhas.Texto -join ' ') -replace '\s+',' '
    Assert-True ($texto -match 'Opcoes DISM' -and $texto -match '\[ALTERACAO\]' -and
        $texto -match '\[0 ou Enter\] Voltar') 'Titulo, aviso de alteracao ou retorno foram perdidos.'
    $cores = & $module { Get-SuporteCorConsole Yellow Black; Get-SuporteCorConsole Yellow White; Get-SuporteCorConsole Blue White }
    Assert-True (($cores -join ',') -eq 'Yellow,DarkYellow,DarkBlue') 'A paleta nao se adaptou ao fundo claro.'
}

if ($IncluirConsultasReais) {
    foreach ($query in ($queries + 'bateria' + 'filaimpressao')) {
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
