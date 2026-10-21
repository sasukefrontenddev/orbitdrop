using System;
using System.Runtime.InteropServices;

namespace OrbitDrop.Native;

internal sealed class GlobalInputHook : IDisposable
{
    private static readonly UIntPtr ReplayMarker = new(0x4F524249u);
    private readonly Func<System.Drawing.Point, bool> _mouseMove;
    private readonly Func<bool> _triggerDown;
    private readonly Func<bool> _triggerUp;
    private readonly Func<bool> _escape;
    private readonly NativeMethods.HookProcedure _mouseProcedure;
    private readonly NativeMethods.HookProcedure _keyboardProcedure;
    private IntPtr _mouseHook;
    private IntPtr _keyboardHook;
    internal int TriggerVirtualKey { get; set; }
    internal bool TriggerIsModifier => IsModifierVirtualKey(TriggerVirtualKey);

    internal GlobalInputHook(
        Func<System.Drawing.Point, bool> mouseMove,
        Func<bool> triggerDown,
        Func<bool> triggerUp,
        Func<bool> escape,
        int triggerVirtualKey)
    {
        _mouseMove = mouseMove;
        _triggerDown = triggerDown;
        _triggerUp = triggerUp;
        _escape = escape;
        TriggerVirtualKey = triggerVirtualKey;
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
                NativeMethods.WmMouseMove => _mouseMove(point),
                _ => false
            };
            if (handled) return new IntPtr(1);
        }
        return NativeMethods.CallNextHookEx(_mouseHook, code, message, data);
    }

    private IntPtr KeyboardCallback(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0)
        {
            var messageCode = message.ToInt32();
            var hookData = Marshal.PtrToStructure<NativeMethods.KeyboardHookData>(data);
            var virtualKey = (int)hookData.VirtualKey;
            if (hookData.ExtraInfo == ReplayMarker)
                return NativeMethods.CallNextHookEx(_keyboardHook, code, message, data);
            var handled = false;
            if (virtualKey == NativeMethods.VkEscape && messageCode == NativeMethods.WmKeyDown)
                handled = _escape();
            else if (MatchesTrigger(virtualKey) && (messageCode == NativeMethods.WmKeyDown || messageCode == NativeMethods.WmSysKeyDown))
            {
                handled = _triggerDown();
                if (TriggerIsModifier) handled = false;
            }
            else if (MatchesTrigger(virtualKey) && (messageCode == NativeMethods.WmKeyUp || messageCode == NativeMethods.WmSysKeyUp))
            {
                handled = _triggerUp();
                if (TriggerIsModifier) handled = false;
            }
            if (handled) return new IntPtr(1);
        }
        return NativeMethods.CallNextHookEx(_keyboardHook, code, message, data);
    }

    internal void ReplayTriggerTap()
    {
        if (TriggerIsModifier) return;
        var virtualKey = (byte)TriggerVirtualKey;
        var extended = IsExtendedVirtualKey(TriggerVirtualKey) ? NativeMethods.KeyEventfExtendedKey : 0u;
        NativeMethods.keybd_event(virtualKey, 0, extended, ReplayMarker);
        NativeMethods.keybd_event(virtualKey, 0, extended | NativeMethods.KeyEventfKeyUp, ReplayMarker);
    }

    private static bool IsModifierVirtualKey(int virtualKey) => virtualKey is
        (int)System.Windows.Forms.Keys.ShiftKey or
        (int)System.Windows.Forms.Keys.LShiftKey or
        (int)System.Windows.Forms.Keys.RShiftKey or
        (int)System.Windows.Forms.Keys.ControlKey or
        (int)System.Windows.Forms.Keys.LControlKey or
        (int)System.Windows.Forms.Keys.RControlKey or
        (int)System.Windows.Forms.Keys.Menu or
        (int)System.Windows.Forms.Keys.LMenu or
        (int)System.Windows.Forms.Keys.RMenu or
        (int)System.Windows.Forms.Keys.LWin or
        (int)System.Windows.Forms.Keys.RWin;

    private static bool IsExtendedVirtualKey(int virtualKey) => virtualKey is
        (int)System.Windows.Forms.Keys.Insert or
        (int)System.Windows.Forms.Keys.Delete or
        (int)System.Windows.Forms.Keys.Home or
        (int)System.Windows.Forms.Keys.End or
        (int)System.Windows.Forms.Keys.PageUp or
        (int)System.Windows.Forms.Keys.PageDown or
        (int)System.Windows.Forms.Keys.Left or
        (int)System.Windows.Forms.Keys.Right or
        (int)System.Windows.Forms.Keys.Up or
        (int)System.Windows.Forms.Keys.Down;

    private bool MatchesTrigger(int virtualKey)
    {
        if (virtualKey == TriggerVirtualKey) return true;
        return TriggerVirtualKey switch
        {
            (int)System.Windows.Forms.Keys.ShiftKey => virtualKey is (int)System.Windows.Forms.Keys.LShiftKey or (int)System.Windows.Forms.Keys.RShiftKey,
            (int)System.Windows.Forms.Keys.ControlKey => virtualKey is (int)System.Windows.Forms.Keys.LControlKey or (int)System.Windows.Forms.Keys.RControlKey,
            (int)System.Windows.Forms.Keys.Menu => virtualKey is (int)System.Windows.Forms.Keys.LMenu or (int)System.Windows.Forms.Keys.RMenu,
            _ => false
        };
    }

    public void Dispose()
    {
        if (_mouseHook != IntPtr.Zero) NativeMethods.UnhookWindowsHookEx(_mouseHook);
        if (_keyboardHook != IntPtr.Zero) NativeMethods.UnhookWindowsHookEx(_keyboardHook);
        _mouseHook = IntPtr.Zero;
        _keyboardHook = IntPtr.Zero;
    }
}
