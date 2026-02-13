using System;
using System.Collections.Concurrent;
using System.Management.Automation;
using System.Threading;
using System.Threading.Tasks;

namespace Ansible.Debugger.Commands;

// PowerShell 7.6 (net10.0) introduces PipelineStopToken which does the same
// thing here. Remove the #else block when net10.0 is the minimum target.
#if NET10_0_OR_GREATER
public abstract class AsyncPSCmdlet : PSCmdlet
{
#else
public abstract class AsyncPSCmdlet : PSCmdlet, IDisposable
{
    private CancellationTokenSource _cancelSource = new();

    public CancellationToken PipelineStopToken => _cancelSource.Token;

    protected override void StopProcessing()
    {
        _cancelSource.Cancel();
    }

    public void Dispose()
    {
        _cancelSource.Dispose();
        GC.SuppressFinalize(this);
    }
    ~AsyncPSCmdlet()
        => Dispose();
#endif

    protected override void BeginProcessing()
        => RunBlockInAsync(BeginProcessingAsync);

    protected virtual Task BeginProcessingAsync(AsyncPipeline pipeline, CancellationToken cancellationToken)
        => Task.CompletedTask;

    protected override void ProcessRecord()
        => RunBlockInAsync(ProcessRecordAsync);

    protected virtual Task ProcessRecordAsync(AsyncPipeline pipeline, CancellationToken cancellationToken)
        => Task.CompletedTask;

    protected override void EndProcessing()
        => RunBlockInAsync(EndProcessingAsync);

    protected virtual Task EndProcessingAsync(AsyncPipeline pipeline, CancellationToken cancellationToken)
        => Task.CompletedTask;

    private void RunBlockInAsync(Func<AsyncPipeline, CancellationToken, Task> task)
    {
        // Create the output pipeline and hook up the stop token to complete it
        // if stopping. This will ensure the AsyncCmdlet knows when to emit the
        // PipelineStoppedException as needed.
        using BlockingCollection<(AsyncPipelineType, object?)> outPipe = new();
        using var _ = PipelineStopToken.Register(() => outPipe.CompleteAdding());

        AsyncPipeline cmdlet = new(MyInvocation, outPipe);

        // Kick off the async task in the background.
        Task blockTask = Task.Run(async () =>
        {
            try
            {
                await task(cmdlet, PipelineStopToken);
            }
            finally
            {
                // Ensure the output pipeline is marked as complete when the task
                // finishes. This ensures the consuming loop below can exit.
                outPipe.CompleteAdding();
            }
        });

        // Consume the data intended for the PowerShell pipeline as they arrive.
        foreach ((AsyncPipelineType pipelineType, object? data) in outPipe.GetConsumingEnumerable(PipelineStopToken))
        {
            switch (pipelineType)
            {
                case AsyncPipelineType.Output:
                    OutputRecord output = (OutputRecord)data!;
                    WriteObject(output.Data, output.EnumerateCollection);
                    output.CompletionSource?.TrySetResult();
                    break;

                case AsyncPipelineType.Error:
                    WriteError((ErrorRecord)data!);
                    break;

                case AsyncPipelineType.Warning:
                    WriteWarning((string)data!);
                    break;

                case AsyncPipelineType.Verbose:
                    WriteVerbose((string)data!);
                    break;

                case AsyncPipelineType.Debug:
                    WriteDebug((string)data!);
                    break;

                case AsyncPipelineType.Information:
                    WriteInformation((InformationRecord)data!);
                    break;

                case AsyncPipelineType.Progress:
                    WriteProgress((ProgressRecord)data!);
                    break;

                case AsyncPipelineType.ShouldProcess:
                    ShouldProcessRecord shouldProcess = (ShouldProcessRecord)data!;
                    bool res = ShouldProcess(shouldProcess.Target, shouldProcess.Action);
                    shouldProcess.CompletionSource.TrySetResult(res);
                    break;

                case AsyncPipelineType.ScriptBlock:
                    ScriptRecord scriptRecord = (ScriptRecord)data!;
                    InvokeScriptReturnAsIs(
                        scriptRecord.ScriptBlock,
                        scriptRecord.ArgumentList,
                        scriptRecord.ReturnType,
                        scriptRecord.CompletionSource);

                    break;
            }
        }

        blockTask.GetAwaiter().GetResult();
    }

