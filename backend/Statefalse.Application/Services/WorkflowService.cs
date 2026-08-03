using Microsoft.EntityFrameworkCore;
using Statefalse.Domain.Contracts;
using Statefalse.Application;
using Statefalse.Domain.Models;

namespace Statefalse.Application;

/// <summary>
/// Workflow run queries + rerun/sync/target operations.
/// </summary>
public class WorkflowService
{
    private readonly IAppDbContext _db;
    private readonly IGitHubClient _github;
    private readonly IGitHubTokenResolver _tokens;
    private readonly ISignalRNotifier _notifier;
    private readonly ILogger<WorkflowService> _logger;

    public WorkflowService(
        IAppDbContext db,
        IGitHubClient github,
        IGitHubTokenResolver tokens,
        ISignalRNotifier notifier,
        ILogger<WorkflowService> logger)
    {
        _db = db;
        _github = github;
        _tokens = tokens;
        _notifier = notifier;
        _logger = logger;
    }

    public async Task<ApiResult> GetRunsAsync(long gitHubId, int limit)
    {
        // Get PRs user is subscribed to (including authored)
        var subscribedPrs = await _db.PullRequestEvents
            .Where(e => e.Status == "open"
                && (e.AuthorGitHubId == gitHubId
                    || (e.SubscriberIds != null && e.SubscriberIds.Contains(gitHubId.ToString()))))
            .Select(e => new { e.RepoFullName, e.HeadBranch })
            .Distinct()
            .ToListAsync();

        var subscribedRepoBranches = subscribedPrs
            .Select(p => (p.RepoFullName, p.HeadBranch))
            .Where(p => !string.IsNullOrEmpty(p.HeadBranch))
            .ToList();

        var myRuns = await _db.WorkflowRuns
            .Where(w => w.GitHubId == gitHubId && !w.IsIgnored)
            .OrderByDescending(w => w.Id)
            .Take(limit)
            .ToListAsync();

        var targetRuns = await _db.WorkflowRuns
            .Where(w => w.GitHubId != gitHubId && w.TargetGitHubIds != null && !w.IsIgnored)
            .OrderByDescending(w => w.Id)
            .Take(limit * 2)
            .ToListAsync();

        var filteredTargetRuns = targetRuns
            .Where(w => IdListSerializer.Deserialize(w.TargetGitHubIds).Contains(gitHubId))
            .Take(limit)
            .ToList();

        // Get runs from PRs user is subscribed to (but not already in myRuns/targetRuns)
        var subscribedRuns = new List<WorkflowRun>();
        if (subscribedRepoBranches.Count > 0)
        {
            var repoBranches = subscribedRepoBranches.ToList();
            subscribedRuns = await _db.WorkflowRuns
                .Where(w => !w.IsIgnored
                    && w.GitHubId != gitHubId
                    && repoBranches.Any(rb => rb.RepoFullName == w.Repo && rb.HeadBranch == w.HeadBranch))
                .OrderByDescending(w => w.Id)
                .Take(limit)
                .ToListAsync();
        }

        var allRuns = myRuns.Concat(filteredTargetRuns).Concat(subscribedRuns)
            .DistinctBy(w => w.Id)
            .OrderByDescending(w => w.Id)
            .Take(limit)
            .ToList();

        // Look up PRs matching each run's repo+branch
        var branchKeys = allRuns
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
                .Where(e => e.Status == "open" && repoList.Contains(e.RepoFullName) && e.HeadBranch != null && branchList.Contains(e.HeadBranch))
                .Select(e => new { e.RepoFullName, e.HeadBranch, e.PrNumber, e.Title })
                .ToListAsync();
            prs = prEvents
                .Where(e => e.HeadBranch != null)
                .Select(e => (e.RepoFullName, e.HeadBranch!, e.PrNumber, e.Title ?? ""))
                .ToList();
        }

