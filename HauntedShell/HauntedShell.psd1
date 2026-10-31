@{
    RootModule        = 'HauntedShell.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '6a1f3c2e-9d4b-4e7a-8b1c-2f0d5e6a7b31'
    Author            = 'Kuntal'
    Description       = 'A ghost possesses your PowerShell prompt and whispers back, powered by a local open-weight model in Ollama.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Enable-Ghost', 'Disable-Ghost', 'Enable-Calavera', 'Disable-Calavera',
                          'Get-GhostConfig', 'Set-GhostConfig', 'Show-Ofrenda', 'Test-Ghost')
    AliasesToExport   = @('summon', 'banish', 'ofrenda')
    CmdletsToExport   = @()
    VariablesToExport = @()
    PrivateData       = @{ PSData = @{ Tags = @('Halloween', 'Ollama', 'LLM', 'Prompt', 'DiaDeLosMuertos') } }
}
