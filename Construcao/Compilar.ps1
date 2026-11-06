#requires -Version 5.1
<#
Compila "Suporte TI.exe" e Recursos\SuporteTI.Windows.dll a partir de Recursos\*.cs,
usando o csc.exe do .NET Framework 4.x que acompanha o Windows. Nao precisa de Visual Studio.

  .\Construcao\Compilar.ps1                      # grava sobre os binarios do pacote
  .\Construcao\Compilar.ps1 -Destino C:\saida    # grava em outra pasta (usado pelo CI)

O compilador do .NET Framework nao gera binarios byte a byte identicos entre compilacoes.
Os hashes SHA256 exibidos no fim identificam os arquivos gerados nesta compilacao.
#>
[CmdletBinding()]
param([string]$Destino)
$ErrorActionPreference = 'Stop'

$raiz = Split-Path $PSScriptRoot -Parent
$recursos = Join-Path $raiz 'Recursos'
if (-not $Destino) { $Destino = $raiz }
$Destino = [IO.Path]::GetFullPath($Destino)

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path -LiteralPath $csc)) { throw 'csc.exe do .NET Framework 4.x nao encontrado.' }

# A versao do executavel precisa acompanhar a versao do modulo.
$versaoModulo = (Import-PowerShellDataFile -LiteralPath (Join-Path $raiz 'Modulos\SuporteTI.psd1')).ModuleVersion
$iniciador = Get-Content -LiteralPath (Join-Path $recursos 'Iniciador.cs') -Raw
foreach ($atributo in 'AssemblyVersion','AssemblyFileVersion') {
    if ($iniciador -notmatch ('\[assembly: ' + $atributo + '\("([0-9.]+)"\)\]')) { throw ($atributo + ' ausente em Iniciador.cs.') }
    if ($Matches[1] -ne ($versaoModulo + '.0')) {
        throw ($atributo + ' ' + $Matches[1] + ' difere da versao do modulo ' + $versaoModulo + '. Atualize Recursos\Iniciador.cs.')
    }
}

$alvos = @(
    @{
        Saida = Join-Path $Destino 'Recursos\SuporteTI.Windows.dll'
        Opcoes = @('/target:library','/reference:System.Windows.Forms.dll','/reference:System.Drawing.dll','/reference:System.Core.dll')
        Fontes = @('LogonNativo.cs','MapaOcupacao.cs','MensagensWindows.cs')
    }
    @{
        Saida = Join-Path $Destino 'Suporte TI.exe'
        Opcoes = @('/target:exe',('/win32icon:' + (Join-Path $recursos 'SuporteTI.ico')))
        Fontes = @('Iniciador.cs')
    }
)

foreach ($alvo in $alvos) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($alvo.Saida))
    $argumentos = @('/nologo','/optimize+','/platform:anycpu','/warnaserror+',('/out:' + $alvo.Saida)) +
        $alvo.Opcoes + @($alvo.Fontes | ForEach-Object { Join-Path $recursos $_ })
    & $csc @argumentos
    if ($LASTEXITCODE -ne 0) { throw ('Falha ao compilar ' + [IO.Path]::GetFileName($alvo.Saida) + ' (codigo ' + $LASTEXITCODE + ').') }
}

Write-Host ('Compilado com ' + $csc + ' | versao ' + $versaoModulo)
foreach ($alvo in $alvos) {
    Write-Host ('{0}  {1}' -f (Get-FileHash -LiteralPath $alvo.Saida -Algorithm SHA256).Hash, $alvo.Saida)
}
