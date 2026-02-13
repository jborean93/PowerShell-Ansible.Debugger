using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Text;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.Text;

namespace Script.Generator;

[Generator]
public class LocalScriptGenerator : IIncrementalGenerator
{
    private const string EmbedScriptsAttribute = @"using System;

namespace Script.Generator
{
    [AttributeUsage(AttributeTargets.Class, AllowMultiple = false, Inherited = false)]
    public class EmbedScriptsAttribute : Attribute
    {
    }
}
";

    public void Initialize(IncrementalGeneratorInitializationContext context)
    {
        context.RegisterPostInitializationOutput(static ctx =>
        {
            ctx.AddEmbeddedAttributeDefinition();
            ctx.AddSource(
                "LocalScriptAttribute.g.cs",
                SourceText.From(EmbedScriptsAttribute, Encoding.UTF8));
        });

        IncrementalValuesProvider<INamedTypeSymbol?> classesToGenerate = context.SyntaxProvider
            .ForAttributeWithMetadataName(
                "Script.Generator.EmbedScriptsAttribute",
                predicate: static (s, _) => true,
                transform: static (ctx, _) => (INamedTypeSymbol?)ctx.TargetSymbol)
            .Where(static m => m is not null);

        var combined = classesToGenerate
            .Combine(context.AdditionalTextsProvider.Collect());

        context.RegisterSourceOutput(combined,
            static (spc, source) =>
            {
                var (scriptInfo, files) = source;
                Generate(spc, scriptInfo, files);
            });
    }

    private static void Generate(
        SourceProductionContext context,
        INamedTypeSymbol? classSymbol,
        ImmutableArray<AdditionalText> files)
    {
        if (classSymbol is null)
        {
            return;
        }

        StringBuilder sb = new StringBuilder();
        sb.AppendLine($"// Auto-generated script for {classSymbol.Name}");

        if (!classSymbol.ContainingNamespace.IsGlobalNamespace)
        {
            sb.AppendLine($"namespace {classSymbol.ContainingNamespace.ToDisplayString()};");
            sb.AppendLine();
        }

        sb.AppendLine($"partial class {classSymbol.Name}");
        sb.AppendLine("{");

        foreach (AdditionalText file in files)
        {
            string fieldName = Path.GetFileNameWithoutExtension(file.Path);
            string scriptText = file.GetText(context.CancellationToken)?.ToString() ?? "";
            string escapedContent = scriptText.Replace("\"", "\"\"");

            sb.AppendLine($"    // Script: {file.Path}");
            sb.AppendLine($"    public const string {fieldName} = @\"{escapedContent}\";");
        }

        sb.AppendLine("}");

        context.AddSource(
            $"{classSymbol.Name}.EmbedScripts.g.cs",
            sb.ToString());
    }
}
