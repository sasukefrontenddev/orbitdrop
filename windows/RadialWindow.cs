using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Threading;
using Forms = System.Windows.Forms;
using DrawingPoint = System.Drawing.Point;

namespace OrbitDrop.Native;

internal enum OrbitAction { Pdf, Png, Jpg, Tiff, Bmp, Zip, Shrink, Resize, Rotate, Flip, Grayscale, Copy }

internal sealed class RadialWindow : Window
{
    private const double WindowSize = 480;
    private readonly RadialVisual _visual = new();
    private double _scale = 1;

    internal RadialWindow()
    {
        Width = WindowSize;
        Height = WindowSize;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = true;
        ResizeMode = ResizeMode.NoResize;
        IsHitTestVisible = false;
        Content = _visual;
        _visual.Effect = new DropShadowEffect { BlurRadius = 28, ShadowDepth = 4, Opacity = 0.34, Color = Color.FromRgb(4, 3, 14) };
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        var handle = new WindowInteropHelper(this).Handle;
        var style = NativeMethods.GetWindowLong(handle, NativeMethods.GwlExStyle);
        NativeMethods.SetWindowLong(handle, NativeMethods.GwlExStyle, style | NativeMethods.WsExNoActivate | NativeMethods.WsExToolWindow);
    }

    internal void ShowAt(DrawingPoint point, IReadOnlyList<string> files)
    {
        _scale = Math.Max(1, NativeMethods.GetDpiForSystem() / 96.0);
        var screen = Forms.Screen.FromPoint(point).WorkingArea;
        var pixelWidth = WindowSize * _scale;
        var pixelHeight = WindowSize * _scale;
        var x = Math.Clamp(point.X - pixelWidth / 2, screen.Left, screen.Right - pixelWidth);
        var y = Math.Clamp(point.Y - pixelHeight / 2, screen.Top, screen.Bottom - pixelHeight);
        Left = x / _scale;
        Top = y / _scale;
        _visual.Configure(files);
        BeginAnimation(OpacityProperty, null);
        Opacity = 0;
        if (!IsVisible) Show();
        BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(130))
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
        });
    }

    internal void HideSmooth(bool animated = true)
    {
        _visual.Highlighted = null;
        if (!IsVisible) return;
        if (!animated)
        {
            BeginAnimation(OpacityProperty, null);
            Opacity = 1;
            Hide();
            return;
        }
        var fade = new DoubleAnimation(Opacity, 0, TimeSpan.FromMilliseconds(110))
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseIn }
        };
        fade.Completed += (_, _) =>
        {
            Hide();
            BeginAnimation(OpacityProperty, null);
            Opacity = 1;
        };
        BeginAnimation(OpacityProperty, fade);
    }

    internal void ShowProcessing(OrbitAction action) => _visual.ShowProcessing(action);
    internal void ShowResult(bool success, string message) => _visual.ShowResult(success, message);
    internal void UpdateHighlight(DrawingPoint point) => _visual.Highlighted = ActionAt(point);

    internal OrbitAction? ActionAt(DrawingPoint point)
    {
        var local = new System.Windows.Point(point.X / _scale - Left, point.Y / _scale - Top);
        return _visual.ActionAt(local);
    }
}

internal sealed class RadialVisual : FrameworkElement
{
    private enum DisplayPhase { Ready, Processing, Success, Failure }

    private static readonly OrbitAction[] Actions = Enum.GetValues<OrbitAction>();
    private static readonly string[] Titles = { "PDF", "PNG", "JPG", "TIFF", "BMP", "ZIP", "SHRINK", "50%", "ROTATE", "FLIP", "GRAY", "COPY" };
    private static readonly string[] Details =
    {
        "Create a PDF", "Convert to PNG", "Convert to JPG", "Convert to TIFF", "Convert to BMP", "Create a ZIP",
        "Compress the file", "Resize image to 50%", "Rotate 90 degrees", "Flip horizontally", "Make grayscale", "Create a safe copy"
    };
    private static readonly HashSet<string> Images = new(StringComparer.OrdinalIgnoreCase) { ".png", ".jpg", ".jpeg", ".bmp", ".gif", ".tif", ".tiff", ".ico", ".heic" };
    private static readonly HashSet<string> Documents = new(StringComparer.OrdinalIgnoreCase) { ".docx", ".rtf", ".txt", ".html", ".htm" };
    private static readonly Color Lime = Color.FromRgb(198, 250, 42);
    private readonly HashSet<OrbitAction> _disabled = new();
    private readonly DispatcherTimer _pulseTimer;
    private IReadOnlyList<string> _files = Array.Empty<string>();
    private OrbitAction? _highlighted;
    private OrbitAction _processingAction;
    private DisplayPhase _phase = DisplayPhase.Ready;
    private string _statusMessage = "";
    private double _pulse;
    private const double Center = 240;
    private const double Inner = 88;
    private const double Outer = 218;

