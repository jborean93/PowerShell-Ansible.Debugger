using System.Management.Automation;
using System.Threading;
using System.Threading.Tasks;
using Ansible.Debugger.Commands;

namespace TestAsyncCmdlet;

[Cmdlet(VerbsDiagnostic.Test, "CmdletBlocks")]
public sealed class TestCmdletBlocks : AsyncPSCmdlet
{
    [Parameter(ValueFromPipeline = true)]
    public string[]? InputObject { get; set; }

    protected override async Task BeginProcessingAsync(AsyncPipeline pipeline, CancellationToken cancellationToken)
    {
        await Task.Delay(0, cancellationToken); // Simulate async work
        pipeline.WriteHost("BeginProcessing");
    }

    protected override async Task ProcessRecordAsync(AsyncPipeline pipeline, CancellationToken cancellationToken)
    {
        await Task.Delay(0, cancellationToken); // Simulate async work
        pipeline.WriteHost("ProcessRecord");
        await pipeline.WriteObjectAsync(InputObject ?? [], cancellationToken: cancellationToken);
    }

    protected override async Task EndProcessingAsync(AsyncPipeline pipeline, CancellationToken cancellationToken)
    {
        await Task.Delay(0, cancellationToken); // Simulate async work
        pipeline.WriteHost("EndProcessing");
    }
}
