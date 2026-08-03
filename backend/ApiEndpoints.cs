using System.Text.Json;
using Statefalse.Domain.Contracts;
using Statefalse.Application;
using Statefalse.Infrastructure.Data;

namespace Statefalse.Api;

/// <summary>
/// Minimal API endpoint definitions (replaces MVC controllers).
/// Route + rate-limit parity with the previous controllers.
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

    private static void MapAuth(WebApplication app)
    {
        app.MapGet("/api/auth/login", (string? redirect_uri, AuthService auth)
            => Results.Redirect(auth.LoginUrl(redirect_uri)));

        app.MapGet("/api/auth/callback", async (string code, string? state, AuthService auth) =>
        {
            var result = await auth.HandleCallbackAsync(code, state);
            if (result.Error != null)
                return Results.Json(result.Error.Value, statusCode: result.Error.StatusCode);
            if (result.RedirectUrl != null)
                return Results.Redirect(result.RedirectUrl);
            return Results.Ok(result.OkBody);
        });

        app.MapGet("/api/auth/me", async (long gitHubId, AuthService auth)
            => await MapAsync(auth.GetMeAsync(gitHubId)));

        app.MapPost("/api/auth/pat", async (long gitHubId, PatRequest body, AuthService auth)
            => await MapAsync(auth.SavePatAsync(gitHubId, body.PatToken)));

        app.MapGet("/api/auth/token", async (long gitHubId, AuthService auth)
            => await MapAsync(auth.GetTokenAsync(gitHubId)));
    }

    private static void MapPunishments(WebApplication app)
    {
        app.MapGet("/api/punishments", async (PunishmentService service, int days = 7, int limit = 50)
            => await MapAsync(service.GetRecentAsync(days, limit)));

        app.MapGet("/api/punishments/summary", async (PunishmentService service, int days = 7)
            => await MapAsync(service.GetSummaryAsync(days)));
    }

    private static void MapPullRequests(WebApplication app)
    {
        app.MapPost("/api/pullrequests/sync", async (long gitHubId, PullRequestSyncService service)
            => await MapAsync(service.SyncFromGitHubAsync(gitHubId))).RequireRateLimiting("api");

        app.MapGet("/api/pullrequests/active", async (PullRequestQueryService service, long gitHubId, int page = 1, int pageSize = 50)
            => await MapAsync(service.GetActiveAsync(gitHubId, page, pageSize))).RequireRateLimiting("api");

        app.MapGet("/api/pullrequests/{prNumber}/detail", async (long prNumber, string repo, long gitHubId, PullRequestQueryService service)
            => await MapAsync(service.GetDetailAsync(prNumber, repo, gitHubId))).RequireRateLimiting("api");

        app.MapPost("/api/pullrequests/{prNumber}/merge", async (PullRequestActionService service, long prNumber, string repo, long gitHubId, string method = "squash")
            => await MapAsync(service.MergeAsync(prNumber, repo, gitHubId, method)));

        app.MapPost("/api/pullrequests/{prNumber}/draft", async (long prNumber, string repo, long gitHubId, bool draft, PullRequestActionService service)
            => await MapAsync(service.SetDraftAsync(prNumber, repo, gitHubId, draft)));

        app.MapPost("/api/pullrequests/{prNumber}/update-branch", async (long prNumber, string repo, long gitHubId, PullRequestActionService service)
            => await MapAsync(service.UpdateBranchAsync(prNumber, repo, gitHubId)));

        app.MapGet("/api/pullrequests/{prNumber}/commits", async (long prNumber, string repo, long gitHubId, PullRequestQueryService service)
            => await MapAsync(service.GetCommitsAsync(prNumber, repo, gitHubId)));

        app.MapGet("/api/pullrequests/{prNumber}/files", async (long prNumber, string repo, long gitHubId, PullRequestQueryService service)
            => await MapAsync(service.GetFilesAsync(prNumber, repo, gitHubId)));

        app.MapGet("/api/pullrequests/{prNumber}/checks", async (long prNumber, string repo, long gitHubId, PullRequestQueryService service)
            => await MapAsync(service.GetChecksAsync(prNumber, repo, gitHubId)));

        app.MapPost("/api/pullrequests/{prNumber}/subscribe", async (long prNumber, string repo, long gitHubId, PullRequestSubscriptionService service)
            => await MapAsync(service.SubscribeAsync(prNumber, repo, gitHubId))).RequireRateLimiting("api");

        app.MapPost("/api/pullrequests/{prNumber}/unsubscribe", async (long prNumber, string repo, long gitHubId, PullRequestSubscriptionService service)
            => await MapAsync(service.UnsubscribeAsync(prNumber, repo, gitHubId))).RequireRateLimiting("api");

        app.MapGet("/api/pullrequests/{prNumber}/subscribers", async (long prNumber, string repo, PullRequestSubscriptionService service)
            => await MapAsync(service.GetSubscribersAsync(prNumber, repo))).RequireRateLimiting("api");

        app.MapPost("/api/pullrequests/{prNumber}/add-subscriber", async (long prNumber, string repo, long gitHubId, string? username, long? subscriberId, PullRequestSubscriptionService service)
            => await MapAsync(service.AddSubscriberAsync(prNumber, repo, gitHubId, username, subscriberId))).RequireRateLimiting("api");

        app.MapPost("/api/pullrequests/{prNumber}/remove-subscriber", async (long prNumber, string repo, long gitHubId, long subscriberId, PullRequestSubscriptionService service)
            => await MapAsync(service.RemoveSubscriberAsync(prNumber, repo, gitHubId, subscriberId))).RequireRateLimiting("api");
    }

    private static void MapWebhook(WebApplication app)
    {
        app.MapGet("/api/webhook/logs", (WebhookService service, int limit = 30)
            => Results.Ok(service.GetLogs(limit)));

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
        }).RequireRateLimiting("webhook");
    }

    private static void MapGitHub(WebApplication app)
    {
        app.MapGet("/api/github/my-branches", async (long gitHubId, string repo, GitHubApiService service)
            => await MapAsync(service.GetMyBranchesAsync(gitHubId, repo)));

        app.MapPost("/api/github/create-pr", async (long gitHubId, string repo, string head, string baseBranch,
            string title, string? body, string? subscribers, GitHubApiService service)
            => await MapAsync(service.CreatePrAsync(gitHubId, repo, head, baseBranch, title, body, subscribers)));

        app.MapPost("/api/github/pr-preview", async (GitHubApiService service, long gitHubId, string repo, string head, string baseBranch,
            string title, bool useAI = true)
            => await MapAsync(service.PrPreviewAsync(gitHubId, repo, head, baseBranch, title, useAI)));

        app.MapPost("/api/github/interpret", async (InterpretRequest request, GitHubApiService service)
            => await MapAsync(service.InterpretAsync(request)));
    }

    private static void MapWorkflows(WebApplication app)
    {
        app.MapGet("/api/workflows/runs", async (WorkflowService service, long gitHubId, int limit = 20)
            => await MapAsync(service.GetRunsAsync(gitHubId, limit))).RequireRateLimiting("api");

        app.MapPut("/api/workflows/runs/{id}/target", async (int id, SetTargetRequest request, WorkflowService service)
            => await MapAsync(service.SetTargetAsync(id, request)));

        app.MapPost("/api/workflows/runs/{runId}/rerun", async (long runId, long gitHubId, WorkflowService service)
            => await MapAsync(service.RerunAsync(runId, gitHubId)));

        app.MapPost("/api/workflows/sync-active", async (long gitHubId, WorkflowService service)
            => await MapAsync(service.SyncActiveAsync(gitHubId)));
    }

    private static void MapUsers(WebApplication app)
    {
        app.MapGet("/api/users", async (AuthService auth) => await MapAsync(auth.GetUsersAsync()));
    }

    private static async Task<IResult> MapAsync(Task<ApiResult> task)
    {
        var result = await task;
        return Results.Json(result.Value, statusCode: result.StatusCode);
    }
}
