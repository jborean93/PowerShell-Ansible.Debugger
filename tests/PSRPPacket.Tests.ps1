using namespace System.Buffers.Binary
using namespace System.IO
using namespace System.Text

. ([Path]::Combine($PSScriptRoot, 'common.ps1'))

Function global:Get-PSRPPacket {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Ansible.Debugger.PSRPDestination]
        $Destination,

        [Parameter(Mandatory)]
        [Ansible.Debugger.PSRPMessageType]
        $MessageType,

        [Parameter(Mandatory)]
        [string]
        $Data
    )

    $dataBytes = [Encoding]::UTF8.GetBytes($Data)
    $msgBytes = [byte[]]::new(21 + 40 + $dataBytes.Length)

    # Fragment
    [BinaryPrimitives]::WriteInt64BigEndian(
        [ArraySegment[byte]]::new($msgBytes, 0, 8),
        1)  # ObjectId
    [BinaryPrimitives]::WriteInt64BigEndian(
        [ArraySegment[byte]]::new($msgBytes, 8, 8),
        0)  # FragmentId
    $msgBytes[16] = 3  # Start + End
    [BinaryPrimitives]::WriteInt32BigEndian(
        [ArraySegment[byte]]::new($msgBytes, 17, 4),
        (40 + $dataBytes.Length))

    # Message
    [BinaryPrimitives]::WriteInt32LittleEndian(
        [ArraySegment[byte]]::new($msgBytes, 21, 4),
        $Destination)
    [BinaryPrimitives]::WriteInt32LittleEndian(
        [ArraySegment[byte]]::new($msgBytes, 25, 4),
        $MessageType)
    # RPID and PID in the mock packet are all zeros so we can skip
    # writing them since the buffer is initialized to zeroes
    [Array]::Copy($dataBytes, 0, $msgBytes, 61, $dataBytes.Length)

    "<Data Stream='Default' PSGuid='00000000-0000-0000-0000-000000000000'>$([Convert]::ToBase64String($msgBytes))</Data>"
}

