# PowerShell Ansible.Debugger

[![Test workflow](https://github.com/jborean93/PowerShell-Ansible.Debugger/workflows/Test%20PowerShell-Ansible.Debugger/badge.svg)](https://github.com/jborean93/PowerShell-Ansible.Debugger/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://github.com/jborean93/PowerShell-Ansible.Debugger/blob/main/LICENSE)

PowerShell module for debugging PowerShell based Ansible modules.

## Overview

`Ansible.Debugger` is a PowerShell module that enables interactive debugging of PowerShell-based Ansible modules using Visual Studio Code. It works in conjunction with the `ansible-test pwsh-debug` command to establish a debugging bridge between VSCode and PowerShell runspaces executing within Ansible.

Right now the functionality in Ansible to enable PowerShell debugging is only available in a fork at https://github.com/jborean93/ansible/tree/ps-debugging.
The end goal is to have this functionality included in Ansible so it works straight from an install.

### How It Works

The module creates a Unix domain socket listener that Ansible connects to when running PowerShell modules. When a debug session is initiated:

1. `Start-AnsibleDebugger` creates a listener socket at `~/.ansible/test/debugging/pwsh-listener.sock`
2. Ansible connects to this socket when executing PowerShell modules via `ansible-test pwsh-debug`
3. The module establishes a named pipe connection to VSCode's PowerShell extension
4. PowerShell Remoting Protocol (PSRP) traffic is routed between VSCode and the Ansible-hosted PowerShell runspace
5. You can set breakpoints, step through code, inspect variables, and use all standard VSCode debugging features

This enables full-featured debugging of PowerShell modules as they execute within the actual Ansible runtime environment, including access to Ansible-provided module arguments and execution context.

### Key Features

- **Interactive Debugging**: Set breakpoints and step through PowerShell module code in VSCode
- **PSRP Analysis**: Parse and format PowerShell Remoting Protocol packets for troubleshooting
- **Real Runtime Environment**: Debug modules with actual Ansible-provided arguments and execution context

### Caveats and Limitations

There are a few caveats and limitations to be aware of when using `Ansible.Debugger`:

- **Single Session Only**: Only one debug session can be active at a time. Ensure your launch configuration targets a single host in your inventory or the `--limit` keyword is applied to `ansible-test pwsh-debug`

- **Windows PowerShell 5.1 Behavior**: PowerShell 5.1 sessions will always stop at entry.
  - This is a limitation of PowerShellEditorServices and PowerShell 5.1 that cannot be bypassed.
  - PowerShell 7.x does not have this limitation and will only hit breakpoints if:
    - A breakpoint is explicitly set in the code, or
    - The `--wait-at-entry` flag is specified as an `ansible-test pwsh-debug` argument.

- **Performance Overhead**: The session setup and initial breakpoint add some overhead to execution time.

- **SSH Connection Required**: The target host must use the `ssh` connection type. This is required to forward the sockets used to transport debug sessions.

## Documentation

Documentation for this module and details on the cmdlets included can be found [here](docs/en-US/Ansible.Debugger/Ansible.Debugger.md).

### Available Cmdlets

- **[Start-AnsibleDebugger](docs/en-US/Ansible.Debugger/Start-AnsibleDebugger.md)** - Starts the PowerShell debugger listener for Ansible debugging sessions
- **[Get-AnsibleLaunchConfig](docs/en-US/Ansible.Debugger/Get-AnsibleLaunchConfig.md)** - Generates a VSCode launch configuration for debugging Ansible PowerShell modules
- **[ConvertTo-PSRPPacket](docs/en-US/Ansible.Debugger/ConvertTo-PSRPPacket.md)** - Parses PSRP protocol strings into structured packet objects
- **[Format-PSRPPacket](docs/en-US/Ansible.Debugger/Format-PSRPPacket.md)** - Formats PSRP packets into human-readable, color-coded output

## Requirements

These cmdlets have the following requirements:

### Ansible Controller Environment

- PowerShell 7.4 or later
- The `Ansible.Debugger` module installed and in the `PSModulePath`
- Ansible with PowerShell debugging support
  - Currently only available in the fork: https://github.com/jborean93/ansible/tree/ps-debugging
  - This functionality will be upstreamed to official Ansible in the future
- Ansible inventory setup with a host that has
  - `ansible_connection=ssh`
  - **Windows only** `ansible_shell_type=powershell` or `ansible_shell_type=cmd`
  - Other variables needed for a successful SSH connection
- **Optional** `ansible.cfg` in the current working directory that sets the default inventory and other Ansible specific options

## Target Environment

- Configures to run PowerShell modules through Ansible
- SSH enabled and reachable from the Ansible Controller

### VSCode Requirements

- Visual Studio Code installed on the controller/debugger host
- Required VSCode extensions:
  - **PowerShell** extension (ms-vscode.powershell) - For PowerShell debugging
  - **Python** extension (ms-python.python) - For Python/Ansible debugging

## Installing

### Installing the Module

The module is not yet available on the PowerShell Gallery.

### Building from Source

1. Clone this repository:

```bash
git clone https://github.com/jborean93/PowerShell-Ansible.Debugger.git
cd PowerShell-Ansible.Debugger
```

2. Build the module using PowerShell:

```powershell
pwsh -File build.ps1 -Task Build -Configuration Release
```

The built module will be placed in `output/Ansible.Debugger`.

3. Copy `output/Ansible.Debugger` to an entry under `$env:PSModulePath`

### Verifying Installation

Verify the module is available:

```powershell
Import-Module -Name Ansible.Debugger
```

## Quick Start

This guide walks through setting up and running your first debugging session.

### Prerequisites

Before starting, ensure you have:
1. An Ansible inventory file with at least 1 Windows host defined
2. SSH connectivity to the Windows host verified
3. VSCode with PowerShell and Python extensions installed
4. The `Ansible.Debugger` module installed

### Step 1: Configure Your Inventory

Create or update your Ansible inventory file with a Windows host configured for SSH:

```ini
[windows]
win-host  ansible_host=my-server

[windows:vars]
ansible_user=winuser
ansible_port=22
ansible_connection=ssh
ansible_shell_type=powershell
```

### Step 2: Verify Connectivity

Test that Ansible can successfully connect to the Windows host:

```bash
ansible win-host -m ansible.windows.win_ping
```

You should see a SUCCESS response. If this fails, resolve connectivity issues before proceeding.

### Step 3: Generate VSCode Launch Configuration

In PowerShell, generate the launch configuration:

```powershell
Get-AnsibleLaunchConfig
```

This outputs a JSON configuration object.

```json
{
    "type": "PowerShell",
    "cwd": "${workspaceFolder}",
    "script": "Start-AnsibleDebugger",
    "name": "Debug Ansible PowerShell Module",
    "request": "launch",
    "serverReadyAction": {
        "action": "startDebugging",
        "config": {
            "type": "debugpy",
            "module": "ansible",
            "args": [
                "test",
                "pwsh-debug"
            ],
            "console": "integratedTerminal",
            "name": "Debug Shell",
            "request": "launch"
        },
        "pattern": "PowerShell Debugger Listener started",
        "killOnServerStop": true
    }
}
```

### Step 4: Configure VSCode

1. Create or open `.vscode/launch.json` in your workspace
2. Add the generated configuration to the `configurations` list
3. Customize the configuration if needed:
   - If your inventory is not in `ansible.cfg`, add `"--inventory", "inventory.ini"` to the `args` list
   - If you have multiple hosts, add `"--limit", "host-pattern"` to target only one host
   - **PowerShell 7.x only** Add `"--wait-at-entry"` to pause execution at the start of each module
   - Add any extra arguments to run that as a command with the debug configuration set rather than spawn an interactive shell

Example customized args:

```json
"args": [
    "test",
    "pwsh-debug",
    "--inventory", "inventory/hosts.ini",
    "--limit", "win-host"
]
```

Example of launching a command rather than an interactive shell. In this case `ansible.cfg` is present in the cwd with `inventory = inventory.ini` set to select the inventory that way:

```json
"args": [
    "test",
    "pwsh-debug",
    "--limit", "win-host",
    "ansible", "win-host", "-m", "ansible.windows.win_ping"
]
```

### Step 5: Set Breakpoints

Open your PowerShell module file (e.g., `library/win_mymodule.ps1`) and set breakpoints by clicking in the gutter next to line numbers.
This can be skipped if running against a PowerShell 5.1 targer or `--wait-at-entry` is specified as an `ansible-test pwsh-debug` argument.

### Step 6: Start Debugging

1. In VSCode, select the launch configuration from the debug dropdown
2. Press F5 or click the green play button
3. The integrated terminal will open showing the `ansible-test pwsh-debug` shell

### Step 7: Execute an Ansible Command

In the integrated terminal that opened, run an Ansible command that uses your PowerShell module:

```bash
ansible win-host -m win_mymodule -a "name=test"
```

When the module executes:
- VSCode will start a new `PowerShell Extension (TEMP)` window
- Execution will pause at your breakpoint or at entrypoint
- You can inspect variables, step through code, and use all VSCode debugging features like a normal PowerShell debugger

### Step 8: Debug Interactively

While paused at a breakpoint, you can:
- Hover over variables to see their values
- Use the Debug Console to evaluate PowerShell expressions
- Step over (F10), step into (F11), or step out (Shift+F11)
- View the call stack and local variables in the sidebar
- Continue execution (F5) or stop debugging (Shift+F5)

## Examples

### Example 1: Debug a Custom Module

Suppose you have a custom module at `library/win_mymodule.ps1`:

```powershell
#!powershell
#AnsibleRequires -CSharpUtil Ansible.Basic

$spec = @{
    options = @{
        name = @{ type = "str"; required = $true }
        state = @{ type = "str"; default = "present"; choices = @("present", "absent") }
    }
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$name = $module.Params.name
$state = $module.Params.state

# Set a breakpoint on the next line to inspect the parameters
$module.Result.message = "Processing $name with state $state"

$module.ExitJson()
```

1. Set a breakpoint on the line `$module.Result.message = ...`
2. Start the debug configuration
3. In the terminal, run:

```bash
ansible win-host -m win_mymodule -a "name=testapp state=present" --playbook-dir .
```

4. When the breakpoint hits, inspect `$name`, `$state`, and `$module.Params` in the Variables pane

### Example 2: Debug Multiple Module Invocations

The debug shell remains active for multiple commands:

1. Start debugging
2. Run your first module:

```bash
ansible win-host -m ansible.windows.win_file -a "path=C:/temp state=directory"
```

3. Debug completes, you're back at the prompt
4. Run another module:

```bash
ansible win-host -m ansible.windows.win_copy -a "src=./file.txt dest=C:/temp/file.txt"
```

5. Each module invocation starts a fresh debug session

### Example 3: Debug PowerShell script

It is possible to also debug PowerShell scripts run through the `script` action.
The debug wrapper will automatically pick up these script invocations just like a module and start the debug session for these.

1. Start debugging
2. Run your script

```bash
ansible win-host -m script -a "test.ps1"
```

3. Debug session is started for this script invocation

## Troubleshooting

### Socket Already in Use

**Error**: `Failed to bind to socket path ... as another debugger is already using it`

**Solution**: Another instance of `Start-AnsibleDebugger` is running. Either:
- Stop the existing instance (Ctrl+C in the terminal)
- Remove the stale socket: `rm ~/.ansible/test/debugging/pwsh-listener.sock`

### Start-AnsibleDebugger is not recognized as a name of a cmdlet

**Error**: `The term 'Start-AnsibleDebugger' is not recognized as a name of a cmdlet, function, script file, or executable program.`

**Solution**: The `Ansible.Debugger` module is not present in `PSModulePath` or failed to be imported
  - Verify the module is present in `$env:PSModulePath` or `Get-Module -ListAvailable`
  - Verify the module can be imported with `Import-Module -Name Ansible.Debugger`
  - If built locally, add `Import-Module -Name /home/user/path/to/PowerShell-Ansible.Debugger/output/Ansible.Debugger; Start-AnsibleDebugger` to the launch `"script"`

### Breakpoints Not Hitting

**Symptoms**: Module executes but never pauses at breakpoints

**Possible Causes**:
1. **Breakpoint not set before execution**: Set breakpoints before running the Ansible command
2. **Module code is different**: Ensure the module file in VSCode matches what Ansible is executing, `-vvv` will show the module path used
3. **Wrong PowerShell version**: If targeting PowerShell 5.1, execution always stops at entry. Add `--wait-at-entry` for PowerShell 7.x
4. **Module not executed**: Verify your Ansible command actually runs the module you expect

**Debug Steps**:
```powershell
# Enable verbose output
ansible win-host -m ansible.windows.win_ping -vvv

# Check if the module is being executed and the path
# Using module file /home/user/dev/ansible_collections/ansible/windows/plugins/modules/win_ping.ps1
```

### SSH Connection Failures

**Error**: `ansible-test pwsh-debug` fails to connect or reports connection errors

**Solution**:
1. Verify SSH works outside of Ansible:

```bash
ssh winuser@my-server
```

2. Check SSH configuration in inventory:

```ini
ansible_connection=ssh
ansible_shell_type=powershell  # Windows only, may need to be set to cmd depending on sshd DefaultShell
```

3. Ensure the host has an SSH server running
4. Check firewall rules allow SSH (port 22)

### Multiple Hosts Targeted

**Error**: `ansible-test pwsh-debug` fails on the assertion `Verify we are running with a single host`

**Solution**: Use `--limit` to target a single host:

```json
"args": [
    "--limit", "win-host"
]
```

Or create a separate inventory file with only one host for debugging purposes.

### Python terminal not echoing keys

**Error**: The `Python Debug Console` in VSCode does not echo back any key input

**Solution**: Kill the debug console window and re-launch a new debug session

## Contributing

Contributing is quite easy, fork this repo and submit a pull request with the changes.
To build this module run `./build.ps1 -Task Build` in PowerShell.
To test a build run `./build.ps1 -Task Test` in PowerShell.
This script will ensure all dependencies are installed before running the test suite.
