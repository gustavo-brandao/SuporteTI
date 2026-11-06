#requires -Version 5.1
<#
Assina com Authenticode os scripts e binarios proprios de uma copia de distribuicao do Suporte TI.

  .\Construcao\Assinar.ps1 -Pacote D:\Distribuicao\SuporteTI -Impressao <thumbprint do certificado>

Assine a pasta que sera compactada no ZIP, nao o clone do git: a conversao de fim de linha
do git altera os arquivos e invalida as assinaturas. O smartctl e de terceiros e nao e assinado aqui.

Quando todos os scripts de Modulos tem assinatura valida, a janela elevada passa a usar
-ExecutionPolicy AllSigned. O certificado precisa ser confiavel nas estacoes atendidas
(por exemplo, distribuido pela GPO da instituicao em Editores Confiaveis).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Pacote,
    [Parameter(Mandatory)][ValidatePattern('^[0-9A-Fa-f]{40}$')][string]$Impressao,
    [string]$Carimbo = 'http://timestamp.digicert.com'
)
$ErrorActionPreference = 'Stop'

$Pacote = [IO.Path]::GetFullPath($Pacote)
if (-not (Test-Path -LiteralPath (Join-Path $Pacote 'Modulos\SuporteTI.psd1'))) { throw 'A pasta informada nao contem o pacote do Suporte TI.' }

$certificado = @(Get-ChildItem -LiteralPath 'Cert:\CurrentUser\My','Cert:\LocalMachine\My' |
    Where-Object { $_.Thumbprint -eq $Impressao.ToUpperInvariant() }) | Select-Object -First 1
if (-not $certificado) { throw 'Certificado nao encontrado em CurrentUser\My ou LocalMachine\My.' }
if (-not $certificado.HasPrivateKey) { throw 'O certificado nao tem chave privada disponivel.' }
if (@($certificado.EnhancedKeyUsageList | Where-Object { $_.ObjectId -eq '1.3.6.1.5.5.7.3.3' }).Count -eq 0) {
    throw 'O certificado nao e de assinatura de codigo.'
}

$arquivos = @(Join-Path $Pacote 'Iniciar.ps1') +
    @(Get-ChildItem -LiteralPath (Join-Path $Pacote 'Modulos') -File | Where-Object Extension -in '.ps1','.psm1','.psd1' | ForEach-Object FullName) +
    @((Join-Path $Pacote 'Recursos\SuporteTI.Windows.dll'),(Join-Path $Pacote 'Suporte TI.exe'))

foreach ($arquivo in $arquivos) {
    $assinatura = Set-AuthenticodeSignature -LiteralPath $arquivo -Certificate $certificado -TimestampServer $Carimbo -HashAlgorithm SHA256
    if ($assinatura.Status -ne 'Valid') { throw ('Assinatura nao validada em ' + $arquivo + ': ' + $assinatura.StatusMessage) }
    Write-Host ('Assinado: ' + $arquivo)
}
Write-Host ('Total: ' + $arquivos.Count + ' arquivos. Compacte a pasta sem editar os arquivos depois da assinatura.')
