#requires -Version 5.1
[CmdletBinding()]
param([switch]$SemCores)

$ErrorActionPreference = 'Stop'
try {
    if ($env:OS -ne 'Windows_NT') { throw 'Esta ferramenta requer Windows.' }
    Import-Module (Join-Path $PSScriptRoot 'Modulos\SuporteTI.psd1') -Force
    Start-SuporteMenu -ModuleRoot $PSScriptRoot -SemCores:$SemCores
} catch {
    Write-Host ('Nao foi possivel iniciar: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Se a execucao estiver bloqueada, consulte a equipe responsavel pela politica da instituicao.'
    exit 1
}
