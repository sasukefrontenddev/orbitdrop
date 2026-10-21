using System;
using System.IO;
using Forms = System.Windows.Forms;

namespace OrbitDrop.Native;

internal readonly record struct TriggerKeyOption(int VirtualKey, string Label)
{
    internal static TriggerKeyOption FromKey(Forms.Keys key)
    {
        var code = key & Forms.Keys.KeyCode;
        var label = code switch
        {
            Forms.Keys.Space => "Space",
            Forms.Keys.Return => "Enter",
            Forms.Keys.Escape => "Escape",
            Forms.Keys.Back => "Backspace",
            Forms.Keys.ShiftKey => "Shift",
            Forms.Keys.ControlKey => "Control",
            Forms.Keys.Menu => "Alt",
            Forms.Keys.LShiftKey => "Left Shift",
            Forms.Keys.RShiftKey => "Right Shift",
            Forms.Keys.LControlKey => "Left Control",
            Forms.Keys.RControlKey => "Right Control",
            Forms.Keys.LMenu => "Left Alt",
            Forms.Keys.RMenu => "Right Alt",
            _ => new Forms.KeysConverter().ConvertToString(code) ?? code.ToString()
        };
        return new TriggerKeyOption((int)code, label);
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
            var parts = File.ReadAllText(SettingsPath).Split('|', 2);
            if (int.TryParse(parts[0], out var stored))
            {
                var label = parts.Length == 2 && !string.IsNullOrWhiteSpace(parts[1])
                    ? parts[1]
                    : TriggerKeyOption.FromKey((Forms.Keys)stored).Label;
                return new TriggerKeyOption(stored, label);
            }
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        return TriggerKeyOption.FromKey(Forms.Keys.Space);
    }

    internal static void Save(TriggerKeyOption option)
    {
        try
        {
            var directory = Path.GetDirectoryName(SettingsPath)!;
            Directory.CreateDirectory(directory);
            File.WriteAllText(SettingsPath, $"{option.VirtualKey}|{option.Label.Replace("|", string.Empty)}");
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}
