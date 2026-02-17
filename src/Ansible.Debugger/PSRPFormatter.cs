using System.Diagnostics.CodeAnalysis;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Text;
using System.Xml.Linq;

namespace Ansible.Debugger;

public class PSRPFormatter
{
    public readonly string Reset = "";
    public readonly string Red = "";
    public readonly string Green = "";
    public readonly string Yellow = "";
    public readonly string Blue = "";
    public readonly string Magenta = "";
    public readonly string Cyan = "";
    public readonly string BrightBlack = "";
    public readonly string BrightYellow = "";
    public readonly string BrightCyan = "";
    public readonly string BrightWhite = "";

    public PSRPFormatter(bool noColor)
    {
        if (!noColor)
        {
            Reset = "\x1b[0m";
            Red = "\x1b[31m";
            Green = "\x1b[32m";
            Yellow = "\x1b[33m";
            Blue = "\x1b[34m";
            Magenta = "\x1b[35m";
            Cyan = "\x1b[36m";
            BrightBlack = "\x1b[90m";
            BrightYellow = "\x1b[93m";
            BrightCyan = "\x1b[96m";
            BrightWhite = "\x1b[97m";
        }
    }

    public string FormatOutOfProcPacket(OutOfProcPacket packet)
    {
        // Determine border color based on message destination or packet type
        string borderColor;
        if (packet.Messages.Length > 0)
        {
            // Use first message's destination
            borderColor = packet.Messages[0].Destination == PSRPDestination.Client
                ? BrightYellow
                : BrightCyan;
        }
        else
        {
            // Color by packet type when no messages
            borderColor = packet.Type switch
            {
                "Data" => BrightBlack,
                "DataAck" => BrightBlack,
                "Command" => Magenta,
                "CommandAck" => Magenta,
                "Signal" => Blue,
                "SignalAck" => Blue,
                "Close" => Red,
                "CloseAck" => Red,
                _ => Cyan
            };
        }

        StringBuilder sb = new();
        sb.AppendLine($"{borderColor}╔═══ {BrightWhite}{packet.Type}{borderColor} ═══{Reset}");
        sb.AppendLine($"{borderColor}║{Reset} {BrightBlack}PSGuid:{Reset} {Yellow}{packet.PSGuid}{Reset}");

        if (packet.Stream is not null)
        {
            sb.AppendLine($"{borderColor}║{Reset} {BrightBlack}Stream:{Reset} {Green}{packet.Stream}{Reset}");
        }

        if (packet.Fragments.Length > 0)
        {
            sb.AppendLine($"{borderColor}╠══{Reset} {BrightCyan}Fragments{Reset}");
            foreach (PSRPFragment frag in packet.Fragments)
            {
                sb.AppendLine($"{borderColor}║{Reset}   {FormatFragment(frag)}");
            }
        }

        if (packet.Messages.Length > 0)
        {
            sb.AppendLine($"{borderColor}╠══{Reset} {BrightCyan}Messages{Reset}");
            foreach (PSRPMessage msg in packet.Messages)
            {
                foreach (string line in FormatMessage(msg).Split('\n'))
                {
                    if (!string.IsNullOrWhiteSpace(line))
                    {
                        sb.AppendLine($"{borderColor}║{Reset}   {line}");
                    }
                }
            }
        }

        sb.AppendLine($"{borderColor}╚═══{Reset}");
        return sb.ToString();
    }

    public string FormatFragment(PSRPFragment fragment)
    {
        return $"{BrightBlack}Obj={Reset}{fragment.ObjectId} {BrightBlack}Frag={Reset}{fragment.FragmentId} {BrightBlack}Start={Reset}{fragment.Start} {BrightBlack}End={Reset}{fragment.End}";
    }

    public string FormatMessage(PSRPMessage message)
    {
        StringBuilder sb = new();

        string destColor = message.Destination == PSRPDestination.Client ? BrightYellow : BrightCyan;
        sb.AppendLine($"{BrightBlack}Destination:{Reset} {destColor}{message.Destination}{Reset}");
        sb.AppendLine($"{BrightBlack}MessageType:{Reset} {Blue}{message.MessageType}{Reset}");
        sb.AppendLine($"{BrightBlack}RPID:{Reset} {Yellow}{message.RunspacePoolId}{Reset}");
        sb.AppendLine($"{BrightBlack}PID:{Reset}  {Yellow}{message.PipelineId}{Reset}");

        if (!string.IsNullOrWhiteSpace(message.Data))
        {
            sb.AppendLine($"{BrightBlack}Data:{Reset}");
            try
            {
                XDocument doc = XDocument.Parse(message.Data);
                string prettyXml = doc.ToString();
                foreach (string line in prettyXml.Split('\n'))
                {
                    if (!string.IsNullOrWhiteSpace(line))
                    {
                        // Colorize XML
                        string coloredLine = ColorizeXml(line);
                        sb.AppendLine($"  {coloredLine}");
                    }
                }
            }
            catch
            {
                sb.AppendLine($"  {message.Data}");
            }
        }

        // Special handling for messages that could be clearer
        try
        {
            string? extraInfo = message.MessageType switch
            {
                PSRPMessageType.RunspacePoolState => GetStateFromData<RunspacePoolState>(message.Data, "RunspaceState"),
                PSRPMessageType.PipelineState => GetStateFromData<PSInvocationState>(message.Data, "PipelineState"),
                _ => null
            };

            if (extraInfo is not null)
            {
                sb.AppendLine(extraInfo);
            }
        }
        catch
        {
            // We don't care about deserialization errors, just return the raw data if it fails
        }

        return sb.ToString();
    }

    private string? GetStateFromData<T>(string data, string propertyName)
    {
        TryDeserializeClixml(data, out PSObject? psObj);
        object? stateValue = psObj?.Properties[propertyName]?.Value;
        if (stateValue is not null)
        {
            T state = (T)stateValue;
            string stateVal = state.ToString()!;

            object? exception = psObj!.Properties["ExceptionAsErrorRecord"]?.Value;
            if (exception is PSObject exObj)
            {
                string errorMsg = $"{BrightBlack}ErrorRecord:{Reset} {Red}{exObj}{Reset}";
                stateVal = $"{Red}{stateVal}\n{errorMsg}";
            }

            return $"{BrightBlack}State:{Reset} {stateVal}";
        }

        return null;
    }

    private string ColorizeXml(string xmlLine)
    {
        // Simple XML colorization
        string result = xmlLine
            .Replace("<", $"{BrightBlack}<{Magenta}")
            .Replace(">", $"{BrightBlack}>{Reset}")
            .Replace("=\"", $"{BrightBlack}=\"{Green}")
            .Replace("\"", $"{Green}\"{Reset}");

        return result;
    }

    private static bool TryDeserializeClixml(string raw, [NotNullWhen(true)] out PSObject? psObject)
    {
        string clixml = $"""
<Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04">
{raw}
</Objs>
""";

        object? deserialized = PSSerializer.Deserialize(clixml);
        if (deserialized is null)
        {
            psObject = null;
            return false;
        }
        else
        {
            psObject = PSObject.AsPSObject(deserialized);
            return true;
        }
    }
}
