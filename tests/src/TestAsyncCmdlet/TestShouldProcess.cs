using System.Management.Automation;
using System.Threading;
using System.Threading.Tasks;
using Ansible.Debugger.Commands;

namespace TestAsyncCmdlet;

[Cmdlet(VerbsDiagnostic.Test, "ShouldProcess", SupportsShouldProcess = true)]
public sealed class TestShouldProcess : AsyncPSCmdlet
{
    protected override async Task ProcessRecordAsync(AsyncPipeline pipeline, CancellationToken cancellationToken)
    {
        await Task.Delay(0, cancellationToken); // Simulate async work

        bool res = await pipeline.ShouldProcessAsync("target", "action", cancellationToken);
        pipeline.WriteObject(res);
    }
}
