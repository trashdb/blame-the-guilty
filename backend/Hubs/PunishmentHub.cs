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

    public async Task RegisterConnection(long gitHubId)
    {
        var user = await _db.GitHubUsers
            .FirstOrDefaultAsync(u => u.GitHubId == gitHubId);

        if (user != null)
        {
            user.SignalRConnectionId = Context.ConnectionId;
            user.LastLoginAt = DateTime.UtcNow;
            await _db.SaveChangesAsync();
        }

        // Group by GitHubId for targeted messaging
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
