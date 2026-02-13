using System.Diagnostics.CodeAnalysis;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Text;
using System.Xml.Linq;

namespace Ansible.Debugger;

public static class PSRPFormattingExtensions
{
    public static string ToFormattedString(
        this OutOfProcPacket packet,
        bool noColor = false)
    {
        ColorPalette colors = noColor ? ColorPalette.NoColor : ColorPalette.Default;

        // Determine border color based on message destination or packet type
        string borderColor;
        if (packet.Messages.Length > 0)
        {
            // Use first message's destination
            borderColor = packet.Messages[0].Destination == PSRPDestination.Client
                ? colors.BrightYellow
                : colors.BrightCyan;
        }
        else
        {
            // Color by packet type when no messages
            borderColor = packet.Type switch
            {
                "Data" => colors.Gray,
                "DataAck" => colors.Gray,
                "Command" => colors.Magenta,
                "CommandAck" => colors.Magenta,
                "Signal" => colors.Blue,
                "SignalAck" => colors.Blue,
                "Close" => colors.Red,
                "CloseAck" => colors.Red,
                _ => colors.Cyan
            };
        }

        StringBuilder sb = new();
        sb.AppendLine($"{borderColor}╔═══ {colors.BrightWhite}{packet.Type}{borderColor} ═══{colors.Reset}");
        sb.AppendLine($"{borderColor}║{colors.Reset} {colors.Gray}PSGuid:{colors.Reset} {colors.Yellow}{packet.PSGuid}{colors.Reset}");

        if (packet.Stream is not null)
        {
            sb.AppendLine($"{borderColor}║{colors.Reset} {colors.Gray}Stream:{colors.Reset} {colors.Green}{packet.Stream}{colors.Reset}");
        }

        if (packet.Fragments.Length > 0)
        {
            sb.AppendLine($"{borderColor}╠══{colors.Reset} {colors.BrightCyan}Fragments{colors.Reset}");
            foreach (PSRPFragment frag in packet.Fragments)
            {
                sb.AppendLine($"{borderColor}║{colors.Reset}   {frag.ToFormattedString(noColor)}");
            }
        }

        if (packet.Messages.Length > 0)
        {
            sb.AppendLine($"{borderColor}╠══{colors.Reset} {colors.BrightCyan}Messages{colors.Reset}");
            foreach (PSRPMessage msg in packet.Messages)
            {
                foreach (string line in msg.ToFormattedString(noColor).Split('\n'))
                {
                    if (!string.IsNullOrWhiteSpace(line))
                    {
                        sb.AppendLine($"{borderColor}║{colors.Reset}   {line}");
                    }
                }
            }
        }

        sb.AppendLine($"{borderColor}╚═══{colors.Reset}");
        return sb.ToString();
    }

    public static string ToFormattedString(this PSRPFragment fragment, bool noColor = false)
    {
        ColorPalette colors = noColor ? ColorPalette.NoColor : ColorPalette.Default;
        return $"{colors.Gray}Obj={colors.Reset}{fragment.ObjectId}{colors.Reset} {colors.Gray}Frag={colors.Reset}{fragment.FragmentId} {colors.Gray}Start={colors.Reset}{fragment.Start} {colors.Gray}End={colors.Reset}{fragment.End}";
    }

