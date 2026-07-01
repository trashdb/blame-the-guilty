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

    private void ForceForeground()
    {
        Topmost = true;
        WindowState = WindowState.Maximized;
        Activate();
        RedemptionText.Focus();
    }

    private void Window_Closing(object? sender, WindowClosingEventArgs e)
    {
        // Do not allow closing unless CloseByRedemption flag was set
        if (!_redeemed)
            e.Cancel = true;
    }

    private bool _redeemed;

    private void Window_Deactivated(object? sender, EventArgs e)
    {
        Dispatcher.UIThread.Post(() =>
        {
            Topmost = true;
            WindowState = WindowState.Maximized;
            Activate();
        });
    }

    private void RedemptionText_KeyDown(object? sender, KeyEventArgs e)
    {
        // Block Alt+F4
        if (e.Key == Key.F4 && (e.KeyModifiers & KeyModifiers.Alt) == KeyModifiers.Alt)
            e.Handled = true;

        // Block paste (Ctrl+V / Cmd+V)
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
}