    internal RadialVisual()
    {
        _pulseTimer = new DispatcherTimer(DispatcherPriority.Render) { Interval = TimeSpan.FromMilliseconds(33) };
        _pulseTimer.Tick += (_, _) =>
        {
            _pulse = (_pulse + 0.055) % 1;
            InvalidateVisual();
        };
    }

    internal OrbitAction? Highlighted
    {
        get => _highlighted;
        set { if (_highlighted != value) { _highlighted = value; InvalidateVisual(); } }
    }

    internal void Configure(IReadOnlyList<string> files)
    {
        _pulseTimer.Stop();
        _pulse = 0;
        _phase = DisplayPhase.Ready;
        _files = files;
        _disabled.Clear();
        var allImages = files.Count > 0 && files.All(path => Images.Contains(Path.GetExtension(path)));
        var allPdf = files.Count > 0 && files.All(path => Images.Contains(Path.GetExtension(path)) || Documents.Contains(Path.GetExtension(path)));
        if (!allImages)
        {
            _disabled.UnionWith(new[] { OrbitAction.Png, OrbitAction.Jpg, OrbitAction.Tiff, OrbitAction.Bmp, OrbitAction.Resize, OrbitAction.Rotate, OrbitAction.Flip, OrbitAction.Grayscale });
        }
        if (!allPdf) _disabled.Add(OrbitAction.Pdf);
        Highlighted = null;
        InvalidateVisual();
    }

    internal void ShowProcessing(OrbitAction action)
    {
        _processingAction = action;
        _phase = DisplayPhase.Processing;
        Highlighted = action;
        _pulseTimer.Start();
        InvalidateVisual();
    }

    internal void ShowResult(bool success, string message)
    {
        _pulseTimer.Stop();
        Highlighted = null;
        _phase = success ? DisplayPhase.Success : DisplayPhase.Failure;
        _statusMessage = message;
        InvalidateVisual();
    }

    internal OrbitAction? ActionAt(System.Windows.Point point)
    {
        if (_phase != DisplayPhase.Ready) return null;
        var dx = point.X - Center;
        var dy = point.Y - Center;
        var distance = Math.Sqrt(dx * dx + dy * dy);
        if (distance < Inner || distance > Outer) return null;
        var degrees = Math.Atan2(dy, dx) * 180 / Math.PI;
        var clockwiseFromTop = (degrees + 90 + 360) % 360;
        var action = Actions[(int)(clockwiseFromTop / 30)];
        return _disabled.Contains(action) ? null : action;
    }

    protected override void OnRender(DrawingContext context)
    {
        base.OnRender(context);
        DrawAmbientGlow(context);
        foreach (var action in Actions) DrawSector(context, action);
        DrawCenter(context);
    }

    private static void DrawAmbientGlow(DrawingContext context)
    {
        context.DrawEllipse(new SolidColorBrush(Color.FromArgb(28, 94, 54, 238)), null, new System.Windows.Point(Center, Center), Outer + 6, Outer + 6);
    }

    private void DrawSector(DrawingContext context, OrbitAction action)
    {
        var index = (int)action;
        const double gap = 0.65;
        var start = -90 + index * 30 + gap;
        var end = -90 + (index + 1) * 30 - gap;
        var geometry = new StreamGeometry();
        using (var figure = geometry.Open())
        {
            figure.BeginFigure(Polar(Outer, start), true, true);
            figure.ArcTo(Polar(Outer, end), new Size(Outer, Outer), 0, false, SweepDirection.Clockwise, true, false);
            figure.LineTo(Polar(Inner, end), true, false);
            figure.ArcTo(Polar(Inner, start), new Size(Inner, Inner), 0, false, SweepDirection.Counterclockwise, true, false);
        }
        geometry.Freeze();

        var disabled = _disabled.Contains(action);
        var highlighted = Highlighted == action;
        var fill = disabled
            ? Color.FromArgb(112, 11, 13, 25)
            : highlighted ? Color.FromArgb(242, 77, 48, 191) : Color.FromArgb(214, 11, 13, 29);
        var border = highlighted ? Color.FromArgb(220, 198, 250, 42) : Color.FromArgb(disabled ? (byte)34 : (byte)98, 120, 91, 226);
        context.DrawGeometry(new SolidColorBrush(fill), new Pen(new SolidColorBrush(border), highlighted ? 1.8 : 1), geometry);

        var label = Polar(163, -75 + index * 30);
        var foreground = disabled ? Color.FromArgb(118, 148, 148, 165) : highlighted ? Lime : Color.FromRgb(235, 235, 245);
        DrawActionIcon(context, action, label.X, label.Y - 6, foreground, disabled);
        DrawText(context, Titles[index], label.X, label.Y + 17, 8.2, FontWeights.Bold, foreground, 68, true);
    }

