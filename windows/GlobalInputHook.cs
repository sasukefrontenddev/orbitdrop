using System;
using System.Runtime.InteropServices;

namespace OrbitDrop.Native;

internal sealed class GlobalInputHook : IDisposable
{
    private readonly Func<System.Drawing.Point, bool> _rightDown;
    private readonly Func<System.Drawing.Point, bool> _mouseMove;
    private readonly Func<System.Drawing.Point, bool> _rightUp;
    private readonly Func<System.Drawing.Point, bool> _leftDown;
    private readonly Func<bool> _escape;
    private readonly NativeMethods.HookProcedure _mouseProcedure;
    private readonly NativeMethods.HookProcedure _keyboardProcedure;
    private IntPtr _mouseHook;
    private IntPtr _keyboardHook;

    internal GlobalInputHook(
        Func<System.Drawing.Point, bool> rightDown,
        Func<System.Drawing.Point, bool> mouseMove,
        Func<System.Drawing.Point, bool> rightUp,
        Func<System.Drawing.Point, bool> leftDown,
        Func<bool> escape)
    {
        _rightDown = rightDown;
        _mouseMove = mouseMove;
        _rightUp = rightUp;
        _leftDown = leftDown;
        _escape = escape;
        _mouseProcedure = MouseCallback;
        _keyboardProcedure = KeyboardCallback;
    }

    internal void Start()
    {
        var module = NativeMethods.CurrentModuleHandle();
        _mouseHook = NativeMethods.SetWindowsHookEx(NativeMethods.WhMouseLl, _mouseProcedure, module, 0);
        _keyboardHook = NativeMethods.SetWindowsHookEx(NativeMethods.WhKeyboardLl, _keyboardProcedure, module, 0);
        if (_mouseHook == IntPtr.Zero || _keyboardHook == IntPtr.Zero)
            throw new InvalidOperationException("OrbitDrop could not install its native input hook.");
    }

    private IntPtr MouseCallback(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0)
        {
            var hookData = Marshal.PtrToStructure<NativeMethods.MouseHookData>(data);
            var point = new System.Drawing.Point(hookData.Point.X, hookData.Point.Y);
            var handled = message.ToInt32() switch
            {
                NativeMethods.WmRightButtonDown => _rightDown(point),
                NativeMethods.WmMouseMove => _mouseMove(point),
                NativeMethods.WmRightButtonUp => _rightUp(point),
                NativeMethods.WmLeftButtonDown => _leftDown(point),
                _ => false
            };
            if (handled) return new IntPtr(1);
        }
        return NativeMethods.CallNextHookEx(_mouseHook, code, message, data);
    }

    private IntPtr KeyboardCallback(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0 && message.ToInt32() == NativeMethods.WmKeyDown && Marshal.ReadInt32(data) == NativeMethods.VkEscape && _escape())
            return new IntPtr(1);
        return NativeMethods.CallNextHookEx(_keyboardHook, code, message, data);
    }

    public void Dispose()
    {
        if (_mouseHook != IntPtr.Zero) NativeMethods.UnhookWindowsHookEx(_mouseHook);
        if (_keyboardHook != IntPtr.Zero) NativeMethods.UnhookWindowsHookEx(_keyboardHook);
        _mouseHook = IntPtr.Zero;
        _keyboardHook = IntPtr.Zero;
    }
}
