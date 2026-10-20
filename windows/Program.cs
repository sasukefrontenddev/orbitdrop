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
    private IReadOnlyList<string> _files = Array.Empty<string>();
    private System.Drawing.Point _origin;
    private bool _tracking;
    private bool _processing;

    internal OrbitController(WpfApplication application)
    {
        _application = application;
        _updates = new UpdateChecker(application.Dispatcher);
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("OrbitDrop is active").Enabled = false;
        menu.Items.Add("How to use", null, (_, _) => ShowHelp());
        menu.Items.Add("Check for Updates…", null, (_, _) => _updates.Check(true));
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Quit OrbitDrop", null, (_, _) => _application.Shutdown());

        _trayIcon = !string.IsNullOrWhiteSpace(Environment.ProcessPath)
            ? Icon.ExtractAssociatedIcon(Environment.ProcessPath) ?? SystemIcons.Application
            : SystemIcons.Application;
        _tray = new Forms.NotifyIcon
        {
            Text = "OrbitDrop — right-click selected File Explorer items",
            Icon = _trayIcon,
            ContextMenuStrip = menu,
            Visible = true
        };

        _input = new GlobalInputHook(OnRightDown, OnMouseMove, OnRightUp, OnLeftDown, OnEscape);
        _input.Start();
        _updates.Start();
    }

    private bool OnRightDown(System.Drawing.Point point)
    {
        if (_processing || !ExplorerBridge.IsExplorerForeground()) return false;
        _origin = point;
        _tracking = true;
        _wheel.Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Background, () =>
        {
            var selected = ExplorerBridge.SelectedPaths();
            if (!_tracking || selected.Count == 0)
            {
                _tracking = false;
                return;
            }
            _files = selected;
            _wheel.ShowAt(point, selected);
        });
        return false;
    }

    private bool OnMouseMove(System.Drawing.Point point)
    {
        if (!_wheel.IsVisible) return false;
        _wheel.UpdateHighlight(point);
        return _tracking;
    }

    private bool OnRightUp(System.Drawing.Point point)
    {
        if (!_tracking) return false;
        if (!_wheel.IsVisible)
        {
            _tracking = false;
            return false;
        }

        var moved = Math.Sqrt(Math.Pow(point.X - _origin.X, 2) + Math.Pow(point.Y - _origin.Y, 2));
        if (moved < 22)
        {
            _tracking = false;
            _wheel.UpdateHighlight(new System.Drawing.Point(-10000, -10000));
            return true;
        }

        Run(_wheel.ActionAt(point));
        return true;
    }

    private bool OnLeftDown(System.Drawing.Point point)
    {
        if (!_wheel.IsVisible) return false;
        Run(_wheel.ActionAt(point));
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
        _tracking = false;
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
        _tracking = false;
        _files = Array.Empty<string>();
        _wheel.HideSmooth();
    }

    private void Notify(string title, string message, Forms.ToolTipIcon icon)
    {
        _tray.BalloonTipTitle = title;
        _tray.BalloonTipText = message;
        _tray.BalloonTipIcon = icon;
        _tray.ShowBalloonTip(3500);
    }

    private static void ShowHelp()
    {
        System.Windows.MessageBox.Show(
            "1. Select a file in File Explorer.\n2. Hold the right mouse button until the wheel appears.\n3. Glide to an action while still holding, then release to run it.\n\nYou can also right-click and release, move over an action, and left-click it. Press Escape to close the wheel. Files never leave this PC.",
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
