using System.Management.Automation;
using System.Text.Json;

namespace Ansible.Debugger.Commands;

[Cmdlet(VerbsCommon.Get, "AnsibleLaunchConfig")]
[OutputType(typeof(string))]
public sealed class GetAnsibleLaunchConfigCommand : PSCmdlet
{
    protected override void EndProcessing()
    {
        PwshLaunchConfiguration config = new()
        {
            Name = "Debug Ansible PowerShell Module",
            Script = @"Start-AnsibleDebugger",
            ServerReadyAction = new StartDebuggingServerReadyAction()
            {
                Pattern = StartAnsibleDebuggerCommand.StartMsgMarker,
                KillOnServerStop = true,
                Config = new PythonModuleLaunchConfiguration()
                {
                    Name = "Debug Shell",
                    Module = "ansible",
                    Args = [
                        "test",
                        "pwsh-debug"
                    ],
                    Console = "integratedTerminal"
                }
            }
        };
        string configJson = JsonSerializer.Serialize(
            config,
            VSCodeJsonSerializerContext.Default.PwshLaunchConfiguration);
        WriteObject(configJson);
    }
}
