using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace OrbitDrop.Native;

internal static class NativeMethods
{
    internal const int WhMouseLl = 14;
    internal const int WhKeyboardLl = 13;
    internal const int WmMouseMove = 0x0200;
    internal const int WmLeftButtonDown = 0x0201;
    internal const int WmRightButtonDown = 0x0204;
    internal const int WmRightButtonUp = 0x0205;
    internal const int WmKeyDown = 0x0100;
    internal const int WmKeyUp = 0x0101;
    internal const int WmSysKeyDown = 0x0104;
    internal const int WmSysKeyUp = 0x0105;
    internal const int VkEscape = 0x1B;
    internal const int GwlExStyle = -20;
    internal const int WsExToolWindow = 0x00000080;
    internal const int WsExNoActivate = 0x08000000;
    internal const uint GaRoot = 2;

    [StructLayout(LayoutKind.Sequential)]
    internal struct Point
    {
        internal int X;
        internal int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct MouseHookData
    {
        internal Point Point;
        internal uint MouseData;
        internal uint Flags;
        internal uint Time;
        internal UIntPtr ExtraInfo;
    }

    internal delegate IntPtr HookProcedure(int code, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    internal static extern IntPtr SetWindowsHookEx(int idHook, HookProcedure procedure, IntPtr module, uint threadId);

    [DllImport("user32.dll")]
    internal static extern bool UnhookWindowsHookEx(IntPtr hook);

    [DllImport("user32.dll")]
    internal static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    internal static extern IntPtr GetModuleHandle(string? moduleName);

    [DllImport("user32.dll")]
    internal static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    internal static extern int GetClassName(IntPtr window, StringBuilder className, int capacity);

    [DllImport("user32.dll")]
    internal static extern IntPtr GetAncestor(IntPtr window, uint flags);

    [DllImport("user32.dll")]
    internal static extern bool SetProcessDpiAwarenessContext(IntPtr value);

    [DllImport("user32.dll")]
    internal static extern uint GetDpiForSystem();

    [DllImport("user32.dll")]
    internal static extern int GetWindowLong(IntPtr window, int index);

    [DllImport("user32.dll")]
    internal static extern int SetWindowLong(IntPtr window, int index, int value);

    internal static IntPtr CurrentModuleHandle()
    {
        using var process = Process.GetCurrentProcess();
        return GetModuleHandle(process.MainModule?.ModuleName);
    }
}
