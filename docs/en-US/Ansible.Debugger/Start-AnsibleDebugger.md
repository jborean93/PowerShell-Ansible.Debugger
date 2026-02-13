---
document type: cmdlet
external help file: Ansible.Debugger.dll-Help.xml
HelpUri: https://www.github.com/jborean93/PowerShell-Ansible.Debugger/blob/main/docs/en-US/Ansible.Debugger/Start-AnsibleDebugger.md
Locale: en-AU
Module Name: Ansible.Debugger
ms.date: 02/13/2026
PlatyPS schema version: 2024-05-01
title: Start-AnsibleDebugger
---

# Start-AnsibleDebugger

## SYNOPSIS

Starts the PowerShell debugger listener for Ansible debugging sessions.

## SYNTAX

### __AllParameterSets

```
Start-AnsibleDebugger [-PSRemotingLogPath <string>] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

The `Start-AnsibleDebugger` cmdlet starts a Unix domain socket listener that waits for Ansible to connect for PowerShell debugging sessions.

When started, the cmdlet:
1. Creates a Unix domain socket at `~/.ansible/test/debugging/pwsh-listener.sock`
2. Listens for incoming connections from Ansible
3. Establishes a debugging bridge between VSCode and the PowerShell runspace executing the Ansible PowerShell modules
4. Routes PowerShell Remoting Protocol (PSRP) traffic between VSCode and Ansible

The cmdlet blocks until the debugging session is complete and can handle multiple debug requests from an Ansible session sequentially.

## EXAMPLES

### Example 1: Start the debugger listener

```powershell
Start-AnsibleDebugger
```

Starts the listener and waits for Ansible to connect.

### Example 2: Start with PSRP logging

```powershell
Start-AnsibleDebugger -PSRemotingLogPath ./debug.log
```

Starts the listener and logs all PSRP traffic to debug.log for analysis.

## PARAMETERS

### -PSRemotingLogPath

Optional path to a log file where PowerShell Remoting Protocol (PSRP) traffic will be recorded.
Use this for troubleshooting and analyzing the communication between VSCode and Ansible.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None

This cmdlet does not accept pipeline input.

## OUTPUTS

### None

### System.Void

This cmdlet does not produce output objects. Status messages are written to the host.

## NOTES

- The UDS socket path is `~/.ansible/test/debugging/pwsh-listener.sock`
- Only one instance can run at a time (socket bind will fail if already in use)
- The cmdlet blocks until Ctrl+C or the debugging session ends
- Requires the Ansible environment to be configured to connect to the socket, this can be done through `ansible-test pwsh-debug`

## RELATED LINKS

- [Get-AnsibleLaunchConfig](Get-AnsibleLaunchConfig.md)
- [Format-PSRPPacket](Format-PSRPPacket.md)
