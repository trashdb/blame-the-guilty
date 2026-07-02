using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace BlameTheGuilty.Desktop.Services;

public static class NotificationService
{
    public static void ShowPunishmentNotification(JsonElement data)
    {
        var culprit = data.GetProperty("culprit").GetString() ?? "unknown";
        var repo = data.TryGetProperty("repo", out var r) ? r.GetString() : "unknown";
        var runId = data.TryGetProperty("runId", out var rid) ? rid.GetInt64() : 0;

        var title = $"\u26a0\ufe0f Blame the Guilty";
        var message = $"{culprit} merged a failing workflow in {repo}";
        var subtitle = $"Run #{runId}";

        Show(title, message, subtitle);
    }

    public static void Show(string title, string message, string? subtitle = null)
    {
        try
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
                ShowMacOS(title, message, subtitle);
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
                ShowLinux(title, message);
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                ShowWindows(title, message);
        }
        catch
        {
            // Notifications are non-critical; fail silently
        }
    }

    private static void ShowMacOS(string title, string message, string? subtitle)
    {
        var escapedMessage = message.Replace("\"", "\\\"");
        var escapedTitle = title.Replace("\"", "\\\"");

        var script = $"display notification \"{escapedMessage}\" with title \"{escapedTitle}\" sound name \"default\"";
        if (!string.IsNullOrEmpty(subtitle))
        {
            var escapedSubtitle = subtitle.Replace("\"", "\\\"");
            script += $" subtitle \"{escapedSubtitle}\"";
        }

        var psi = new ProcessStartInfo("osascript")
        {
            UseShellExecute = false,
            CreateNoWindow = true
        };
        psi.ArgumentList.Add("-e");
        psi.ArgumentList.Add(script);
        Process.Start(psi);
    }

    private static void ShowLinux(string title, string message)
    {
        var psi = new ProcessStartInfo("notify-send")
        {
            UseShellExecute = false,
            CreateNoWindow = true
        };
        psi.ArgumentList.Add(title);
        psi.ArgumentList.Add(message);
        Process.Start(psi);
    }

    private static void ShowWindows(string title, string message)
    {
        var psi = new ProcessStartInfo("powershell")
        {
            UseShellExecute = false,
            CreateNoWindow = true
        };
        psi.ArgumentList.Add("-NoProfile");
        psi.ArgumentList.Add("-Command");
        psi.ArgumentList.Add($@"
$toast = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime];
$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02);
$textNodes = $template.GetElementsByTagName('text');
$textNodes.Item(0).AppendChild($template.CreateTextNode('{title.Replace("'", "''")}'));
$textNodes.Item(1).AppendChild($template.CreateTextNode('{message.Replace("'", "''")}'));
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Blame the Guilty').Show($toast);
");
        Process.Start(psi);
    }
}
