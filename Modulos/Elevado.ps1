#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('spooler','cache','gpcomputer','sfcverify','sfcrepair','dismcheck','dismscan','dismrestore','diskhealth','gpcomputerquery','gpcomputerhtml','netdhcp','netstatic','chkdskread','chkdskfull','perfillocal','autologonenable','autologondisable')][string]$Acao,
    [Parameter(Mandatory)][string]$Documentos64,
    [switch]$Forcar,
    [switch]$SemCores
)
$ErrorActionPreference='Stop'
$code=0
try {
    $docs=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Documentos64))
    Import-Module (Join-Path $PSScriptRoot 'SuporteTI.psd1') -Force
    # O Windows controla a elevacao. Operacoes de logon confirmam a alteracao antes de gravar.
    & (Get-Module SuporteTI) { param($action,$documents,$forcePolicy,$noColors)
        if (-not (Test-SuporteAdmin)) { throw 'Elevacao administrativa ausente.' }
        Request-SuporteOperacao -Acao $action -Documentos $documents -Forcar:$forcePolicy -SemCores:$noColors
    } $Acao $docs ([bool]$Forcar) ([bool]$SemCores)
} catch { Write-Host ('Falha: '+$_.Exception.Message); $code=1 }
[void](Read-Host '0 ou Enter para voltar ao menu')
exit $code
