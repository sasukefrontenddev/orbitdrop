using System;
using System.Drawing;
using Forms = System.Windows.Forms;

namespace OrbitDrop.Native;

internal sealed class TriggerKeyRecorderForm : Forms.Form
{
    private readonly Forms.Label _captured;
    private readonly Forms.Button _save;
    internal TriggerKeyOption? RecordedKey { get; private set; }

    internal TriggerKeyRecorderForm(TriggerKeyOption current)
    {
        var messageFontFamily = SystemFonts.MessageBoxFont?.FontFamily ?? Forms.Control.DefaultFont.FontFamily;
        Text = "Record OrbitDrop trigger key";
        ClientSize = new Size(430, 190);
        FormBorderStyle = Forms.FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = Forms.FormStartPosition.CenterScreen;
        KeyPreview = true;

        var instruction = new Forms.Label
        {
            Text = "Press the physical key you want to hold in File Explorer.\nThere is no preset list.",
            AutoSize = false,
            TextAlign = ContentAlignment.MiddleCenter,
            Bounds = new Rectangle(20, 15, 390, 48)
        };
        _captured = new Forms.Label
        {
            Text = $"Press any key  •  Current: {current.Label}",
            Font = new Font(messageFontFamily, 15, FontStyle.Bold),
            ForeColor = Color.FromArgb(155, 220, 55),
            BackColor = Color.FromArgb(28, 31, 40),
            AutoSize = false,
            TextAlign = ContentAlignment.MiddleCenter,
            Bounds = new Rectangle(35, 70, 360, 54)
        };
        _save = new Forms.Button { Text = "Save", Enabled = false, DialogResult = Forms.DialogResult.OK, Bounds = new Rectangle(235, 142, 80, 30) };
        var cancel = new Forms.Button { Text = "Cancel", DialogResult = Forms.DialogResult.Cancel, Bounds = new Rectangle(325, 142, 80, 30) };
        Controls.AddRange(new Forms.Control[] { instruction, _captured, _save, cancel });
        AcceptButton = _save;
        CancelButton = cancel;
        KeyDown += CaptureKey;
    }

    private void CaptureKey(object? sender, Forms.KeyEventArgs eventArgs)
    {
        var key = TriggerKeyOption.FromKey(eventArgs.KeyCode);
        RecordedKey = key;
        _captured.Text = key.Label;
        _save.Enabled = true;
        eventArgs.Handled = true;
        eventArgs.SuppressKeyPress = true;
    }
}
