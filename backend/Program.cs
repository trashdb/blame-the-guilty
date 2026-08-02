using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.RateLimiting;
using System.Threading.RateLimiting;
using Serilog;
using Scalar.AspNetCore;
using Statefalse.Api;
using Statefalse.Api.Data;
using Statefalse.Api.Hubs;
using Statefalse.Api.Services;

Log.Logger = new LoggerConfiguration()
    .WriteTo.Console()
    .WriteTo.File("logs/statefalse-api-.log", rollingInterval: RollingInterval.Day,
        retainedFileCountLimit: 30, restrictedToMinimumLevel: Serilog.Events.LogEventLevel.Warning)
    .CreateBootstrapLogger();

try
{
    var builder = WebApplication.CreateBuilder(args);

    builder.Host.UseSerilog((context, config) =>
    {
        config.ReadFrom.Configuration(context.Configuration)
            .Enrich.FromLogContext()
            .WriteTo.Console()
            .WriteTo.File("logs/statefalse-api-.log", rollingInterval: RollingInterval.Day,
                retainedFileCountLimit: 30);
    });

    // Database
    builder.Services.AddDbContext<AppDbContext>(options =>
        options.UseSqlite(builder.Configuration.GetConnectionString("DefaultConnection")));

    // SignalR
    builder.Services.AddSignalR();

    // HttpClient for GitHub OAuth
    builder.Services.AddHttpClient<GitHubOAuthService>();
    builder.Services.AddHttpClient<IGitHubClient, GitHubClient>(client =>
    {
        client.BaseAddress = new Uri("https://api.github.com");
    });

    // Application services
    builder.Services.AddScoped<IGitHubTokenResolver, GitHubTokenResolver>();
    builder.Services.AddScoped<SignalRNotifier>();
    builder.Services.AddScoped<PullRequestQueries>();
    builder.Services.AddScoped<PullRequestSyncService>();
    builder.Services.AddScoped<PullRequestQueryService>();
    builder.Services.AddScoped<PullRequestActionService>();
    builder.Services.AddScoped<PullRequestSubscriptionService>();
    builder.Services.AddScoped<WebhookService>();
    builder.Services.AddScoped<AiService>();
    builder.Services.AddScoped<GitHubApiService>();
    builder.Services.AddScoped<WorkflowService>();
    builder.Services.AddScoped<AuthService>();
    builder.Services.AddScoped<PunishmentService>();

    // Webhook handlers (dispatched by WebhookService via X-GitHub-Event)
    builder.Services.AddScoped<IWebhookHandler, WorkflowRunWebhookHandler>();
    builder.Services.AddScoped<IWebhookHandler, CheckSuiteWebhookHandler>();
    builder.Services.AddScoped<IWebhookHandler, PullRequestWebhookHandler>();
    builder.Services.AddScoped<IWebhookHandler, PullRequestReviewWebhookHandler>();
    builder.Services.AddScoped<IWebhookHandler, IssueCommentWebhookHandler>();
    builder.Services.AddScoped<IWebhookHandler, PullRequestReviewCommentWebhookHandler>();

    // GitHub OAuth config
    builder.Services.Configure<GitHubOAuthOptions>(
        builder.Configuration.GetSection("GitHubOAuth"));

    // JSON serialization (used by Minimal API results + body binding)
    builder.Services.ConfigureHttpJsonOptions(options =>
    {
        options.SerializerOptions.Converters.Add(new UtcDateTimeConverter());
    });

    // OpenAPI / Swagger
    builder.Services.AddOpenApi();

    // Rate limiting
    builder.Services.AddRateLimiter(options =>
    {
        options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;

        options.AddFixedWindowLimiter("api", limiterOptions =>
        {
            limiterOptions.PermitLimit = 100;
            limiterOptions.Window = TimeSpan.FromMinutes(1);
            limiterOptions.QueueLimit = 10;
        });

        options.AddFixedWindowLimiter("webhook", limiterOptions =>
        {
            limiterOptions.PermitLimit = 50;
            limiterOptions.Window = TimeSpan.FromMinutes(1);
        });
    });

    // CORS (for ngrok + WPF dev)
    builder.Services.AddCors(options =>
    {
        options.AddDefaultPolicy(policy =>
        {
            policy.AllowAnyOrigin()
                  .AllowAnyHeader()
                  .AllowAnyMethod();
        });

        options.AddPolicy("SignalR", policy =>
        {
            policy.SetIsOriginAllowed(_ => true)
                  .AllowAnyHeader()
                  .AllowAnyMethod()
                  .AllowCredentials();
        });
    });

    var app = builder.Build();

    // Auto-migrate database
    using (var scope = app.Services.CreateScope())
    {
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        ApplyMigrations(db);
    }

    app.UseCors("SignalR");
    app.UseRateLimiter();

    // Health check
    app.MapGet("/health", async (AppDbContext db) =>
    {
        try
        {
            var canConnect = await db.Database.CanConnectAsync();
            return Results.Ok(new
            {
                status = canConnect ? "healthy" : "degraded",
                database = canConnect,
                timestamp = DateTime.UtcNow
            });
        }
        catch (Exception ex)
        {
            return Results.Ok(new
            {
                status = "unhealthy",
                database = false,
                error = ex.Message,
                timestamp = DateTime.UtcNow
            });
        }
    });

    app.MapOpenApi();
    app.MapScalarApiReference();

    app.MapHub<PunishmentHub>("/hub/punishment");
    app.MapApiEndpoints();

    await app.RunAsync();

    return 0;
}
catch (Exception ex)
{
    Log.Fatal(ex, "Application terminated unexpectedly");
    return 1;
}
finally
{
    Log.CloseAndFlush();
}
void ApplyMigrations(AppDbContext db)
{
    var migrations = db.Database.GetMigrations().ToList();
    if (migrations.Count == 0) return;

    // Databases created before EF migrations adoption (or from a failed early
    // Migrate() attempt) have tables but no applied migrations. Baseline them so
    // Migrate() skips the schema that already exists.
    var hasHistoryTable = db.Database
        .SqlQueryRaw<int>("SELECT COUNT(*) AS \"Value\" FROM sqlite_master WHERE type = 'table' AND name = '__EFMigrationsHistory'")
        .Single() > 0;

    var appliedMigrations = hasHistoryTable
        ? db.Database.GetAppliedMigrations().ToList()
        : new List<string>();

    var hasTables = db.Database
        .SqlQueryRaw<int>("SELECT COUNT(*) AS \"Value\" FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
        .Single() > 0;

    if (hasTables && appliedMigrations.Count < migrations.Count)
    {
        db.Database.ExecuteSqlRaw("""
            CREATE TABLE IF NOT EXISTS "__EFMigrationsHistory" (
                "MigrationId" TEXT NOT NULL CONSTRAINT "PK___EFMigrationsHistory" PRIMARY KEY,
                "ProductVersion" TEXT NOT NULL
            );
            """);

        var productVersion = typeof(DbContext).Assembly.GetName().Version?.ToString() ?? "10.0";
        foreach (var m in migrations)
        {
            db.Database.ExecuteSqlRaw(
                """INSERT OR IGNORE INTO "__EFMigrationsHistory" ("MigrationId", "ProductVersion") VALUES ({0}, {1});""",
                m, productVersion);
        }
    }

    db.Database.Migrate();

    // ── Data maintenance (not schema) ────────────────────────────────

    // Recover stuck runs: mark in_progress older than 24h as cancelled
    var cutoff = DateTime.UtcNow.AddHours(-24);
    var stuck = db.WorkflowRuns.Count(w => w.Status == "in_progress" && w.StartedAt < cutoff);
    if (stuck > 0)
    {
        db.Database.ExecuteSqlRaw("""
            UPDATE "WorkflowRuns" SET "Status" = 'cancelled'
            WHERE "Status" = 'in_progress' AND "StartedAt" < {0}
            """, cutoff);
        Console.WriteLine("Marked {Count} stale in_progress runs as cancelled", stuck);
    }

    // Mark superseded runs: any in_progress run that is NOT the latest
    // (by RunId) for its (Repo, WorkflowName, HeadBranch) combo
    var superseded = db.Database.ExecuteSqlRaw("""
        UPDATE "WorkflowRuns"
        SET "Status" = 'superseded'
        WHERE "Id" IN (
            SELECT w1."Id"
            FROM "WorkflowRuns" w1
            INNER JOIN (
                SELECT "Repo", "WorkflowName", "HeadBranch", MAX("RunId") AS "MaxRunId"
                FROM "WorkflowRuns"
                WHERE "HeadBranch" IS NOT NULL
                GROUP BY "Repo", "WorkflowName", "HeadBranch"
            ) w2 ON w1."Repo" = w2."Repo"
                AND w1."WorkflowName" = w2."WorkflowName"
                AND w1."HeadBranch" = w2."HeadBranch"
                AND w1."RunId" < w2."MaxRunId"
            WHERE w1."Status" = 'in_progress'
        )
        """);
    if (superseded > 0)
        Console.WriteLine("Marked {Count} superseded in_progress runs as superseded", superseded);
}