using System.Text.Json.Serialization;

namespace Ansible.Debugger;

[JsonDerivedType(typeof(PwshLaunchConfiguration))]
[JsonDerivedType(typeof(PythonModuleLaunchConfiguration))]
public abstract class LaunchConfiguration
{
    public abstract string Type { get; set; }

    public string Name { get; set; } = string.Empty;
    public string Request { get; set; } = "launch";
    public ServerReadyAction? ServerReadyAction { get; set; }
}

public sealed class PwshLaunchConfiguration : LaunchConfiguration
{
    public override string Type { get; set; } = "PowerShell";

    public string? Cwd { get; set; }
    public string Script { get; set; } = string.Empty;
}

public sealed class PythonModuleLaunchConfiguration : LaunchConfiguration
{
    public override string Type { get; set; } = "debugpy";

    public string Module { get; set; } = string.Empty;
    public string[] Args { get; set; } = [];
    public string Console { get; set; } = string.Empty;
    public string? Cwd { get; set; }
}

[JsonDerivedType(typeof(StartDebuggingServerReadyAction))]
public abstract class ServerReadyAction
{
    public abstract string Action { get; set; }

    public string Pattern { get; set; } = string.Empty;
    public bool KillOnServerStop { get; set; }

}

public sealed class StartDebuggingServerReadyAction : ServerReadyAction
{
    public override string Action { get; set; } = "startDebugging";

    public LaunchConfiguration? Config { get; set; }
}

[JsonSourceGenerationOptions(
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    WriteIndented = true,
    MaxDepth = 10
)]
[JsonSerializable(typeof(LaunchConfiguration))]
[JsonSerializable(typeof(ServerReadyAction))]
public partial class VSCodeJsonSerializerContext : JsonSerializerContext
{
}
