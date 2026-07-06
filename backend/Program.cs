using Microsoft.EntityFrameworkCore;
using BlameTheGuilty.Api.Data;
using BlameTheGuilty.Api.Hubs;
using BlameTheGuilty.Api.Services;

var builder = WebApplication.CreateBuilder(args);

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

// Controllers
builder.Services.AddControllers();

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

    db.Database.ExecuteSqlRaw("""
        CREATE TABLE IF NOT EXISTS "PrComments" (
            "Id" INTEGER NOT NULL CONSTRAINT "PK_PrComments" PRIMARY KEY AUTOINCREMENT,
            "PrNumber" INTEGER NOT NULL,
            "AuthorLogin" TEXT NOT NULL,
            "AuthorGitHubId" INTEGER,
            "RepoFullName" TEXT NOT NULL,
            "PrUrl" TEXT,
            "CommentBody" TEXT,
            "OccurredAt" TEXT NOT NULL,
            "WasNotified" INTEGER NOT NULL DEFAULT 0
        );
        """);

    db.Database.ExecuteSqlRaw("""
        CREATE INDEX IF NOT EXISTS "IX_PrComments_PrNumber" ON "PrComments" ("PrNumber");
        """);

    // Add AccessToken column to existing GitHubUsers table if missing
    try { db.Database.ExecuteSqlRaw("""ALTER TABLE "GitHubUsers" ADD COLUMN "AccessToken" TEXT;"""); } catch { }

    // Add TargetGitHubId column to existing WorkflowRuns table if missing
    try { db.Database.ExecuteSqlRaw("""ALTER TABLE "WorkflowRuns" ADD COLUMN "TargetGitHubId" INTEGER;"""); } catch { }
}

app.UseCors("SignalR");

app.MapHub<PunishmentHub>("/hub/punishment");
app.MapControllers();

app.Run();
