using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using BlameTheGuilty.Api.Data;
using BlameTheGuilty.Api.Models;

namespace BlameTheGuilty.Api.Controllers;

[ApiController]
[Route("api/punishments")]
public class PunishmentsController : ControllerBase
{
    private readonly AppDbContext _db;

    public PunishmentsController(AppDbContext db)
    {
        _db = db;
    }

    [HttpGet]
    public async Task<IActionResult> GetRecent([FromQuery] int days = 7, [FromQuery] int limit = 50)
    {
        var since = DateTime.UtcNow.AddDays(-days);

        var events = await _db.PunishmentEvents
            .Where(e => e.OccurredAt >= since)
            .OrderByDescending(e => e.OccurredAt)
            .Take(limit)
            .Select(e => new
            {
                e.RunId,
                e.CulpritLogin,
                e.RepoFullName,
                e.WorkflowName,
                e.WorkflowUrl,
                e.OccurredAt,
                e.WasNotified
            })
            .ToListAsync();

        return Ok(events);
    }
}
