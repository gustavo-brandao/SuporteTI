@{
    RootModule = 'SuporteTI.psm1'
    ModuleVersion = '0.1.23'
    GUID = '965a6dcd-afcb-432b-9ac4-527c052dbabc'
    Author = 'Gustavo Brandão Gimenez'
    Description = 'Caixa de ferramentas local com diagnosticos e intervencoes selecionadas no menu.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Start-SuporteMenu', 'Get-SuporteCatalogo', 'Invoke-SuporteConsulta', 'Save-SuporteResultado', 'Get-SuporteDiscoClassificacao')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