    private static void DrawActionIcon(DrawingContext context, OrbitAction action, double x, double y, Color color, bool disabled)
    {
        var brush = new SolidColorBrush(color);
        var pen = new Pen(brush, disabled ? 1.35 : 1.7) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
        var thin = new Pen(brush, 1.25) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
        switch (action)
        {
            case OrbitAction.Pdf:
                context.DrawRectangle(null, pen, new Rect(x - 7, y - 9, 14, 18));
                context.DrawLine(thin, new System.Windows.Point(x - 4, y + 1), new System.Windows.Point(x + 4, y + 1));
                context.DrawLine(thin, new System.Windows.Point(x - 4, y + 5), new System.Windows.Point(x + 2, y + 5));
                break;
            case OrbitAction.Png:
            case OrbitAction.Jpg:
                context.DrawRoundedRectangle(action == OrbitAction.Jpg ? new SolidColorBrush(Color.FromArgb(34, color.R, color.G, color.B)) : null, pen, new Rect(x - 9, y - 7, 18, 14), 2, 2);
                context.DrawEllipse(brush, null, new System.Windows.Point(x + 4, y - 3), 1.8, 1.8);
                context.DrawLine(thin, new System.Windows.Point(x - 7, y + 5), new System.Windows.Point(x - 1, y - 1));
                context.DrawLine(thin, new System.Windows.Point(x - 1, y - 1), new System.Windows.Point(x + 2, y + 2));
                context.DrawLine(thin, new System.Windows.Point(x + 2, y + 2), new System.Windows.Point(x + 7, y - 2));
                break;
            case OrbitAction.Tiff:
                context.DrawRectangle(null, thin, new Rect(x - 9, y - 5, 14, 12));
                context.DrawRectangle(null, pen, new Rect(x - 5, y - 8, 14, 12));
                break;
            case OrbitAction.Bmp:
                for (var row = -1; row <= 1; row++)
                    for (var column = -1; column <= 1; column++)
                        context.DrawRectangle((row + column) % 2 == 0 ? brush : null, thin, new Rect(x + column * 5 - 2, y + row * 5 - 2, 4, 4));
                break;
            case OrbitAction.Zip:
                context.DrawRoundedRectangle(null, pen, new Rect(x - 9, y - 7, 18, 14), 2, 2);
                context.DrawLine(thin, new System.Windows.Point(x, y - 6), new System.Windows.Point(x, y + 2));
                context.DrawRectangle(brush, null, new Rect(x - 1.8, y + 2, 3.6, 3.6));
                break;
            case OrbitAction.Shrink:
                DrawArrow(context, pen, new System.Windows.Point(x - 9, y - 8), new System.Windows.Point(x - 2, y - 1));
                DrawArrow(context, pen, new System.Windows.Point(x + 9, y + 8), new System.Windows.Point(x + 2, y + 1));
                break;
            case OrbitAction.Resize:
                context.DrawLine(pen, new System.Windows.Point(x - 9, y + 2), new System.Windows.Point(x - 9, y + 8));
                context.DrawLine(pen, new System.Windows.Point(x - 9, y + 8), new System.Windows.Point(x - 3, y + 8));
                context.DrawLine(pen, new System.Windows.Point(x + 9, y - 2), new System.Windows.Point(x + 9, y - 8));
                context.DrawLine(pen, new System.Windows.Point(x + 9, y - 8), new System.Windows.Point(x + 3, y - 8));
                DrawArrow(context, thin, new System.Windows.Point(x - 5, y + 4), new System.Windows.Point(x + 5, y - 4));
                break;
            case OrbitAction.Rotate:
                var arc = new StreamGeometry();
                using (var figure = arc.Open())
                {
                    figure.BeginFigure(new System.Windows.Point(x - 7, y + 5), false, false);
                    figure.ArcTo(new System.Windows.Point(x + 7, y - 3), new Size(9, 9), 0, false, SweepDirection.Counterclockwise, true, false);
                }
                context.DrawGeometry(null, pen, arc);
                DrawArrowHead(context, brush, new System.Windows.Point(x + 7, y - 3), new Vector(-5, -1));
                break;
            case OrbitAction.Flip:
                context.DrawLine(thin, new System.Windows.Point(x, y - 9), new System.Windows.Point(x, y + 9));
                DrawArrow(context, pen, new System.Windows.Point(x - 2, y), new System.Windows.Point(x - 9, y));
                DrawArrow(context, pen, new System.Windows.Point(x + 2, y), new System.Windows.Point(x + 9, y));
                break;
            case OrbitAction.Grayscale:
                context.DrawEllipse(null, pen, new System.Windows.Point(x, y), 8, 8);
                var half = new StreamGeometry();
                using (var figure = half.Open())
                {
                    figure.BeginFigure(new System.Windows.Point(x, y - 8), true, true);
                    figure.ArcTo(new System.Windows.Point(x, y + 8), new Size(8, 8), 0, false, SweepDirection.Counterclockwise, true, false);
                    figure.LineTo(new System.Windows.Point(x, y - 8), true, false);
                }
                context.DrawGeometry(brush, null, half);
                break;
            case OrbitAction.Copy:
                context.DrawRoundedRectangle(null, thin, new Rect(x - 8, y - 8, 12, 14), 1.5, 1.5);
                context.DrawRoundedRectangle(null, pen, new Rect(x - 3, y - 4, 12, 14), 1.5, 1.5);
                break;
        }
    }