    public static string ToFormattedString(this PSRPMessage message, bool noColor = false)
    {
        ColorPalette colors = noColor ? ColorPalette.NoColor : ColorPalette.Default;
        StringBuilder sb = new();

        string destColor = message.Destination == PSRPDestination.Client ? colors.BrightYellow : colors.BrightCyan;
        sb.AppendLine($"{colors.Gray}Destination:{colors.Reset} {destColor}{message.Destination}{colors.Reset}");
        sb.AppendLine($"{colors.Gray}MessageType:{colors.Reset} {colors.Blue}{message.MessageType}{colors.Reset}");
        sb.AppendLine($"{colors.Gray}RPID:{colors.Reset} {colors.Yellow}{message.RunspacePoolId}{colors.Reset}");
        sb.AppendLine($"{colors.Gray}PID:{colors.Reset}  {colors.Yellow}{message.PipelineId}{colors.Reset}");

        if (!string.IsNullOrWhiteSpace(message.Data))
        {
            sb.AppendLine($"{colors.Gray}Data:{colors.Reset}");
            try
            {
                XDocument doc = XDocument.Parse(message.Data);
                string prettyXml = doc.ToString();
                foreach (string line in prettyXml.Split('\n'))
                {
                    if (!string.IsNullOrWhiteSpace(line))
                    {
                        // Colorize XML
                        string coloredLine = ColorizeXml(line, colors);
                        sb.AppendLine($"  {coloredLine}");
                    }
                }
            }
            catch
            {
                sb.AppendLine($"  {message.Data}");
            }
        }

        if (string.IsNullOrWhiteSpace(message.Data))
        {
            return sb.ToString();
        }

        // Special handling for messages that could be clearer
        try
        {
            string? extraInfo = message.MessageType switch
            {
                PSRPMessageType.RunspacePoolState => GetStateFromData<RunspacePoolState>(message.Data, "RunspaceState", colors),
                PSRPMessageType.PipelineState => GetStateFromData<PSInvocationState>(message.Data, "PipelineState", colors),
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

    private static string? GetStateFromData<T>(string data, string propertyName, ColorPalette colors)
    {
        TryDeserializeClixml(data, out PSObject? psObj);
        object? stateValue = psObj?.Properties[propertyName]?.Value;
        if (stateValue is not null)
        {
            T state = (T)stateValue;
            string stateVal = state.ToString()!;

            object? exception = psObj?.Properties["ExceptionAsErrorRecord"]?.Value;
            if (exception is not null && exception is PSObject exObj)
            {
                string errorMsg = $"{colors.Gray}ErrorRecord:{colors.Reset} {colors.Red}{exObj}{colors.Reset}";
                stateVal = $"{colors.Red}{stateVal}\n{errorMsg}";
            }

            return $"{colors.Gray}State:{colors.Reset} {stateVal}";
        }

        return null;
    }

    private static bool TryDeserializeClixml(string raw, [NotNullWhen(true)] out PSObject? psObject)
    {
        string clixml = $"""
<Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04">
{raw}
</Objs>
""";

        object? deserialized = PSSerializer.Deserialize(clixml);
        if (deserialized is PSObject psObj)
        {
            psObject = psObj;
            return true;
        }
        else if (PSObject.AsPSObject(deserialized) is {} psObj2)
        {
            psObject = psObj2;
            return true;
        }

        psObject = null;
        return false;
    }

    private static string ColorizeXml(string xmlLine, ColorPalette colors)
    {
        // Simple XML colorization
        string result = xmlLine
            .Replace("<", $"{colors.Gray}<{colors.Magenta}")
            .Replace(">", $"{colors.Gray}>{colors.Reset}")
            .Replace("=\"", $"{colors.Gray}=\"{colors.Green}")
            .Replace("\"", $"{colors.Green}\"{colors.Reset}");

        return result;
    }

    private readonly struct ColorPalette
    {
        public readonly string Reset;
        public readonly string Red;
        public readonly string Green;
        public readonly string Yellow;
        public readonly string Blue;
        public readonly string Magenta;
        public readonly string Cyan;
        public readonly string Gray;
        public readonly string BrightYellow;
        public readonly string BrightCyan;
        public readonly string BrightWhite;

        private ColorPalette(
            string reset,
            string red,
            string green,
            string yellow,
            string blue,
            string magenta,
            string cyan,
            string gray,
            string brightYellow,
            string brightCyan,
            string brightWhite)
        {
            Reset = reset;
            Red = red;
            Green = green;
            Yellow = yellow;
            Blue = blue;
            Magenta = magenta;
            Cyan = cyan;
            Gray = gray;
            BrightYellow = brightYellow;
            BrightCyan = brightCyan;
            BrightWhite = brightWhite;
        }

        public static readonly ColorPalette Default = new(
            reset: "\x1b[0m",
            red: "\x1b[31m",
            green: "\x1b[32m",
            yellow: "\x1b[33m",
            blue: "\x1b[34m",
            magenta: "\x1b[35m",
            cyan: "\x1b[36m",
            gray: "\x1b[90m",
            brightYellow: "\x1b[93m",
            brightCyan: "\x1b[96m",
            brightWhite: "\x1b[97m");

        public static readonly ColorPalette NoColor = new(
            reset: "",
            red: "",
            green: "",
            yellow: "",
            blue: "",
            magenta: "",
            cyan: "",
            gray: "",
            brightYellow: "",
            brightCyan: "",
            brightWhite: "");
    }
}
