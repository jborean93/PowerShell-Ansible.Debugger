using namespace System.Collections.Generic
using namespace System.IO
using namespace System.Management.Automation
using namespace System.Management.Automation.Host
using namespace System.Threading

. ([Path]::Combine($PSScriptRoot, 'common.ps1'))

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Security;

public class TestHost : PSHost
{
    public readonly PSHost _origHost;
    public readonly PSHostUserInterface _ui;

    public TestHost(PSHost origHost, PSHostUserInterface ui = null)
    {
        _origHost = origHost;
        _ui = ui;
    }

    public override CultureInfo CurrentCulture => _origHost.CurrentCulture;
    public override CultureInfo CurrentUICulture => _origHost.CurrentUICulture;
    public override Guid InstanceId => _origHost.InstanceId;
    public override string Name => _origHost.Name;
    public override PSHostUserInterface UI => _ui;
    public override Version Version => _origHost.Version;

    public override void EnterNestedPrompt()
    {
        _origHost.EnterNestedPrompt();
    }

    public override void ExitNestedPrompt()
    {
        _origHost.ExitNestedPrompt();
    }

    public override void NotifyBeginApplication()
    {
        _origHost.NotifyBeginApplication();
    }

    public override void NotifyEndApplication()
    {
        _origHost.NotifyEndApplication();
    }

    public override void SetShouldExit(int exitCode)
    {
        _origHost.SetShouldExit(exitCode);
    }
}

public class TestHostUserInterface : PSHostUserInterface
{
    private readonly PSHostUserInterface _origUI;
    private readonly bool _throwOnWrite;

    public TestHostUserInterface(PSHostUserInterface origUI, bool throwOnWrite = false)
    {
        _origUI = origUI;
        _throwOnWrite = throwOnWrite;
    }

    public List<string> HostLines { get; } = new List<string>();

    public override PSHostRawUserInterface RawUI => _origUI.RawUI;

    public override Dictionary<string, PSObject> Prompt(string caption, string message, Collection<FieldDescription> descriptions)
    {
        return _origUI.Prompt(caption, message, descriptions);
    }

    public override int PromptForChoice(string caption, string message, Collection<ChoiceDescription> choices, int defaultChoice)
    {
        return _origUI.PromptForChoice(caption, message, choices, defaultChoice);
    }

    public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName)
    {
        return _origUI.PromptForCredential(caption, message, userName, targetName);
    }

    public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName, PSCredentialTypes allowedCredentialTypes, PSCredentialUIOptions options)
    {
        return _origUI.PromptForCredential(caption, message, userName, targetName, allowedCredentialTypes, options);
    }

    public override string ReadLine()
    {
        return _origUI.ReadLine();
    }

    public override SecureString ReadLineAsSecureString()
    {
        return _origUI.ReadLineAsSecureString();
    }

    public override void Write(string value)
    {
        WriteToHost(value);
    }

    public override void Write(ConsoleColor foregroundColor, ConsoleColor backgroundColor, string value)
    {
        WriteToHost($"{foregroundColor} - {backgroundColor} - {value}");
    }

     public override void WriteLine(string value)
    {
        WriteToHost(value + "\n");
    }

    public override void WriteLine(ConsoleColor foregroundColor, ConsoleColor backgroundColor, string value)
    {
        WriteToHost($"{foregroundColor} - {backgroundColor} - {value}\n");
    }

    public override void WriteDebugLine(string message)
    {
        WriteToHost($"DEBUG: {message}\n");
    }

    public override void WriteErrorLine(string message)
    {
        WriteToHost($"ERROR: {message}\n");
    }

    public override void WriteVerboseLine(string message)
    {
        WriteToHost($"VERBOSE: {message}\n");
    }

    public override void WriteWarningLine(string message)
    {
        WriteToHost($"WARNING: {message}\n");
    }

    public override void WriteProgress(long sourceId, ProgressRecord record)
    {
        WriteToHost($"PROGRESS: {sourceId} - {record.Activity} - {record.StatusDescription}\n");
    }

    private void WriteToHost(string line)
    {
        if (_throwOnWrite)
        {
            throw new Exception($"Line was blocked: {line}");
        }
        HostLines.Add(line);
    }
}
'@