    private static void DrawArrow(DrawingContext context, Pen pen, System.Windows.Point from, System.Windows.Point to)
    {
        context.DrawLine(pen, from, to);
        DrawArrowHead(context, pen.Brush, to, from - to);
    }

    private static void DrawArrowHead(DrawingContext context, Brush brush, System.Windows.Point tip, Vector direction)
    {
        direction.Normalize();
        var normal = new Vector(-direction.Y, direction.X);
        var back = tip + direction * 4.2;
        var geometry = new StreamGeometry();
        using (var figure = geometry.Open())
        {
            figure.BeginFigure(tip, true, true);
            figure.LineTo(back + normal * 2.7, true, false);
            figure.LineTo(back - normal * 2.7, true, false);
        }
        context.DrawGeometry(brush, null, geometry);
    }

    private void DrawCenter(DrawingContext context)
    {
        context.DrawEllipse(new SolidColorBrush(Color.FromArgb(248, 6, 7, 18)), new Pen(new SolidColorBrush(Color.FromArgb(138, 104, 75, 230)), 5), new System.Windows.Point(Center, Center), 82, 82);
        switch (_phase)
        {
            case DisplayPhase.Ready:
                DrawBrandMark(context, Center, Center - 36);
                if (Highlighted is OrbitAction action)
                    DrawCenterLines(context, Titles[(int)action], Details[(int)action], "RELEASE TO RUN");
                else
                {
                    var type = _files.Count > 1 ? $"{_files.Count} FILES" : _files.Count == 1 ? Path.GetExtension(_files[0]).TrimStart('.').ToUpperInvariant() : "FILE";
                    var name = _files.Count > 1 ? "Batch action" : _files.Count == 1 ? Path.GetFileName(_files[0]) : "Selected file";
                    DrawCenterLines(context, type, name, "DRAG & RELEASE");
                }
                break;
            case DisplayPhase.Processing:
                DrawSpinner(context);
                DrawCenterLines(context, Titles[(int)_processingAction], "Working locally…", "KEEPING ORIGINAL SAFE", 4);
                break;
            case DisplayPhase.Success:
                DrawCheck(context, true);
                DrawCenterLines(context, "DONE", _statusMessage, "REVEALED IN EXPLORER", 4);
                break;
            case DisplayPhase.Failure:
                DrawCheck(context, false);
                DrawCenterLines(context, "NOT COMPLETED", "Check the notification", "ORIGINAL UNCHANGED", 4);
                break;
        }
    }

