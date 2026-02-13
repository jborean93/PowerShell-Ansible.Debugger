---
document type: module
Help Version: 1.0.0.0
HelpInfoUri: https://www.github.com/jborean93/PowerShell-Ansible.Debugger/blob/main/docs/en-US/Ansible.Debugger/Ansible.Debugger.md
Locale: en-AU
Module Guid: 2788ed6f-2c29-4a26-8c5b-4e93c6cac0ec
Module Name: Ansible.Debugger
ms.date: 02/13/2026
PlatyPS schema version: 2024-05-01
title: Ansible.Debugger Module
---

# Ansible.Debugger Module

## Description

PowerShell module that is used for debugging PowerShell based Ansible modules.
This is used in conjunction with Visual Studio Code, `ansible-test` to setup the debugging environment.

## Ansible.Debugger Cmdlets

### [ConvertTo-PSRPPacket](ConvertTo-PSRPPacket.md)

Converts PSRP Out of Process protocol strings into parsed packet objects.

### [Format-PSRPPacket](Format-PSRPPacket.md)

Formats PSRP packet objects into human-readable output.

### [Get-AnsibleLaunchConfig](Get-AnsibleLaunchConfig.md)

Generates a VSCode launch configuration for debugging Ansible PowerShell modules.

### [Start-AnsibleDebugger](Start-AnsibleDebugger.md)

Starts the PowerShell debugger listener for Ansible debugging sessions.

