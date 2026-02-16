---
document type: cmdlet
external help file: Ansible.Debugger.dll-Help.xml
HelpUri: https://www.github.com/jborean93/PowerShell-Ansible.Debugger/blob/main/docs/en-US/Ansible.Debugger/Start-AnsibleDebugger.md
Locale: en-AU
Module Name: Ansible.Debugger
ms.date: 02/16/2026
PlatyPS schema version: 2024-05-01
title: Start-AnsibleDebugger
---

# Start-AnsibleDebugger

## SYNOPSIS

Starts the PowerShell debugger listener for Ansible debugging sessions.

## SYNTAX

### __AllParameterSets

```
Start-AnsibleDebugger [-PSRemotingLogPath <string>] [-__Internal_ForTesting <string>]
 [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

The `Start-AnsibleDebugger` cmdlet starts a Unix domain socket listener that waits for Ansible to connect for PowerShell debugging sessions.

When started, the cmdlet:
1. Creates a Unix domain socket at `~/.ansible/test/debugging/pwsh-listener.sock`
2. Creates a TCP listener on a random port bound to `localhost`
3. Waits for `ansible-test pwsh-debug` (started separately) to connect to the UDS
4. Sends debug configuration (TCP port and authentication token) to `ansible-test` via the UDS
5. Waits for remote PowerShell instance, started through Ansible, to connect to the TCP listener
6. When a connection is received, creates an ephemeral named pipe and instructs Debug Adapter Client/VSCode to attach to it
7. Routes PowerShell Remoting Protocol (PSRP) traffic between DA client and the remote PowerShell instance

The cmdlet acts as a bidirectional proxy, bridging Debug Adapter Client (via named pipe) with remote PowerShell instances (via TCP socket):

```
Setup Phase (when cmdlet is invoked):
┌──────────────────────────────────────────────────────────────────────┐
│                    Start-AnsibleDebugger                             │
│                                                                      │
│  1. UDS Listener: ~/.ansible/test/debugging/pwsh-listener.sock       │
│  2. TCP Listener: localhost:<random-port>                            │
│  3. Token: <generated-auth-token>                                    │
│  4. Wait for ansible-test to connect to UDS                          │
└──────────────────────────────────────────────────────────────────────┘
                              ▲
                              │ UDS: Send config (port + token)
                              ▼
                ┌────────────────────────────┐
                │  ansible-test pwsh-debug   │
                │  Interactive shell with    │
                │  debug config set          │
                └────────────────────────────┘

Debug Session Phase (on connection to TCP Listener):
┌──────────────────────────────────────────────────────────────────────┐
│                    Start-AnsibleDebugger                             │
│                         (PSRP Proxy)                                 │
│                                                                      │
│  ┌────────────────────┐                  ┌───────────────────┐       │
│  │  Named Pipe        │◄────────────────►│  TCP Listener     │       │
│  │  MyPipe-<guid>     │  PSRP OutOfProc  │  localhost:<port> │       │
│  │  (ephemeral)       │      XML         │  (persistent)     │       │
│  └────────────────────┘                  └───────────────────┘       │
│           ▲                                        ▲                 │
└───────────┼────────────────────────────────────────┼─────────────────┘
            │                                        │
            │ PSRP OutOfProc XML                     │ PSRP OutOfProc XML
            │ (over Named Pipe)                      │ (over TCP Socket)
            │                                        │
            ▼                                        │
   ┌───────────────────────┐                         │
   │  Debug Adapter Client │                         │
   │  (attach to pipe)     │                         │
   └───────────────────────┘                         │
            ▲                                        │
            │ DAP API: startDebugging()              │
            │ config: attach to MyPipe-<guid>        │
            │                                        │
   ┌────────┴────────────────────────────┐           │
   │  Start-AnsibleDebugger invokes      │           │
   │  DAP Client to attach debugger      │           │
   └─────────────────────────────────────┘           │
                                                     ▼
                                        ┌──────────────────────────────┐
                                        │  Remote PowerShell Instance  │
                                        │  Ansible PowerShell Module   │
                                        │  Connects with token         │
                                        └──────────────────────────────┘
