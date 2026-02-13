using namespace System.Collections

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]
    $CustomPipeName,

    [Parameter(Mandatory)]
    [int]
    $RunspaceId,

    [Parameter(Mandatory)]
    [string]
    $Name,

    [Parameter(Mandatory)]
    [IDictionary[]]
    $PathMapping
)

$ErrorActionPreference = 'Stop'

Start-DebugAttachSession @PSBoundParameters -WindowActionOnEnd Hide