Describe "ConvertTo-PSRPPacket" {
    It "Parses packet with single message" {
        $packet = "<Data Stream='Default' PSGuid='6e6e7727-08b7-4440-855f-6e417c17511c'>AAAAAAAAAAQAAAAAAAAAAAMAAABnAQAAAAYQBACvXvqm+i4+S4Bve+JSo5vpJ3dubrcIQESFX25BfBdRHO+7vzxPYmogUmVmSWQ9IjAiPjxNUz48STMyIE49IlBpcGVsaW5lU3RhdGUiPjQ8L0kzMj48L01TPjwvT2JqPg==</Data>" |
            ConvertTo-PSRPPacket

        $packet.Type | Should -Be Data
        $packet.PSGuid | Should -Be "6e6e7727-08b7-4440-855f-6e417c17511c"
        $packet.Stream | Should -Be "Default"

        $packet.Fragments | Should -HaveCount 1
        $packet.Fragments[0].ObjectId | Should -Be 4
        $packet.Fragments[0].FragmentId | Should -Be 0
        $packet.Fragments[0].Start | Should -BeTrue
        $packet.Fragments[0].End | Should -BeTrue

        $packet.Messages | Should -HaveCount 1
        $packet.Messages[0].Destination | Should -Be Client
        $packet.Messages[0].MessageType | Should -Be PipelineState
        $packet.Messages[0].RunspacePoolId | Should -Be "a6fa5eaf-2efa-4b3e-806f-7be252a39be9"
        $packet.Messages[0].PipelineId | Should -Be "6e6e7727-08b7-4440-855f-6e417c17511c"
        $packet.Messages[0].Data | Should -BeLike '<Obj RefId="0">*'

        $packet.Raw | Should -BeLike "<Data Stream='Default' PSGuid='6e6e7727-08b7-4440-855f-6e417c17511c'>*</Data>"
    }

    It "Parses packet with multiple messages" {
        $packet = "<Data Stream='Default' PSGuid='00000000-0000-0000-0000-000000000000'>AAAAAAAAAAEAAAAAAAAAAAMAAADKAgAAAAIAAQCvXvqm+i4+S4Bve+JSo5vpAAAAAAAAAAAAAAAAAAAAAO+7vzxPYmogUmVmSWQ9IjAiPjxNUz48VmVyc2lvbiBOPSJwcm90b2NvbHZlcnNpb24iPjIuMzwvVmVyc2lvbj48VmVyc2lvbiBOPSJQU1ZlcnNpb24iPjIuMDwvVmVyc2lvbj48VmVyc2lvbiBOPSJTZXJpYWxpemF0aW9uVmVyc2lvbiI+MS4xLjAuMTwvVmVyc2lvbj48L01TPjwvT2JqPgAAAAAAAAACAAAAAAAAAAADAAAO4AIAAAAEAAEAr176pvouPkuAb3viUqOb6QAAAAAAAAAAAAAAAAAAAADvu788T2JqIFJlZklkPSIwIj48TVM+PEkzMiBOPSJNaW5SdW5zcGFjZXMiPjE8L0kzMj48STMyIE49Ik1heFJ1bnNwYWNlcyI+MTwvSTMyPjxPYmogTj0iUFNUaHJlYWRPcHRpb25zIiBSZWZJZD0iMSI+PFROIFJlZklkPSIwIj48VD5TeXN0ZW0uTWFuYWdlbWVudC5BdXRvbWF0aW9uLlJ1bnNwYWNlcy5QU1RocmVhZE9wdGlvbnM8L1Q+PFQ+U3lzdGVtLkVudW08L1Q+PFQ+U3lzdGVtLlZhbHVlVHlwZTwvVD48VD5TeXN0ZW0uT2JqZWN0PC9UPjwvVE4+PFRvU3RyaW5nPkRlZmF1bHQ8L1RvU3RyaW5nPjxJMzI+MDwvSTMyPjwvT2JqPjxPYmogTj0iQXBhcnRtZW50U3RhdGUiIFJlZklkPSIyIj48VE4gUmVmSWQ9IjEiPjxUPlN5c3RlbS5UaHJlYWRpbmcuQXBhcnRtZW50U3RhdGU8L1Q+PFQ+U3lzdGVtLkVudW08L1Q+PFQ+U3lzdGVtLlZhbHVlVHlwZTwvVD48VD5TeXN0ZW0uT2JqZWN0PC9UPjwvVE4+PFRvU3RyaW5nPlVua25vd248L1RvU3RyaW5nPjxJMzI+MjwvSTMyPjwvT2JqPjxPYmogTj0iQXBwbGljYXRpb25Bcmd1bWVudHMiIFJlZklkPSIzIj48VE4gUmVmSWQ9IjIiPjxUPlN5c3RlbS5NYW5hZ2VtZW50LkF1dG9tYXRpb24uUFNQcmltaXRpdmVEaWN0aW9uYXJ5PC9UPjxUPlN5c3RlbS5Db2xsZWN0aW9ucy5IYXNodGFibGU8L1Q+PFQ+U3lzdGVtLk9iamVjdDwvVD48L1ROPjxEQ1Q+PEVuPjxTIE49IktleSI+UFNWZXJzaW9uVGFibGU8L1M+PE9iaiBOPSJWYWx1ZSIgUmVmSWQ9IjQiPjxUTlJlZiBSZWZJZD0iMiIgLz48RENUPjxFbj48UyBOPSJLZXkiPk9TPC9TPjxTIE49IlZhbHVlIj5GZWRvcmEgTGludXggNDMgKFNlcnZlciBFZGl0aW9uKTwvUz48L0VuPjxFbj48UyBOPSJLZXkiPkdpdENvbW1pdElkPC9TPjxTIE49IlZhbHVlIj43LjUuMTwvUz48L0VuPjxFbj48UyBOPSJLZXkiPlBTVmVyc2lvbjwvUz48VmVyc2lvbiBOPSJWYWx1ZSI+Ny41LjE8L1ZlcnNpb24+PC9Fbj48RW4+PFMgTj0iS2V5Ij5QU1JlbW90aW5nUHJvdG9jb2xWZXJzaW9uPC9TPjxWZXJzaW9uIE49IlZhbHVlIj4yLjM8L1ZlcnNpb24+PC9Fbj48RW4+PFMgTj0iS2V5Ij5TZXJpYWxpemF0aW9uVmVyc2lvbjwvUz48VmVyc2lvbiBOPSJWYWx1ZSI+MS4xLjAuMTwvVmVyc2lvbj48L0VuPjxFbj48UyBOPSJLZXkiPldTTWFuU3RhY2tWZXJzaW9uPC9TPjxWZXJzaW9uIE49IlZhbHVlIj4zLjA8L1ZlcnNpb24+PC9Fbj48RW4+PFMgTj0iS2V5Ij5QU0VkaXRpb248L1M+PFMgTj0iVmFsdWUiPkNvcmU8L1M+PC9Fbj48RW4+PFMgTj0iS2V5Ij5QU0NvbXBhdGlibGVWZXJzaW9uczwvUz48T2JqIE49IlZhbHVlIiBSZWZJZD0iNSI+PFROIFJlZklkPSIzIj48VD5TeXN0ZW0uVmVyc2lvbltdPC9UPjxUPlN5c3RlbS5BcnJheTwvVD48VD5TeXN0ZW0uT2JqZWN0PC9UPjwvVE4+PExTVD48VmVyc2lvbj4xLjA8L1ZlcnNpb24+PFZlcnNpb24+Mi4wPC9WZXJzaW9uPjxWZXJzaW9uPjMuMDwvVmVyc2lvbj48VmVyc2lvbj40LjA8L1ZlcnNpb24+PFZlcnNpb24+NS4wPC9WZXJzaW9uPjxWZXJzaW9uPjUuMTwvVmVyc2lvbj48VmVyc2lvbj42LjA8L1ZlcnNpb24+PFZlcnNpb24+Ny4wPC9WZXJzaW9uPjwvTFNUPjwvT2JqPjwvRW4+PEVuPjxTIE49IktleSI+UFNTZW1hbnRpY1ZlcnNpb248L1M+PFMgTj0iVmFsdWUiPjcuNS4xPC9TPjwvRW4+PEVuPjxTIE49IktleSI+UGxhdGZvcm08L1M+PFMgTj0iVmFsdWUiPlVuaXg8L1M+PC9Fbj48L0RDVD48L09iaj48L0VuPjwvRENUPjwvT2JqPjxPYmogTj0iSG9zdEluZm8iIFJlZklkPSI2Ij48TVM+PEIgTj0iX2lzSG9zdFVJTnVsbCI+ZmFsc2U8L0I+PEIgTj0iX2lzSG9zdFJhd1VJTnVsbCI+ZmFsc2U8L0I+PEIgTj0iX2lzSG9zdE51bGwiPmZhbHNlPC9CPjxPYmogTj0iX2hvc3REZWZhdWx0RGF0YSIgUmVmSWQ9IjciPjxNUz48T2JqIE49ImRhdGEiIFJlZklkPSI4Ij48VE4gUmVmSWQ9IjQiPjxUPlN5c3RlbS5Db2xsZWN0aW9ucy5IYXNodGFibGU8L1Q+PFQ+U3lzdGVtLk9iamVjdDwvVD48L1ROPjxEQ1Q+PEVuPjxJMzIgTj0iS2V5Ij45PC9JMzI+PE9iaiBOPSJWYWx1ZSIgUmVmSWQ9IjkiPjxNUz48UyBOPSJUIj5TeXN0ZW0uU3RyaW5nPC9TPjxTIE49IlYiPjwvUz48L01TPjwvT2JqPjwvRW4+PEVuPjxJMzIgTj0iS2V5Ij44PC9JMzI+PE9iaiBOPSJWYWx1ZSIgUmVmSWQ9IjEwIj48TVM+PFMgTj0iVCI+U3lzdGVtLk1hbmFnZW1lbnQuQXV0b21hdGlvbi5Ib3N0LlNpemU8L1M+PE9iaiBOPSJWIiBSZWZJZD0iMTEiPjxNUz48STMyIE49IndpZHRoIj4xNTY8L0kzMj48STMyIE49ImhlaWdodCI+MTc8L0kzMj48L01TPjwvT2JqPjwvTVM+PC9PYmo+PC9Fbj48RW4+PEkzMiBOPSJLZXkiPjc8L0kzMj48T2JqIE49IlZhbHVlIiBSZWZJZD0iMTIiPjxNUz48UyBOPSJUIj5TeXN0ZW0uTWFuYWdlbWVudC5BdXRvbWF0aW9uLkhvc3QuU2l6ZTwvUz48T2JqIE49IlYiIFJlZklkPSIxMyI+PE1TPjxJMzIgTj0id2lkdGgiPjE1NjwvSTMyPjxJMzIgTj0iaGVpZ2h0Ij4xNzwvSTMyPjwvTVM+PC9PYmo+PC9NUz48L09iaj48L0VuPjxFbj48STMyIE49IktleSI+NjwvSTMyPjxPYmogTj0iVmFsdWUiIFJlZklkPSIxNCI+PE1TPjxTIE49IlQiPlN5c3RlbS5NYW5hZ2VtZW50LkF1dG9tYXRpb24uSG9zdC5TaXplPC9TPjxPYmogTj0iViIgUmVmSWQ9IjE1Ij48TVM+PEkzMiBOPSJ3aWR0aCI+MTU2PC9JMzI+PEkzMiBOPSJoZWlnaHQiPjE3PC9JMzI+PC9NUz48L09iaj48L01TPjwvT2JqPjwvRW4+PEVuPjxJMzIgTj0iS2V5Ij41PC9JMzI+PE9iaiBOPSJWYWx1ZSIgUmVmSWQ9IjE2Ij48TVM+PFMgTj0iVCI+U3lzdGVtLk1hbmFnZW1lbnQuQXV0b21hdGlvbi5Ib3N0LlNpemU8L1M+PE9iaiBOPSJWIiBSZWZJZD0iMTciPjxNUz48STMyIE49IndpZHRoIj4xNTY8L0kzMj48STMyIE49ImhlaWdodCI+MTc8L0kzMj48L01TPjwvT2JqPjwvTVM+PC9PYmo+PC9Fbj48RW4+PEkzMiBOPSJLZXkiPjQ8L0kzMj48T2JqIE49IlZhbHVlIiBSZWZJZD0iMTgiPjxNUz48UyBOPSJUIj5TeXN0ZW0uSW50MzI8L1M+PEkzMiBOPSJWIj4xMDA8L0kzMj48L01TPjwvT2JqPjwvRW4+PEVuPjxJMzIgTj0iS2V5Ij4zPC9JMzI+PE9iaiBOPSJWYWx1ZSIgUmVmSWQ9IjE5Ij48TVM+PFMgTj0iVCI+U3lzdGVtLk1hbmFnZW1lbnQuQXV0b21hdGlvbi5Ib3N0LkNvb3JkaW5hdGVzPC9TPjxPYmogTj0iViIgUmVmSWQ9IjIwIj48TVM+PEkzMiBOPSJ4Ij4wPC9JMzI+PEkzMiBOPSJ5Ij4wPC9JMzI+PC9NUz48L09iaj48L01TPjwvT2JqPjwvRW4+PEVuPjxJMzIgTj0iS2V5Ij4yPC9JMzI+PE9iaiBOPSJWYWx1ZSIgUmVmSWQ9IjIxIj48TVM+PFMgTj0iVCI+U3lzdGVtLk1hbmFnZW1lbnQuQXV0b21hdGlvbi5Ib3N0LkNvb3JkaW5hdGVzPC9TPjxPYmogTj0iViIgUmVmSWQ9IjIyIj48TVM+PEkzMiBOPSJ4Ij4wPC9JMzI+PEkzMiBOPSJ5Ij4xPC9JMzI+PC9NUz48L09iaj48L01TPjwvT2JqPjwvRW4+PEVuPjxJMzIgTj0iS2V5Ij4xPC9JMzI+PE9iaiBOPSJWYWx1ZSIgUmVmSWQ9IjIzIj48TVM+PFMgTj0iVCI+U3lzdGVtLkNvbnNvbGVDb2xvcjwvUz48STMyIE49IlYiPi0xPC9JMzI+PC9NUz48L09iaj48L0VuPjxFbj48STMyIE49IktleSI+MDwvSTMyPjxPYmogTj0iVmFsdWUiIFJlZklkPSIyNCI+PE1TPjxTIE49IlQiPlN5c3RlbS5Db25zb2xlQ29sb3I8L1M+PEkzMiBOPSJWIj4tMTwvSTMyPjwvTVM+PC9PYmo+PC9Fbj48L0RDVD48L09iaj48L01TPjwvT2JqPjxCIE49Il91c2VSdW5zcGFjZUhvc3QiPmZhbHNlPC9CPjwvTVM+PC9PYmo+PC9NUz48L09iaj4=</Data>" |
            ConvertTo-PSRPPacket

        $packet.Type | Should -Be Data
        $packet.PSGuid | Should -Be "00000000-0000-0000-0000-000000000000"
        $packet.Stream | Should -Be "Default"

        $packet.Fragments | Should -HaveCount 2
        $packet.Fragments[0].ObjectId | Should -Be 1
        $packet.Fragments[0].FragmentId | Should -Be 0
        $packet.Fragments[0].Start | Should -BeTrue
        $packet.Fragments[0].End | Should -BeTrue

        $packet.Fragments[1].ObjectId | Should -Be 2
        $packet.Fragments[1].FragmentId | Should -Be 0
        $packet.Fragments[1].Start | Should -BeTrue
        $packet.Fragments[1].End | Should -BeTrue

        $packet.Messages | Should -HaveCount 2
        $packet.Messages[0].Destination | Should -Be Server
        $packet.Messages[0].MessageType | Should -Be SessionCapability
        $packet.Messages[0].RunspacePoolId | Should -Be a6fa5eaf-2efa-4b3e-806f-7be252a39be9
        $packet.Messages[0].PipelineId | Should -Be "00000000-0000-0000-0000-000000000000"
        $packet.Messages[0].Data | Should -BeLike '<Obj RefId="0">*'

        $packet.Messages[1].Destination | Should -Be Server
        $packet.Messages[1].MessageType | Should -Be InitRunspacePool
        $packet.Messages[1].RunspacePoolId | Should -Be a6fa5eaf-2efa-4b3e-806f-7be252a39be9
        $packet.Messages[1].PipelineId | Should -Be "00000000-0000-0000-0000-000000000000"
        $packet.Messages[1].Data | Should -BeLike '<Obj RefId="0">*'

        $packet.Raw | Should -BeLike "<Data Stream='Default' PSGuid='00000000-0000-0000-0000-000000000000'>*</Data>"
    }

    It "Parses packets across multiple fragments" {
        # Produced by running ('a' * 65KB) in a pipeline
        $packets = Get-Content -LiteralPath ([Path]::Combine($PSScriptRoot, 'data', 'large-psrp-packet.txt')) | ConvertTo-PSRPPacket

        $packets | Should -HaveCount 3
        $packets[0].Type | Should -Be Data
        $packets[0].PSGuid | Should -Be c8cf479a-daf8-4b7c-872c-95a22e6d344f
        $packets[0].Stream | Should -Be Default
        $packets[0].Fragments | Should -HaveCount 1
        $packets[0].Fragments[0].ObjectId | Should -Be 327
        $packets[0].Fragments[0].FragmentId | Should -Be 0
        $packets[0].Fragments[0].Start | Should -BeTrue
        $packets[0].Fragments[0].End | Should -BeFalse
        $packets[0].Messages | Should -HaveCount 0

        $packets[1].Type | Should -Be Data
        $packets[1].PSGuid | Should -Be c8cf479a-daf8-4b7c-872c-95a22e6d344f
        $packets[1].Stream | Should -Be Default
        $packets[1].Fragments | Should -HaveCount 1
        $packets[1].Fragments[0].ObjectId | Should -Be 327
        $packets[1].Fragments[0].FragmentId | Should -Be 1
        $packets[1].Fragments[0].Start | Should -BeFalse
        $packets[1].Fragments[0].End | Should -BeFalse
        $packets[1].Messages | Should -HaveCount 0

        $packets[2].Type | Should -Be Data
        $packets[2].PSGuid | Should -Be c8cf479a-daf8-4b7c-872c-95a22e6d344f
        $packets[2].Stream | Should -Be Default
        $packets[2].Fragments | Should -HaveCount 1
        $packets[2].Fragments[0].ObjectId | Should -Be 327
        $packets[2].Fragments[0].FragmentId | Should -Be 2
        $packets[2].Fragments[0].Start | Should -BeFalse
        $packets[2].Fragments[0].End | Should -BeTrue
        $packets[2].Messages | Should -HaveCount 1
        $packets[2].Messages[0].Destination | Should -Be Client
        $packets[2].Messages[0].MessageType | Should -Be PipelineOutput
        $packets[2].Messages[0].RunspacePoolId | Should -Be 0f3f9c78-7ad4-4615-ac8d-72cbc42e225d
        $packets[2].Messages[0].PipelineId | Should -Be c8cf479a-daf8-4b7c-872c-95a22e6d344f
        $packets[2].Messages[0].Data | Should -BeLike "<S>a*</S>"
        $packets[2].Messages[0].Data.Length | Should -Be 66567  # 65KB of 'a' plus the XML wrapper
    }

    It "Ignores whitespace only lines" {
        $packet = '', "<DataAck Stream='Default' PSGuid='00000000-0000-0000-0000-000000000000' />", ' ' | ConvertTo-PSRPPacket
        $packet | Should -HaveCount 1

        $packet.Type | Should -Be DataAck
        $packet.PSGuid | Should -Be 00000000-0000-0000-0000-000000000000
        $packet.Stream | Should -Be Default
        $packet.Fragments | Should -HaveCount 0
        $packet.Messages | Should -HaveCount 0
        $packet.Raw | Should -Be "<DataAck Stream='Default' PSGuid='00000000-0000-0000-0000-000000000000' />"
    }

    It "Missing Stream value" {
        $packet = "<DataAck PSGuid='00000000-0000-0000-0000-000000000000' />" | ConvertTo-PSRPPacket
        $packet | Should -HaveCount 1

        $packet.Type | Should -Be DataAck
        $packet.PSGuid | Should -Be 00000000-0000-0000-0000-000000000000
        $packet.Stream | Should -BeNullOrEmpty
        $packet.Fragments | Should -HaveCount 0
        $packet.Messages | Should -HaveCount 0
        $packet.Raw | Should -Be "<DataAck PSGuid='00000000-0000-0000-0000-000000000000' />"
    }

    It "Message data contains UTF-8 BOM" {
        $rawPacket = Get-PSRPPacket -Destination Client -MessageType PipelineOutput -Data "$([char]0xFEFF)<S>a</S>"
        $packet = $rawPacket | ConvertTo-PSRPPacket

        $packet.Type | Should -Be Data
        $packet.PSGuid | Should -Be 00000000-0000-0000-0000-000000000000
        $packet.Stream | Should -Be Default
        $packet.Fragments | Should -HaveCount 1
        $packet.Fragments[0].ObjectId | Should -Be 1
        $packet.Fragments[0].FragmentId | Should -Be 0
        $packet.Fragments[0].Start | Should -BeTrue
        $packet.Fragments[0].End | Should -BeTrue
        $packet.Messages | Should -HaveCount 1
        $packet.Messages[0].Destination | Should -Be Client
        $packet.Messages[0].MessageType | Should -Be PipelineOutput
        $packet.Messages[0].RunspacePoolId | Should -Be 00000000-0000-0000-0000-000000000000
        $packet.Messages[0].PipelineId | Should -Be 00000000-0000-0000-0000-000000000000
        $packet.Messages[0].Data | Should -Be "<S>a</S>"
        $packet.Messages[0].Data.Length | Should -Be 8 # Excludes the 3 byte UTF-8 BOM
    }

    It "Emits error for invalid XML" {
        $err = $null
        $packet = 'invalid', "<DataAck Stream='Default' PSGuid='00000000-0000-0000-0000-000000000000' />" | ConvertTo-PSRPPacket -ErrorAction SilentlyContinue -ErrorVariable err
        $packet | Should -HaveCount 1

        $packet.Type | Should -Be DataAck
        $packet.PSGuid | Should -Be 00000000-0000-0000-0000-000000000000
        $packet.Stream | Should -Be Default
        $packet.Fragments | Should -HaveCount 0
        $packet.Messages | Should -HaveCount 0

        $err | Should -HaveCount 1
        [string]$err[0] | Should -Be "Failed to parse line 'invalid': Data at the root level is invalid. Line 1, position 1."
        $err[0].FullyQualifiedErrorId | Should -Be "ParseError,Ansible.Debugger.Commands.ConvertToPSRPPacketCommand"
        $err[0].CategoryInfo.Category | Should -Be InvalidData
        $err[0].TargetObject | Should -Be 'invalid'
    }

    It "Emits error for missing PSGuid value" {
        $err = $null
        $packet = "<DataAck Stream='Default' />" | ConvertTo-PSRPPacket -ErrorAction SilentlyContinue -ErrorVariable err
        $packet | Should -HaveCount 0

        $err | Should -HaveCount 1
        [string]$err[0] | Should -Match "Failed to parse line '.*': Missing PSGuid attribute"
        $err[0].FullyQualifiedErrorId | Should -Be "ParseError,Ansible.Debugger.Commands.ConvertToPSRPPacketCommand"
        $err[0].CategoryInfo.Category | Should -Be InvalidData
    }

    It "Emits error for invalid PSGuid value" {
        $err = $null
        $packet = "<DataAck Stream='Default' PSGuid='invalid' />" | ConvertTo-PSRPPacket -ErrorAction SilentlyContinue -ErrorVariable err
        $packet | Should -HaveCount 0

        $err | Should -HaveCount 1
        [string]$err[0] | Should -Match "Failed to parse line '.*': Invalid PSGuid value: invalid"
        $err[0].FullyQualifiedErrorId | Should -Be "ParseError,Ansible.Debugger.Commands.ConvertToPSRPPacketCommand"
        $err[0].CategoryInfo.Category | Should -Be InvalidData
    }
}

