function Test-SuporteCaminhoSemLinks {
    param([string]$Caminho)
    $item = Get-Item -LiteralPath $Caminho -Force -ErrorAction Stop
    while ($null -ne $item) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
        $item = $item.Parent
    }
    $true
}

function Invoke-SuporteCacheChrome {
    param([string]$DadosChrome = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Google\Chrome\User Data'))
    if (Test-SuporteAdmin) { throw 'Abra o Suporte TI como usuario comum para limpar o cache da sessao.' }
    if (Get-Process -Name chrome -ErrorAction SilentlyContinue) { throw 'Feche o Chrome, inclusive processos em segundo plano, e tente novamente.' }
    $raiz = [IO.Path]::GetFullPath($DadosChrome)
    if ($raiz -notmatch '^[A-Za-z]:\\' -or [IO.DriveInfo]::new([IO.Path]::GetPathRoot($raiz)).DriveType -ne 'Fixed') {
        throw 'O cache precisa estar em uma unidade local fixa.'
    }
    if (-not (Test-Path -LiteralPath $raiz -PathType Container)) { return 'Pasta padrao do Chrome ausente nesta conta.' }
    if (-not (Test-SuporteCaminhoSemLinks $raiz)) { throw 'A pasta do Chrome usa redirecionamento. Limpeza interrompida.' }

    $removidos = 0
    $ignorados = 0
    $bytes = 0L
    $perfis = Get-ChildItem -LiteralPath $raiz -Directory -Force -ErrorAction Stop |
        Where-Object Name -Match '^(Default|Profile [0-9]+)$'
    foreach ($perfil in $perfis) {
        $cache = Join-Path $perfil.FullName 'Cache'
        if (-not (Test-Path -LiteralPath $cache -PathType Container)) { continue }
        $prefixo = $cache.TrimEnd('\') + '\'
        $pendentes = New-Object 'System.Collections.Generic.Stack[string]'
        $pendentes.Push($cache)
        while ($pendentes.Count -gt 0) {
            $diretorio = $pendentes.Pop()
            try {
                if (-not (Test-SuporteCaminhoSemLinks $diretorio)) { $ignorados++; continue }
                $itens = Get-ChildItem -LiteralPath $diretorio -Force -ErrorAction Stop
            } catch { $ignorados++; continue }
            foreach ($item in $itens) {
                $caminho = [IO.Path]::GetFullPath($item.FullName)
                if (-not $caminho.StartsWith($prefixo,[StringComparison]::OrdinalIgnoreCase) -or
                    ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $ignorados++; continue }
                if ($item.PSIsContainer) { $pendentes.Push($caminho); continue }
                try {
                    $tamanho = $item.Length
                    Remove-Item -LiteralPath $caminho -Force -ErrorAction Stop
                    $removidos++
                    $bytes += $tamanho
                } catch { $ignorados++ }
            }
        }
    }
    'Cache HTTP do Chrome: {0} arquivos removidos | {1:N1} MiB | {2} itens ignorados ou inacessiveis.' -f $removidos,($bytes/1MB),$ignorados
}

function Invoke-SuporteVerificacaoDisco {
    param([switch]$Completa)
    $volumes = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop |
        Where-Object { $_.DeviceID -match '^[A-Z]:$' -and $_.FileSystem -in @('NTFS','FAT','FAT32','exFAT') } |
        Sort-Object DeviceID)
    if (-not $volumes.Count) { throw 'Nenhum volume local compativel encontrado.' }
    for ($i=0; $i -lt $volumes.Count; $i++) {
        Write-Host ('[{0}] {1} {2} ({3})' -f ($i+1),$volumes[$i].DeviceID,$volumes[$i].VolumeName,$volumes[$i].FileSystem)
    }
    $escolha = 0
    $entrada = Read-Host 'Volume (Enter ou 0 volta)'
    if (-not $entrada -or $entrada -eq '0') { return 'Selecao cancelada.' }
    if (-not [int]::TryParse($entrada,[ref]$escolha) -or $escolha -lt 1 -or $escolha -gt $volumes.Count) { throw 'Volume invalido.' }
    $volume = $volumes[$escolha-1].DeviceID
    $argumentos = @($volume)
    if ($Completa) {
        Write-Host 'A verificacao completa pode demorar. Se o volume estiver em uso, o Windows podera oferecer o agendamento para o proximo reinicio.'
        $argumentos += @('/f','/r')
    }
    Invoke-SuporteNativeAction 'chkdsk.exe' $argumentos
}
