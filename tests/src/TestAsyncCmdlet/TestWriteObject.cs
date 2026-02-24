using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Threading;
using System.Threading.Tasks;
using Ansible.Debugger.Commands;

namespace TestAsyncCmdlet;

[Cmdlet(VerbsDiagnostic.Test, "WriteObject")]
public sealed class TestWriteObject : AsyncPSCmdlet
{
    [Parameter(Mandatory = true)]
    [AllowEmptyCollection]
    public List<string> ListTracker { get; set; } = [];

    [Parameter]
    public SwitchParameter WriteAsync { get; set; }

    [Parameter]
    public SwitchParameter NoEnumerate { get; set; }

    protected override async Task ProcessRecordAsync(AsyncPipeline pipeline, CancellationToken cancellationToken)
    {
        await Task.Delay(0, cancellationToken); // Simulate async work

        string[] data = ["foo", "bar"];
        if (WriteAsync)
        {
            // Running it with async should have it wait until the downstream
            // pipeline has processed the data which adds it back to the
            // ListTracker list.
            await pipeline.WriteObjectAsync(
                data,
                enumerateCollection: !NoEnumerate,
                cancellationToken: cancellationToken);

            bool isExpected = NoEnumerate
                ? ListTracker.Count == 1 && ListTracker[0] == "foo bar"
                : ListTracker.Count == 2 && ListTracker[0] == "foo" && ListTracker[1] == "bar";

            if (!isExpected)
            {
                pipeline.WriteError(new ErrorRecord(
                    new Exception("ListTracker should contain 'foo' and 'bar' when WriteAsync is set."),
                    "ListTrackerInvalid",
                    ErrorCategory.InvalidData,
                    null));
            }
        }
        else
        {
            // Running it without async has it return straight away so
            // ListTracker should be empty.
            pipeline.WriteObject(
                data,
                enumerateCollection: !NoEnumerate);

            if (ListTracker.Count != 0)
            {
                pipeline.WriteError(new ErrorRecord(
                    new Exception("ListTracker should be empty when WriteAsync is not set."),
                    "ListTrackerNotEmpty",
                    ErrorCategory.InvalidData,
                    null));
            }
        }
    }
}
