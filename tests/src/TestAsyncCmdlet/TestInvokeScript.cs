using System.Diagnostics;
using System.Management.Automation;
using System.Threading;
using System.Threading.Tasks;
using Ansible.Debugger.Commands;

namespace TestAsyncCmdlet;

[Cmdlet(VerbsDiagnostic.Test, "InvokeScript")]
public sealed class TestInvokeScript : AsyncPSCmdlet
{
    [Parameter(Mandatory = true, Position = 0)]
    public ScriptBlock? ScriptBlock { get; set; }

    [Parameter]
    public object?[]? ArgumentList { get; set; }

    protected override async Task ProcessRecordAsync(AsyncPipeline pipeline, CancellationToken cancellationToken)
    {
        Debug.Assert(ScriptBlock is not null, "ScriptBlock should not be null");
        await Task.Delay(0, cancellationToken); // Simulate async work

        int? res = await pipeline.InvokeScriptAsync<int?>(
            ScriptBlock.ToString(),
            ArgumentList,
            cancellationToken);
        await pipeline.WriteObjectAsync(res, cancellationToken: cancellationToken);
    }
}
