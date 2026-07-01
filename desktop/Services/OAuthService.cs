using System.Diagnostics;
using System.Net;
using System.Web;

namespace BlameTheGuilty.Desktop.Services;

public class OAuthResult
{
    public long Id { get; set; }
    public string Username { get; set; } = string.Empty;
}

public class OAuthService
{
    private readonly string _backendUrl;

    public OAuthService(string backendUrl)
    {
        _backendUrl = backendUrl.TrimEnd('/');
    }

    public async Task<OAuthResult?> LoginAsync()
    {
        var listener = new HttpListener();
        var port = GetRandomAvailablePort();
        listener.Prefixes.Add($"http://localhost:{port}/");
        listener.Start();

        var redirectUri = $"http://localhost:{port}/callback";
        var loginUrl = $"{_backendUrl}/api/auth/login?redirect_uri={Uri.EscapeDataString(redirectUri)}";

        Process.Start(new ProcessStartInfo
        {
            FileName = loginUrl,
            UseShellExecute = true
        });

        var tcs = new TaskCompletionSource<OAuthResult?>();
        await ListenForCallbackAsync(listener, tcs);

        var result = await tcs.Task;
        listener.Stop();
        return result;
    }

    private static async Task ListenForCallbackAsync(HttpListener listener, TaskCompletionSource<OAuthResult?> tcs)
    {
        try
        {
            var context = await listener.GetContextAsync();
            var request = context.Request;
            var response = context.Response;

            var idStr = request.QueryString["id"];
            var username = request.QueryString["username"];

            if (!string.IsNullOrEmpty(idStr) && !string.IsNullOrEmpty(username))
            {
                var result = new OAuthResult
                {
                    Id = long.Parse(idStr),
                    Username = HttpUtility.UrlDecode(username)
                };

                var responseBytes = System.Text.Encoding.UTF8.GetBytes(
                    "<html><body><h1>Authentication successful!</h1><p>You can close this window.</p></body></html>");
                response.ContentType = "text/html; charset=utf-8";
                await response.OutputStream.WriteAsync(responseBytes);
                response.OutputStream.Close();

                tcs.TrySetResult(result);
            }
            else
            {
                var responseBytes = System.Text.Encoding.UTF8.GetBytes(
                    "<html><body><h1>Authentication failed.</h1></body></html>");
                response.ContentType = "text/html; charset=utf-8";
                await response.OutputStream.WriteAsync(responseBytes);
                response.OutputStream.Close();

                tcs.TrySetResult(null);
            }
        }
        catch (Exception ex)
        {
            tcs.TrySetException(ex);
        }
    }

    private static int GetRandomAvailablePort()
    {
        var listener = new System.Net.Sockets.TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;
        listener.Stop();
        return port;
    }
}
