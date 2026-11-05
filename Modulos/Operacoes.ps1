# Operacoes restritas. Nao aceita comandos livres, caminhos de sistema ou alvos remotos.
function Get-SuporteOperacao {
    param([Parameter(Mandatory)][string]$Acao)
    $map=@{
        spooler=@{Titulo='Reiniciar spooler local';Admin=$true;Impacto='Interrompe temporariamente a impressao local. Nao exclui trabalhos.'}
        cache=@{Titulo='Recriar cache de download do Windows Update';Admin=$true;Impacto='Interrompe BITS/Windows Update temporariamente e renomeia somente SoftwareDistribution\Download. Nao desinstala atualizacoes. O cache anterior permanece no disco.'}
        gpuser=@{Titulo='Atualizar GPO do usuario atual';Admin=$false;Impacto='Pode aplicar configuracoes institucionais. Nao solicita reinicio nem logoff automatico.'}
        gpcomputer=@{Titulo='Atualizar GPO do computador';Admin=$true;Impacto='Pode aplicar configuracoes institucionais e iniciar acoes previstas pela GPO. Sem /boot ou /logoff.'}
        sfcverify=@{Titulo='SFC - verificar sem reparar';Admin=$true;Impacto='Consulta demorada de arquivos protegidos. Produz logs nativos.'}
        sfcrepair=@{Titulo='SFC /scannow';Admin=$true;Impacto='Pode substituir arquivos do Windows. Pode demorar; nao feche a janela durante o reparo.'}
        dismcheck=@{Titulo='DISM CheckHealth';Admin=$true;Impacto='Consulta o estado registrado da imagem; nao realiza varredura completa.'}
        dismscan=@{Titulo='DISM ScanHealth';Admin=$true;Impacto='Verificacao demorada da imagem, sem RestoreHealth.'}
        dismrestore=@{Titulo='DISM RestoreHealth';Admin=$true;Impacto='Repara a imagem usando as fontes configuradas no Windows/GPO. Pode acessar a rede e demorar.'}
        diskhealth=@{Titulo='Saude detalhada dos discos';Admin=$true;Impacto='Somente leitura SMART/NVMe; sem testes extensos ou reparos.'}
        gpcomputerquery=@{Titulo='Consultar GPO do computador';Admin=$true;Impacto='Consulta somente leitura.'}
        gpcomputerhtml=@{Titulo='Exportar GPO do computador em HTML';Admin=$true;Impacto='Exporta politicas do computador, sem alterar GPO. O destino e escolhido na janela elevada.'}
        netdhcp=@{Titulo='Trocar IPv4 fixo por DHCP';Admin=$true;Impacto='Remove IPv4 e gateway fixos do adaptador selecionado e configura DNS IPv4 automatico. Pode interromper a conexao.'}
        netstatic=@{Titulo='Configurar IPv4 fixo';Admin=$true;Impacto='Substitui enderecos e gateway IPv4 no adaptador escolhido. Use uma atribuicao autorizada pela equipe de rede.'}
        chromecache=@{Titulo='Limpar cache de paginas do Chrome';Admin=$false;Impacto='Remove arquivos de cache HTTP dos perfis padrao do Chrome da sessao. Feche o navegador antes de usar.'}
        chkdskread=@{Titulo='CHKDSK - consultar volume';Admin=$true;Impacto='Verifica o sistema de arquivos do volume selecionado sem solicitar reparos.'}
        chkdskfull=@{Titulo='CHKDSK /f /r';Admin=$true;Impacto='Repara o sistema de arquivos e procura setores defeituosos. Pode exigir agendamento e reinicializacao.'}
        perfillocal=@{Titulo='Verificar perfil local duplicado';Admin=$true;Impacto='Mostra os perfis candidatos. A exclusao de dados locais exige confirmacao.'}
    }
    if (-not $map.ContainsKey($Acao)) { throw 'Operacao nao autorizada.' }
    $map[$Acao]
}

function Test-SuporteAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SuporteArgumentosGpupdate {
    param([ValidateSet('user','computer')][string]$Escopo,[switch]$Forcar)
    "/target:$Escopo"
    '/wait:-1'
    if ($Forcar) { '/force' }
}

