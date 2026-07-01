using System.Text.Json;
using Microsoft.AspNetCore.SignalR.Client;

namespace BlameTheGuilty.Desktop.Services;

public class SignalRService
{
    private readonly string _hubUrl;
    private HubConnection? _connection;

    public event Action<JsonElement>? OnPunishmentTriggered;
    public event Action<string>? OnConnectionStateChanged;

    public bool IsConnected => _connection?.State == HubConnectionState.Connected;

    public SignalRService(string backendUrl)
    {
        _hubUrl = $"{backendUrl.TrimEnd('/')}/hub/punishment";
    }

    public async Task ConnectAsync(long gitHubId)
    {
        _connection = new HubConnectionBuilder()
            .WithUrl(_hubUrl)
            .WithAutomaticReconnect()
            .Build();

        _connection.On<JsonElement>("TriggerPunishment", data =>
        {
            OnPunishmentTriggered?.Invoke(data);
        });

        _connection.Reconnecting += _ =>
        {
            OnConnectionStateChanged?.Invoke("Reconnecting...");
            return Task.CompletedTask;
        };

        _connection.Reconnected += _ =>
        {
            OnConnectionStateChanged?.Invoke("Connected");
            return _connection.InvokeAsync("RegisterConnection", gitHubId);
        };

        _connection.Closed += _ =>
        {
            OnConnectionStateChanged?.Invoke("Disconnected");
            return Task.CompletedTask;
        };

        await _connection.StartAsync();
        await _connection.InvokeAsync("RegisterConnection", gitHubId);

        OnConnectionStateChanged?.Invoke("Connected");
    }

    public async Task DisconnectAsync()
    {
        if (_connection != null)
        {
            await _connection.StopAsync();
            await _connection.DisposeAsync();
            _connection = null;
        }
    }
}
