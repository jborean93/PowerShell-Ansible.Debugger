---
document type: cmdlet
external help file: Ansible.Debugger.dll-Help.xml
HelpUri: https://www.github.com/jborean93/PowerShell-Ansible.Debugger/blob/main/docs/en-US/Ansible.Debugger/Format-PSRPPacket.md
Locale: en-AU
Module Name: Ansible.Debugger
ms.date: 02/16/2026
PlatyPS schema version: 2024-05-01
title: Format-PSRPPacket
---

# Format-PSRPPacket

## SYNOPSIS

Formats PSRP packet objects into human-readable output.

## SYNTAX

### __AllParameterSets

```
Format-PSRPPacket -Packet <OutOfProcPacket[]> [-NoColor] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

The `Format-PSRPPacket` cmdlet formats parsed PSRP (PowerShell Remoting Protocol) packet objects into human-readable text output with color coding.

The formatted output displays:
- Packet type and GUID
- Stream information
- Fragment details (object ID, fragment ID, start/end markers)
- PSRP message details (destination, message type, runspace pool ID, pipeline ID)
- XML message data with syntax highlighting

The output uses ANSI color codes by default for improved readability, with different colors indicating message direction and packet types.

## EXAMPLES

### Example 1: Format packets from a log file

```powershell
Get-Content psremoting.log | ConvertTo-PSRPPacket | Format-PSRPPacket
```

Reads, parses, and formats PSRP packets with color output.

### Example 2: Format packets without color

```powershell
Get-Content psremoting.log | ConvertTo-PSRPPacket | Format-PSRPPacket -NoColor
```

Formats PSRP packets without ANSI color codes for plain text output.

## PARAMETERS

### -NoColor

Disables ANSI color codes in the output.
Use this when redirecting to a file or when color output is not desired.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- NoColour
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

### -Packet

The PSRP packet objects to format.
Accepts pipeline input from `ConvertTo-PSRPPacket`.

```yaml
Type: Ansible.Debugger.OutOfProcPacket[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
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

### Ansible.Debugger.OutOfProcPacket

Parsed PSRP packet objects from `ConvertTo-PSRPPacket`.

## OUTPUTS

### System.String

Formatted, human-readable representation of the PSRP packets with optional color coding.

## NOTES

## RELATED LINKS

- [ConvertTo-PSRPPacket](ConvertTo-PSRPPacket.md)
