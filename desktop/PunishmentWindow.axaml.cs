using System.Runtime.InteropServices;
using System.Text.Json;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Threading;

namespace BlameTheGuilty.Desktop;

public partial class PunishmentWindow : Window
{
    private const string MagicPhrase = "Prometo correr los tests en local antes de mergear";

    public PunishmentWindow()
    {
        InitializeComponent();
        Loaded += (_, _) => ForceForeground();
    }

    public PunishmentWindow(JsonElement data) : this()
    {
        var culprit = data.GetProperty("culprit").GetString();
        var repo = data.TryGetProperty("repo", out var r) ? r.GetString() : "unknown";
        var runId = data.TryGetProperty("runId", out var rid) ? rid.GetInt64() : 0;

        DetailsText.Text = $"@{culprit} \u00b7 {repo} \u00b7 run #{runId}";
    }

    private async void ForceForeground()
    {
        Topmost = true;
        // Small delay to ensure native window handle is ready
        await Task.Delay(100);
        MakeKeyAndOrderFrontNative();
        RedemptionText.Focus();
    }

    private void Window_Activated(object? sender, EventArgs e)
    {
        Topmost = true;
        RedemptionText.Focus();
    }

    private async void Window_Deactivated(object? sender, EventArgs e)
    {
        await Task.Delay(50);
        Dispatcher.UIThread.Post(() =>
        {
            Topmost = true;
            MakeKeyAndOrderFrontNative();
        });
    }

    private void MakeKeyAndOrderFrontNative()
    {
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
        {
            Activate();
            return;
        }

        try
        {
            var handle = TryGetPlatformHandle();
            if (handle == null || handle.Handle == IntPtr.Zero) return;

            var nsWindow = handle.Handle;

            // Make key and order front (bring to front and focus)
            _ = objc_msgSend(nsWindow, sel_registerName("makeKeyAndOrderFront:"), IntPtr.Zero);

            // Set level to NSScreenSaverWindowLevel (1000) — above everything
            _ = objc_msgSend(nsWindow, sel_registerName("setLevel:"), (IntPtr)1000);

            // Appear in all spaces and over full-screen apps
            // NSWindowCollectionBehaviorCanJoinAllSpaces (1) | NSWindowCollectionBehaviorFullScreenAuxiliary (256)
            _ = objc_msgSend(nsWindow, sel_registerName("setCollectionBehavior:"), (IntPtr)257);
        }
        catch
        {
            Activate();
        }
    }

    private void Window_Closing(object? sender, WindowClosingEventArgs e)
    {
        if (!_redeemed)
            e.Cancel = true;
    }

    private bool _redeemed;

    private void RedemptionText_KeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key == Key.F4 && (e.KeyModifiers & KeyModifiers.Alt) == KeyModifiers.Alt)
            e.Handled = true;

        if (e.Key == Key.V && (e.KeyModifiers & (KeyModifiers.Control | KeyModifiers.Meta)) != 0)
            e.Handled = true;
    }

    private void RedemptionText_KeyUp(object? sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter) return;

        if (RedemptionText.Text?.Trim() == MagicPhrase)
        {
            _redeemed = true;
            Close();
        }
        else
        {
            ErrorText.Text = "\u274c Frase incorrecta. Vuelve a intentarlo.";
            RedemptionText.Clear();
            RedemptionText.Focus();
        }
    }

    // Native macOS Objective-C interop
    [DllImport("/usr/lib/libobjc.dylib")]
    private static extern IntPtr objc_msgSend(IntPtr receiver, IntPtr selector, IntPtr arg);

    [DllImport("/usr/lib/libobjc.dylib")]
    private static extern IntPtr sel_registerName(string name);
}