function Invoke-SuporteNativeAction {
    param([string]$Programa,[string[]]$Argumentos)
    $allowed=@('sfc.exe','dism.exe','gpupdate.exe','netsh.exe','chkdsk.exe')
    if ($Programa -notin $allowed) { throw 'Executavel nao autorizado.' }
    $exe=Join-Path $env:SystemRoot ('System32\'+$Programa)
    # Herda o console: progresso visivel, sem arquivos temporarios nem timeout forcado.
    & $exe @Argumentos | Out-Host
    $code=$LASTEXITCODE
    if ($Programa -eq 'chkdsk.exe') {
        switch ($code) {
            0 { 'CHKDSK retornou codigo 0. Se houve agendamento, execute a verificacao no proximo reinicio.' }
            1 { 'CHKDSK encontrou e corrigiu erros.' }
            2 { 'CHKDSK retornou codigo 2. Consulte a saida para verificar a limpeza realizada ou pendente.' }
            default { throw ('CHKDSK retornou codigo '+$code+'. Consulte a saida para identificar verificacao ou reparo pendente.') }
        }
        return
    }
    if ($code -notin @(0,3010)) { throw ('O comando terminou com codigo '+$code+'. Consulte a mensagem e os logs nativos; nao presumir sucesso.') }
    if ($code -eq 3010) { 'O Windows informou necessidade de reiniciar. Reinicio nao executado.' }
    'Comando encerrado. Confira a conclusao detalhada exibida acima e os logs nativos.'
}

function Invoke-SuporteCache {
    # Recusar operacoes concorrentes com instalacao/reparo. Nunca apaga DataStore/catroot2.
    if (@(Get-Process -Name TiWorker,TrustedInstaller,MoUsoCoreWorker,dism,sfc -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Ha manutencao/atualizacao ativa. Aguarde a conclusao antes de recriar o cache.' }
    $pending=@('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    foreach ($key in $pending) { if (Test-Path -LiteralPath $key) { throw 'Ha reinicializacao pendente. Reavalie apos reiniciar manualmente.' } }
    $root=[IO.Path]::GetFullPath($env:SystemRoot)
    $download=Join-Path $root 'SoftwareDistribution\Download'
    if (-not (Test-Path -LiteralPath $download)) { throw 'Cache de download ausente; nenhuma alteracao necessaria.' }
    foreach ($path in @($root,(Join-Path $root 'SoftwareDistribution'),$download)) {
        $entry=Get-Item -LiteralPath $path -Force
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Caminho de cache com redirecionamento; operacao bloqueada.' }
    }
    $states=@{}; $restoreErrors=New-Object 'System.Collections.Generic.List[string]'
    try {
        foreach ($name in @('bits','wuauserv')) {
            $svc=Get-Service -Name $name -ErrorAction Stop
            if ([string]$svc.Status -notin @('Running','Stopped')) { throw ('Servico em transicao: '+$name) }
            $states[$name]=[string]$svc.Status
            if ($svc.Status -eq 'Running') { Stop-Service -Name $name -ErrorAction Stop; (Get-Service $name).WaitForStatus('Stopped',[TimeSpan]::FromSeconds(15)) }
        }
        foreach ($name in @('bits','wuauserv')) { if ((Get-Service $name).Status -ne 'Stopped') { throw 'Nao foi possivel parar os servicos. Cache preservado.' } }
        $backup='Download.anterior_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'_'+[guid]::NewGuid().ToString('N')
        Rename-Item -LiteralPath $download -NewName $backup -ErrorAction Stop
        'Cache anterior preservado em: '+(Join-Path (Split-Path $download -Parent) $backup)
        'O Windows recriara o cache quando a atualizacao for retomada. Novo download nao foi iniciado automaticamente.'
    } finally {
        foreach ($name in @('wuauserv','bits')) {
            if ($states.ContainsKey($name) -and $states[$name] -eq 'Running') {
                try { Start-Service -Name $name -ErrorAction Stop; (Get-Service $name).WaitForStatus('Running',[TimeSpan]::FromSeconds(15)) }
                catch { $restoreErrors.Add($name+': '+$_.Exception.Message) }
            }
        }
        if ($restoreErrors.Count -gt 0) { throw ('Nao foi possivel restaurar servicos: '+($restoreErrors -join '; ')) }
    }
}

function Invoke-SuporteOperacao {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param([Parameter(Mandatory)][string]$Acao,[switch]$Forcar)
    $info=Get-SuporteOperacao $Acao
    if ($Forcar -and $Acao -notin @('gpuser','gpcomputer')) { throw 'Force so e permitido para GPO.' }
    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME,$info.Titulo)) { return 'Operacao cancelada; nenhuma alteracao executada.' }
    if ($info.Admin -and -not (Test-SuporteAdmin)) { throw 'Esta operacao requer elevacao pelo Windows.' }
    $mutex=New-Object Threading.Mutex($false,'Local\SuporteTI.Intervencao')
    $locked=$false
    try {
    try { $locked=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked=$true }
    if(-not $locked){throw 'Outra operacao desta ferramenta esta em andamento nesta sessao.'}
    switch ($Acao) {
        'spooler' {
            $svc=Get-Service -Name Spooler -ErrorAction Stop
            if ($svc.Status -eq 'Running') { Restart-Service -Name Spooler -ErrorAction Stop } else { Start-Service -Name Spooler -ErrorAction Stop }
            (Get-Service Spooler).WaitForStatus('Running',[TimeSpan]::FromSeconds(15))
            if ((Get-Service Spooler).Status -ne 'Running') { throw 'Spooler nao permaneceu em execucao.' }
            'Spooler em execucao. Nenhum trabalho foi excluido; confirme a impressao.'
        }
        'cache' { Invoke-SuporteCache }
        {$_ -in @('gpuser','gpcomputer')} {
            $scope=if ($Acao -eq 'gpuser') { 'user' } else { 'computer' }
            $argsList=@(Get-SuporteArgumentosGpupdate $scope -Forcar:$Forcar)
            Invoke-SuporteNativeAction 'gpupdate.exe' $argsList
        }
        'sfcverify' { Invoke-SuporteNativeAction 'sfc.exe' @('/verifyonly') }
        'sfcrepair' { Invoke-SuporteNativeAction 'sfc.exe' @('/scannow') }
        'dismcheck' { Invoke-SuporteNativeAction 'dism.exe' @('/Online','/Cleanup-Image','/CheckHealth','/NoRestart') }
        'dismscan' { Invoke-SuporteNativeAction 'dism.exe' @('/Online','/Cleanup-Image','/ScanHealth','/NoRestart') }
        'dismrestore' { Invoke-SuporteNativeAction 'dism.exe' @('/Online','/Cleanup-Image','/RestoreHealth','/NoRestart') }
        'diskhealth' { Invoke-SuporteConsulta -Id discos -TimeoutSeconds 40 }
        'gpcomputerquery' { Invoke-SuporteConsulta -Id gpcomputador }
        'netdhcp' { Invoke-SuporteConfiguracaoIPv4 Dhcp }
        'netstatic' { Invoke-SuporteConfiguracaoIPv4 Estatico }
        'chromecache' { Invoke-SuporteCacheChrome }
        'chkdskread' { Invoke-SuporteVerificacaoDisco }
        'chkdskfull' { Invoke-SuporteVerificacaoDisco -Completa }
        'perfillocal' { Invoke-SuporteLimpezaPerfil }
        default { throw 'Operacao requer fluxo de exportacao.' }
    }
    } finally { if($locked){$mutex.ReleaseMutex()};$mutex.Dispose() }
}

function Request-SuporteOperacao {
    param([string]$Acao,[string]$Documentos,[switch]$Forcar)
    $info=Get-SuporteOperacao $Acao
    Write-Host ('ACAO: '+$info.Titulo)
    Write-Host ('IMPACTO: '+$info.Impacto)
    if ($Forcar) { Write-Host 'FORCE: reaplica todas as configuracoes do escopo selecionado.' }
    if ($info.Admin -and -not (Test-SuporteAdmin)) {
        $worker=Join-Path $PSScriptRoot 'Elevado.ps1'
        if ($worker.Contains('"')) { throw 'Caminho do projeto invalido.' }
        $doc64=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Documentos))
        $arguments='-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "'+$worker+'" -Acao '+$Acao+' -Documentos64 '+$doc64
        if ($Forcar) { $arguments+=' -Forcar' }
        Write-Host 'O Windows solicitara elevacao. Use uma conta com direitos nesta estacao.'
        Write-Host 'A operacao selecionada sera executada na janela elevada se voce autorizar no Windows.'
        try {
            $p=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $arguments -Verb RunAs -PassThru -Wait -ErrorAction Stop
            if ($p.ExitCode -ne 0) { Write-Host 'Operacao cancelada, bloqueada ou falhou. Confira a janela elevada.' }
            else { Write-Host 'Janela elevada encerrada. O resultado detalhado foi apresentado nela.' }
        } catch { Write-Host ('Elevacao nao concluida: '+$_.Exception.Message) }
        return
    }
    $start=(Get-Date).ToString('o')
    try {
        if($Acao -eq 'gpcomputerhtml'){Request-SuporteExportar -Tipo gphtml -Documentos $Documentos -Escopo Computer;return}
        $output=Invoke-SuporteOperacao -Acao $Acao -Forcar:$Forcar -Confirm:$false
        if ($Acao -in @('diskhealth','gpcomputerquery')) { Show-SuporteResultado $output; Request-SuporteSalvar $output $Documentos }
        else {
            $text=($output | Out-String); Write-Host $text
            $result=[pscustomobject]@{Computador=$env:COMPUTERNAME;Consulta=$info.Titulo;Inicio=$start;Fim=(Get-Date).ToString('o');Status='Ver conclusao e mensagens nativas';Texto=$text}
            Request-SuporteSalvar $result $Documentos
        }
    } catch { Write-Host ('Falha: '+$_.Exception.Message); Write-Host 'Nao presumir sucesso; preserve e consulte os logs nativos.' }
}