    private static void DrawBrandMark(DrawingContext context, double x, double y)
    {
        context.DrawEllipse(null, new Pen(new SolidColorBrush(Color.FromRgb(103, 67, 244)), 4), new System.Windows.Point(x, y), 15, 15);
        var orbit = new StreamGeometry();
        using (var figure = orbit.Open())
        {
            figure.BeginFigure(new System.Windows.Point(x + 19, y - 5), false, false);
            figure.ArcTo(new System.Windows.Point(x - 14, y + 14), new Size(20, 20), 0, true, SweepDirection.Clockwise, true, false);
        }
        context.DrawGeometry(null, new Pen(new SolidColorBrush(Lime), 2), orbit);
        context.DrawEllipse(new SolidColorBrush(Lime), null, new System.Windows.Point(x + 19, y - 5), 3.5, 3.5);
        var play = new StreamGeometry();
        using (var figure = play.Open())
        {
            figure.BeginFigure(new System.Windows.Point(x - 5, y - 7), true, true);
            figure.LineTo(new System.Windows.Point(x + 7, y), true, false);
            figure.LineTo(new System.Windows.Point(x - 5, y + 7), true, false);
        }
        context.DrawGeometry(new SolidColorBrush(Lime), null, play);
    }

    private void DrawSpinner(DrawingContext context)
    {
        var start = -90 + 360 * _pulse;
        var end = start + 245;
        var arc = new StreamGeometry();
        using (var figure = arc.Open())
        {
            figure.BeginFigure(PolarFrom(Center, Center - 34, 18, start), false, false);
            figure.ArcTo(PolarFrom(Center, Center - 34, 18, end), new Size(18, 18), 0, true, SweepDirection.Clockwise, true, false);
        }
        context.DrawGeometry(null, new Pen(new SolidColorBrush(Lime), 3.2) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round }, arc);
    }

    private static void DrawCheck(DrawingContext context, bool success)
    {
        var color = success ? Lime : Color.FromRgb(255, 108, 126);
        var pen = new Pen(new SolidColorBrush(color), 3.2) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
        if (success)
        {
            context.DrawLine(pen, new System.Windows.Point(Center - 10, Center - 35), new System.Windows.Point(Center - 2, Center - 27));
            context.DrawLine(pen, new System.Windows.Point(Center - 2, Center - 27), new System.Windows.Point(Center + 12, Center - 43));
        }
        else
        {
            context.DrawLine(pen, new System.Windows.Point(Center, Center - 45), new System.Windows.Point(Center, Center - 30));
            context.DrawEllipse(new SolidColorBrush(color), null, new System.Windows.Point(Center, Center - 23), 2.2, 2.2);
        }
    }

    private static void DrawCenterLines(DrawingContext context, string kicker, string title, string footer, double offset = 0)
    {
        DrawText(context, kicker, Center, Center + 3 + offset, 8.5, FontWeights.Bold, Lime, 116, true);
        DrawText(context, title, Center, Center + 24 + offset, 10, FontWeights.SemiBold, Colors.White, 124, false);
        DrawText(context, footer, Center, Center + 44 + offset, 6.6, FontWeights.Medium, Color.FromRgb(177, 177, 194), 118, true);
    }

    private static void DrawText(DrawingContext context, string text, double x, double y, double size, FontWeight weight, Color color, double maxWidth, bool monospace)
    {
        var family = monospace ? new FontFamily("Cascadia Mono, Consolas") : new FontFamily("Segoe UI");
        var formatted = new FormattedText(text, CultureInfo.InvariantCulture, System.Windows.FlowDirection.LeftToRight, new Typeface(family, FontStyles.Normal, weight, FontStretches.Normal), size, new SolidColorBrush(color), 1)
        {
            MaxTextWidth = maxWidth,
            MaxLineCount = 1,
            Trimming = TextTrimming.CharacterEllipsis,
            TextAlignment = TextAlignment.Center
        };
        context.DrawText(formatted, new System.Windows.Point(x - maxWidth / 2, y - formatted.Height / 2));
    }

    private static System.Windows.Point Polar(double radius, double degrees) => PolarFrom(Center, Center, radius, degrees);

    private static System.Windows.Point PolarFrom(double x, double y, double radius, double degrees)
    {
        var radians = degrees * Math.PI / 180;
        return new System.Windows.Point(x + Math.Cos(radians) * radius, y + Math.Sin(radians) * radius);
    }
}