        return ApiResult.Ok(allRuns.Select(w => new WorkflowRunDto(
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
            IdListSerializer.Deserialize(w.TargetGitHubIds),
            w.HeadBranch != null
                ? (int?)prs.FirstOrDefault(p => p.repo == w.Repo && p.branch == w.HeadBranch).prNumber
                : null,
            w.HeadBranch != null
                ? prs.FirstOrDefault(p => p.repo == w.Repo && p.branch == w.HeadBranch).title
                : null)));
    }

    public async Task<ApiResult> SetTargetAsync(int id, SetTargetRequest request)
    {
        var run = await _db.WorkflowRuns
            .Where(w => w.Id == id)
            .FirstOrDefaultAsync();

        if (run == null)
            return ApiResult.NotFound("Workflow run not found.");

        run.TargetGitHubIds = IdListSerializer.Serialize(request.TargetGitHubIds ?? []);
        await _db.SaveChangesAsync();

        return ApiResult.Ok(new { runId = run.RunId, targetGitHubIds = IdListSerializer.Deserialize(run.TargetGitHubIds) });
    }

    public async Task<ApiResult> RerunAsync(long runId, long gitHubId)
    {
        var run = await _db.WorkflowRuns
            .Where(w => w.RunId == runId)
            .OrderByDescending(w => w.Id)
            .FirstOrDefaultAsync();
        if (run == null)
            return ApiResult.NotFound("Workflow run not found.");

        var token = await _tokens.ResolveAsync(gitHubId);
        if (string.IsNullOrEmpty(token))
            return ApiResult.Unauthorized("No access token available.");

        var response = await _github.PostAsync($"/repos/{run.Repo}/actions/runs/{run.RunId}/rerun", token, new { });
        if (response.StatusCode == 0)
            return ApiResult.FromGitHubStatus(0, "GitHub API unreachable");
        if (response.StatusCode is < 200 or >= 300)
        {
            _logger.LogWarning("GitHub rerun failed: {Status} {Body}", response.StatusCode, response.Body?.GetRawText());
            return ApiResult.FromGitHubStatus(response.StatusCode, response.Body?.GetRawText() ?? "Rerun failed");
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

        await _notifier.NotifyUserAsync(gitHubId, "WorkflowRunStarted", new
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

        await _notifier.NotifyPullRequestsUpdatedAsync();

        return ApiResult.Ok(new { rerun = true });
    }

    public async Task<ApiResult> SyncActiveAsync(long gitHubId)
    {
        var token = await _tokens.ResolveAsync(gitHubId);
        if (string.IsNullOrEmpty(token))
            return ApiResult.Unauthorized("No access token available.");

        var repos = await _db.PullRequestEvents
            .Where(e => e.Status == "open")
            .Select(e => e.RepoFullName)
            .Distinct()
            .ToListAsync();

        if (repos.Count == 0)
            return ApiResult.Ok(new { synced = 0, repos = 0, message = "No active PRs found." });

        var newCount = 0;
        foreach (var repo in repos)
        {
            var response = await _github.GetAsync($"/repos/{repo}/actions/runs?status=in_progress&per_page=10", token);
            if (response.StatusCode is < 200 or >= 300 || response.Body is not { } doc) continue;

            foreach (var run in doc.GetProperty("workflow_runs").EnumerateArray())
            {
                var runId = run.GetProperty("id").GetInt64();
                var name = run.TryGetProperty("name", out var wn) ? wn.GetString() : "Workflow";
                var isIgnored = IgnoredWorkflows.IsIgnored(name);

                var exists = await _db.WorkflowRuns.AnyAsync(w => w.RunId == runId && w.Status == "in_progress");
                if (exists) continue;

                var actor = run.TryGetProperty("actor", out var act)
                    ? act.GetProperty("login").GetString() ?? "unknown"
                    : "unknown";
                var branch = run.TryGetProperty("head_branch", out var hb) ? hb.GetString() : null;
                var htmlUrl = run.TryGetProperty("html_url", out var hu) ? hu.GetString() : null;
                var startedAt = run.TryGetProperty("run_started_at", out var rsa)
                    ? rsa.GetDateTime()
                    : DateTime.UtcNow;
                var trigger = run.TryGetProperty("event", out var ev) ? ev.GetString() : null;

                _db.WorkflowRuns.Add(new WorkflowRun
                {
                    RunId = runId,
                    GitHubId = gitHubId,
                    WorkflowName = name,
                    Repo = repo,
                    Actor = actor,
                    HeadBranch = branch,
                    Trigger = trigger,
                    HtmlUrl = htmlUrl,
                    Status = "in_progress",
                    StartedAt = startedAt,
                    IsIgnored = isIgnored
                });
                newCount++;
            }
        }

        if (newCount > 0)
            await _db.SaveChangesAsync();

        return ApiResult.Ok(new { synced = newCount, repos = repos.Count });
    }
}
