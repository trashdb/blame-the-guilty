using Microsoft.EntityFrameworkCore;
using Serilog;
using Scalar.AspNetCore;
using BlameTheGuilty.Api.Data;
using BlameTheGuilty.Api.Hubs;
using BlameTheGuilty.Api.Services;

Log.Logger = new LoggerConfiguration()
    .WriteTo.Console()
    .WriteTo.File("logs/blame-api-.log", rollingInterval: RollingInterval.Day,
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
            .WriteTo.File("logs/blame-api-.log", rollingInterval: RollingInterval.Day,
                retainedFileCountLimit: 30);
    });

    // Database
    builder.Services.AddDbContext<AppDbContext>(options =>
        options.UseSqlite(builder.Configuration.GetConnectionString("DefaultConnection")));

    // SignalR
    builder.Services.AddSignalR();

    // HttpClient for GitHub OAuth
    builder.Services.AddHttpClient<GitHubOAuthService>();

    // GitHub OAuth config
    builder.Services.Configure<GitHubOAuthOptions>(
        builder.Configuration.GetSection("GitHubOAuth"));

    // Controllers + JSON serialization
    builder.Services.AddControllers()
        .AddJsonOptions(options =>
        {
            options.JsonSerializerOptions.Converters.Add(new UtcDateTimeConverter());
        });

    // OpenAPI / Swagger
    builder.Services.AddOpenApi();

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
    app.MapControllers();

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
    db.Database.EnsureCreated();

    // Ensure the PunishmentEvents table exists even on existing DBs
    db.Database.ExecuteSqlRaw("""
        CREATE TABLE IF NOT EXISTS "PunishmentEvents" (
            "Id" INTEGER NOT NULL CONSTRAINT "PK_PunishmentEvents" PRIMARY KEY AUTOINCREMENT,
            "RunId" INTEGER NOT NULL,
            "CulpritLogin" TEXT NOT NULL,
            "CulpritGitHubId" INTEGER,
            "RepoFullName" TEXT NOT NULL,
            "WorkflowName" TEXT,
            "WorkflowUrl" TEXT,
            "OccurredAt" TEXT NOT NULL,
            "WasNotified" INTEGER NOT NULL DEFAULT 0
        );
        """);

    db.Database.ExecuteSqlRaw("""
        CREATE TABLE IF NOT EXISTS "WorkflowRuns" (
            "Id" INTEGER NOT NULL CONSTRAINT "PK_WorkflowRuns" PRIMARY KEY AUTOINCREMENT,
            "RunId" INTEGER NOT NULL,
            "GitHubId" INTEGER NOT NULL,
            "WorkflowName" TEXT,
            "Repo" TEXT NOT NULL,
            "Actor" TEXT NOT NULL,
            "HtmlUrl" TEXT,
            "Status" TEXT NOT NULL DEFAULT 'in_progress',
            "StartedAt" TEXT NOT NULL
        );
        """);

    db.Database.ExecuteSqlRaw("""
        CREATE INDEX IF NOT EXISTS "IX_WorkflowRuns_GitHubId" ON "WorkflowRuns" ("GitHubId");
        """);
    db.Database.ExecuteSqlRaw("""
        CREATE INDEX IF NOT EXISTS "IX_WorkflowRuns_Status" ON "WorkflowRuns" ("Status");
        """);
    db.Database.ExecuteSqlRaw("""
        CREATE INDEX IF NOT EXISTS "IX_WorkflowRuns_RunId" ON "WorkflowRuns" ("RunId");
        """);

    db.Database.ExecuteSqlRaw("""
        CREATE TABLE IF NOT EXISTS "CheckSuiteEvents" (
            "Id" INTEGER NOT NULL CONSTRAINT "PK_CheckSuiteEvents" PRIMARY KEY AUTOINCREMENT,
            "CheckSuiteId" INTEGER NOT NULL,
            "Conclusion" TEXT NOT NULL,
            "HeadBranch" TEXT,
            "HeadSha" TEXT,
            "PrAuthorLogin" TEXT,
            "PrAuthorGitHubId" INTEGER,
            "PrNumber" INTEGER,
            "RepoFullName" TEXT NOT NULL,
            "OccurredAt" TEXT NOT NULL,
            "WasNotified" INTEGER NOT NULL DEFAULT 0
        );
        """);

    db.Database.ExecuteSqlRaw("""
        CREATE TABLE IF NOT EXISTS "PullRequestEvents" (
            "Id" INTEGER NOT NULL CONSTRAINT "PK_PullRequestEvents" PRIMARY KEY AUTOINCREMENT,
            "PrNumber" INTEGER NOT NULL,
            "Title" TEXT NOT NULL,
            "AuthorLogin" TEXT NOT NULL,
            "AuthorGitHubId" INTEGER,
            "RepoFullName" TEXT NOT NULL,
            "HeadBranch" TEXT,
            "BaseBranch" TEXT,
            "PrUrl" TEXT,
            "Status" TEXT NOT NULL,
            "Conclusion" TEXT,
            "ExtraInfo" TEXT,
            "OccurredAt" TEXT NOT NULL,
            "WasNotified" INTEGER NOT NULL DEFAULT 0
        );
        """);

    db.Database.ExecuteSqlRaw("""
        CREATE INDEX IF NOT EXISTS "IX_PullRequestEvents_AuthorLogin" ON "PullRequestEvents" ("AuthorLogin");
        """);
    db.Database.ExecuteSqlRaw("""
        CREATE INDEX IF NOT EXISTS "IX_PullRequestEvents_Status" ON "PullRequestEvents" ("Status");
        """);
    db.Database.ExecuteSqlRaw("""
        CREATE INDEX IF NOT EXISTS "IX_PullRequestEvents_PrNumber" ON "PullRequestEvents" ("PrNumber");
        """);

    // Add columns that may not exist on older DBs
    try { db.Database.ExecuteSqlRaw("""ALTER TABLE "GitHubUsers" ADD COLUMN "AccessToken" TEXT;"""); } catch { }
    try { db.Database.ExecuteSqlRaw("""ALTER TABLE "WorkflowRuns" ADD COLUMN "TargetGitHubIds" TEXT;"""); } catch { }
    try { db.Database.ExecuteSqlRaw("""ALTER TABLE "PullRequestEvents" ADD COLUMN "Draft" INTEGER NOT NULL DEFAULT 0;"""); } catch { }
    try { db.Database.ExecuteSqlRaw("""ALTER TABLE "PullRequestEvents" ADD COLUMN "MergeableState" TEXT;"""); } catch { }
    try { db.Database.ExecuteSqlRaw("""ALTER TABLE "WorkflowRuns" ADD COLUMN "HeadBranch" TEXT;"""); } catch { }
    try { db.Database.ExecuteSqlRaw("""ALTER TABLE "WorkflowRuns" ADD COLUMN "Trigger" TEXT;"""); } catch { }
    try { db.Database.ExecuteSqlRaw("""ALTER TABLE "PullRequestEvents" ADD COLUMN "ReviewApproved" INTEGER NOT NULL DEFAULT 0;"""); } catch { }
    try { db.Database.ExecuteSqlRaw("""ALTER TABLE "PullRequestEvents" ADD COLUMN "ApprovedBy" TEXT;"""); } catch { }
    try { db.Database.ExecuteSqlRaw("""ALTER TABLE "GitHubUsers" ADD COLUMN "AvatarUrl" TEXT;"""); } catch { }
    try { db.Database.ExecuteSqlRaw("""ALTER TABLE "GitHubUsers" ADD COLUMN "UserPatToken" TEXT;"""); } catch { }
    try { db.Database.ExecuteSqlRaw("""ALTER TABLE "WorkflowRuns" ADD COLUMN "IsIgnored" INTEGER NOT NULL DEFAULT 0;"""); } catch { }
    try { db.Database.ExecuteSqlRaw("""ALTER TABLE "PullRequestEvents" ADD COLUMN "LastCommentBy" TEXT;"""); } catch { }
    try { db.Database.ExecuteSqlRaw("""ALTER TABLE "PullRequestEvents" ADD COLUMN "LastCommentBody" TEXT;"""); } catch { }
    try { db.Database.ExecuteSqlRaw("""ALTER TABLE "PullRequestEvents" ADD COLUMN "LastCommentAt" TEXT;"""); } catch { }
    try { db.Database.ExecuteSqlRaw("""ALTER TABLE "WorkflowRuns" ADD COLUMN "HeadSha" TEXT;"""); } catch { }
    try { db.Database.ExecuteSqlRaw("""ALTER TABLE "PullRequestEvents" ADD COLUMN "HeadSha" TEXT;"""); } catch { }
    try { db.Database.ExecuteSqlRaw("""ALTER TABLE "PullRequestEvents" ADD COLUMN "LastCommentUrl" TEXT;"""); } catch { }
    try { db.Database.ExecuteSqlRaw("""ALTER TABLE "PullRequestEvents" ADD COLUMN "LastReviewFilePath" TEXT;"""); } catch { }
    try { db.Database.ExecuteSqlRaw("""ALTER TABLE "PullRequestEvents" ADD COLUMN "LastReviewLine" INTEGER;"""); } catch { }

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
