using System.Text.Json;
using Avalonia.Controls;
using Avalonia.Threading;
using BlameTheGuilty.Desktop.Services;

namespace BlameTheGuilty.Desktop;

public partial class MainWindow : Window
{
    private const string BackendUrl = "https://moonlike-silenced-sprung.ngrok-free.dev";

    private readonly OAuthService _oauth;
    private readonly SignalRService _signalR;
    private long _gitHubId;

    public MainWindow()
    {
        InitializeComponent();

        _oauth = new OAuthService(BackendUrl);
        _signalR = new SignalRService(BackendUrl);

        _signalR.OnPunishmentTriggered += OnPunishmentTriggered;
        _signalR.OnConnectionStateChanged += state =>
        {
            Dispatcher.UIThread.Post(() => ConnectionText.Text = state);
        };
    }

    private async void LoginButton_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        LoginButton.IsEnabled = false;
        StatusText.Text = "Logging in...";
        StatusText.Foreground = Avalonia.Media.Brushes.Orange;

        try
        {
            var result = await _oauth.LoginAsync();

            if (result == null)
            {
                StatusText.Text = "Authentication failed";
                StatusText.Foreground = Avalonia.Media.Brushes.Red;
                return;
            }

            _gitHubId = result.Id;
            UserText.Text = result.Username;
            StatusText.Text = "Authenticated";
            StatusText.Foreground = Avalonia.Media.Brushes.Green;

            await _signalR.ConnectAsync(_gitHubId);
        }
        catch (Exception ex)
        {
            StatusText.Text = $"Error: {ex.Message}";
            StatusText.Foreground = Avalonia.Media.Brushes.Red;
        }
        finally
        {
            LoginButton.IsEnabled = _signalR.IsConnected;
        }
    }

    private void OnPunishmentTriggered(JsonElement data)
    {
        Dispatcher.UIThread.Post(() =>
            NotificationService.ShowPunishmentNotification(data)
        );
    }

    protected override void OnClosing(WindowClosingEventArgs e)
    {
        _ = _signalR.DisconnectAsync();
        base.OnClosing(e);
    }
}
