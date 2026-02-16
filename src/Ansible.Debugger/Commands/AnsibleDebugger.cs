using System;
using System.Buffers;
using System.Buffers.Binary;
using System.Collections.Generic;
using System.IO;
using System.IO.Pipes;
using System.Management.Automation;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace Ansible.Debugger.Commands;

[Cmdlet(VerbsLifecycle.Start, "AnsibleDebugger")]
[OutputType(typeof(void))]
public sealed class StartAnsibleDebuggerCommand : AsyncPSCmdlet
{
    private const string PwshSockPath = "~/.ansible/test/debugging/pwsh-listener.sock";
    internal const string StartMsgMarker = "PowerShell Debugger Listener started";


    [Parameter]
    public string? PSRemotingLogPath { get; set; }

    [Parameter(
        DontShow = true
    )]
    public string? __Internal_ForTesting { get; set; }

    protected override async Task EndProcessingAsync(AsyncPipeline pipeline, CancellationToken cancellationToken)
    {
        // We check that we are running in a debug session so that when the
        // remote PowerShell instance connects it can actually launch the new
        // debug session. We check all command types because there are no
        // guarantees it'll stay a Function in the future.
        CommandInfo? cmd = SessionState.InvokeCommand.GetCommand(
            "Start-DebugAttachSession",
            CommandTypes.All);
        if (cmd is null)
        {
            ErrorRecord errorRecord = new(
                new InvalidOperationException(
                    $"{MyInvocation.MyCommand.Name} must be run in a VSCode debugging session. Ensure you have started this cmdlet from a PowerShell Debug configuration in VSCode."),
                "NotInDebugSession",
                ErrorCategory.InvalidOperation,
                null);
            ThrowTerminatingError(errorRecord);
        }

        string? logPath = null;
        if (!string.IsNullOrWhiteSpace(PSRemotingLogPath))
        {
            logPath = SessionState.Path.GetUnresolvedProviderPathFromPSPath(PSRemotingLogPath);
            pipeline.WriteVerbose($"Using PSRemoting log path: '{logPath}'");
        }

        string sockPathFull = SessionState.Path.GetUnresolvedProviderPathFromPSPath(
            string.IsNullOrWhiteSpace(__Internal_ForTesting) ? PwshSockPath : __Internal_ForTesting);
        string sockPathDir = Path.GetDirectoryName(sockPathFull)!;
        if (!Directory.Exists(sockPathDir))
        {
            pipeline.WriteVerbose($"Creating socket directory at '{sockPathDir}'");
            Directory.CreateDirectory(sockPathDir);
        }

        using Socket listenerSock = new(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
        pipeline.WriteVerbose($"Binding to socket path '{sockPathFull}'");
        try
        {
            listenerSock.Bind(new UnixDomainSocketEndPoint(sockPathFull));
        }
        catch (SocketException ex) when (ex.SocketErrorCode == SocketError.AddressAlreadyInUse)
        {
            // This can happen if this cmdlet is running in another process or
            // if another process was hard killed and .NET didn't cleanup the
            // socket.
            ErrorRecord errorRecord = new(
                ex,
                "SocketBindError",
                ErrorCategory.ResourceExists,
                sockPathFull)
            {
                ErrorDetails = new($"Failed to bind to socket path '{sockPathFull}' as another debugger is already using it.")
                {
                    RecommendedAction = $"Ensure no other instances of the Ansible Debugger are running and that the socket file at '{sockPathFull}' has been removed.",
                }
            };
            ThrowTerminatingError(errorRecord);
        }
        listenerSock.Listen(1);

        // This is used by the debug launch configuration to know when it can
        // launch the Python ansible-test pwsh-debug configuration.
        pipeline.WriteHost(StartMsgMarker);

        using Socket ansibleClient = await listenerSock.AcceptAsync(cancellationToken);

        // We don't allow subsequent connections without restarting the cmdlet.
        listenerSock.Close();

        pipeline.WriteVerbose($"Ansible client connected, starting debug session");

        // Create a linked cancellation token that will be cancelled when
        // either the pipeline is stopped or the ansible client disconnects.
        using CancellationTokenSource linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);

        // We don't care about the result of this receive, we just want it to
        // mark our linked token as cancelled if the socket is closed from the
        // ansible client side.
        _ = WaitForClientDisconnectAsync(ansibleClient, pipeline, linkedCts, cancellationToken);

        try
        {
            await HandleAnsibleDebugSessionAsync(
                pipeline,
                new NetworkStream(ansibleClient, ownsSocket: false),
                logPath,
                linkedCts.Token);
        }
        catch (OperationCanceledException)
        {
            pipeline.WriteVerbose("Debug session cancelled");
        }
    }

