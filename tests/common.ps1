using namespace System.IO
using namespace System.Management.Automation

$moduleName = (Get-Item ([Path]::Combine($PSScriptRoot, '..', 'module', '*.psd1'))).BaseName

if (-not (Get-Module -Name $moduleName -ErrorAction SilentlyContinue)) {
    $manifestPath = [Path]::Combine($PSScriptRoot, '..', 'output', $moduleName)
    Import-Module $manifestPath
}

if (-not (Get-Variable IsWindows -ErrorAction SilentlyContinue)) {
    # Running WinPS so guaranteed to be Windows.
    Set-Variable -Name IsWindows -Value $true -Scope Global
}

if (-not (Get-Variable -Name alcLoader -ErrorAction SilentlyContinue)) {
    # Out TestAsyncCmdlet module has deps on Ansible.Debugger so it needs to be
    # loaded in an ALC. We build an ALC that looks in the Ansible.Debugger bin
    # dir as well as the TestAsyncCmdlet bin dir to find the assemblies.
    $alcLoaderPath = [Path]::Combine($PSScriptRoot, '..', 'output', 'TestModules', 'AlcLoader', 'AlcLoader.dll')
    Add-Type -LiteralPath $alcLoaderPath

    $testModulePath = [Path]::Combine($PSScriptRoot, '..', 'output', 'TestModules', 'TestAsyncCmdlet', 'TestAsyncCmdlet.dll')

    $global:alcLoader = [AlcLoader.LoadContext]::new($moduleName, @(
        Split-Path ([Ansible.Debugger.Commands.AsyncPSCmdlet].Assembly.Location) -Parent
        Split-Path $testModulePath -Parent
    ))
    $global:alcLoader.LoadFromAssemblyPath($testModulePath) | Import-Module -Assembly { $_ }
}
