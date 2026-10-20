using System;
using System.Collections.Generic;
using System.IO;
using Forms = System.Windows.Forms;

namespace OrbitDrop.Native;

internal readonly record struct TriggerKeyOption(int VirtualKey, string Label)
{
    internal static readonly IReadOnlyList<TriggerKeyOption> Supported = BuildSupported();

    private static IReadOnlyList<TriggerKeyOption> BuildSupported()
    {
        var keys = new List<TriggerKeyOption>
        {
            new((int)Forms.Keys.Space, "Space"),
            new((int)Forms.Keys.F6, "F6"), new((int)Forms.Keys.F7, "F7"),
            new((int)Forms.Keys.F8, "F8"), new((int)Forms.Keys.F9, "F9"),
            new((int)Forms.Keys.F10, "F10"), new((int)Forms.Keys.F11, "F11"),
            new((int)Forms.Keys.F12, "F12")
        };
        for (var key = Forms.Keys.A; key <= Forms.Keys.Z; key++)
            keys.Add(new TriggerKeyOption((int)key, key.ToString()));
        return keys;
    }
}

internal static class TriggerKeySettings
{
    private static readonly string SettingsPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "OrbitDrop",
        "trigger-key.txt");

    internal static TriggerKeyOption Load()
    {
        try
        {
            if (int.TryParse(File.ReadAllText(SettingsPath), out var stored))
                foreach (var option in TriggerKeyOption.Supported)
                    if (option.VirtualKey == stored) return option;
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        return TriggerKeyOption.Supported[0];
    }

    internal static void Save(TriggerKeyOption option)
    {
        try
        {
            var directory = Path.GetDirectoryName(SettingsPath)!;
            Directory.CreateDirectory(directory);
            File.WriteAllText(SettingsPath, option.VirtualKey.ToString());
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}
