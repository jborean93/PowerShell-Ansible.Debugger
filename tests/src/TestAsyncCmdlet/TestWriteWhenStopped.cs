using System;
using System.Collections;
using System.Diagnostics;
using System.Management.Automation;
using System.Threading;
using System.Threading.Tasks;
using Ansible.Debugger.Commands;

namespace TestAsyncCmdlet;

[Cmdlet(VerbsDiagnostic.Test, "WriteWhenStopped")]
public sealed class TestWriteWhenStopped : AsyncPSCmdlet
{
    [Parameter(Mandatory = true)]
    public Hashtable? State { get; set; }

    [Parameter(Mandatory = true)]
    public ManualResetEventSlim? WaitEvent { get; set; }


    protected override async Task ProcessRecordAsync(AsyncPipeline pipeline, CancellationToken cancellationToken)
    {
        Debug.Assert(State is not null, "State should not be null");
        Debug.Assert(WaitEvent is not null, "WaitEvent should not be null");

        await Task.Delay(0, cancellationToken); // Simulate async work

        // Triggers caller to set the stop event.
        WaitEvent.Set();

        // Wait until the cancellationToken is cancelled by the Stop event.
        // We want to test that pipeline.WriteObject fails accordingly.
        bool wasError = false;
        try {
            await Task.Delay(10000, cancellationToken);
        }
        catch (OperationCanceledException)
        {
            wasError = true;
        }
        State["WasCancelled"] = wasError;

        wasError = false;
        try
        {
            pipeline.WriteObject("foo");
        }
        catch (PipelineStoppedException)
        {
            wasError = true;
        }
        State["WriteObjectThrew"] = wasError;
    }
}