Describe "AsyncPSCmdlet" {
    BeforeAll {
        Function Wait-PowerShellWithTimeout {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory)]
                [ScriptBlock]
                $ScriptBlock,

                [Parameter(Mandatory)]
                [int]
                $Timeout,

                [Parameter()]
                [PSHost]
                $PSHost,

                [Parameter()]
                [switch]
                $StopOnStartup,

                [Parameter()]
                [Hashtable]
                $State
            )

            $ps = $beginTask = $stopTask = $startEvent = $null
            try {
                $startEvent = [ManualResetEventSlim]::new($false)

                $ps = [PowerShell]::Create()
                $null = $ps.AddScript({
                    param ($Assembly, $WaitEvent, $ScriptBlock)

                    $ErrorActionPreference = 'Stop'

                    Import-Module -Assembly $Assembly

                    $invokeParams = @{}
                    if ($WaitEvent) {
                        $invokeParams.WaitEvent = $WaitEvent
                    }

                    ${function:<Invoke>} = $ScriptBlock.Ast.GetScriptBlock()
                }).AddParameters(@{
                    Assembly = [TestAsyncCmdlet.TestWriteObject].Assembly
                    ScriptBlock = $ScriptBlock
                }).AddStatement()

                # We use a separate command as we can get a better error message if the
                # ScriptBlock fails.
                $null = $ps.AddCommand('<Invoke>')
                if ($StopOnStartup) {
                    $null = $ps.AddParameter('WaitEvent', $startEvent)
                }
                if ($State) {
                    $null = $ps.AddParameter('State', $State)
                }

                $inputCollection = [PSDataCollection[PSObject]]::new()
                $invocationSettings = [PSInvocationSettings]::new()
                if ($PSHost) {
                    $invocationSettings.Host = $PSHost
                }
                $beginTask = $ps.BeginInvoke($inputCollection, $invocationSettings, $null, $null)

                if ($StopOnStartup) {
                    $start = Get-Date
                    while ($true) {
                        if ($beginTask.IsCompleted) {
                            throw "PowerShell task completed before Stop could be triggered"
                        }

                        if ($startEvent.IsSet) {
                            break
                        }

                        $elapsed = (Get-Date) - $start
                        if ($elapsed.TotalSeconds -gt $Timeout) {
                            throw "Test timed out waiting for PowerShell task to start"
                        }

                        Start-Sleep -Milliseconds 100
                    }

                    $stopTask = $ps.BeginStop($null, $null)
                }

                $start = Get-Date
                while (-not $beginTask.AsyncWaitHandle.WaitOne(100)) {
                    if (((Get-Date) - $start).TotalSeconds -gt $Timeout) {
                        throw "Test timed out waiting for PowerShell task to complete"
                    }
                }

                if ($stopTask) {
                    $ps.EndStop($stopTask)
                    $stopTask = $null
                }

                try {
                    $ps.EndInvoke($beginTask)
                }
                catch [PipelineStoppedException] {
                    # Expected with Stop, this is ignored.
                }

                # This can happen if the ScriptBlock contained a single command that
                # was not valid. Weird that EAP = 'Stop' doesn't have it through in
                # EndInvoke() but better to check just in case.
                if ($ps.HadErrors -and $ps.Streams.Error[0] -notlike "*The pipeline has been stopped.*") {
                    throw "PowerShell reported an error during execution:"
                }

                foreach ($warn in $ps.Streams.Warning) {
                    $PSCmdlet.WriteWarning($warn)
                }
                foreach ($verbose in $ps.Streams.Verbose) {
                    $PSCmdlet.WriteVerbose($verbose);
                }
                foreach ($debug in $ps.Streams.Debug) {
                    $PSCmdlet.WriteDebug($debug);
                }
                foreach ($info in $ps.Streams.Information) {
                    $PSCmdlet.WriteInformation($info);
                }
            }
            catch {
                $errorDetails = @(
                    if ($stopTask -and $stopTask.IsCompleted) {
                        try {
                            $ps.EndStop($stopTask)
                        }
                        catch {
                            "StopException: $_"
                        }
                    }

                    if ($beginTask -and $beginTask.IsCompleted) {
                        try {
                            $ps.EndInvoke($beginTask)
                        }
                        catch {
                            $msg = if ($_.Exception.InnerException) {
                                $_.Exception.InnerException
                            }
                            else {
                                $_
                            }
                            "TaskException: $msg"
                        }
                    }

                    if ($ps -and $ps.Streams.Error.Count -gt 0) {
                        "PowerShell had $($ps.Streams.Error.Count) error(s) in the stream:"

                        foreach ($err in $ps.Streams.Error) {
                            [string]$err
                            $err.ScriptStackTrace
                        }
                    }
                )

                [string]$msg = $_
                if ($errorDetails) {
                    $msg += "`nErrorDetails:`n$($errorDetails -join "`n")"
                }

                $err = [ErrorRecord]::new(
                    [Exception]::new($msg, $_.Exception),
                    "PowerShellExecutionFailed",
                    [ErrorCategory]::NotSpecified,
                    $null)

                $PSCmdlet.ThrowTerminatingError($err)
            }
            finally {
                ${startEvent}?.Dispose()
                ${ps}?.Dispose()
            }
        }
    }

    It "WriteObject does not await by default" {
        $list = [List[string]]::new()

        $first = $true
        Test-WriteObject -ListTracker $list -ErrorAction Stop | ForEach-Object {
            $_.GetType().FullName | Should -Be "System.String"
            if ($first)
            {
                $_ | Should -Be foo
                $first = $false
            }
            else
            {
                $_ | Should -Be bar
            }

            Start-Sleep -Seconds 1
            $list.Add($_)
        }
    }

    It "WriteObject with no enumeration should not await by default" {
        $list = [List[string]]::new()

        Test-WriteObject -ListTracker $list -NoEnumerate -ErrorAction Stop | ForEach-Object {
            $_.GetType().FullName | Should -Be "System.String[]"
            $_.Count | Should -Be 2
            $_[0] | Should -Be foo
            $_[1] | Should -Be bar

            Start-Sleep -Seconds 1
            $list.Add($_)
        }
    }

    It "WriteObjectAsync should await the downstream pipeline" {
        $list = [List[string]]::new()

        $first = $true
        Test-WriteObject -ListTracker $list -WriteAsync -ErrorAction Stop | ForEach-Object {
            $_.GetType().FullName | Should -Be "System.String"
            if ($first)
            {
                $_ | Should -Be foo
                $first = $false
            }
            else
            {
                $_ | Should -Be bar
            }

            Start-Sleep -Seconds 1
            $list.Add($_)
        }
    }

    It "WriteObjectAsync with no enumeration should await the downstream pipeline" {
        $list = [List[string]]::new()

        Test-WriteObject -ListTracker $list -WriteAsync -NoEnumerate -ErrorAction Stop | ForEach-Object {
            $_.GetType().FullName | Should -Be "System.String[]"
            $_.Count | Should -Be 2
            $_[0] | Should -Be foo
            $_[1] | Should -Be bar

            Start-Sleep -Seconds 1
            $list.Add($_)
        }
    }

    It "Can stop WriteObjectAsync" {
        Wait-PowerShellWithTimeout -Timeout 10 -ScriptBlock {
            param ($WaitEvent)

            Test-WriteObject -ListTracker @() -WriteAsync | ForEach-Object {
                $WaitEvent.Set()

                Start-Sleep -Seconds 10
                throw "Should not be reached"
            }
        } -StopOnStartup
    }

    It "ShouldProcess returns true without -WhatIf" {
        $testHost = [TestHost]::new($Host, [TestHostUserInterface]::new($Host.UI))

        $res = Wait-PowerShellWithTimeout -Timeout 10 -ScriptBlock {
            Test-ShouldProcess
        } -PSHost $testHost

        $res | Should -BeTrue
        $testHost.UI.HostLines | Should -HaveCount 0
    }

    It "ShouldProcess returns false with -WhatIf" {
        $testHost = [TestHost]::new($Host, [TestHostUserInterface]::new($Host.UI))

        $res = Wait-PowerShellWithTimeout -Timeout 10 -ScriptBlock {
            Test-ShouldProcess -WhatIf
        } -PSHost $testHost

        $res | Should -BeFalse
        $testHost.UI.HostLines | Should -HaveCount 1
        $testHost.UI.HostLines[0] | Should -Be "What if: Performing the operation `"action`" on target `"target`".`n"
    }

    It "ShouldProcess propagates exceptions" {
        $testHost = [TestHost]::new($Host, [TestHostUserInterface]::new($Host.UI, $true))

        $err = {
            Wait-PowerShellWithTimeout -Timeout 10 -ScriptBlock {
                Test-ShouldProcess -WhatIf
            } -PSHost $testHost
        } | Should -Throw -PassThru

        [string]$err | Should -BeLike "PowerShell reported an error during execution:*"
        [string]$err | Should -BeLike "*Line was blocked: What if: Performing the operation `"action`" on target `"target`".*"
    }

    It "Should write error record" {
        $ErrorActionPreference = 'Continue'

        $out = $null
        $actual = . { Test-WriteStream -ErrorMessage "This is error" | Set-Variable -Name out } 2>&1

        $out | Should -BeNullOrEmpty
        $actual | Should -HaveCount 1
        $actual[0].ToString() | Should -Be "This is error"
    }

    It "Should write warning record" {
        $WarningPreference = 'Continue'

        $out = $null
        $actual = . { Test-WriteStream -WarningMessage "This is warning" | Set-Variable -Name out } 3>&1

        $out | Should -BeNullOrEmpty
        $actual | Should -HaveCount 1
        $actual[0].ToString() | Should -Be "This is warning"
    }

    It "Should write verbose record" {
        $VerbosePreference = 'Continue'

        $out = $null
        $actual = . { Test-WriteStream -VerboseMessage "This is verbose" | Set-Variable -Name out } 4>&1

        $out | Should -BeNullOrEmpty
        $actual | Should -HaveCount 1
        $actual[0].ToString() | Should -Be "This is verbose"
    }

    It "Should write debug record" {
        $DebugPreference = 'Continue'

        $out = $null
        $actual = . { Test-WriteStream -DebugMessage "This is debug" | Set-Variable -Name out } 5>&1

        $out | Should -BeNullOrEmpty
        $actual | Should -HaveCount 1
        $actual[0].ToString() | Should -Be "This is debug"
    }

    It "Should write information record" {
        $InformationPreference = 'Continue'

        $out = $null
        $actual = . { Test-WriteStream -InformationMessage "This is information" | Set-Variable -Name out } 6>&1

        $out | Should -BeNullOrEmpty
        $actual | Should -HaveCount 1
        $actual[0].ToString() | Should -Be "This is information"
        $actual.Tags | Should -HaveCount 1
        $actual.Tags[0] | Should -Be "TestTag"
        $actual.Source | Should -Be $PSCommandPath
    }

    It "Should write information record as object" {
        $InformationPreference = 'Continue'

        $out = $null
        $actual = . {
            Test-WriteStream -InformationMessage "This is information" -InformationAsObject | Set-Variable -Name out
        } 6>&1

        $out | Should -BeNullOrEmpty
        $actual | Should -HaveCount 1
        $actual[0].ToString() | Should -Be "This is information"
        $actual.Tags | Should -BeNullOrEmpty
        $actual.Source | Should -Be "TestInformation"
    }

    It "Should write host record with -HostNoNewLine:<NewLine>" -TestCases @(
        @{ NewLine = $false }
        @{ NewLine = $true }
    ) {
        param ($NewLine)

        $out = $null
        $actual = . {
            Test-WriteStream -HostMessage "This is host message" -HostNoNewLine:$NewLine | Set-Variable -Name out
        } 6>&1

        $out | Should -BeNullOrEmpty
        $actual | Should -HaveCount 1
        $actual[0].ToString() | Should -Be "This is host message"
        $actual[0].MessageData | Should -BeOfType ([HostInformationMessage])
        $actual[0].MessageData.Message | Should -Be "This is host message"
        $actual[0].MessageData.NoNewLine | Should -Be $NewLine
        $actual.Tags | Should -HaveCount 1
        $actual.Tags[0] | Should -Be "PSHOST"
    }

    It "Should write progress record" {
        $testHost = [TestHost]::new($Host, [TestHostUserInterface]::new($Host.UI))

        $res = Wait-PowerShellWithTimeout -Timeout 10 -ScriptBlock {
            Test-WriteStream -Progress ([ProgressRecord]::new(1, "Test Activity", "Test Status"))
        } -PSHost $testHost

        $testHost.UI.HostLines | Should -HaveCount 1
        $testHost.UI.HostLines[0] | Should -Be "PROGRESS: 1 - Test Activity - Test Status`n"

        $res | Should -BeNullOrEmpty
    }

    It "InvokesScriptAsync with no arguments" {
        $res = Test-InvokeScript -ScriptBlock { 1 }
        $res | Should -Be 1
    }

    It "InvokesScriptAsync with arguments" {
        $res = Test-InvokeScript -ScriptBlock { param($a, $b) $a + $b } -ArgumentList 2, 3
        $res | Should -Be 5
    }

    It "Casts InvokeScriptAsync results to expected type" {
        $res = Test-InvokeScript -ScriptBlock { '1' }
        $res | Should -Be 1
    }

    It "Casts nullable results to null <ScriptBlock>" -TestCases @(
        @{ ScriptBlock = { $null } }
        @{ ScriptBlock = { } }
    ) {
        param ($ScriptBlock)

        $res = Test-InvokeScript -ScriptBlock $ScriptBlock
        $null -eq $res | Should -BeTrue
    }

    It "Propagates streams from InvokeScriptAsync" {
        $testHost = [TestHost]::new($Host, [TestHostUserInterface]::new($Host.UI))

        # Stops it from being written to the PSHost as Wait-PowerShellWithTimeout
        # writes out the streams after execution.
        $WarningPreference = 'Ignore'
        $InformationPreference = 'Ignore'

        Wait-PowerShellWithTimeout -Timeout 10 -ScriptBlock {
            $WarningPreference = 'Continue'
            $VerbosePreference = 'Continue'
            $DebugPreference = 'Continue'
            $InformationPreference = 'Continue'

            Test-InvokeScript -ScriptBlock {
                Write-Warning "Test warning"
                Write-Verbose "Test verbose"
                Write-Debug "Test debug"
                Write-Information "Test information"
                Write-Host "Test host message"
                Write-Progress -Id 1 -Activity "Test Activity" -Status "Test Status"
            }
        } -PSHost $testHost -ErrorVariable err

        $testHost.UI.HostLines | Should -HaveCount 6
        $testHost.UI.HostLines[0] | Should -Be "WARNING: Test warning`n"
        $testHost.UI.HostLines[1] | Should -Be "VERBOSE: Test verbose`n"
        $testHost.UI.HostLines[2] | Should -Be "DEBUG: Test debug`n"
        $testHost.UI.HostLines[3] | Should -Be "Test information`n"
        $testHost.UI.HostLines[4] | Should -Be "-1 - -1 - Test host message`n"
        $testHost.UI.HostLines[5] | Should -Be "PROGRESS: 0 - Test Activity - Test Status`n"
    }

    It "Propagates exceptions from InvokeScriptAsync" {
        $err = { Test-InvokeScript -ScriptBlock { throw "Test exception" } } | Should -Throw -PassThru
        [string]$err | Should -BeLike "Test exception"
    }

    It "Cancels InvokeScriptAsync" {
        Wait-PowerShellWithTimeout -Timeout 5 -ScriptBlock {
            param ($WaitEvent)

            $WaitEvent.Set()
            Start-Sleep -Seconds 10
        } -StopOnStartup
    }

    It "Works with begin/process/end blocks" {
        $blockTest = {
            param (
                [Parameter(Mandatory)]
                [string]
                $Marker,

                [Parameter(ValueFromPipeline)]
                [string[]]
                $InputObject
            )

            begin {
                Write-Host "Begin $Marker"
            }
            process {
                Write-Host "Process $Marker"
                $input
            }
            end {
                Write-Host "End $Marker"
            }
        }
        $res = & {
            $null = 1 | & $blockTest -Marker first | Test-CmdletBlocks | & $blockTest -Marker last
        } 6>&1

        $res | Should -HaveCount 9
        $res[0] | Should -Be "Begin first"
        $res[1] | Should -Be "BeginProcessing"
        $res[2] | Should -Be "Begin last"
        $res[3] | Should -Be "Process first"
        $res[4] | Should -Be "ProcessRecord"
        $res[5] | Should -Be "Process last"
        $res[6] | Should -Be "End first"
        $Res[7] | Should -Be "EndProcessing"
        $res[8] | Should -Be "End last"
    }

    It "Handles broken pipeline in still running async task" {
        $state = @{}
        Wait-PowerShellWithTimeout -Timeout 10 -ScriptBlock {
            param ($WaitEvent, $State)

            Test-WriteWhenStopped -State $State -WaitEvent $WaitEvent
        } -StopOnStartup -State $state

        $state.WasCancelled | Should -BeTrue
        $state.WriteObjectThrew | Should -BeTrue
    }

    It "Can dispose AsyncPSCmdlet twice" {
        $cmdlet = [TestAsyncCmdlet.TestWriteObject]::new()
        $cmdlet.Dispose()
        # This should not throw an exception
        $cmdlet.Dispose()
    }
}
