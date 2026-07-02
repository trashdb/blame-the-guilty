using System.Runtime.InteropServices;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;

namespace BlameTheGuilty.Desktop;

public partial class ToastWindow : Window
{
    private bool _acknowledged;

    public ToastWindow()
    {
        InitializeComponent();
    }

    public ToastWindow(string culprit, string repo, long runId) : this()
    {
        MessageText.Text = $"@{culprit} merged a failing workflow";
        DetailsText.Text = $"{(repo ?? "unknown")} \u00b7 run #{runId}";

        Loaded += (_, _) =>
        {
            PositionWindow();
            ForceForeground();
        };
    }

    private void PositionWindow()
    {
        if (Screens.Primary is { } screen)
        {
            var wa = screen.WorkingArea;
            Position = new PixelPoint(
                wa.X + wa.Width - (int)Width - 20,
                wa.Y + 40
            );
        }
    }

    private void DismissButton_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        _acknowledged = true;
        Close();
    }

    private void Window_Closing(object? sender, WindowClosingEventArgs e)
    {
        if (!_acknowledged)
            e.Cancel = true;
    }

    private void Window_Activated(object? sender, EventArgs e)
    {
        Topmost = true;
    }

    private void Window_Deactivated(object? sender, EventArgs e)
    {
        Topmost = true;
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            _acknowledged = true;
            Close();
            e.Handled = true;
            return;
        }
        base.OnKeyDown(e);
    }

    private void ForceForeground()
    {
        Topmost = true;

        if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            MakeKeyAndOrderFrontNative();
        else
            Activate();
    }

    private void MakeKeyAndOrderFrontNative()
    {
        try
        {
            var handle = TryGetPlatformHandle();
            if (handle == null || handle.Handle == IntPtr.Zero) return;

            var nsWindow = handle.Handle;

            objc_msgSend(nsWindow, sel_registerName("makeKeyAndOrderFront:"), IntPtr.Zero);
            objc_msgSend(nsWindow, sel_registerName("setLevel:"), (IntPtr)1000);
            objc_msgSend(nsWindow, sel_registerName("setCollectionBehavior:"), (IntPtr)257);
        }
        catch
        {
            Activate();
        }
    }

    [DllImport("/usr/lib/libobjc.dylib")]
    private static extern IntPtr objc_msgSend(IntPtr receiver, IntPtr selector, IntPtr arg);

    [DllImport("/usr/lib/libobjc.dylib")]
    private static extern IntPtr sel_registerName(string name);
}
