using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace Ansible.Debugger;

public readonly record struct DebugPayload(
    [property: JsonRequired] int RunspaceId,
    [property: JsonRequired] string Name,
    [property: JsonRequired] Dictionary<string, string>[] PathMapping);

public readonly record struct ListenerConfig(int Pid, string Host, int Port, string Token)
{
    // Indicates to ansible-test pwsh-debug what config version this is.
    public int Version { get; } = 1;
}

[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.SnakeCaseLower)]
[JsonSerializable(typeof(DebugPayload))]
[JsonSerializable(typeof(ListenerConfig))]
public partial class DebuggerJsonSerializerContext : JsonSerializerContext
{
}
