using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows;
using Forms = System.Windows.Forms;
using WpfApplication = System.Windows.Application;

namespace OrbitDrop.Native;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        NativeMethods.SetProcessDpiAwarenessContext(new IntPtr(-4));
        var application = new WpfApplication { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        using var controller = new OrbitController(application);
        application.Run();
    }
}

internal sealed class OrbitController : IDisposable
{
    private readonly WpfApplication _application;
    private readonly Forms.NotifyIcon _tray;
    private readonly Icon _trayIcon;
    private readonly RadialWindow _wheel = new();
    private readonly GlobalInputHook _input;
    private readonly UpdateChecker _updates;
    private readonly Forms.ToolStripMenuItem _triggerMenu;
    private IReadOnlyList<string> _files = Array.Empty<string>();
    private System.Drawing.Point _origin;
    private TriggerKeyOption _triggerKey;
    private int _holdSequence;
    private bool _triggerHeld;
    private bool _processing;

    internal OrbitController(WpfApplication application)
    {
        _application = application;
        _updates = new UpdateChecker(application.Dispatcher);
        _triggerKey = TriggerKeySettings.Load();
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("OrbitDrop is active").Enabled = false;
        menu.Items.Add("How to use", null, (_, _) => ShowHelp());
        _triggerMenu = new Forms.ToolStripMenuItem($"Trigger key: {_triggerKey.Label}");
        foreach (var option in TriggerKeyOption.Supported)
        {
            var item = new Forms.ToolStripMenuItem(option.Label) { Checked = option == _triggerKey };
            item.Click += (_, _) => SetTriggerKey(option);
            _triggerMenu.DropDownItems.Add(item);
        }
        menu.Items.Add(_triggerMenu);
        menu.Items.Add("Check for Updates…", null, (_, _) => _updates.Check(true));
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Quit OrbitDrop", null, (_, _) => _application.Shutdown());

        _trayIcon = !string.IsNullOrWhiteSpace(Environment.ProcessPath)
            ? Icon.ExtractAssociatedIcon(Environment.ProcessPath) ?? SystemIcons.Application
            : SystemIcons.Application;
        _tray = new Forms.NotifyIcon
        {
            Text = $"OrbitDrop — hold {_triggerKey.Label} on selected files",
            Icon = _trayIcon,
            ContextMenuStrip = menu,
            Visible = true
        };

        _input = new GlobalInputHook(OnMouseMove, OnTriggerDown, OnTriggerUp, OnEscape, _triggerKey.VirtualKey);
        _input.Start();
        _updates.Start();
    }

    private bool OnTriggerDown()
    {
        if (_triggerHeld) return true;
        if (_processing || !ExplorerBridge.IsExplorerForeground()) return false;
        _origin = Forms.Cursor.Position;
        _triggerHeld = true;
        var sequence = ++_holdSequence;
        _wheel.Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Background, () =>
        {
            var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
            timer.Tick += (_, _) =>
            {
                timer.Stop();
                if (!_triggerHeld || sequence != _holdSequence || !ExplorerBridge.IsExplorerForeground()) return;
                var selected = ExplorerBridge.SelectedPaths();
                if (!_triggerHeld || sequence != _holdSequence || selected.Count == 0) return;
                _files = selected;
                _wheel.ShowAt(_origin, selected);
            };
            timer.Start();
        });
        return true;
    }

    private bool OnMouseMove(System.Drawing.Point point)
    {
        if (!_wheel.IsVisible) return false;
        _wheel.UpdateHighlight(point);
        return false;
    }

    private bool OnTriggerUp()
    {
        if (!_triggerHeld) return false;
        _triggerHeld = false;
        _holdSequence++;
        if (_wheel.IsVisible)
        {
            Run(_wheel.ActionAt(Forms.Cursor.Position));
        }
        else
        {
            _files = Array.Empty<string>();
        }
        return true;
    }

    private bool OnEscape()
    {
        if (!_wheel.IsVisible) return false;
        Dismiss();
        return true;
    }

    private void Run(OrbitAction? action)
    {
        var files = _files;
        if (action is null)
        {
            Dismiss();
            return;
        }
        _triggerHeld = false;
        _processing = true;
        _files = Array.Empty<string>();
        _wheel.ShowProcessing(action.Value);
        FileOperations.Perform(action.Value, files, Notify, (success, message) =>
        {
            _wheel.ShowResult(success, message);
            var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(success ? 950 : 1200) };
            timer.Tick += (_, _) =>
            {
                timer.Stop();
                _wheel.HideSmooth();
                _processing = false;
            };
            timer.Start();
        });
    }

    private void Dismiss()
    {
        _triggerHeld = false;
        _holdSequence++;
        _files = Array.Empty<string>();
        _wheel.HideSmooth();
    }

    private void SetTriggerKey(TriggerKeyOption option)
    {
        Dismiss();
        _triggerKey = option;
        _input.TriggerVirtualKey = option.VirtualKey;
        TriggerKeySettings.Save(option);
        _triggerMenu.Text = $"Trigger key: {option.Label}";
        foreach (Forms.ToolStripMenuItem item in _triggerMenu.DropDownItems)
            item.Checked = item.Text == option.Label;
        _tray.Text = $"OrbitDrop — hold {option.Label} on selected files";
    }

    private void Notify(string title, string message, Forms.ToolTipIcon icon)
    {
        _tray.BalloonTipTitle = title;
        _tray.BalloonTipText = message;
        _tray.BalloonTipIcon = icon;
        _tray.ShowBalloonTip(3500);
    }

    private void ShowHelp()
    {
        System.Windows.MessageBox.Show(
            $"1. Select one or more files in File Explorer.\n2. Hold {_triggerKey.Label} for a moment until the wheel appears.\n3. Keep holding, move the pointer onto an action, then release the key to run it.\n\nChoose a different trigger key from the OrbitDrop tray menu at any time. Press Escape to close the wheel. Files never leave this PC.",
            "OrbitDrop — native Windows utility",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    public void Dispose()
    {
        _input.Dispose();
        _updates.Dispose();
        _wheel.Close();
        _tray.Visible = false;
        _tray.Dispose();
        if (!ReferenceEquals(_trayIcon, SystemIcons.Application)) _trayIcon.Dispose();
    }
}
