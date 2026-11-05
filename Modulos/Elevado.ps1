#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('spooler','cache','gpcomputer','sfcverify','sfcrepair','dismcheck','dismscan','dismrestore','diskhealth','gpcomputerquery','gpcomputerhtml','netdhcp','netstatic','chkdskread','chkdskfull','perfillocal')][string]$Acao,
    [Parameter(Mandatory)][string]$Documentos64,
    [switch]$Forcar
)
$ErrorActionPreference='Stop'
$code=0
try {
    $docs=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Documentos64))
    Import-Module (Join-Path $PSScriptRoot 'SuporteTI.psd1') -Force
    # A selecao no menu autoriza a acao; o Windows controla a elevacao. Sem prompt textual extra.
    & (Get-Module SuporteTI) { param($action,$documents,$forcePolicy)
        if (-not (Test-SuporteAdmin)) { throw 'Elevacao administrativa ausente.' }
        Request-SuporteOperacao -Acao $action -Documentos $documents -Forcar:$forcePolicy
    } $Acao $docs ([bool]$Forcar)
} catch { Write-Host ('Falha: '+$_.Exception.Message); $code=1 }
[void](Read-Host 'Enter para fechar esta janela e voltar ao menu')
exit $code