    private static void InvokeScriptReturnAsIs(
        string script,
        object?[] argumentList,
        Type returnType,
        TaskCompletionSource<object?> tcs)
    {
        try
        {
            ScriptBlock scriptBlock = ScriptBlock.Create(script);

            // As this is hooked up to the current runspace a StopProcessing
            // signal will be sent to this pipeline and we don't need to handle
            // it ourselves.
            object? result = scriptBlock.InvokeReturnAsIs(argumentList);
            object? convertedResult = LanguagePrimitives.ConvertTo(result, returnType);
            tcs.TrySetResult(convertedResult);
        }
        catch (Exception ex)
        {
            tcs.TrySetException(ex);
        }
    }
}

internal enum AsyncPipelineType
{
    Output,
    Error,
    Warning,
    Verbose,
    Debug,
    Information,
    Progress,
    ShouldProcess,
    ScriptBlock,
}

internal record OutputRecord(object? Data, bool EnumerateCollection, TaskCompletionSource? CompletionSource = null);
internal record ShouldProcessRecord(string Target, string Action, TaskCompletionSource<bool> CompletionSource);
internal record ScriptRecord(string ScriptBlock, object?[] ArgumentList, Type ReturnType, TaskCompletionSource<object?> CompletionSource);

public sealed class AsyncPipeline
{
    private readonly InvocationInfo _myInvocation;
    private readonly BlockingCollection<(AsyncPipelineType, object?)> _pipeline;

    internal AsyncPipeline(
        InvocationInfo myInvocation,
        BlockingCollection<(AsyncPipelineType, object?)> pipeline)
    {
        _myInvocation = myInvocation;
        _pipeline = pipeline;
    }

    public async ValueTask<bool> ShouldProcessAsync(
        string target,
        string action,
        CancellationToken cancellationToken = default)
    {
        TaskCompletionSource<bool> tcs = new();
        using var _ = cancellationToken.Register(() => tcs.TrySetCanceled());

        WritePipeline(AsyncPipelineType.ShouldProcess, new ShouldProcessRecord(target, action, tcs));
        return await tcs.Task;
    }

    public void WriteObject(
        object? sendToPipeline,
        bool enumerateCollection = false)
    {
        WritePipeline(
            AsyncPipelineType.Output,
            new OutputRecord(sendToPipeline, enumerateCollection));
    }

    public async ValueTask WriteObjectAsync(
        object? sendToPipeline,
        bool enumerateCollection = false,
        CancellationToken cancellationToken = default)
    {
        TaskCompletionSource tcs = new();
        using var _ = cancellationToken.Register(() => tcs.TrySetCanceled());

        WritePipeline(
            AsyncPipelineType.Output,
            new OutputRecord(sendToPipeline, enumerateCollection, tcs));
        await tcs.Task;
    }

    public void WriteError(ErrorRecord errorRecord)
        => WritePipeline(AsyncPipelineType.Error, errorRecord);

    public void WriteWarning(string message)
        => WritePipeline(AsyncPipelineType.Warning, message);

    public void WriteVerbose(string message)
        => WritePipeline(AsyncPipelineType.Verbose, message);

    public void WriteDebug(string message)
        => WritePipeline(AsyncPipelineType.Debug, message);

    public void WriteInformation(InformationRecord informationRecord)
        => WritePipeline(AsyncPipelineType.Information, informationRecord);

    public void WriteInformation(object messageData, string[] tags)
    {
        string? source = _myInvocation.PSCommandPath;
        if (string.IsNullOrEmpty(source))
        {
            source = _myInvocation.MyCommand.Name;
        }

        InformationRecord infoRecord = new(
            messageData,
            source);
        infoRecord.Tags.AddRange(tags);
        WriteInformation(infoRecord);
    }

    public void WriteHost(
        string message,
        bool noNewLine = false)
    {
        HostInformationMessage msg = new()
        {
            Message = message,
            NoNewLine = noNewLine,
        };
        WriteInformation(msg, ["PSHOST"]);
    }

    public void WriteProgress(ProgressRecord progressRecord)
        => WritePipeline(AsyncPipelineType.Progress, progressRecord);

    private void WritePipeline(AsyncPipelineType type, object? data)
    {
        try
        {
            _pipeline.Add((type, data));
        }
        catch (InvalidOperationException)
        {
            // Thrown if the pipeline has been marked as complete. This indicates
            // that the cmdlet is stopping so we just need to exit out.
            throw new PipelineStoppedException();
        }
    }

    public async Task<T> InvokeScriptAsync<T>(
        string script,
        object?[]? argumentList = null,
        CancellationToken cancellationToken = default)
    {
        TaskCompletionSource<object?> tcs = new();
        using var _ = cancellationToken.Register(() => tcs.TrySetCanceled());

        WritePipeline(
            AsyncPipelineType.ScriptBlock,
            new ScriptRecord(script, argumentList ?? [], typeof(T), tcs));

        // InvokeScriptReturnAsIs will handle conversion to T for us.
        return (T)(await tcs.Task)!;
    }
}
