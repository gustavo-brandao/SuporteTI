function Open-SuporteWinlogon {
    param([switch]$Gravavel)
    $raiz = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine','Registry64')
    try {
        $chave = $raiz.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon',[bool]$Gravavel)
        if (-not $chave) { throw 'Chave Winlogon indisponivel.' }
        $chave
    } finally { $raiz.Dispose() }
}

function Get-SuporteEstadoLogon {
    param($Chave)
    [pscustomobject]@{
        Ativo = [string]$Chave.GetValue('AutoAdminLogon') -eq '1'
        Usuario = [string]$Chave.GetValue('DefaultUserName')
        Dominio = [string]$Chave.GetValue('DefaultDomainName')
        SenhaLegada = $Chave.GetValueNames() -contains 'DefaultPassword'
        Temporario = $Chave.GetValueNames() -contains 'AutoLogonCount'
    }
}

function Get-SuporteResumoLogon {
    $chave = Open-SuporteWinlogon
    try { $estado = Get-SuporteEstadoLogon $chave } finally { $chave.Dispose() }
    if ($estado.Ativo) {
        'Estado: configurado. O Windows tentara entrar no proximo logon.'
        'Conta configurada: ' + (($estado.Dominio,$estado.Usuario | Where-Object { $_ }) -join '\')
        if ($estado.Temporario) { 'A configuracao atual tem limite de logons.' }
    } else { 'Estado: desativado.' }
    if ($estado.SenhaLegada) { 'Atencao: existe uma entrada de senha legada no Registro. Use Desativar para remove-la.' }
}

function Set-SuporteSegredoLogon {
    param([Security.SecureString]$Senha)
    Import-SuporteWindows
    if ($null -eq $Senha) { [SuporteTI.LogonNativo]::RemoverSenha() }
    else { [SuporteTI.LogonNativo]::GravarSenha($Senha) }
}

function Enable-SuporteLogon {
    param($Chave,[string]$Usuario,[string]$Dominio,[Security.SecureString]$Senha)
    $anteriores = @{}
    foreach ($nome in 'DefaultUserName','DefaultDomainName') { $anteriores[$nome] = $Chave.GetValue($nome) }
    $Chave.SetValue('AutoAdminLogon','0','String')
    $gravou = $false
    try {
        Set-SuporteSegredoLogon $Senha
        $gravou = $true
        $Chave.SetValue('DefaultUserName',$Usuario,'String')
        $Chave.SetValue('DefaultDomainName',$Dominio,'String')
        $Chave.SetValue('AutoAdminLogon','1','String')
    } catch {
        if ($gravou) {
            try {
                Set-SuporteSegredoLogon
                foreach ($nome in 'DefaultUserName','DefaultDomainName') {
                    if ($null -eq $anteriores[$nome]) { $Chave.DeleteValue($nome,$false) }
                    else { $Chave.SetValue($nome,$anteriores[$nome]) }
                }
            } catch { throw 'Login automatico permaneceu desativado. Revise a configuracao pela opcao Desativar.' }
        }
        throw 'Falha ao gravar a configuracao. O login automatico permaneceu desativado.'
    }
}

function Invoke-SuporteLogon {
    param([switch]$Desativar)
    $chave = Open-SuporteWinlogon -Gravavel
    try {
        $estado = Get-SuporteEstadoLogon $chave
        if ($Desativar) {
            if ((Read-Host 'Desativar e remover a senha configurada? [s/N]') -ine 's') { return 'Operacao cancelada.' }
            $chave.SetValue('AutoAdminLogon','0','String')
            try {
                $chave.DeleteValue('AutoLogonCount',$false)
                $chave.DeleteValue('ForceAutoLogon',$false)
                $chave.DeleteValue('DefaultPassword',$false)
                Set-SuporteSegredoLogon
            } catch { throw 'Login automatico desativado. A remocao completa da configuracao nao foi confirmada.' }
            return 'Login automatico desativado e credencial removida.'
        }

        if ($estado.Ativo -or $estado.SenhaLegada) { throw 'Desative a configuracao existente antes de configurar outra conta.' }
        if ($estado.Temporario -or [string]$chave.GetValue('ForceAutoLogon') -eq '1') { throw 'Existe uma configuracao especial de logon nesta estacao. Revise-a antes de prosseguir.' }
        $politica = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction Stop
        foreach ($nome in 'LegalNoticeCaption','LegalNoticeText') {
            $valor = $politica.PSObject.Properties[$nome]
            if (($valor -and -not [string]::IsNullOrWhiteSpace([string]$valor.Value)) -or $chave.GetValue($nome)) {
                throw 'O aviso obrigatorio de logon impede a configuracao do login automatico.'
            }
        }
        $usuario = ([string](Read-Host 'Usuario (0 ou Enter volta)')).Trim()
        if ($usuario -in @('','0')) { return 'Operacao cancelada.' }
        if ($usuario -match '[\\/@\x00-\x1f]' -or $usuario.Length -gt 104) { throw 'Informe apenas o nome de usuario, sem dominio.' }
        $dominio = ([string](Read-Host 'Dominio AD (Enter = conta local, 0 volta)')).Trim()
        if ($dominio -eq '0') { return 'Operacao cancelada.' }
        if ($dominio -in @('','.')) { $dominio = [Environment]::MachineName }
        if ($dominio -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,252}$') { throw 'Nome de dominio invalido.' }
        if ((Read-Host "Configurar entrada automatica para $dominio\$usuario? [s/N]") -ine 's') { return 'Operacao cancelada.' }
        if ([Console]::IsInputRedirected) { throw 'A configuracao exige um console interativo para ler a senha.' }
        $senha = Read-Host 'Senha da conta (Enter cancela)' -AsSecureString
        try {
            if (-not $senha -or $senha.Length -eq 0) { return 'Operacao cancelada.' }
            if ($senha.Length -gt 256) { throw 'Senha excede o limite aceito.' }
            Enable-SuporteLogon $chave $usuario $dominio $senha
            'Configuracao gravada. Confira a autenticacao no proximo logon ou reinicio manual.'
        } finally { if ($senha) { $senha.Dispose() } }
    } finally { $chave.Dispose() }
}
