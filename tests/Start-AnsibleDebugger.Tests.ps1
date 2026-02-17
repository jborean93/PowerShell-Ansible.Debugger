using namespace System.Buffers.Binary
using namespace System.IO
using namespace System.IO.Pipes
using namespace System.Management.Automation
using namespace System.Net.Sockets
using namespace System.Text
using namespace System.Threading

. ([Path]::Combine($PSScriptRoot, 'common.ps1'))

Describe "Start-AnsibleDebugger" {
    BeforeAll {
        $testSockPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
            "TestDrive:/uds/Ansible.Debugger.Test.sock")

        $testParams = @{
            __Internal_ForTesting = $testSockPath
        }

        Function Start-TestDebugSession {
            [CmdletBinding()]
            param (
                [Parameter()]
                [string]
                $PSRemotingLogPath,

                [Parameter()]
                [ScriptBlock]
                $StartDebugAttachSession
            )

            $modulePath = Join-Path (Get-Module -Name Ansible.Debugger).ModuleBase 'Ansible.Debugger.psd1'

            if (-not $StartDebugAttachSession) {
                $StartDebugAttachSession = {
                    param($CustomPipeName, $RunspaceId, $Name, $PathMapping, $WindowActionOnEnd)

                    $pipe = [NamedPipeClientStream]::new(
                        ".",
                        $CustomPipeName,
                        [PipeDirection]::InOut,
                        [PipeOptions]::Asynchronous)
                    $connectTask = $pipe.ConnectAsync()

                    $start = Get-Date
                    while (-not $connectTask.AsyncWaitHandle.WaitOne(300)) {
                        if (((Get-Date) - $start).TotalSeconds -gt 10) {
                            throw "Timeout waiting for debugger to connect to named pipe"
                        }
                    }
                    $null = $connectTask.GetAwaiter().GetResult()

                    $global:StartState['PSBoundParameters'] = $PSBoundParameters
                    $global:StartState['Pipe'] = $pipe
                    $global:StartState['WaitEvent'].Set()
                }
            }

            $splat = $testParams.Clone()
            if ($PSRemotingLogPath) {
                $splat.PSRemotingLogPath = $PSRemotingLogPath
            }

            $startState = @{
                WaitEvent = [ManualResetEventSlim]::new($false)
            }
            $ps = [PowerShell]::Create()
            $null = $ps.AddScript({
                param ($Path, $StartState, $StartDebugAttachSession, $Params)

                $ErrorActionPreference = "Stop"

                $global:StartState = $StartState
                ${function:Start-DebugAttachSession} = $StartDebugAttachSession.Ast.GetScriptBlock()

                Import-Module -Name $Path

                Start-AnsibleDebugger @Params -Verbose
            })
            $null = $ps.AddArgument($modulePath)
            $null = $ps.AddArgument($startState)
            $null = $ps.AddArgument($StartDebugAttachSession)
            $null = $ps.AddArgument($splat)
            $task = $ps.BeginInvoke()

            $session = [PSCustomObject]@{
                PowerShell = $ps
                Task = $task
                UDSEndpoint = [UnixDomainSocketEndPoint]::new($testSockPath)
                StartState = $startState
            }
            $session.PSObject.Methods.Add([PSScriptMethod]::new('Dispose', {
                $this.StartState.WaitEvent.Dispose()

                if ($this.PowerShell.InvocationStateInfo.State -notin @('Completed', 'Stopping', 'Stopped')) {
                    try {
                        $stopTask = $this.PowerShell.BeginStop($null, $null)

                        $start = Get-Date
                        while (-not $stopTask.AsyncWaitHandle.WaitOne(300)) {
                            if (((Get-Date) - $start).TotalSeconds -gt 5) {
                                break
                            }
                        }
                        if ($stopTask.IsCompleted) {
                            $this.PowerShell.EndStop($stopTask)
                        }
                    }
                    catch {
                    }
                }

                if ($this.Task.IsCompleted) {
                    try {
                        $this.PowerShell.EndInvoke($this.Task)
                    }
                    catch {
                    }
                }

                $this.PowerShell.Dispose()
            }))

            # Wait for the debug session to start by checking for information
            # stream messages which indicate the listener has started.
            { $ps.Streams.Information.Count -gt 0 } | Invoke-WithTimeout -Timeout 10 -DebugSession $session

            $session
        }

        Function Start-ClientTcpConnection {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory)]
                [PSObject]
                $DebugSession,

                [Parameter(Mandatory)]
                [int]
                $Port,

                [Parameter(Mandatory)]
                [string]
                $Token,

                [Parameter()]
                [string]
                $ConfigJson
            )

            $remote = $remoteStream
            try {
                $remote = [TcpClient]::new()
                $connectTask = $remote.ConnectAsync("localhost", $Port)
                { $connectTask.IsCompleted } | Invoke-WithTimeout -Timeout 10 -DebugSession $DebugSession
                $null = $connectTask.GetAwaiter().GetResult()

                $remoteStream = $remote.GetStream()
                $remoteWriter = [StreamWriter]::new($remoteStream, [Encoding]::UTF8, 4096, $true)
                $remoteWriter.AutoFlush = $true
                $remoteReader = [StreamReader]::new($remoteStream, [Encoding]::UTF8, $false, 4096, $true)

                $sendTask = $remoteWriter.WriteLineAsync($Token)
                { $sendTask.IsCompleted } | Invoke-WithTimeout -Timeout 10 -DebugSession $DebugSession
                $null = $sendTask.GetAwaiter().GetResult()

                if (-not $ConfigJson) {
                    $debugInfo = @{
                        runspace_id = 1234
                        name = "module_name"
                        path_mapping = @(
                            @{ localRoot = 'local1'; remoteRoot = 'remote1' }
                            @{ localRoot = 'local2'; remoteRoot = 'remote2' }
                        )
                    }
                    $ConfigJson = $debugInfo | ConvertTo-Json -Compress
                }

                $sendTask = $remoteWriter.WriteLineAsync($ConfigJson)
                { $sendTask.IsCompleted } | Invoke-WithTimeout -Timeout 10 -DebugSession $DebugSession
                $null = $sendTask.GetAwaiter().GetResult()

                $remote, $remoteStream, $remoteReader, $remoteWriter
            }
            catch {
                ${remoteStream}?.Dispose()
                ${remote}?.Dispose()
                throw
            }
        }

        Function Start-DebugAttachSession {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory)]
                [PSObject]
                $DebugSession
            )

            $pipe = $null
            try {
                { $DebugSession.StartState.WaitEvent.IsSet } | Invoke-WithTimeout -Timeout 10 -DebugSession $DebugSession
                $DebugSession.StartState.WaitEvent.Reset()

                $pipe = $DebugSession.StartState.Pipe
                $writer = [StreamWriter]::new($pipe, [Encoding]::UTF8, 4096, $true)
                $writer.AutoFlush = $true
                $reader = [StreamReader]::new($pipe, [Encoding]::UTF8, $false, 4096, $true)

                $pipe, $reader, $writer
            }
            catch {
                ${pipe}?.Dispose()
                throw
            }
        }

        Function Get-TestDebugSessionConfig {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory)]
                [PSObject]
                $DebugSession
            )

            $socket = [Socket]::new([AddressFamily]::Unix, [SocketType]::Stream, [ProtocolType]::Unspecified)
            try {
                $connectTask = $socket.ConnectAsync($DebugSession.UDSEndpoint)
                { $connectTask.IsCompleted } | Invoke-WithTimeout -Timeout 10 -DebugSession $DebugSession
                $null = $connectTask.GetAwaiter().GetResult()

                $buffer = [byte[]]::new(1024)
                $segment = [ArraySegment[byte]]::new($buffer, 0, $buffer.Length)
                $receiveTask = $socket.ReceiveAsync($segment)
                { $receiveTask.IsCompleted } | Invoke-WithTimeout -Timeout 10 -DebugSession $DebugSession
                $bytesReceived = $receiveTask.GetAwaiter().GetResult()

                $length = [BinaryPrimitives]::ReadInt32LittleEndian(
                    [ArraySegment[byte]]::new($buffer, 0, 4))

                while ($bytesReceived -lt ($length + 4)) {
                    $segment = [ArraySegment[byte]]::new($buffer, $bytesReceived, $buffer.Length - $bytesReceived)
                    $receiveTask = $socket.ReceiveAsync($segment)
                    { $receiveTask.IsCompleted } | Invoke-WithTimeout -Timeout 10 -DebugSession $DebugSession
                    $bytesReceived += $receiveTask.GetAwaiter().GetResult()
                }

                $json = [Encoding]::UTF8.GetString($buffer, 4, $length) | ConvertFrom-Json

                $socket
                $json
            }
            catch {
                $socket.Dispose()
                throw
            }
        }

        Function Invoke-WithTimeout {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory, ValueFromPipeline)]
                [ScriptBlock]
                $ScriptBlock,

                [Parameter(Mandatory)]
                [int]
                $Timeout,

                [Parameter()]
                [PSObject]
                $DebugSession
            )

            process {
                $start = Get-Date
                while ($true) {
                    $hasFinished = $DebugSession.Task.IsCompleted
                    $result = & $ScriptBlock
                    if ($result) {
                        return
                    }

                    # If the task has completed but the ScriptBlock doesn't
                    # return true we will throw because nothing will change
                    # on subsequent checks.
                    $elapsed = (Get-Date) - $start
                    if ($elapsed.TotalSeconds -gt $Timeout -or $hasFinished) {


                        if (-not ($DebugSession.Task.IsCompleted) -and $DebugSession.PowerShell.InvokeStateInfo.State -notin @('Stopping', 'Stopped')) {
                            # Stop can block so we try and stop it but wait for 5
                            # seconds before giving up.
                            $stopTask = $DebugSession.PowerShell.BeginStop($null, $null)
                            $stopStart = Get-Date
                            while (-not $stopTask.AsyncWaitHandle.WaitOne(300)) {
                                if (((Get-Date) - $stopStart).TotalSeconds -gt 5) {
                                    break
                                }
                            }

                            if ($stopTask.IsCompleted) {
                                try {
                                    $DebugSession.PowerShell.EndStop($stopTask)
                                }
                                catch {
                                    # Ignore errors from EndStop since we're already in an error path
                                }
                            }
                        }

                        $taskResult = $null
                        if ($DebugSession.Task.IsCompleted) {
                            try {
                                $taskResult = $DebugSession.PowerShell.EndInvoke($DebugSession.Task)
                            }
                            catch {
                                $taskResult = "Error during debug session: $_"
                            }
                        }
                        $taskErrors = @($DebugSession.PowerShell.Streams.Error | ForEach-Object ToString) -join ([Environment]::NewLine)
                        $taskVerbose = @($DebugSession.PowerShell.Streams.Verbose | ForEach-Object ToString) -join ([Environment]::NewLine)

                        $msg = "Timeout after $Timeout seconds."
                        if ($taskResult) {
                            $msg += " ScriptBlock result: $taskResult."
                        }
                        if ($taskErrors) {
                            $msg += "`n`nTask errors:`n$taskErrors"
                        }
                        if ($taskVerbose) {
                            $msg += "`n`nTask verbose stream:`n$taskVerbose"
                        }

                        throw $msg
                    }
                    Start-Sleep -Milliseconds 300
                }
            }
        }
    }
    AfterAll {
        if (Test-Path -LiteralPath $testSockPath) {
            Remove-Item -LiteralPath $testSockPath
        }
    }

    It "Fails when not run in a debug session" {
        $modulePath = Join-Path (Get-Module -Name Ansible.Debugger).ModuleBase 'Ansible.Debugger.psd1'

        $ps = [PowerShell]::Create()
        $null = $ps.AddScript('Import-Module -Name $args[0]; Start-AnsibleDebugger')
        $null = $ps.AddArgument($modulePath)
        $ps.Invoke()

        $ps.Streams.Error | Should -HaveCount 1
        [string]$ps.Streams.Error[0] | Should -BeLike "Start-AnsibleDebugger must be run in a VSCode debugging session.*"
    }

    It "Fails if UDS already bound" {
        $session = Start-TestDebugSession
        try {
            { Start-TestDebugSession } | Should -Throw "*Failed to bind to socket path '*' as another debugger is already using it*"
        }
        finally {
            $session.Dispose()
        }
    }

    It "Responds to stop signal" {
        $session = Start-TestDebugSession

        try {
            Test-Path -LiteralPath $testSockPath | Should -BeTrue
            $session.PowerShell.Streams.Information | Should -HaveCount 1
            $session.PowerShell.Streams.Information[0].MessageData | Should -Be "PowerShell Debugger Listener started"
            $session.PowerShell.Streams.Information[0].Tags | Should -Contain "PSHOST"

            $stopTask = $session.PowerShell.BeginStop($null, $null)
            { $stopTask.IsCompleted } | Invoke-WithTimeout -Timeout 10 -DebugSession $session

            $session.PowerShell.EndStop($stopTask)

            $session.PowerShell.InvocationStateInfo.State | Should -Be Stopped
            { $session.PowerShell.EndInvoke($session.Task) } | Should -Throw "*The pipeline has been stopped*"
            Test-Path -LiteralPath $testSockPath | Should -BeFalse
        }
        finally {
            $session.Dispose()
        }
    }

    It "Responds to UDS connection" {
        $session = $socket = $null
        try {
            $session = Start-TestDebugSession
            $socket, $json = Get-TestDebugSessionConfig -DebugSession $session

            $json.version | Should -Be 1
            $json.pid | Should -Be $PID
            $json.host | Should -Be localhost
            $json.port | Should -BeOfType ([long])
            $json.token | Should -BeOfType ([string])

            # Closing the socket should cause the debug session to end
            $socket.Close()
            { $session.Task.IsCompleted } | Invoke-WithTimeout -Timeout 10 -DebugSession $session
        }
        finally {
            ${socket}?.Dispose()
            ${session}?.Dispose()
        }
    }

    It "Creates UDS directory if it doesn't already exist" {
        $session = $socket = $null
        try {
            $udsDir = Split-Path -Path $testSockPath -Parent
            if (Test-Path -LiteralPath $udsDir) {
                Remove-Item -LiteralPath $udsDir
            }

            $session = Start-TestDebugSession
            $socket, $json = Get-TestDebugSessionConfig -DebugSession $session

            $json.version | Should -Be 1
            $json.pid | Should -Be $PID
            $json.host | Should -Be localhost
            $json.port | Should -BeOfType ([long])
            $json.token | Should -BeOfType ([string])

            # Closing the socket should cause the debug session to end
            $socket.Close()
            { $session.Task.IsCompleted } | Invoke-WithTimeout -Timeout 10 -DebugSession $session
        }
        finally {
            ${socket}?.Dispose()
            ${session}?.Dispose()
        }
    }

    It "Rejects second UDS connection" {
        $session = $socket = $socketFail = $null
        try {
            $session = Start-TestDebugSession
            $socket, $null = Get-TestDebugSessionConfig -DebugSession $session

            $socketFail = [Socket]::new([AddressFamily]::Unix, [SocketType]::Stream, [ProtocolType]::Unspecified)
            $connectTask = $socketFail.ConnectAsync($session.UDSEndpoint)
            $connectTask.AsyncWaitHandle.WaitOne(1000) | Should -BeTrue
            $connectTask.IsCompleted | Should -BeTrue
            $connectTask.IsFaulted | Should -BeTrue
            { $connectTask.GetAwaiter().GetResult() } | Should -Throw
        }
        finally {
            ${socketFail}?.Dispose()
            ${socket}?.Dispose()
            ${session}?.Dispose()
        }
    }

    It "Starts debug exchange" {
        $session = $socket = $clientTcp = $clientStream = $debugPipe = $null
        try {
            $session = Start-TestDebugSession
            $socket, $json = Get-TestDebugSessionConfig -DebugSession $session
            $clientTcp, $clientStream, $clientReader, $clientWriter = Start-ClientTcpConnection -DebugSession $session -Port $json.port -Token $json.token
            $debugPipe, $debugReader, $debugWriter = Start-DebugAttachSession -DebugSession $session

            $debugWriter.WriteLine("From client")
            $clientReader.ReadLine() | Should -Be "From client"
            $clientWriter.WriteLine("From remote")
            $debugReader.ReadLine() | Should -Be "From remote"
        }
        finally {
            ${debugPipe}?.Dispose()
            ${clientStream}?.Dispose()
            ${clientTcp}?.Dispose()
            ${socket}?.Dispose()
            ${session}?.Dispose()
        }
    }

    It "Logs TCP Listener packets" {
        $logPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
            (Join-Path "TestDrive:/" "log.txt"))

        $session = $socket = $clientTcp = $clientStream = $debugPipe = $null
        try {
            $session = Start-TestDebugSession -PSRemotingLogPath $logPath
            $socket, $json = Get-TestDebugSessionConfig -DebugSession $session
            $clientTcp, $clientStream, $clientReader, $clientWriter = Start-ClientTcpConnection -DebugSession $session -Port $json.port -Token $json.token
            $debugPipe, $debugReader, $debugWriter = Start-DebugAttachSession -DebugSession $session

            $debugWriter.WriteLine("From client")
            $clientReader.ReadLine() | Should -Be "From client"
            $clientWriter.WriteLine("From remote")
            $debugReader.ReadLine() | Should -Be "From remote"

            $logs = Get-Content -LiteralPath $logPath
            $logs | Should -HaveCount 2
            $logs[0] | Should -Be "From client"
            $logs[1] | Should -Be "From remote"
        }
        finally {
            ${debugPipe}?.Dispose()
            ${clientStream}?.Dispose()
            ${clientTcp}?.Dispose()
            ${socket}?.Dispose()
            ${session}?.Dispose()
        }
    }

    It "Handles invalid debug payload <Json> from TCP client" -TestCases @(
        @{ Json = 'invalid' }
        @{ Json = ' ' }
        @{ Json = 'null' }
        @{ Json = '{}'}
        @{ Json = '{"name": "Name", "path_mapping": []}'}
        @{ Json = '{"runspace_id": null, "name": "Name", "path_mapping": []}'}
        @{ Json = '{"runspace_id": "invalid", "name": "Name", "path_mapping": []}'}

        @{ Json = '{"runspace_id": 0, "path_mapping": []}'}
        @{ Json = '{"runspace_id": 0, "name": null, "path_mapping": []}'}

        @{ Json = '{"runspace_id": 0, "name": "name"}'}
        @{ Json = '{"runspace_id": 0, "name": "name", "path_mapping": null}'}
    ) {
        param ($Json)

        $session = $socket = $clientTcp = $clientStream = $null
        try {
            $session = Start-TestDebugSession
            $socket, $sessionJson = Get-TestDebugSessionConfig -DebugSession $session
            $clientTcp, $clientStream, $clientReader, $clientWriter = Start-ClientTcpConnection -DebugSession $session -Port $sessionJson.port -Token $sessionJson.token -ConfigJson $Json

            # The server should have closed the connection after the error
            $buffer = [byte[]]::new(1)
            $readTask = $clientStream.ReadAsync($buffer, 0, 1)
            $readTask.GetAwaiter().GetResult() | Should -Be 0

            $session.Task.IsCompleted | Should -BeFalse
        }
        finally {
            ${clientStream}?.Dispose()
            ${clientTcp}?.Dispose()
            ${socket}?.Dispose()
            ${session}?.Dispose()
        }
    }

    It "Handles error when calling Start-DebugAttachSession" {
        $session = $socket = $clientTcp = $clientStream = $null
        try {
            $session = Start-TestDebugSession -StartDebugAttachSession {
                throw "Test error from Start-DebugAttachSession"
            }

            $socket, $json = Get-TestDebugSessionConfig -DebugSession $session
            $clientTcp, $clientStream, $clientReader, $clientWriter = Start-ClientTcpConnection -DebugSession $session -Port $json.port -Token $json.token

            # The server should have closed the connection after the error
            $buffer = [byte[]]::new(1)
            $readTask = $clientStream.ReadAsync($buffer, 0, 1)
            $readTask.GetAwaiter().GetResult() | Should -Be 0

            $session.Task.IsCompleted | Should -BeFalse
        }
        finally {
            ${clientStream}?.Dispose()
            ${clientTcp}?.Dispose()
            ${socket}?.Dispose()
            ${session}?.Dispose()
        }
    }

    It "Handles Start-DebugAttachSession returning before pipe connect" {
        $session = $socket = $clientTcp = $clientStream = $null
        try {
            $session = Start-TestDebugSession -StartDebugAttachSession {}

            $socket, $json = Get-TestDebugSessionConfig -DebugSession $session
            $clientTcp, $clientStream, $clientReader, $clientWriter = Start-ClientTcpConnection -DebugSession $session -Port $json.port -Token $json.token

            # The server should have closed the connection after the error
            $buffer = [byte[]]::new(1)
            $readTask = $clientStream.ReadAsync($buffer, 0, 1)
            $readTask.GetAwaiter().GetResult() | Should -Be 0

            $session.Task.IsCompleted | Should -BeFalse
        }
        finally {
            ${clientStream}?.Dispose()
            ${clientTcp}?.Dispose()
            ${socket}?.Dispose()
            ${session}?.Dispose()
        }
    }

    It "Receives invalid token from TCP client" {
        $session = $socket = $clientTcp = $clientStream = $null
        try {
            $session = Start-TestDebugSession
            $socket, $json = Get-TestDebugSessionConfig -DebugSession $session
            $clientTcp, $clientStream, $clientReader, $clientWriter = Start-ClientTcpConnection -DebugSession $session -Port $json.port -Token FAKE

            # The server should have closed the connection after the error
            $buffer = [byte[]]::new(1)
            $readTask = $clientStream.ReadAsync($buffer, 0, 1)
            $readTask.GetAwaiter().GetResult() | Should -Be 0

            $session.Task.IsCompleted | Should -BeFalse
        }
        finally {
            ${clientStream}?.Dispose()
            ${clientTcp}?.Dispose()
            ${socket}?.Dispose()
            ${session}?.Dispose()
        }
    }

    It "Handles close on TCP client end" {
        $session = $socket = $clientTcp = $clientStream = $debugPipe = $null
        try {
            $session = Start-TestDebugSession
            $socket, $json = Get-TestDebugSessionConfig -DebugSession $session
            $clientTcp, $clientStream, $clientReader, $clientWriter = Start-ClientTcpConnection -DebugSession $session -Port $json.port -Token $json.token
            $debugPipe, $debugReader, $debugWriter = Start-DebugAttachSession -DebugSession $session

            $debugWriter.WriteLine("From client")
            $clientReader.ReadLine() | Should -Be "From client"
            $clientWriter.WriteLine("From remote")
            $debugReader.ReadLine() | Should -Be "From remote"

            $clientStream.Dispose()
            $clientStream = $null

            $debugReader.ReadLine() | Should -BeNullOrEmpty
            $session.Task.IsCompleted | Should -BeFalse
        }
        finally {
            ${debugPipe}?.Dispose()
            ${clientStream}?.Dispose()
            ${clientTcp}?.Dispose()
            ${socket}?.Dispose()
            ${session}?.Dispose()
        }
    }

    It "Handles close on named pipe end" {
        $session = $socket = $clientTcp = $clientStream = $debugPipe = $null
        try {
            $session = Start-TestDebugSession
            $socket, $json = Get-TestDebugSessionConfig -DebugSession $session
            $clientTcp, $clientStream, $clientReader, $clientWriter = Start-ClientTcpConnection -DebugSession $session -Port $json.port -Token $json.token
            $debugPipe, $debugReader, $debugWriter = Start-DebugAttachSession -DebugSession $session

            $debugWriter.WriteLine("From client")
            $clientReader.ReadLine() | Should -Be "From client"
            $clientWriter.WriteLine("From remote")
            $debugReader.ReadLine() | Should -Be "From remote"

            $debugPipe.Dispose()
            $debugPipe = $null

            $clientReader.ReadLine() | Should -BeNullOrEmpty
            $session.Task.IsCompleted | Should -BeFalse
        }
        finally {
            ${debugPipe}?.Dispose()
            ${clientStream}?.Dispose()
            ${clientTcp}?.Dispose()
            ${socket}?.Dispose()
            ${session}?.Dispose()
        }
    }

    It "Handles multiple TCP requests" {
        $session = $socket = $clientTcp = $clientStream = $debugPipe = $null
        try {
            $session = Start-TestDebugSession
            $socket, $json = Get-TestDebugSessionConfig -DebugSession $session
            $clientTcp, $clientStream, $clientReader, $clientWriter = Start-ClientTcpConnection -DebugSession $session -Port $json.port -Token $json.token
            $debugPipe, $debugReader, $debugWriter = Start-DebugAttachSession -DebugSession $session

            $debugWriter.WriteLine("From client")
            $clientReader.ReadLine() | Should -Be "From client"
            $clientWriter.WriteLine("From remote")
            $debugReader.ReadLine() | Should -Be "From remote"

            $debugWriter.Dispose()
            $debugReader.Dispose()
            $clientReader.Dispose()
            $clientWriter.Dispose()
            $debugPipe.Dispose()
            $debugPipe = $debugReader = $debugWriter = $clientReader = $clientWriter = $null

            $clientTcp, $clientStream, $clientReader, $clientWriter = Start-ClientTcpConnection -DebugSession $session -Port $json.port -Token $json.token
            $debugPipe, $debugReader, $debugWriter = Start-DebugAttachSession -DebugSession $session

            $debugWriter.WriteLine("From client")
            $clientReader.ReadLine() | Should -Be "From client"
            $clientWriter.WriteLine("From remote")
            $debugReader.ReadLine() | Should -Be "From remote"
        }
        finally {
            ${debugPipe}?.Dispose()
            ${clientStream}?.Dispose()
            ${clientTcp}?.Dispose()
            ${socket}?.Dispose()
            ${session}?.Dispose()
        }
    }

    It "Is able to exit cmdlet with an active TCP connection" {
        $session = $socket = $clientTcp = $clientStream = $null
        try {
            $session = Start-TestDebugSession
            $socket, $json = Get-TestDebugSessionConfig -DebugSession $session
            $clientTcp, $clientStream, $clientReader, $clientWriter = Start-ClientTcpConnection -DebugSession $session -Port $json.port -Token $json.token

            $socket.Dispose()

            { $session.Task.IsCompleted } | Invoke-WithTimeout -Timeout 10 -DebugSession $session
        }
        finally {
            ${clientStream}?.Dispose()
            ${clientTcp}?.Dispose()
            ${socket}?.Dispose()
            ${session}?.Dispose()
        }
    }
}
