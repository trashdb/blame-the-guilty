using System.Security.Claims;
using System.Text.Json;
using Statefalse.Domain.Contracts;
using Statefalse.Application;
using Statefalse.Infrastructure.Data;

namespace Statefalse.Api;

/// <summary>
/// Minimal API endpoint definitions (replaces MVC controllers).
/// Route + rate-limit parity with the previous controllers.
/// All endpoints require a session JWT except login/callback, the signed
/// GitHub webhook, and /health.
/// </summary>
public static class ApiEndpoints
{
    public static void MapApiEndpoints(this WebApplication app)
    {
        MapAuth(app);
        MapPunishments(app);
        MapPullRequests(app);
        MapWebhook(app);
        MapGitHub(app);
        MapWorkflows(app);
        MapUsers(app);
    }

    private static long GitHubId(this HttpContext ctx)
    {
        var claim = ctx.User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (claim == null || !long.TryParse(claim, out var id))
            throw new UnauthorizedAccessException("Missing identity claim.");
        return id;
    }

    private static void MapAuth(WebApplication app)
    {
        app.MapGet("/api/auth/login", (string? redirect_uri, AuthService auth)
            => Results.Redirect(auth.LoginUrl(redirect_uri))).AllowAnonymous();

        app.MapGet("/api/auth/callback", async (string code, string? state, AuthService auth) =>
        {
            var result = await auth.HandleCallbackAsync(code, state);
            if (result.Error != null)
                return Results.Json(result.Error.Value, statusCode: result.Error.StatusCode);
            if (result.RedirectUrl != null)
                return Results.Redirect(result.RedirectUrl);
            return Results.Ok(result.OkBody);
        }).AllowAnonymous();

        app.MapGet("/api/auth/me", async (HttpContext ctx, AuthService auth)
            => await MapAsync(auth.GetMeAsync(ctx.GitHubId()))).RequireAuthorization();

        app.MapPost("/api/auth/pat", async (HttpContext ctx, PatRequest body, AuthService auth)
            => await MapAsync(auth.SavePatAsync(ctx.GitHubId(), body.PatToken))).RequireAuthorization();

        app.MapGet("/api/auth/token", async (HttpContext ctx, AuthService auth)
            => await MapAsync(auth.GetTokenAsync(ctx.GitHubId()))).RequireAuthorization();
    }

    private static void MapPunishments(WebApplication app)
    {
        app.MapGet("/api/punishments", async (PunishmentService service, int days = 7, int limit = 50)
            => await MapAsync(service.GetRecentAsync(days, limit))).RequireAuthorization();

        app.MapGet("/api/punishments/summary", async (PunishmentService service, int days = 7)
            => await MapAsync(service.GetSummaryAsync(days))).RequireAuthorization();
    }

    private static void MapPullRequests(WebApplication app)
    {
        app.MapPost("/api/pullrequests/sync", async (HttpContext ctx, PullRequestSyncService service)
            => await MapAsync(service.SyncFromGitHubAsync(ctx.GitHubId()))).RequireAuthorization().RequireRateLimiting("api");

        app.MapGet("/api/pullrequests/active", async (PullRequestQueryService service, HttpContext ctx, int page = 1, int pageSize = 50)
            => await MapAsync(service.GetActiveAsync(ctx.GitHubId(), page, pageSize))).RequireAuthorization().RequireRateLimiting("api");

        app.MapGet("/api/pullrequests/{prNumber}/detail", async (long prNumber, string repo, HttpContext ctx, PullRequestQueryService service)
            => await MapAsync(service.GetDetailAsync(prNumber, repo, ctx.GitHubId()))).RequireAuthorization().RequireRateLimiting("api");

        app.MapPost("/api/pullrequests/{prNumber}/merge", async (PullRequestActionService service, long prNumber, string repo, HttpContext ctx, string method = "squash")
            => await MapAsync(service.MergeAsync(prNumber, repo, ctx.GitHubId(), method))).RequireAuthorization();

        app.MapPost("/api/pullrequests/{prNumber}/draft", async (long prNumber, string repo, HttpContext ctx, bool draft, PullRequestActionService service)
            => await MapAsync(service.SetDraftAsync(prNumber, repo, ctx.GitHubId(), draft))).RequireAuthorization();

        app.MapPost("/api/pullrequests/{prNumber}/update-branch", async (long prNumber, string repo, HttpContext ctx, PullRequestActionService service)
            => await MapAsync(service.UpdateBranchAsync(prNumber, repo, ctx.GitHubId()))).RequireAuthorization();

        app.MapGet("/api/pullrequests/{prNumber}/commits", async (long prNumber, string repo, HttpContext ctx, PullRequestQueryService service)
            => await MapAsync(service.GetCommitsAsync(prNumber, repo, ctx.GitHubId()))).RequireAuthorization();

        app.MapGet("/api/pullrequests/{prNumber}/files", async (long prNumber, string repo, HttpContext ctx, PullRequestQueryService service)
            => await MapAsync(service.GetFilesAsync(prNumber, repo, ctx.GitHubId()))).RequireAuthorization();

        app.MapGet("/api/pullrequests/{prNumber}/checks", async (long prNumber, string repo, HttpContext ctx, PullRequestQueryService service)
            => await MapAsync(service.GetChecksAsync(prNumber, repo, ctx.GitHubId()))).RequireAuthorization();

        app.MapPost("/api/pullrequests/{prNumber}/subscribe", async (long prNumber, string repo, HttpContext ctx, PullRequestSubscriptionService service)
            => await MapAsync(service.SubscribeAsync(prNumber, repo, ctx.GitHubId()))).RequireAuthorization().RequireRateLimiting("api");

        app.MapPost("/api/pullrequests/{prNumber}/unsubscribe", async (long prNumber, string repo, HttpContext ctx, PullRequestSubscriptionService service)
            => await MapAsync(service.UnsubscribeAsync(prNumber, repo, ctx.GitHubId()))).RequireAuthorization().RequireRateLimiting("api");

        app.MapGet("/api/pullrequests/{prNumber}/subscribers", async (long prNumber, string repo, PullRequestSubscriptionService service)
            => await MapAsync(service.GetSubscribersAsync(prNumber, repo))).RequireAuthorization().RequireRateLimiting("api");

        app.MapPost("/api/pullrequests/{prNumber}/add-subscriber", async (long prNumber, string repo, HttpContext ctx, string? username, long? subscriberId, PullRequestSubscriptionService service)
            => await MapAsync(service.AddSubscriberAsync(prNumber, repo, ctx.GitHubId(), username, subscriberId))).RequireAuthorization().RequireRateLimiting("api");

        app.MapPost("/api/pullrequests/{prNumber}/remove-subscriber", async (long prNumber, string repo, HttpContext ctx, long subscriberId, PullRequestSubscriptionService service)
            => await MapAsync(service.RemoveSubscriberAsync(prNumber, repo, ctx.GitHubId(), subscriberId))).RequireAuthorization().RequireRateLimiting("api");
    }

