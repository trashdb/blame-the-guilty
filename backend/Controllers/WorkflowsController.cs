using System.Net.Http.Headers;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using BlameTheGuilty.Api.Data;
using BlameTheGuilty.Api.Hubs;
using BlameTheGuilty.Api.Models;

namespace BlameTheGuilty.Api.Controllers;

[ApiController]
[Route("api/workflows")]
public class WorkflowsController : ControllerBase
{
    private static readonly HashSet<string> IgnoredWorkflows = new(StringComparer.OrdinalIgnoreCase)
    {
        "CodeQL High Severity",
        "Dependency Review",
        "Label PR by Team Member",
        "Verify ForgeRock Secrets"
    };

    private static readonly HttpClient _githubClient = new();

    private readonly IHubContext<PunishmentHub> _hubContext;
    private readonly AppDbContext _db;
    private readonly ILogger<WorkflowsController> _logger;
    private readonly IConfiguration _configuration;

    public WorkflowsController(IHubContext<PunishmentHub> hubContext, AppDbContext db, ILogger<WorkflowsController> logger, IConfiguration configuration)
    {
        _hubContext = hubContext;
        _db = db;
        _logger = logger;
        _configuration = configuration;
    }

    [HttpGet("runs")]
    public async Task<IActionResult> GetRuns(
        [FromQuery] long gitHubId,
        [FromQuery] int limit = 20)
    {
        var myRuns = await _db.WorkflowRuns
            .Where(w => w.GitHubId == gitHubId && !IgnoredWorkflows.Contains(w.WorkflowName))
            .OrderByDescending(w => w.Id)
            .Take(limit)
            .ToListAsync();

        var targetRuns = await _db.WorkflowRuns
            .Where(w => w.GitHubId != gitHubId && w.TargetGitHubIds != null && !IgnoredWorkflows.Contains(w.WorkflowName))
            .OrderByDescending(w => w.Id)
            .Take(limit * 2)
            .ToListAsync();

        var filteredTargetRuns = targetRuns
            .Where(w => DeserializeIds(w.TargetGitHubIds).Contains(gitHubId))
            .Take(limit)
            .ToList();

        var runs = myRuns.Concat(filteredTargetRuns)
            .DistinctBy(w => w.Id)
            .OrderByDescending(w => w.Id)
            .Take(limit)
            .ToList();

        // Look up PRs matching each run's repo+branch
        var branchKeys = runs
            .Where(r => r.HeadBranch != null)
            .Select(r => new { r.Repo, r.HeadBranch })
            .Distinct()
            .ToList();
        var prs = new List<(string repo, string branch, long prNumber, string title)>();
        if (branchKeys.Count != 0)
        {
            var repoList = branchKeys.Select(b => b.Repo).ToList();
            var branchList = branchKeys.Select(b => b.HeadBranch!).ToList();
            var prEvents = await _db.PullRequestEvents
                .Where(e => e.Status == "open" && repoList.Contains(e.RepoFullName) && branchList.Contains(e.HeadBranch))
                .Select(e => new { e.RepoFullName, e.HeadBranch, e.PrNumber, e.Title })
                .ToListAsync();
            prs = prEvents
                .Where(e => e.HeadBranch != null)
                .Select(e => (e.RepoFullName, e.HeadBranch!, e.PrNumber, e.Title ?? ""))
                .ToList();
        }

        return Ok(runs.Select(w => new
        {
            w.Id,
            w.RunId,
            w.WorkflowName,
            w.Repo,
            w.Actor,
            w.HeadBranch,
            w.Trigger,
            w.Status,
            w.HtmlUrl,
            w.StartedAt,
            TargetGitHubIds = DeserializeIds(w.TargetGitHubIds),
            PrNumber = w.HeadBranch != null
                ? (int?)prs.FirstOrDefault(p => p.repo == w.Repo && p.branch == w.HeadBranch).prNumber
                : null,
            PrTitle = w.HeadBranch != null
                ? prs.FirstOrDefault(p => p.repo == w.Repo && p.branch == w.HeadBranch).title
                : null
        }));
    }