function Invoke-SuporteExportNative {
    param([string]$Programa,[string[]]$Argumentos)
    if ($Programa -notin @('gpresult.exe','wevtutil.exe')) { throw 'Exportador nao permitido.' }
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=Join-Path $env:SystemRoot ('System32\'+$Programa)
    $quoted=@(foreach($argument in $Argumentos){
        if($argument.Contains('"')){throw 'Argumento de exportacao invalido.'}
        '"'+$argument+'"'
    })
    $psi.Arguments=$quoted -join ' '; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
    $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    $process=New-Object Diagnostics.Process; $process.StartInfo=$psi
    try {
        [void]$process.Start(); $out=$process.StandardOutput.ReadToEndAsync();$err=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(30000)){$process.Kill();throw 'Exportacao excedeu 30 segundos. Pode haver arquivo parcial no destino.'}
        $process.WaitForExit()
        if($process.ExitCode -ne 0){throw ('Exportador retornou '+$process.ExitCode+': '+$err.Result+' '+$out.Result)}
    } finally {$process.Dispose()}
}

function Test-SuporteEvtx {
    param([string]$Path)
    $query=New-Object Diagnostics.Eventing.Reader.EventLogQuery($Path,[Diagnostics.Eventing.Reader.PathType]::FilePath)
    $reader=New-Object Diagnostics.Eventing.Reader.EventLogReader($query)
    try {$event=$reader.ReadEvent(); if($null -ne $event){$event.Dispose()}} finally {$reader.Dispose()}
}