    private static string GenerateToken()
    {
        Span<byte> tokenBytes = stackalloc byte[32];
        Random.Shared.NextBytes(tokenBytes);
        return Convert.ToHexString(tokenBytes);
    }

    private static async Task HandleAnsibleDebugSessionAsync(
        AsyncPipeline pipeline,
        NetworkStream ansibleClient,
        string? logPath,
        CancellationToken cancellationToken)
    {
        FileStream? logStream = null;
        StreamWriter? logger = null;
        try
        {
            if (logPath is not null)
            {
                logStream = new FileStream(
                    logPath,
                    FileMode.Append,
                    FileAccess.Write,
                    FileShare.Read);
                logger = new(logStream, Encoding.UTF8);
            }

            using TcpListener listener = new(IPAddress.IPv6Loopback, 0);
            listener.Server.DualMode = true;
            listener.Start();
            int listenerPort = ((IPEndPoint)listener.LocalEndpoint).Port;
            pipeline.WriteVerbose($"PowerShell Debugger Listener started on port {listenerPort}");

            string token = GenerateToken();
            pipeline.WriteVerbose($"Generated connection token: {token}");

            // Provide the metadata needed by the ansible client to give to the
            // remote PowerShell instance so it can connect back to us.
            await WriteConfigToSocketAsync(ansibleClient, listenerPort, token, cancellationToken);

            // We wait for the PowerShell client to connect continuously. This
            // whole loop will be cancelled when either the the cmdlet is
            // stopped or the ansible client disconnects.
            while (true)
            {
                pipeline.WriteVerbose("Waiting for remote PowerShell connection...");
                using TcpClient client = await listener.AcceptTcpClientAsync(cancellationToken);

                try
                {
                    await HandleRemotePowerShellSessionAsync(
                        pipeline,
                        client,
                        logger,
                        token,
                        cancellationToken);
                }
                catch (OperationCanceledException)
                {
                    throw;
                }
                catch (Exception e)
                {
                    pipeline.WriteVerbose($"Exception caught while handling remote PowerShell session: {e.Message}");
                }
                finally
                {
                    pipeline.WriteVerbose("Remote PowerShell session ended");
                }
            }
        }
        finally
        {
            logger?.Dispose();
            logStream?.Dispose();
        }
    }

    private static async Task HandleRemotePowerShellSessionAsync(
        AsyncPipeline pipeline,
        TcpClient client,
        StreamWriter? logger,
        string expectedToken,
        CancellationToken cancellationToken)
    {
        string clientEndpoint = client.Client.RemoteEndPoint?.ToString() ?? "Unknown";
        pipeline.WriteVerbose($"PowerShell connected from {clientEndpoint}");

        using NetworkStream stream = client.GetStream();
        using StreamReader reader = new(stream, Encoding.UTF8, leaveOpen: true);
        string? receivedToken = await reader.ReadLineAsync(cancellationToken);
        pipeline.WriteVerbose($"Received token: '{receivedToken}'");

        if (receivedToken?.Equals(expectedToken, StringComparison.OrdinalIgnoreCase) != true)
        {
            pipeline.WriteWarning($"Received invalid token from client {clientEndpoint}, skipping");
            return;
        }

        string debugInfoRaw = await reader.ReadLineAsync(cancellationToken) ?? "";
        pipeline.WriteVerbose($"Received debug request:\n{debugInfoRaw}");
        DebugPayload? debugInfo = JsonSerializer.Deserialize(
            debugInfoRaw,
            DebuggerJsonSerializerContext.Default.DebugPayload);
        if (debugInfo is null)
        {
            pipeline.WriteVerbose("Received invalid debug payload from client, skipping");
            return;
        }

        // PSES does not support a socket as a target but it does support named
        // pipes so we use that and proxy the data.
        // Named pipes on POSIX is a UDS which is limited to 108 chars so we
        // slim the GUID as much as we can.
        string pipeId = Guid.NewGuid().ToString().Replace("-", "");
        string pipeName = $"AnsibleTest-{pipeId}";
        using NamedPipeServerStream pipe = new(
            pipeName,
            PipeDirection.InOut,
            1,
            PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous);
        Task waitForPipeTask = pipe.WaitForConnectionAsync(cancellationToken);

        pipeline.WriteVerbose($"Starting VSCode attach to Pipe {pipeName}");
        Task<object?> startTask = pipeline.InvokeScriptAsync<object?>(
            Scripts.StartDebugAttachSession,
            [ pipeName, debugInfo.Value.RunspaceId, debugInfo.Value.Name, debugInfo.Value.PathMapping ],
            cancellationToken: cancellationToken);

        pipeline.WriteVerbose($"Waiting for VSCode to attach to Pipe");
        Task finishedTask = await Task.WhenAny(waitForPipeTask, startTask);
        if (finishedTask == startTask)
        {
            pipeline.WriteVerbose($"VSCode failed to attach to pipe");
            await finishedTask;

            return;
        }
        else
        {
            await waitForPipeTask;
        }

        pipeline.WriteVerbose("Starting socket <-> pipe streaming");
        Task writeTask = CopyToAsyncWithLogging(
            pipe,
            stream,
            logger,
            cancellationToken);
        Task readTask = CopyToAsyncWithLogging(
            stream,
            pipe,
            logger,
            cancellationToken);

        pipeline.WriteVerbose("Waiting for startDebugging attach response to arrive");
        await startTask;

        pipeline.WriteVerbose("Waiting for debug session to end");

        List<Task> taskList = [writeTask, readTask];;
        while (taskList.Count > 0)
        {
            finishedTask = await Task.WhenAny(taskList);
            if (finishedTask == writeTask)
            {
                pipeline.WriteVerbose($"VSCode disconnected from Pipe {pipeName} and RunspaceId {debugInfo.Value.RunspaceId}");
                client.Close();
            }
            else
            {
                pipeline.WriteVerbose($"Socket disconnected from Pipe {pipeName} and RunspaceId {debugInfo.Value.RunspaceId}");
                pipe.Close();
            }

            taskList.Remove(finishedTask);
            try
            {
                await finishedTask;
            }
            catch (IOException e)
            {
                pipeline.WriteVerbose($"IOException caught while waiting for task to complete: {e.Message}");
            }
        }
    }

