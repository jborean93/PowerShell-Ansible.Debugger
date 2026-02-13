---
document type: cmdlet
external help file: Ansible.Debugger.dll-Help.xml
HelpUri: https://www.github.com/jborean93/PowerShell-Ansible.Debugger/blob/main/docs/en-US/Ansible.Debugger/Get-AnsibleLaunchConfig.md
Locale: en-AU
Module Name: Ansible.Debugger
ms.date: 02/13/2026
PlatyPS schema version: 2024-05-01
title: Get-AnsibleLaunchConfig
---

# Get-AnsibleLaunchConfig

## SYNOPSIS

Generates a VSCode launch configuration for debugging Ansible PowerShell modules.

## SYNTAX

### __AllParameterSets

```
Get-AnsibleLaunchConfig [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

The `Get-AnsibleLaunchConfig` cmdlet generates a JSON configuration object for VSCode's launch.json file.
This configuration sets up a compound debugging session that:

1. Starts the PowerShell debugger listener with `Start-AnsibleDebugger`
2. Waits for the listener to be ready
3. Launches an `ansible-test debug-pwsh` in a Python debugger
4. Waits for subsequent Ansible PowerShell module invocations to debug

The generated configuration uses VSCode's `serverReadyAction` feature to coordinate the multi-language debugging session.

The options for the `ansible-test debug-pwsh` can be modified based on your requirements.
See `ansible-test debug-pwsh --help` for more information around the arguments that can be provided to it.

## EXAMPLES

### Example 1: Generate and save the launch configuration

```powershell
Get-AnsibleLaunchConfig
```

Generates the launch configuration to provide the up to date launch configuration for debugging Ansible PowerShell modules.

## PARAMETERS

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None

This cmdlet does not accept pipeline input.

## OUTPUTS

### System.String

A JSON-formatted VSCode launch configuration string.

## NOTES

- The configuration is designed for VSCode with both PowerShell and Python extensions installed
- The Ansible module to debug is specified as `ansible test pwsh-debug`
- The configuration uses `integratedTerminal` console mode for Python debugging

## RELATED LINKS

- [Start-AnsibleDebugger](Start-AnsibleDebugger.md)