```

The data flow for each debug session:
1. **Remote PowerShell → TCP Socket → Start-AnsibleDebugger**: Remote PowerShell instance (running an Ansible module) connects to the TCP listener with the authentication token.

2. **Start-AnsibleDebugger**: Creates ephemeral named pipe `MyPipe-<guid>` and invokes DAP/VSCode to attach to it.

3. **DAP ↔ Named Pipe ↔ Start-AnsibleDebugger ↔ TCP Socket ↔ Remote PowerShell**: PSRP commands (set breakpoint, step) and events (breakpoint hit, variable data) flow bidirectionally.

All traffic consists of PowerShell Remoting Protocol OutOfProc XML messages, which can be captured and analyzed using the `-PSRemotingLogPath` parameter.

The cmdlet blocks until `ansible-test` disconnects from the UDS or the stop signal is sent to PowerShell.
Each session can handle multiple debug requests from a remote Ansible PowerShell instance sequentially and will continue to wait for subsequent requests until `ansible-test` disconnects.

The cmdlet [Get-AnsibleLaunchConfig](./Get-AnsibleLaunchConfig.md) can be used to setup a VSCode launch configuration that runs this cmdlet and starts `ansible-test pwsh-debug`.

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
The log file contains line-delimited OutOfProc XML packets that can be analyzed with `ConvertTo-PSRPPacket` and `Format-PSRPPacket`.

### Example 3: Manual invocation workflow

```powershell
# Terminal 1: Start the debugger listener
Start-AnsibleDebugger -Verbose
# Output: PowerShell Debugger Listener started

# Terminal 2: Start ansible-test separately
ansible-test pwsh-debug --inventory hosts.ini --limit win-host

# Terminal 2: Run Ansible commands  inside the interactive shell
# launched by ansible-test.
ansible win-host -m ansible.windows.win_ping
```

This example shows manual invocation outside of the VSCode launch configuration.
Useful for troubleshooting or when you need more control over the startup sequence.

## PARAMETERS

### -PSRemotingLogPath

Optional path to a log file where PowerShell Remoting Protocol (PSRP) traffic will be recorded.

The log captures bidirectional PSRP traffic between the Debug Adapter Client and the remote PowerShell instance.
Each line in the log file is a complete OutOfProc XML packet that can be parsed with `ConvertTo-PSRPPacket` and formatted with `Format-PSRPPacket` for analysis.

Use this for:
- Troubleshooting debugging session issues
- Analyzing the communication flow between VSCode and Ansible
- Understanding PSRP protocol behavior
- Diagnosing breakpoint or variable inspection problems

The log file is appended to if it already exists, allowing multiple debug sessions to be captured sequentially.

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

This cmdlet does not produce output objects. Status messages are written to the host via `Write-Host` and `Write-Verbose`.

## NOTES

### Socket and Network Configuration

- **UDS Socket Path**: `~/.ansible/test/debugging/pwsh-listener.sock`
  - Created automatically with appropriate permissions
  - Removed automatically when the cmdlet exits cleanly
  - If the cmdlet crashes, manually remove stale sockets with: `rm ~/.ansible/test/debugging/pwsh-listener.sock`

- **TCP Listener**: Bound to `localhost` on a random available port
  - Port is dynamically allocated by the operating system
  - Sent to `ansible-test` via the UDS connection
  - Only accepts connections from localhost, SSH port forwarding is typically used to forward these ports to a remote instance

- **Single Instance**: Only one instance can run at a time
  - Socket bind will fail with an error if already in use
  - Use `lsof` or similar tools to find processes using the socket

### Authentication and Security

- **Token-Based Authentication**: A random 32-byte token is generated on startup
  - Token is sent to `ansible-test` via the UDS
  - Remote PowerShell instances must present this token to connect
  - Token is regenerated each time the cmdlet starts
  - Basic attempt to stop any other process from starting an attach request in DAP

### Session Lifecycle

- **Blocking Behavior**: The cmdlet blocks until:
  - `ansible-test` disconnects from the UDS, or
  - A stop signal (Ctrl+C) is sent to PowerShell

- **Multiple Debug Sessions**: Can handle multiple sequential PowerShell module invocations
  - Each invocation creates a new ephemeral named pipe
  - Previous debug sessions are cleaned up before starting new ones
  - Named pipes follow the pattern: `MyPipe-<guid>`

- **Cleanup on Exit**: When the cmdlet exits:
  - UDS socket is removed
  - TCP listener is closed
  - Any active named pipes are closed
  - In-progress debug sessions are terminated

## RELATED LINKS

- [Get-AnsibleLaunchConfig](Get-AnsibleLaunchConfig.md)
- [Format-PSRPPacket](Format-PSRPPacket.md)
