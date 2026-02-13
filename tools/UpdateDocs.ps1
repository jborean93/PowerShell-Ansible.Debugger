using namespace System.IO

#Requires -Version 7.2

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$projectRoot = [Path]::GetFullPath([Path]::Combine($PSScriptRoot, '..'))
$moduleName = (Get-Item ([Path]::Combine($projectRoot, 'module', '*.psd1'))).BaseName
$docsFolder = [Path]::Combine($projectRoot, 'docs', 'en-US')

Import-Module -Name ([Path]::Combine($projectRoot, 'output', $moduleName))
Import-Module -Name ([Path]::Combine($projectRoot, 'output', 'Modules', 'Microsoft.PowerShell.PlatyPS'))

# Ensure new commands are generated if not already.
Get-Command -Module $moduleName |
    New-MarkdownCommandHelp -OutputFolder $docsFolder -WithModulePage -WarningAction Ignore |
    Out-Null

# Update existing commands with new parameters or other changes.
$docsFolder = [Path]::Combine($docsFolder, $moduleName)

Measure-PlatyPSMarkdown -Path ([Path]::Combine($docsFolder, "*.md")) |
    Where-Object FileType -match CommandHelp |
    Update-MarkdownCommandHelp -LiteralPath { $_.FilePath } -NoBackup |
    Out-Null

# Update the module markdown file.
Measure-PlatyPSMarkdown -Path ([Path]::Combine($docsFolder, "*.md")) |
    Where-Object FileType -match CommandHelp |
    Import-MarkdownCommandHelp -LiteralPath { $_.FilePath } |
    Update-MarkdownModuleFile -LiteralPath ([Path]::Combine($docsFolder, "$moduleName.md")) -NoBackup -Force |
    Out-Null
