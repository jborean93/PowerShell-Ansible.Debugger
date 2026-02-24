using System.IO;
using System.Reflection;
using System.Runtime.Loader;

namespace AlcLoader;

public class LoadContext : AssemblyLoadContext
{
    private string[] _assemblyDirs;

    public LoadContext(string name, string[] assemblyDirs)
        : base (name: name, isCollectible: false)
    {
        _assemblyDirs = assemblyDirs;
    }

    protected override Assembly? Load(AssemblyName assemblyName)
    {
        foreach (string assemblyDir in _assemblyDirs)
        {
            string asmPath = Path.Join(assemblyDir, $"{assemblyName.Name}.dll");
            if (File.Exists(asmPath))
            {
                return LoadFromAssemblyPath(asmPath);
            }
        }

        return null;
    }
}