function Export-SuporteArquivo {
    [CmdletBinding()]
    param([ValidateSet('gphtml','evtx')][string]$Tipo,[string]$PastaBase,[ValidateSet('User','Computer')][string]$Escopo='User')
    if (-not [IO.Path]::IsPathRooted($PastaBase)) { throw 'Informe caminho absoluto.' }
    if($Tipo -eq 'gphtml' -and $Escopo -eq 'Computer' -and -not (Test-SuporteAdmin)){throw 'Exportacao de GPO do computador requer elevacao.'}
    $folder=Join-Path (Join-Path ([IO.Path]::GetFullPath($PastaBase)) $env:COMPUTERNAME) ((Get-Date -Format 'yyyy-MM-dd_HHmmss')+'_'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($folder)
    $results=@()
    if ($Tipo -eq 'gphtml') {
        $path=Join-Path $folder ('gpresult-'+$Escopo.ToLowerInvariant()+'.html')
        Invoke-SuporteExportNative 'gpresult.exe' @('/Scope',$Escopo,'/H',$path)
        if (-not (Test-Path -LiteralPath $path)) { throw 'Falha ao exportar GPO. Nenhum sucesso presumido.' }
        $results+=Get-Item -LiteralPath $path
    } else {
        foreach ($log in @('Application','System','Setup')) {
            $path=Join-Path $folder ($log+'.evtx')
            try {
                $filtro='/q:*[System[TimeCreated[timediff(@SystemTime) <= 86400000]]]'
                Write-Host ('Comando: wevtutil.exe epl {0} "{1}" "{2}"' -f $log,$path,$filtro)
                Invoke-SuporteExportNative 'wevtutil.exe' @('epl',$log,$path,$filtro)
                if (-not (Test-Path -LiteralPath $path)) { throw 'Arquivo nao criado.' }
                Test-SuporteEvtx $path
            } catch { throw ('Exportacao parcial: falha no canal '+$log+'. Arquivos ja exportados estao em '+$folder+'. '+$_.Exception.Message) }
            $results+=Get-Item -LiteralPath $path
        }
    }
    $manifest=@($results | ForEach-Object { [pscustomobject]@{Arquivo=$_.Name;Bytes=$_.Length;SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash} })
    $manifestPath=Join-Path $folder 'manifesto.json'
    $payload=[pscustomobject]@{Computador=$env:COMPUTERNAME;Data=(Get-Date).ToString('o');Tipo=$Tipo;Escopo=$(if($Tipo -eq 'gphtml'){$Escopo}else{'Application/System/Setup'});Periodo=$(if($Tipo -eq 'evtx'){'Ultimas 24h'}else{'Estado atual'});Arquivos=$manifest}
    [IO.File]::WriteAllText($manifestPath,($payload | ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($true)))
    'Exportado em: '+$folder
}

function Request-SuporteExportar {
    param([ValidateSet('gphtml','evtx')][string]$Tipo,[string]$Documentos,[ValidateSet('User','Computer','Escolher')][string]$Escopo='Escolher')
    if($Tipo -eq 'gphtml' -and $Escopo -eq 'Escolher'){
        $selection=Read-Host '[1] HTML do usuario atual | [2] HTML do computador (administrador) | [0] Cancelar'
        if($selection -eq '1'){$Escopo='User'}elseif($selection -eq '2'){$Escopo='Computer'}else{return}
    }
    if($Tipo -eq 'gphtml' -and $Escopo -eq 'Computer' -and -not (Test-SuporteAdmin)){
        Request-SuporteOperacao gpcomputerhtml $Documentos;return
    }
    Write-Host 'Exportacao pode conter dados internos. Escolha um destino com acesso adequado.'
    if ((Read-Host 'Salvar exportacao? [s/N]') -ine 's') { return }
    $suggested=if ($Documentos) { Join-Path $Documentos 'SuporteTI\Resultados' } else { '' }
    Write-Host ('Destino padrao: '+$suggested)
    $path=Read-Host 'Outro destino completo ou Enter para usar o padrao (0 cancela)'
    if ($path -eq '0') { return }; if (-not $path) { $path=$suggested }
    $scopeValue=if($Escopo -eq 'Computer'){'Computer'}else{'User'}
    try { Export-SuporteArquivo -Tipo $Tipo -PastaBase $path -Escopo $scopeValue | ForEach-Object { Write-Host $_ } }
    catch { Write-Host ('Exportacao falhou: '+$_.Exception.Message) }
}
