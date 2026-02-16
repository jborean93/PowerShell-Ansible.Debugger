# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

@{

    # Script module or binary module file associated with this manifest.
    RootModule        = 'Ansible.Debugger.psm1'

    # Version number of this module.
    ModuleVersion     = '0.1.0'

    # Supported PSEditions
    # CompatiblePSEditions = @()

    # ID used to uniquely identify this module
    GUID              = '2788ed6f-2c29-4a26-8c5b-4e93c6cac0ec'

    # Author of this module
    Author            = 'Ansible Project'

    # Company or vendor of this module
    CompanyName       = 'Ansible'

    # Copyright statement for this module
    Copyright         = '(c) 2026 Ansible Project. All rights reserved.'

    # Description of the functionality provided by this module
    Description       = 'Ansible Debugging Tools for PowerShell modules'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.4'

    # Minimum version of Microsoft .NET Framework required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
    # DotNetFrameworkVersion = '6.0'

    # Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
    # ClrVersion             = '6.0'

    # Processor architecture (None, X86, Amd64) required by this module
    # ProcessorArchitecture = ''

    # Modules that must be imported into the global environment prior to importing this module
    # RequiredModules = @()

    # Assemblies that must be loaded prior to importing this module
    # RequiredAssemblies = @()

    # Script files (.ps1) that are run in the caller's environment prior to importing this module.
    # ScriptsToProcess = @()

    # Type files (.ps1xml) to be loaded when importing this module
    TypesToProcess    = @()

    # Format files (.ps1xml) to be loaded when importing this module
    FormatsToProcess = @()

    # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
    NestedModules     = @()

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @()

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport   = @(
        'ConvertTo-PSRPPacket'
        'Get-AnsibleLaunchConfig'
        'Format-PSRPPacket'
        'Start-AnsibleDebugger'
    )

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport   = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData       = @{

        PSData = @{

            # Tags applied to this module. These help with module discovery in online galleries.
            Tags         = @(
                'Ansible'
                'Debugging'
                'PSRP'
                'PSRemoting'
            )

            # A URL to the license for this module.
            LicenseUri   = 'https://github.com/jborean93/PowerShell-Ansible.Debugger/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri   = 'https://github.com/jborean93/PowerShell-Ansible.Debugger'

            # A URL to an icon representing this module.
            # IconUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = 'See https://github.com/jborean93/PowerShell-Ansible.Debugger/blob/main/CHANGELOG.md'

            # Prerelease string of this module
            # Prerelease = ''

            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            # RequireLicenseAcceptance = $false

            # External dependent modules of this module
            # ExternalModuleDependencies = @()

        } # End of PSData hashtable

    } # End of PrivateData hashtable

}
