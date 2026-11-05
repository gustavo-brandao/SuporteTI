function Get-SuporteInventarioPerfis {
    $registro = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    $raiz = [IO.Path]::GetFullPath($env:SystemDrive + '\Users').TrimEnd('\')
    $configurada = [Environment]::ExpandEnvironmentVariables((Get-ItemPropertyValue -LiteralPath $registro -Name ProfilesDirectory -ErrorAction Stop))
    if ([IO.Path]::GetFullPath($configurada).TrimEnd('\') -ne $raiz -or -not (Test-SuporteCaminhoSemLinks $raiz)) {
        throw 'A pasta de perfis esta fora do caminho local padrao ou foi redirecionada.'
    }
    $chaves = @(Get-ChildItem -LiteralPath $registro -ErrorAction Stop | ForEach-Object {
        if ($_.PSChildName -match '^(S-1-[0-9-]+)(\..+)?$') {
            $sid = $Matches[1]
            $item = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction Stop
            $propriedade = $item.PSObject.Properties['ProfileImagePath']
            $caminho = if ($propriedade -and $propriedade.Value) {
                [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$propriedade.Value)).TrimEnd('\')
            } else { '' }
            [pscustomobject]@{ Nome=$_.PSChildName; SID=$sid; Caminho=$caminho }
        }
    })
    [pscustomobject]@{
        Registro = $registro
        Raiz = $raiz
        Chaves = $chaves
        Pastas = @(Get-ChildItem -LiteralPath $raiz -Directory -Force -ErrorAction Stop)
        Perfis = @(Get-CimInstance Win32_UserProfile -OperationTimeoutSec 5 -ErrorAction Stop)
    }
}

function Get-SuporteContaPerfil {
    param([string]$SID)
    try { [Security.Principal.SecurityIdentifier]::new($SID).Translate([Security.Principal.NTAccount]).Value }
    catch [Security.Principal.IdentityNotMappedException] { '' }
}

function Test-SuportePerfilCarregado {
    param([string]$SID)
    if ($SID -eq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) { return $true }
    $perfis = @(Get-CimInstance Win32_UserProfile -Filter "SID='$SID'" -OperationTimeoutSec 5 -ErrorAction Stop)
    if ($perfis | Where-Object { $_.Loaded -or $_.Special }) { return $true }
    (Test-Path -LiteralPath "Registry::HKEY_USERS\$SID" -ErrorAction Stop) -or
        (Test-Path -LiteralPath "Registry::HKEY_USERS\${SID}_Classes" -ErrorAction Stop)
}

function Get-SuportePlanosPerfil {
    param($Inventario)
    foreach ($grupo in ($Inventario.Chaves | Group-Object SID)) {
        $sid = $grupo.Name
        if ($sid -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$' -or [long]($sid.Split('-')[-1]) -lt 1000) { continue }
        $chaves = @($grupo.Group | Where-Object Nome -in @($sid,"$sid.bak"))
        if (-not $chaves.Count) { continue }
        $perfil = $Inventario.Perfis | Where-Object SID -eq $sid | Select-Object -First 1
        if ($perfil -and $perfil.Special) { continue }
        $vinculadas = @($chaves | ForEach-Object Caminho | Where-Object { $_ } | Sort-Object -Unique)
        $conta = Get-SuporteContaPerfil $sid
        $temporario = ($perfil -and ([int]$perfil.Status -band 1) -ne 0) -or
            @($vinculadas | Where-Object { [IO.Path]::GetFileName($_) -match '^TEMP(?:\.|$)' }).Count -gt 0
        $pastas = New-Object 'System.Collections.Generic.List[string]'
        $incertas = New-Object 'System.Collections.Generic.List[string]'
        $bloqueios = New-Object 'System.Collections.Generic.List[string]'
        $padrao = $null
        if ($conta -match '^([^\\]+)\\([^\\]+)$') {
            $padrao = '^' + [regex]::Escape($Matches[2]) + '(?:\.' + [regex]::Escape($Matches[1]) + ')?(?:\.\d{3})?$'
        }
        foreach ($pasta in $Inventario.Pastas) {
            if ($pasta.Name -in @('Default','Default User','DefaultAccount','defaultuser0','Public','All Users')) { continue }
            $vinculada = $pasta.FullName -in $vinculadas
            if (-not $vinculada -and (-not $padrao -or $pasta.Name -notmatch $padrao)) { continue }
            $outros = $Inventario.Chaves | Where-Object { $_.Caminho -eq $pasta.FullName -and $_.Nome -notin @($sid,"$sid.bak") }
            $outroPerfil = $Inventario.Perfis | Where-Object { $_.SID -ne $sid -and $_.LocalPath -eq $pasta.FullName }
            if ($outros -or $outroPerfil) { $incertas.Add($pasta.FullName); continue }
            if ($vinculada) { $pastas.Add($pasta.FullName); continue }
            # Sufixo no nome por si so nao autoriza remover uma pasta sem vinculo.
            try {
                if ($pasta.Attributes -band [IO.FileAttributes]::ReparsePoint) { $incertas.Add($pasta.FullName); continue }
                $dono = (Get-Acl -LiteralPath $pasta.FullName -ErrorAction Stop).GetOwner([Security.Principal.SecurityIdentifier]).Value
                if ($dono -eq $sid) { $pastas.Add($pasta.FullName) } else { $incertas.Add($pasta.FullName) }
            } catch { $incertas.Add($pasta.FullName) }
        }
        $temBak = "$sid.bak" -in $chaves.Nome
        if (-not $temporario -and -not $temBak -and ($pastas.Count + $incertas.Count) -lt 2) { continue }
        if (-not $conta) { $bloqueios.Add('A conta associada ao SID nao foi identificada.') }
        if ($perfil -and $perfil.Loaded) { $bloqueios.Add('Perfil carregado. Encerre a sessao do usuario antes de continuar.') }
        if ($incertas.Count) { $bloqueios.Add('Ha pastas candidatas cuja associacao precisa de verificacao manual.') }
        if ($perfil -and $perfil.LocalPath -notin $vinculadas) { $bloqueios.Add('O caminho registrado pelo Windows diverge do ProfileList.') }
        if ($vinculadas | Where-Object {
            [IO.Path]::GetDirectoryName($_) -ne $Inventario.Raiz -or
            [IO.Path]::GetFileName($_) -in @('Default','Default User','DefaultAccount','defaultuser0','Public','All Users')
        }) { $bloqueios.Add('Uma entrada aponta para um caminho protegido ou fora da pasta de perfis.') }
        if ($vinculadas | Where-Object { $caminho = $_; $Inventario.Chaves | Where-Object { $_.Caminho -eq $caminho -and $_.Nome -notin @($sid,"$sid.bak") } }) {
            $bloqueios.Add('Outro registro referencia um dos mesmos caminhos.')
        }
        [pscustomobject]@{
            Conta = $(if ($conta) { $conta } else { $sid })
            SID = $sid
            Temporario = [bool]$temporario
            Chaves = $chaves
            Pastas = @($pastas.ToArray() | Sort-Object -Unique)
            Incertas = $incertas.ToArray()
            Bloqueios = $bloqueios.ToArray()
            Perfil = $perfil
        }
    }
}

function Get-SuporteItensPerfil {
    param([string]$Pasta,[string]$Raiz)
    $pasta = [IO.Path]::GetFullPath($Pasta).TrimEnd('\')
    if ([IO.Path]::GetDirectoryName($pasta) -ne $Raiz -or -not (Test-SuporteCaminhoSemLinks $pasta)) {
        throw "Pasta fora do escopo ou redirecionada: $pasta"
    }
    $pendentes = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
    $pendentes.Push((Get-Item -LiteralPath $pasta -Force -ErrorAction Stop))
    while ($pendentes.Count) {
        $diretorio = $pendentes.Pop()
        if (-not (Test-SuporteCaminhoSemLinks $diretorio.FullName)) { throw "Redirecionamento detectado: $($diretorio.FullName)" }
        $diretorio
        foreach ($item in (Get-ChildItem -LiteralPath $diretorio.FullName -Force -ErrorAction Stop)) {
            if (-not $item.FullName.StartsWith($pasta + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Item fora do perfil.' }
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                if (-not $item.PSIsContainer -or $item.LinkType -ne 'Junction') { throw "Arquivo ou redirecionamento especial: $($item.FullName)" }
                # Juncoes legadas do perfil entram como itens, sem visitar seus destinos.
                $item
            } elseif ($item.PSIsContainer) { $pendentes.Push($item) }
            else { $item }
        }
    }
}

function Remove-SuportePastaPerfil {
    param([string]$Pasta,[string]$Raiz,[string]$SID)
    if (Test-SuportePerfilCarregado $SID) { throw 'Perfil em uso. Limpeza interrompida.' }
    $itens = @(Get-SuporteItensPerfil $Pasta $Raiz | Sort-Object {$_.FullName.Length} -Descending)
    foreach ($item in $itens) {
        $caminho = $item.FullName
        if (-not (Test-SuporteCaminhoSemLinks ([IO.Path]::GetDirectoryName($caminho)))) { throw "Pai redirecionado: $caminho" }
        $atual = Get-Item -LiteralPath $caminho -Force -ErrorAction Stop
        if ($atual.PSIsContainer -ne $item.PSIsContainer -or
            ($atual.Attributes -band [IO.FileAttributes]::ReparsePoint -and $atual.LinkType -ne 'Junction')) { throw "Item mudou: $caminho" }
        if ($atual.PSIsContainer) { [IO.Directory]::Delete($caminho,$false) }
        else { Remove-Item -LiteralPath $caminho -Force -ErrorAction Stop }
    }
}

function Invoke-SuporteLimpezaPerfil {
    $inventario = Get-SuporteInventarioPerfis
    $planos = @(Get-SuportePlanosPerfil $inventario)
    if (-not $planos.Count) { return 'Nenhum candidato a perfil duplicado ou temporario encontrado.' }
    for ($i=0; $i -lt $planos.Count; $i++) {
        $plano = $planos[$i]
        Write-Host ('[{0}] {1} ({2}) | Temporario identificado: {3}' -f ($i+1),$plano.Conta,$plano.SID,$plano.Temporario)
        foreach ($chave in $plano.Chaves) { Write-Host ('  Registro: {0} -> {1}' -f $chave.Nome,$chave.Caminho) }
        foreach ($pasta in $plano.Pastas) { Write-Host ('  Pasta vinculada: ' + $pasta) }
        foreach ($pasta in $plano.Incertas) { Write-Host ('  Pasta a verificar: ' + $pasta) }
        foreach ($motivo in $plano.Bloqueios) { Write-Host ('  Bloqueio: ' + $motivo) }
    }
    $escolha = Read-Host 'Selecione o usuario para revisar a exclusao (Enter ou 0 volta)'
    if (-not $escolha -or $escolha -eq '0') { return 'Consulta encerrada.' }
    $indice = 0
    if (-not [int]::TryParse($escolha,[ref]$indice) -or $indice -lt 1 -or $indice -gt $planos.Count) { throw 'Selecao invalida.' }
    $plano = $planos[$indice-1]
    if ($plano.Bloqueios.Count) { throw ($plano.Bloqueios -join ' ') }
    if (Test-SuportePerfilCarregado $plano.SID) { throw 'Encerre a sessao do usuario antes de continuar.' }
    Write-Host ('ATENCAO. Esta operacao apaga arquivos e configuracoes locais de ' + $plano.Conta + '.') -ForegroundColor Yellow
    Write-Host 'Confirme que os arquivos necessarios foram copiados ou estao acessiveis na pasta compartilhada.'
    $plano.Pastas | ForEach-Object { Write-Host ('  Excluir pasta: ' + $_) }
    $plano.Chaves | ForEach-Object { Write-Host ('  Remover de ProfileList: ' + $_.Nome) }
    if ((Read-Host 'Excluir os dados locais e as entradas listadas? [s/N]') -ine 's') { return 'Exclusao cancelada.' }

    $revisao = Get-SuporteInventarioPerfis
    $alvo = Get-SuportePlanosPerfil $revisao | Where-Object SID -eq $plano.SID | Select-Object -First 1
    if (-not $alvo -or $alvo.Bloqueios.Count -or $alvo.Conta -ne $plano.Conta -or $revisao.Raiz -ne $inventario.Raiz -or
        ($alvo.Pastas -join '|') -ne ($plano.Pastas -join '|') -or
        (ConvertTo-Json -InputObject $alvo.Chaves -Compress) -ne (ConvertTo-Json -InputObject $plano.Chaves -Compress)) {
        throw 'O perfil mudou durante a revisao. Abra a opcao novamente.'
    }
    if (Test-SuportePerfilCarregado $alvo.SID) { throw 'Perfil em uso. Exclusao bloqueada.' }
    foreach ($pasta in $alvo.Pastas) { Get-SuporteItensPerfil $pasta $revisao.Raiz | Out-Null }
    try {
        if ($alvo.Perfil) {
            if (Test-SuportePerfilCarregado $alvo.SID) { throw 'Perfil em uso. Exclusao bloqueada.' }
            Remove-CimInstance -InputObject $alvo.Perfil -ErrorAction Stop
        }
        foreach ($pasta in $alvo.Pastas) {
            if (Test-Path -LiteralPath $pasta -ErrorAction Stop) { Remove-SuportePastaPerfil $pasta $revisao.Raiz $alvo.SID }
        }
        foreach ($chave in $alvo.Chaves) {
            if (Test-SuportePerfilCarregado $alvo.SID) { throw 'Perfil em uso. Limpeza interrompida.' }
            $caminho = Join-Path $revisao.Registro $chave.Nome
            if (Test-Path -LiteralPath $caminho -ErrorAction Stop) {
                $atual = Get-ItemPropertyValue -LiteralPath $caminho -Name ProfileImagePath -ErrorAction Stop
                $atual = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($atual)).TrimEnd('\')
                if ($atual -ne $chave.Caminho) { throw "A entrada mudou: $($chave.Nome)" }
                Remove-Item -LiteralPath $caminho -Recurse -ErrorAction Stop
            }
        }
        foreach ($pasta in $alvo.Pastas) {
            if (Test-Path -LiteralPath $pasta -ErrorAction Stop) { throw "Pasta permaneceu: $pasta" }
        }
        foreach ($chave in $alvo.Chaves) {
            if (Test-Path -LiteralPath (Join-Path $revisao.Registro $chave.Nome) -ErrorAction Stop) { throw "Entrada permaneceu: $($chave.Nome)" }
        }
    } catch { throw ('Limpeza interrompida. Algumas alteracoes podem ter sido aplicadas. Revise as pastas e o Registro. ' + $_.Exception.Message) }
    Write-Host ('Perfil local removido: ' + $alvo.Conta)
    if ((Read-Host 'Reiniciar agora? Salve o trabalho das outras sessoes antes. [s/N]') -ieq 's') {
        Restart-Computer -ErrorAction Stop
    }
    'No proximo logon, o Windows criara um perfil para a conta conforme a politica da estacao.'
}
