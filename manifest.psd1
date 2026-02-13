@{
    InvokeBuildVersion = '5.14.23'
    PesterVersion = '5.7.1'
    BuildRequirements = @(
        @{
            ModuleName = 'Microsoft.PowerShell.PSResourceGet'
            ModuleVersion = '1.1.1'
        }
        @{
            ModuleName = 'Microsoft.PowerShell.PlatyPS'
            RequiredVersion = '1.0.1'
        }
    )
    TestRequirements = @()
}