    private static void MapWebhook(WebApplication app)
    {
        app.MapGet("/api/webhook/logs", (WebhookService service, int limit = 30)
            => Results.Ok(service.GetLogs(limit))).RequireAuthorization();

        app.MapPost("/api/webhook/github", async (HttpContext ctx, WebhookService service) =>
        {
            var signature = ctx.Request.Headers["X-Hub-Signature-256"].FirstOrDefault();
            var eventType = ctx.Request.Headers["X-GitHub-Event"].FirstOrDefault() ?? "";

            ctx.Request.EnableBuffering();
            var result = await service.HandleGitHubWebhookAsync(
                signatureHeader: signature,
                readRawBody: async () =>
                {
                    var body = await new StreamReader(ctx.Request.Body).ReadToEndAsync();
                    ctx.Request.Body.Position = 0;
                    return body;
                },
                readJsonBody: async () =>
                {
                    var payload = await JsonSerializer.DeserializeAsync<JsonElement>(ctx.Request.Body);
                    return payload;
                },
                eventType: eventType);

            return Results.Json(result.Value, statusCode: result.StatusCode);
        }).AllowAnonymous().RequireRateLimiting("webhook");
    }

    private static void MapGitHub(WebApplication app)
    {
        app.MapGet("/api/github/my-branches", async (HttpContext ctx, string repo, GitHubApiService service)
            => await MapAsync(service.GetMyBranchesAsync(ctx.GitHubId(), repo))).RequireAuthorization();

        app.MapPost("/api/github/create-pr", async (HttpContext ctx, string repo, string head, string baseBranch,
            string title, string? body, string? subscribers, GitHubApiService service)
            => await MapAsync(service.CreatePrAsync(ctx.GitHubId(), repo, head, baseBranch, title, body, subscribers))).RequireAuthorization();

        app.MapPost("/api/github/pr-preview", async (GitHubApiService service, HttpContext ctx, string repo, string head, string baseBranch,
            string title, bool useAI = true)
            => await MapAsync(service.PrPreviewAsync(ctx.GitHubId(), repo, head, baseBranch, title, useAI))).RequireAuthorization();

        app.MapPost("/api/github/interpret", async (InterpretRequest request, GitHubApiService service)
            => await MapAsync(service.InterpretAsync(request))).RequireAuthorization();
    }

    private static void MapWorkflows(WebApplication app)
    {
        app.MapGet("/api/workflows/runs", async (WorkflowService service, HttpContext ctx, int limit = 20)
            => await MapAsync(service.GetRunsAsync(ctx.GitHubId(), limit))).RequireAuthorization().RequireRateLimiting("api");

        app.MapPut("/api/workflows/runs/{id}/target", async (int id, SetTargetRequest request, WorkflowService service)
            => await MapAsync(service.SetTargetAsync(id, request))).RequireAuthorization();

        app.MapPost("/api/workflows/runs/{runId}/rerun", async (long runId, HttpContext ctx, WorkflowService service)
            => await MapAsync(service.RerunAsync(runId, ctx.GitHubId()))).RequireAuthorization();

        app.MapPost("/api/workflows/sync-active", async (HttpContext ctx, WorkflowService service)
            => await MapAsync(service.SyncActiveAsync(ctx.GitHubId()))).RequireAuthorization();
    }

    private static void MapUsers(WebApplication app)
    {
        app.MapGet("/api/users", async (AuthService auth) => await MapAsync(auth.GetUsersAsync())).RequireAuthorization();
    }

    private static async Task<IResult> MapAsync(Task<ApiResult> task)
    {
        var result = await task;
        return Results.Json(result.Value, statusCode: result.StatusCode);
    }
}
