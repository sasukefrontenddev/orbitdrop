using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace OrbitDrop.Native;

internal static class ExplorerBridge
{
    private static readonly HashSet<string> ExplorerClasses = new(StringComparer.Ordinal)
    {
        "CabinetWClass", "ExploreWClass", "Progman", "WorkerW"
    };

    internal static bool IsExplorerForeground()
    {
        var foreground = NativeMethods.GetForegroundWindow();
        var name = new StringBuilder(128);
        NativeMethods.GetClassName(foreground, name, name.Capacity);
        return ExplorerClasses.Contains(name.ToString());
    }

    internal static IReadOnlyList<string> SelectedPaths()
    {
        var foreground = NativeMethods.GetForegroundWindow();
        var foregroundRoot = NativeMethods.GetAncestor(foreground, NativeMethods.GaRoot);
        object? shellObject = null;
        try
        {
            var shellType = Type.GetTypeFromProgID("Shell.Application");
            if (shellType is null) return Array.Empty<string>();
            shellObject = Activator.CreateInstance(shellType);
            dynamic shell = shellObject!;
            foreach (var candidate in shell.Windows())
            {
                try
                {
                    dynamic window = candidate;
                    var handle = new IntPtr(Convert.ToInt64(window.HWND));
                    if (NativeMethods.GetAncestor(handle, NativeMethods.GaRoot) != foregroundRoot) continue;
                    var paths = ReadSelectedItems(window.Document);
                    if (paths.Count > 0) return paths;
                }
                catch { }
                finally
                {
                    if (candidate is not null && Marshal.IsComObject(candidate)) Marshal.FinalReleaseComObject(candidate);
                }
            }
        }
        catch { }
        finally
        {
            if (shellObject is not null && Marshal.IsComObject(shellObject)) Marshal.FinalReleaseComObject(shellObject);
        }
        return Array.Empty<string>();
    }

    private static IReadOnlyList<string> ReadSelectedItems(dynamic document)
    {
        var result = new List<string>();
        object? itemsObject = null;
        try
        {
            itemsObject = document.SelectedItems();
            dynamic items = itemsObject;
            for (var index = 0; index < (int)items.Count; index++)
            {
                dynamic item = items.Item(index);
                try
                {
                    var path = (string)item.Path;
                    if (File.Exists(path) || Directory.Exists(path)) result.Add(path);
                }
                finally
                {
                    if (Marshal.IsComObject(item)) Marshal.FinalReleaseComObject(item);
                }
            }
        }
        catch { }
        finally
        {
            if (itemsObject is not null && Marshal.IsComObject(itemsObject)) Marshal.FinalReleaseComObject(itemsObject);
            if (document is not null && Marshal.IsComObject(document)) Marshal.FinalReleaseComObject(document);
        }
        return result;
    }
}
