using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using BlameTheGuilty.Api.Data;

namespace BlameTheGuilty.Api.Hubs;

public class PunishmentHub : Hub
{
    private readonly AppDbContext _db;

    public PunishmentHub(AppDbContext db)
    {
        _db = db;
    }

    public async Task RegisterConnection(long gitHubId, string? username = null)
    {
        var user = await _db.GitHubUsers
            .FirstOrDefaultAsync(u => u.GitHubId == gitHubId);

        if (user != null)
        {
            user.SignalRConnectionId = Context.ConnectionId;
            user.LastLoginAt = DateTime.UtcNow;
            if (!string.IsNullOrEmpty(username)) user.GitHubUsername = username;
        }
        else
        {
            _db.GitHubUsers.Add(new Models.GitHubUser
            {
                GitHubId = gitHubId,
                GitHubUsername = username ?? $"user_{gitHubId}",
                CreatedAt = DateTime.UtcNow,
                LastLoginAt = DateTime.UtcNow,
                SignalRConnectionId = Context.ConnectionId
            });
        }

        await _db.SaveChangesAsync();
        await Groups.AddToGroupAsync(Context.ConnectionId, gitHubId.ToString());
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        var user = await _db.GitHubUsers
            .FirstOrDefaultAsync(u => u.SignalRConnectionId == Context.ConnectionId);

        if (user != null)
        {
            user.SignalRConnectionId = null;
            await _db.SaveChangesAsync();
        }

        await base.OnDisconnectedAsync(exception);
    }
}