    [HttpPut("runs/{id}/target")]
    public async Task<IActionResult> SetTarget(int id, [FromBody] SetTargetRequest request)
    {
        var run = await _db.WorkflowRuns
            .Where(w => w.Id == id)
            .FirstOrDefaultAsync();

        if (run == null)
            return NotFound("Workflow run not found.");

        run.TargetGitHubIds = SerializeIds(request.TargetGitHubIds);
        await _db.SaveChangesAsync();

        return Ok(new { runId = run.RunId, targetGitHubIds = DeserializeIds(run.TargetGitHubIds) });
    }

    [HttpPost("runs/{runId}/rerun")]
    public async Task<IActionResult> RerunRun(long runId, [FromQuery] long gitHubId)
    {
        var run = await _db.WorkflowRuns
            .Where(w => w.RunId == runId)
            .OrderByDescending(w => w.Id)
            .FirstOrDefaultAsync();
        if (run == null)
            return NotFound("Workflow run not found.");

        var user = await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == gitHubId);
        var token = user?.AccessToken;
        if (string.IsNullOrEmpty(token))
            token = _configuration["GitHub:PatToken"];
        if (string.IsNullOrEmpty(token))
            return Unauthorized("No access token available.");

        var request = new HttpRequestMessage(HttpMethod.Post,
            $"https://api.github.com/repos/{run.Repo}/actions/runs/{run.RunId}/rerun");
        request.Headers.UserAgent.ParseAdd("BlameTheGuilty");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github.v3+json"));

        var response = await _githubClient.SendAsync(request);
        if (!response.IsSuccessStatusCode)
        {
            var body = await response.Content.ReadAsStringAsync();
            _logger.LogWarning("GitHub rerun failed: {Status} {Body}", response.StatusCode, body);
            return StatusCode((int)response.StatusCode, body);
        }

        // Create an in_progress record immediately so syncFromApi picks it up
        var newRun = new WorkflowRun
        {
            RunId = run.RunId,
            GitHubId = gitHubId,
            WorkflowName = run.WorkflowName,
            Repo = run.Repo,
            Actor = run.Actor,
            HeadBranch = run.HeadBranch,
            Trigger = "workflow_dispatch",
            HtmlUrl = run.HtmlUrl,
            Status = "in_progress",
            StartedAt = DateTime.UtcNow
        };
        _db.WorkflowRuns.Add(newRun);
        await _db.SaveChangesAsync();

        await _hubContext.Clients.Group(gitHubId.ToString()).SendAsync("WorkflowRunStarted", new
        {
            id = newRun.Id,
            runId = newRun.RunId,
            workflowName = newRun.WorkflowName,
            repo = newRun.Repo,
            branch = newRun.HeadBranch,
            trigger = newRun.Trigger,
            actor = newRun.Actor,
            htmlUrl = newRun.HtmlUrl
        });

        await _hubContext.Clients.All.SendAsync("PullRequestsUpdated");

        return Ok(new { rerun = true });
    }

    private static string? SerializeIds(long[]? ids) =>
        ids is { Length: > 0 } ? JsonSerializer.Serialize(ids) : null;

    private static long[] DeserializeIds(string? raw) =>
        raw is { Length: > 0 } && JsonSerializer.Deserialize<long[]>(raw) is { } arr ? arr : [];

    public class SetTargetRequest
    {
        public long[]? TargetGitHubIds { get; set; }
    }
}

[ApiController]
[Route("api/users")]
public class UsersController : ControllerBase
{
    private readonly AppDbContext _db;

    public UsersController(AppDbContext db)
    {
        _db = db;
    }

    [HttpGet]
    public async Task<IActionResult> GetUsers()
    {
        var users = await _db.GitHubUsers
            .Select(u => new
            {
                u.GitHubId,
                Login = u.GitHubUsername
            })
            .ToListAsync();

        return Ok(users);
    }
}