Describe "Format-PSRPPacket" {
    BeforeAll {
        $common = @{
            NoColor = $true
        }
    }

    It "Formats Data to <Destination> packet with data and color" -TestCases @(
        @{ Destination = 'Client'; Color = $PSStyle.Foreground.BrightYellow }
        @{ Destination = 'Server'; Color = $PSStyle.Foreground.BrightCyan }
    ) {
        param ($Destination, $Color)

        $clixml = @(
            '<Obj RefId="0">'
            '  <MS>'
            '    <I32 N="RunspaceState">3</I32>'
            '  </MS>'
            '</Obj>'
        ) -join ([Environment]::NewLine)
        $packet = Get-PSRPPacket -Destination $Destination -MessageType RunspacePoolState -Data $clixml

        $actual = $packet | ConvertTo-PSRPPacket | Format-PSRPPacket
        $actual | Should -Be (
            @(
                "$Color╔═══ `e[97mData$Color ═══`e[0m"
                "$Color║`e[0m `e[90mPSGuid:`e[0m `e[33m00000000-0000-0000-0000-000000000000`e[0m"
                "$Color║`e[0m `e[90mStream:`e[0m `e[32mDefault`e[0m"
                "$Color╠══`e[0m `e[96mFragments`e[0m"
                "$Color║`e[0m   `e[90mObj=`e[0m1 `e[90mFrag=`e[0m0 `e[90mStart=`e[0mTrue `e[90mEnd=`e[0mTrue"
                "$Color╠══`e[0m `e[96mMessages`e[0m"
                "$Color║`e[0m   `e[90mDestination:`e[0m ${Color}$Destination`e[0m"
                "$Color║`e[0m   `e[90mMessageType:`e[0m `e[34mRunspacePoolState`e[0m"
                "$Color║`e[0m   `e[90mRPID:`e[0m `e[33m00000000-0000-0000-0000-000000000000`e[0m"
                "$Color║`e[0m   `e[90mPID:`e[0m  `e[33m00000000-0000-0000-0000-000000000000`e[0m"
                "$Color║`e[0m   `e[90mData:`e[0m"
                "$Color║`e[0m     `e[90m<`e[35mObj RefId`e[90m=`e[32m`"`e[0m`e[32m0`e[32m`"`e[0m`e[90m>`e[0m"
                "$Color║`e[0m       `e[90m<`e[35mMS`e[90m>`e[0m"
                "$Color║`e[0m         `e[90m<`e[35mI32 N`e[90m=`e[32m`"`e[0m`e[32mRunspaceState`e[32m`"`e[0m`e[90m>`e[0m3`e[90m<`e[35m/I32`e[90m>`e[0m"
                "$Color║`e[0m       `e[90m<`e[35m/MS`e[90m>`e[0m"
                "$Color║`e[0m     `e[90m<`e[35m/Obj`e[90m>`e[0m"
                "$Color║`e[0m   `e[90mState:`e[0m Closed"
                "$Color╚═══`e[0m"
                ""
            ) -join ([Environment]::NewLine)
        )
    }

    It "Formats <Type> packet with no data and color" -TestCases @(
        @{ Type = "Data"; Color = "`e[90m" }
        @{ Type = "DataAck"; Color = "`e[90m" }
        @{ Type = "Command"; Color = "`e[35m" }
        @{ Type = "CommandAck"; Color = "`e[35m" }
        @{ Type = "Signal"; Color = "`e[34m" }
        @{ Type = "SignalAck"; Color = "`e[34m" }
        @{ Type = "Close"; Color = "`e[31m" }
        @{ Type = "CloseAck"; Color = "`e[31m" }
        @{ Type = "Unknown"; Color = "`e[36m" }
    ) {
        param ($Type, $Color)

        $packet = "<$Type Stream='Default' PSGuid='00000000-0000-0000-0000-000000000000' />"

        $actual = $packet | ConvertTo-PSRPPacket | Format-PSRPPacket
        $actual | Should -Be (
            @(
                "$Color╔═══ `e[97m$Type$Color ═══`e[0m"
                "$Color║`e[0m `e[90mPSGuid:`e[0m `e[33m00000000-0000-0000-0000-000000000000`e[0m"
                "$Color║`e[0m `e[90mStream:`e[0m `e[32mDefault`e[0m"
                "$Color╚═══`e[0m"
                ""
            ) -join ([Environment]::NewLine)
        )
    }

    It "Formats packet with RunspacePool state" {
        $packet = "<Data Stream='Default' PSGuid='00000000-0000-0000-0000-000000000000'>AAAAAAAAAVcAAAAAAAAAAAMAAABnAQAAAAUQAgB4nD8P1HoVRqyNcsvELiJdAAAAAAAAAAAAAAAAAAAAAO+7vzxPYmogUmVmSWQ9IjAiPjxNUz48STMyIE49IlJ1bnNwYWNlU3RhdGUiPjM8L0kzMj48L01TPjwvT2JqPg==</Data>"

        $actual = $packet | ConvertTo-PSRPPacket | Format-PSRPPacket @common
        $actual | Should -Be (
            @(
                '╔═══ Data ═══'
                '║ PSGuid: 00000000-0000-0000-0000-000000000000'
                '║ Stream: Default'
                '╠══ Fragments'
                '║   Obj=343 Frag=0 Start=True End=True'
                '╠══ Messages'
                '║   Destination: Client'
                '║   MessageType: RunspacePoolState'
                '║   RPID: 0f3f9c78-7ad4-4615-ac8d-72cbc42e225d'
                '║   PID:  00000000-0000-0000-0000-000000000000'
                '║   Data:'
                '║     <Obj RefId="0">'
                '║       <MS>'
                '║         <I32 N="RunspaceState">3</I32>'
                '║       </MS>'
                '║     </Obj>'
                '║   State: Closed'
                '╚═══'
                ''
            ) -join ([Environment]::NewLine)
        )
    }

    It "Formats packet with PSInvocation state" {
        $packet = "<Data Stream='Default' PSGuid='c8cf479a-daf8-4b7c-872c-95a22e6d344f'>AAAAAAAAAUkAAAAAAAAAAAMAAABnAQAAAAYQBAB4nD8P1HoVRqyNcsvELiJdmkfPyPjafEuHLJWiLm00T++7vzxPYmogUmVmSWQ9IjAiPjxNUz48STMyIE49IlBpcGVsaW5lU3RhdGUiPjQ8L0kzMj48L01TPjwvT2JqPg==</Data>"

        $actual = $packet | ConvertTo-PSRPPacket | Format-PSRPPacket @common
        $actual | Should -Be (
            @(
                '╔═══ Data ═══'
                '║ PSGuid: c8cf479a-daf8-4b7c-872c-95a22e6d344f'
                '║ Stream: Default'
                '╠══ Fragments'
                '║   Obj=329 Frag=0 Start=True End=True'
                '╠══ Messages'
                '║   Destination: Client'
                '║   MessageType: PipelineState'
                '║   RPID: 0f3f9c78-7ad4-4615-ac8d-72cbc42e225d'
                '║   PID:  c8cf479a-daf8-4b7c-872c-95a22e6d344f'
                '║   Data:'
                '║     <Obj RefId="0">'
                '║       <MS>'
                '║         <I32 N="PipelineState">4</I32>'
                '║       </MS>'
                '║     </Obj>'
                '║   State: Completed'
                '╚═══'
                ''
            ) -join ([Environment]::NewLine)
        )
    }

    It "Formats packet with PSInvocation state and error record" {
        $packet = "<Data Stream='Default' PSGuid='9edb7faa-3603-43c6-96a3-4d3e4696b507'>AAAAAAAAAVMAAAAAAAAAAAMAAAhTAQAAAAYQBAB4nD8P1HoVRqyNcsvELiJdqn/bngM2xkOWo00+Rpa1B++7vzxPYmogUmVmSWQ9IjAiPjxNUz48STMyIE49IlBpcGVsaW5lU3RhdGUiPjM8L0kzMj48T2JqIE49IkV4Y2VwdGlvbkFzRXJyb3JSZWNvcmQiIFJlZklkPSIxIj48VE4gUmVmSWQ9IjAiPjxUPlN5c3RlbS5NYW5hZ2VtZW50LkF1dG9tYXRpb24uRXJyb3JSZWNvcmQ8L1Q+PFQ+U3lzdGVtLk9iamVjdDwvVD48L1ROPjxUb1N0cmluZz5UaGUgcGlwZWxpbmUgaGFzIGJlZW4gc3RvcHBlZC48L1RvU3RyaW5nPjxNUz48T2JqIE49IkV4Y2VwdGlvbiIgUmVmSWQ9IjIiPjxUTiBSZWZJZD0iMSI+PFQ+U3lzdGVtLk1hbmFnZW1lbnQuQXV0b21hdGlvbi5QaXBlbGluZVN0b3BwZWRFeGNlcHRpb248L1Q+PFQ+U3lzdGVtLk1hbmFnZW1lbnQuQXV0b21hdGlvbi5SdW50aW1lRXhjZXB0aW9uPC9UPjxUPlN5c3RlbS5TeXN0ZW1FeGNlcHRpb248L1Q+PFQ+U3lzdGVtLkV4Y2VwdGlvbjwvVD48VD5TeXN0ZW0uT2JqZWN0PC9UPjwvVE4+PFRvU3RyaW5nPlN5c3RlbS5NYW5hZ2VtZW50LkF1dG9tYXRpb24uUGlwZWxpbmVTdG9wcGVkRXhjZXB0aW9uOiBUaGUgcGlwZWxpbmUgaGFzIGJlZW4gc3RvcHBlZC5feDAwMERfX3gwMDBBXyAgIGF0IFN5c3RlbS5NYW5hZ2VtZW50LkF1dG9tYXRpb24uUnVuc3BhY2VzLlBpcGVsaW5lU3RvcHBlci5QdXNoKFBpcGVsaW5lUHJvY2Vzc29yIGl0ZW0pX3gwMDBEX194MDAwQV8gICBhdCBTeXN0ZW0uTWFuYWdlbWVudC5BdXRvbWF0aW9uLlJ1bnNwYWNlcy5Mb2NhbFBpcGVsaW5lLkludm9rZUhlbHBlcigpX3gwMDBEX194MDAwQV8gICBhdCBTeXN0ZW0uTWFuYWdlbWVudC5BdXRvbWF0aW9uLlJ1bnNwYWNlcy5Mb2NhbFBpcGVsaW5lLkludm9rZVRocmVhZFByb2MoKTwvVG9TdHJpbmc+PFByb3BzPjxTIE49IkVycm9yUmVjb3JkIj5UaGUgcGlwZWxpbmUgaGFzIGJlZW4gc3RvcHBlZC48L1M+PEIgTj0iV2FzVGhyb3duRnJvbVRocm93U3RhdGVtZW50Ij5mYWxzZTwvQj48UyBOPSJNZXNzYWdlIj5UaGUgcGlwZWxpbmUgaGFzIGJlZW4gc3RvcHBlZC48L1M+PE9iaiBOPSJEYXRhIiBSZWZJZD0iMyI+PFROIFJlZklkPSIyIj48VD5TeXN0ZW0uQ29sbGVjdGlvbnMuTGlzdERpY3Rpb25hcnlJbnRlcm5hbDwvVD48VD5TeXN0ZW0uT2JqZWN0PC9UPjwvVE4+PERDVCAvPjwvT2JqPjxOaWwgTj0iSW5uZXJFeGNlcHRpb24iIC8+PFMgTj0iVGFyZ2V0U2l0ZSI+Vm9pZCBQdXNoKFN5c3RlbS5NYW5hZ2VtZW50LkF1dG9tYXRpb24uSW50ZXJuYWwuUGlwZWxpbmVQcm9jZXNzb3IpPC9TPjxTIE49IlN0YWNrVHJhY2UiPiAgIGF0IFN5c3RlbS5NYW5hZ2VtZW50LkF1dG9tYXRpb24uUnVuc3BhY2VzLlBpcGVsaW5lU3RvcHBlci5QdXNoKFBpcGVsaW5lUHJvY2Vzc29yIGl0ZW0pX3gwMDBEX194MDAwQV8gICBhdCBTeXN0ZW0uTWFuYWdlbWVudC5BdXRvbWF0aW9uLlJ1bnNwYWNlcy5Mb2NhbFBpcGVsaW5lLkludm9rZUhlbHBlcigpX3gwMDBEX194MDAwQV8gICBhdCBTeXN0ZW0uTWFuYWdlbWVudC5BdXRvbWF0aW9uLlJ1bnNwYWNlcy5Mb2NhbFBpcGVsaW5lLkludm9rZVRocmVhZFByb2MoKTwvUz48TmlsIE49IkhlbHBMaW5rIiAvPjxTIE49IlNvdXJjZSI+U3lzdGVtLk1hbmFnZW1lbnQuQXV0b21hdGlvbjwvUz48STMyIE49IkhSZXN1bHQiPi0yMTQ2MjMzMDg3PC9JMzI+PC9Qcm9wcz48L09iaj48TmlsIE49IlRhcmdldE9iamVjdCIgLz48UyBOPSJGdWxseVF1YWxpZmllZEVycm9ySWQiPlBpcGVsaW5lU3RvcHBlZDwvUz48TmlsIE49Ikludm9jYXRpb25JbmZvIiAvPjxJMzIgTj0iRXJyb3JDYXRlZ29yeV9DYXRlZ29yeSI+MTQ8L0kzMj48UyBOPSJFcnJvckNhdGVnb3J5X0FjdGl2aXR5Ij48L1M+PFMgTj0iRXJyb3JDYXRlZ29yeV9SZWFzb24iPlBpcGVsaW5lU3RvcHBlZEV4Y2VwdGlvbjwvUz48UyBOPSJFcnJvckNhdGVnb3J5X1RhcmdldE5hbWUiPjwvUz48UyBOPSJFcnJvckNhdGVnb3J5X1RhcmdldFR5cGUiPjwvUz48UyBOPSJFcnJvckNhdGVnb3J5X01lc3NhZ2UiPk9wZXJhdGlvblN0b3BwZWQ6ICg6KSBbXSwgUGlwZWxpbmVTdG9wcGVkRXhjZXB0aW9uPC9TPjxCIE49IlNlcmlhbGl6ZUV4dGVuZGVkSW5mbyI+ZmFsc2U8L0I+PC9NUz48L09iaj48L01TPjwvT2JqPg==</Data>"

        $actual = $packet | ConvertTo-PSRPPacket | Format-PSRPPacket @common
        $actual | Should -Be (
            @(
                '╔═══ Data ═══'
                '║ PSGuid: 9edb7faa-3603-43c6-96a3-4d3e4696b507'
                '║ Stream: Default'
                '╠══ Fragments'
                '║   Obj=339 Frag=0 Start=True End=True'
                '╠══ Messages'
                '║   Destination: Client'
                '║   MessageType: PipelineState'
                '║   RPID: 0f3f9c78-7ad4-4615-ac8d-72cbc42e225d'
                '║   PID:  9edb7faa-3603-43c6-96a3-4d3e4696b507'
                '║   Data:'
                '║     <Obj RefId="0">'
                '║       <MS>'
                '║         <I32 N="PipelineState">3</I32>'
                '║         <Obj N="ExceptionAsErrorRecord" RefId="1">'
                '║           <TN RefId="0">'
                '║             <T>System.Management.Automation.ErrorRecord</T>'
                '║             <T>System.Object</T>'
                '║           </TN>'
                '║           <ToString>The pipeline has been stopped.</ToString>'
                '║           <MS>'
                '║             <Obj N="Exception" RefId="2">'
                '║               <TN RefId="1">'
                '║                 <T>System.Management.Automation.PipelineStoppedException</T>'
                '║                 <T>System.Management.Automation.RuntimeException</T>'
                '║                 <T>System.SystemException</T>'
                '║                 <T>System.Exception</T>'
                '║                 <T>System.Object</T>'
                '║               </TN>'
                '║               <ToString>System.Management.Automation.PipelineStoppedException: The pipeline has been stopped._x000D__x000A_   at System.Management.Automation.Runspaces.PipelineStopper.Push(PipelineProcessor item)_x000D__x000A_   at System.Management.Automation.Runspaces.LocalPipeline.InvokeHelper()_x000D__x000A_   at System.Management.Automation.Runspaces.LocalPipeline.InvokeThreadProc()</ToString>'
                '║               <Props>'
                '║                 <S N="ErrorRecord">The pipeline has been stopped.</S>'
                '║                 <B N="WasThrownFromThrowStatement">false</B>'
                '║                 <S N="Message">The pipeline has been stopped.</S>'
                '║                 <Obj N="Data" RefId="3">'
                '║                   <TN RefId="2">'
                '║                     <T>System.Collections.ListDictionaryInternal</T>'
                '║                     <T>System.Object</T>'
                '║                   </TN>'
                '║                   <DCT />'
                '║                 </Obj>'
                '║                 <Nil N="InnerException" />'
                '║                 <S N="TargetSite">Void Push(System.Management.Automation.Internal.PipelineProcessor)</S>'
                '║                 <S N="StackTrace">   at System.Management.Automation.Runspaces.PipelineStopper.Push(PipelineProcessor item)_x000D__x000A_   at System.Management.Automation.Runspaces.LocalPipeline.InvokeHelper()_x000D__x000A_   at System.Management.Automation.Runspaces.LocalPipeline.InvokeThreadProc()</S>'
                '║                 <Nil N="HelpLink" />'
                '║                 <S N="Source">System.Management.Automation</S>'
                '║                 <I32 N="HResult">-2146233087</I32>'
                '║               </Props>'
                '║             </Obj>'
                '║             <Nil N="TargetObject" />'
                '║             <S N="FullyQualifiedErrorId">PipelineStopped</S>'
                '║             <Nil N="InvocationInfo" />'
                '║             <I32 N="ErrorCategory_Category">14</I32>'
                '║             <S N="ErrorCategory_Activity"></S>'
                '║             <S N="ErrorCategory_Reason">PipelineStoppedException</S>'
                '║             <S N="ErrorCategory_TargetName"></S>'
                '║             <S N="ErrorCategory_TargetType"></S>'
                '║             <S N="ErrorCategory_Message">OperationStopped: (:) [], PipelineStoppedException</S>'
                '║             <B N="SerializeExtendedInfo">false</B>'
                '║           </MS>'
                '║         </Obj>'
                '║       </MS>'
                '║     </Obj>'
                '║   State: Stopped'
                '║   ErrorRecord: The pipeline has been stopped.'
                '╚═══'
                ''
            ) -join ([Environment]::NewLine)
        )
    }

    It "RunspacePoolState does not contain expected state" {
        $clixml = @(
            '<Obj RefId="1">'
            '  <MS>'
            '    <I32 N="UnexpectedField">123</I32>'
            '  </MS>'
            '</Obj>'
        ) -join ([Environment]::NewLine)
        $rawPacket = Get-PSRPPacket -Destination Client -MessageType RunspacePoolState -Data $clixml
        $actual = $rawPacket | ConvertTo-PSRPPacket | Format-PSRPPacket @common

        $actual | Should -Be (
            @(
                '╔═══ Data ═══'
                '║ PSGuid: 00000000-0000-0000-0000-000000000000'
                '║ Stream: Default'
                '╠══ Fragments'
                '║   Obj=1 Frag=0 Start=True End=True'
                '╠══ Messages'
                '║   Destination: Client'
                '║   MessageType: RunspacePoolState'
                '║   RPID: 00000000-0000-0000-0000-000000000000'
                '║   PID:  00000000-0000-0000-0000-000000000000'
                '║   Data:'
                '║     <Obj RefId="1">'
                '║       <MS>'
                '║         <I32 N="UnexpectedField">123</I32>'
                '║       </MS>'
                '║     </Obj>'
                '╚═══'
                ''
            ) -join ([Environment]::NewLine)
        )
    }

    It "RunspacePoolState contains null for state" {
        $rawPacket = Get-PSRPPacket -Destination Client -MessageType RunspacePoolState -Data '<Nil />'
        $actual = $rawPacket | ConvertTo-PSRPPacket | Format-PSRPPacket @common

        $actual | Should -Be (
            @(
                '╔═══ Data ═══'
                '║ PSGuid: 00000000-0000-0000-0000-000000000000'
                '║ Stream: Default'
                '╠══ Fragments'
                '║   Obj=1 Frag=0 Start=True End=True'
                '╠══ Messages'
                '║   Destination: Client'
                '║   MessageType: RunspacePoolState'
                '║   RPID: 00000000-0000-0000-0000-000000000000'
                '║   PID:  00000000-0000-0000-0000-000000000000'
                '║   Data:'
                '║     <Nil />'
                '╚═══'
                ''
            ) -join ([Environment]::NewLine)
        )
    }

    It "RunspacePoolState contains invalid CLIXML" {
        $rawPacket = Get-PSRPPacket -Destination Client -MessageType RunspacePoolState -Data 'invalid'
        $actual = $rawPacket | ConvertTo-PSRPPacket | Format-PSRPPacket @common

        $actual | Should -Be (
            @(
                '╔═══ Data ═══'
                '║ PSGuid: 00000000-0000-0000-0000-000000000000'
                '║ Stream: Default'
                '╠══ Fragments'
                '║   Obj=1 Frag=0 Start=True End=True'
                '╠══ Messages'
                '║   Destination: Client'
                '║   MessageType: RunspacePoolState'
                '║   RPID: 00000000-0000-0000-0000-000000000000'
                '║   PID:  00000000-0000-0000-0000-000000000000'
                '║   Data:'
                '║     invalid'
                '╚═══'
                ''
            ) -join ([Environment]::NewLine)
        )
    }

    It "RunspacePoolState without exception" {
        $clixml = @(
            '<Obj RefId="1">'
            '  <MS>'
            '    <I32 N="RunspaceState">0</I32>'
            '  </MS>'
            '</Obj>'
        ) -join ([Environment]::NewLine)
        $rawPacket = Get-PSRPPacket -Destination Client -MessageType RunspacePoolState -Data $clixml
        $actual = $rawPacket | ConvertTo-PSRPPacket | Format-PSRPPacket @common

        $actual | Should -Be (
            @(
                '╔═══ Data ═══'
                '║ PSGuid: 00000000-0000-0000-0000-000000000000'
                '║ Stream: Default'
                '╠══ Fragments'
                '║   Obj=1 Frag=0 Start=True End=True'
                '╠══ Messages'
                '║   Destination: Client'
                '║   MessageType: RunspacePoolState'
                '║   RPID: 00000000-0000-0000-0000-000000000000'
                '║   PID:  00000000-0000-0000-0000-000000000000'
                '║   Data:'
                '║     <Obj RefId="1">'
                '║       <MS>'
                '║         <I32 N="RunspaceState">0</I32>'
                '║       </MS>'
                '║     </Obj>'
                '║   State: BeforeOpen'
                '╚═══'
                ''
            ) -join ([Environment]::NewLine)
        )
    }

    It "Formats normal pipeline output" {
        $rawPacket = Get-PSRPPacket -Destination Client -MessageType PipelineOutput -Data '<S>value</S>'
        $actual = $rawPacket | ConvertTo-PSRPPacket | Format-PSRPPacket @common

        $actual | Should -Be (
            @(
                '╔═══ Data ═══'
                '║ PSGuid: 00000000-0000-0000-0000-000000000000'
                '║ Stream: Default'
                '╠══ Fragments'
                '║   Obj=1 Frag=0 Start=True End=True'
                '╠══ Messages'
                '║   Destination: Client'
                '║   MessageType: PipelineOutput'
                '║   RPID: 00000000-0000-0000-0000-000000000000'
                '║   PID:  00000000-0000-0000-0000-000000000000'
                '║   Data:'
                '║     <S>value</S>'
                '╚═══'
                ''
            ) -join ([Environment]::NewLine)
        )
    }
}
