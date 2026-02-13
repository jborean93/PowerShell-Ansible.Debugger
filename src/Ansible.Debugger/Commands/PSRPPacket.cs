using System;
using System.Collections.Generic;
using System.Management.Automation;

namespace Ansible.Debugger.Commands;

[Cmdlet(VerbsCommon.Format, "PSRPPacket")]
[OutputType(typeof(string))]
public sealed class FormatPSRPPacketCommand : PSCmdlet
{
    [Parameter(ValueFromPipeline = true, Mandatory = true)]
    public OutOfProcPacket[] Packet { get; set; } = [];

    [Parameter]
    [Alias("NoColour")]
    public SwitchParameter NoColor { get; set; }

    protected override void ProcessRecord()
    {
        foreach (OutOfProcPacket item in Packet)
        {
            string formattedString = item.ToFormattedString(noColor: NoColor);
            WriteObject(formattedString);
        }
    }
}

[Cmdlet(VerbsData.ConvertTo, "PSRPPacket")]
[OutputType(typeof(OutOfProcPacket))]
public sealed class ConvertToPSRPPacketCommand : PSCmdlet
{
    private readonly Dictionary<ulong, List<byte>> _fragements = new();

    [Parameter(
        Mandatory = true,
        Position = 0,
        ValueFromPipeline = true
    )]
    public string[] InputObject { get; set; } = [];

    protected override void ProcessRecord()
    {
        foreach (string line in InputObject)
        {
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            OutOfProcPacket packet;
            try
            {
                packet = OutOfProcPacket.Parse(line, _fragements);
            }
            catch (Exception ex)
            {
                ErrorRecord errorRecord = new(
                    ex,
                    "ParseError",
                    ErrorCategory.InvalidData,
                    line)
                {
                    ErrorDetails = new($"Failed to parse line '{line}': {ex.Message}")
                };

                WriteError(errorRecord);
                continue;
            }

            WriteObject(packet);
        }
    }
}
