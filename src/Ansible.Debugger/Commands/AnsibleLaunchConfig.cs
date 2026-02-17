using System.Collections.Generic;
using System.Management.Automation;
using System.Text.Json;

namespace Ansible.Debugger.Commands;

[Cmdlet(VerbsCommon.Get, "AnsibleLaunchConfig")]
[OutputType(typeof(string))]
public sealed class GetAnsibleLaunchConfigCommand : PSCmdlet
{
    [Parameter]
    [Alias("Cwd")]
    public string? WorkingDirectory { get; set; }

    [Parameter]
    public string? Inventory { get; set; }

    [Parameter]
    public string? Limit { get; set; }

    [Parameter]
    public SwitchParameter WaitAtEntry { get; set; }

    [Parameter(ValueFromRemainingArguments = true)]
    public string[] ArgumentList { get; set; } = [];

    protected override void EndProcessing()
    {
        List<string> ansibleTestArgs = ["test", "pwsh-debug"];
        if (!string.IsNullOrWhiteSpace(Inventory))
        {
            ansibleTestArgs.Add("--inventory");
            ansibleTestArgs.Add(Inventory);
        }
        if (!string.IsNullOrWhiteSpace(Limit))
        {
            ansibleTestArgs.Add("--limit");
            ansibleTestArgs.Add(Limit);
        }
        if (WaitAtEntry)
        {
            ansibleTestArgs.Add("--wait-at-entry");
        }
        ansibleTestArgs.AddRange(ArgumentList);

        PwshLaunchConfiguration config = new()
        {
            Name = "Debug Ansible PowerShell Module",
            Script = "Start-AnsibleDebugger",
            Cwd = WorkingDirectory,
            ServerReadyAction = new StartDebuggingServerReadyAction()
            {
                Pattern = StartAnsibleDebuggerCommand.StartMsgMarker,
                KillOnServerStop = true,
                Config = new PythonModuleLaunchConfiguration()
                {
                    Name = "Debug Shell",
                    Module = "ansible",
                    Cwd = WorkingDirectory,
                    Args = [.. ansibleTestArgs],
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
