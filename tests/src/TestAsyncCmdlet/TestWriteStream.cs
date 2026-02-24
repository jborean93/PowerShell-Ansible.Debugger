using System;
using System.Management.Automation;
using System.Threading;
using System.Threading.Tasks;
using Ansible.Debugger.Commands;

namespace TestAsyncCmdlet;

[Cmdlet(VerbsDiagnostic.Test, "WriteStream")]
public sealed class TestWriteStream : AsyncPSCmdlet
{
    [Parameter]
    public string? ErrorMessage { get; set; }

    [Parameter]
    public string? WarningMessage { get; set; }

    [Parameter]
    public string? VerboseMessage { get; set; }

    [Parameter]
    public string? DebugMessage { get; set; }

    [Parameter]
    public string? InformationMessage { get; set; }

    [Parameter]
    public SwitchParameter InformationAsObject { get; set; }

    [Parameter]
    public string? HostMessage { get; set; }

    [Parameter]
    public SwitchParameter HostNoNewLine { get; set; }

    [Parameter]
    public ProgressRecord? Progress { get; set; }

    protected override async Task EndProcessingAsync(AsyncPipeline pipeline, CancellationToken cancellationToken)
    {
        await Task.Delay(0, cancellationToken); // Simulate async work

        if (ErrorMessage is not null)
        {
            pipeline.WriteError(
                new ErrorRecord(new Exception(ErrorMessage), "TestError", ErrorCategory.NotSpecified, null));
        }

        if (WarningMessage is not null)
        {
            pipeline.WriteWarning(WarningMessage);
        }

        if (VerboseMessage is not null)
        {
            pipeline.WriteVerbose(VerboseMessage);
        }

        if (DebugMessage is not null)
        {
            pipeline.WriteDebug(DebugMessage);
        }

        if (InformationMessage is not null)
        {
            if (InformationAsObject)
            {
                pipeline.WriteInformation(new InformationRecord(InformationMessage, "TestInformation"));
            }
            else
            {
                pipeline.WriteInformation(InformationMessage, ["TestTag"]);
            }
        }

        if (HostMessage is not null)
        {
            if (HostNoNewLine)
            {
                pipeline.WriteHost(HostMessage, noNewLine: true);
            }
            else
            {
                pipeline.WriteHost(HostMessage);
            }
        }

        if (Progress is not null)
        {
            pipeline.WriteProgress(Progress);
        }
    }
}
