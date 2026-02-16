---
document type: cmdlet
external help file: Ansible.Debugger.dll-Help.xml
HelpUri: https://www.github.com/jborean93/PowerShell-Ansible.Debugger/blob/main/docs/en-US/Ansible.Debugger/ConvertTo-PSRPPacket.md
Locale: en-AU
Module Name: Ansible.Debugger
ms.date: 02/16/2026
PlatyPS schema version: 2024-05-01
title: ConvertTo-PSRPPacket
---

# ConvertTo-PSRPPacket

## SYNOPSIS

Converts PSRP Out of Process protocol strings into parsed packet objects.

## SYNTAX

### __AllParameterSets

```
ConvertTo-PSRPPacket [-InputObject] <string[]> [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

The `ConvertTo-PSRPPacket` cmdlet parses PowerShell Remoting Protocol (PSRP) packet strings into structured `OutOfProcPacket` objects.
These packets are typically captured from PowerShell remoting sessions and contain XML-formatted protocol data.

The cmdlet handles fragmented messages by maintaining state across multiple packets and reassembling them into complete PSRP messages.
This is useful for analyzing PowerShell remoting traffic and debugging remote session communication.

## EXAMPLES

### Example 1: Parse PSRP packets from a log file

```powershell
Get-Content psremoting.log | ConvertTo-PSRPPacket
```

Reads PSRP packet strings from a log file and converts them into parsed packet objects.

### Example 2: Parse and format PSRP packets

```powershell
Get-Content psremoting.log | ConvertTo-PSRPPacket | Format-PSRPPacket
```

Parses PSRP packets and formats them into human-readable output with color coding.

## PARAMETERS

### -InputObject

The PSRP packet strings to parse.
Each string should be a complete XML packet from the PowerShell Remoting Protocol.
Empty or whitespace-only lines are automatically skipped.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
  ValueFromPipeline: true
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

### System.String

PSRP packet strings in XML format. The cmdlet accepts pipeline input and processes each line.

## OUTPUTS

### Ansible.Debugger.OutOfProcPacket

Parsed PSRP packet objects containing the packet type, GUID, stream information, fragments, and decoded messages.

## NOTES

- Invalid packets generate non-terminating errors and are skipped
- Fragment state persists for the lifetime of the cmdlet execution

## RELATED LINKS

- [Format-PSRPPacket](Format-PSRPPacket.md)
