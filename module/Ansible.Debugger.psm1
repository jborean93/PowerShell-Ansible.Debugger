# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

using namespace System.IO
using namespace System.Management.Automation
using namespace System.Reflection

$importModule = Get-Command -Name Import-Module -Module Microsoft.PowerShell.Core
$moduleName = [Path]::GetFileNameWithoutExtension($PSCommandPath)

$isReload = $true
if (-not ('Ansible.Debugger.Shared.LoadContext' -as [type])) {
    $isReload = $false

    Add-Type -Path ([Path]::Combine($PSScriptRoot, 'bin', 'net8.0', "$moduleName.Shared.dll"))
}

$mainModule = [Ansible.Debugger.Shared.LoadContext]::Initialize()
$innerMod = &$importModule -Assembly $mainModule -PassThru:$isReload

if ($innerMod) {
    # Bug in pwsh, Import-Module in an assembly will pick up a cached instance
    # and not call the same path to set the nested module's cmdlets to the
    # current module scope.
    # https://github.com/PowerShell/PowerShell/issues/20710
    $addExportedCmdlet = [PSModuleInfo].GetMethod(
        'AddExportedCmdlet',
        [BindingFlags]'Instance, NonPublic')
    $addExportedAlias = [PSModuleInfo].GetMethod(
        'AddExportedAlias',
        [BindingFlags]'Instance, NonPublic')
    foreach ($cmd in $innerMod.ExportedCmdlets.Values) {
        $addExportedCmdlet.Invoke($ExecutionContext.SessionState.Module, @(, $cmd))
    }
    foreach ($alias in $innerMod.ExportedAliases.Values) {
        $addExportedAlias.Invoke($ExecutionContext.SessionState.Module, @(, $alias))
    }
}