    private static async Task WaitForClientDisconnectAsync(
        Socket clientSock,
        AsyncPipeline pipeline,
        CancellationTokenSource parentCancellation,
        CancellationToken cancellationToken)
    {
        byte[] buffer = new byte[1];
        try
        {
            // Try and receive 1 byte of data, if the client end is closed this
            // will return and we can cancel the linked token to signal the
            // rest of the code to stop.
            await clientSock.ReceiveAsync(buffer, cancellationToken);
        }
        catch (OperationCanceledException)
        {
            // This is expected if the PSCmdlet pipeline is stopped.
            return;
        }
        catch (Exception e)
        {
            // We don't expect this to throw under normal circumstances, but
            // if it does we want to log it if we can.
            pipeline.WriteVerbose($"Exception caught while waiting for client disconnect: {e.Message}");
            return;
        }
        finally
        {
            pipeline.WriteVerbose("Client has disconnected, stopping debug session");
            parentCancellation.Cancel();
        }
    }

    private static async Task WriteConfigToSocketAsync(
        NetworkStream socket,
        int port,
        string token,
        CancellationToken cancellationToken = default)
    {
        ListenerConfig config = new(
            Pid: Environment.ProcessId,
            Host: "localhost",
            Port: port,
            Token: token);

        ArrayBufferWriter<byte> buffer = new(256);
        using (Utf8JsonWriter jsonWriter = new(buffer))
        {
            JsonSerializer.Serialize(
                jsonWriter,
                config,
                DebuggerJsonSerializerContext.Default.ListenerConfig);
        }
        ReadOnlyMemory<byte> jsonData = buffer.WrittenMemory;

        byte[] jsonLength = new byte[4];
        BinaryPrimitives.WriteInt32LittleEndian(jsonLength, jsonData.Length);

        await socket.WriteAsync(jsonLength, cancellationToken);
        await socket.WriteAsync(jsonData, cancellationToken);
        await socket.FlushAsync(cancellationToken);
    }

    private static async Task CopyToAsyncWithLogging(
        Stream source,
        Stream destination,
        StreamWriter? logWriter,
        CancellationToken cancellationToken = default)
    {
        using StreamReader reader = new(source, Encoding.UTF8, leaveOpen: true);
        using StreamWriter writer = new(destination, Encoding.UTF8, leaveOpen: true);

        string? line;
        while ((line = await reader.ReadLineAsync(cancellationToken)) is not null)
        {
            ReadOnlyMemory<char> lineMem = line.AsMemory();
            if (logWriter is not null)
            {
                await logWriter.WriteLineAsync(lineMem, cancellationToken);
                await logWriter.FlushAsync(cancellationToken);
            }

            await writer.WriteLineAsync(lineMem, cancellationToken);
            await writer.FlushAsync(cancellationToken);
        }
    }
}
