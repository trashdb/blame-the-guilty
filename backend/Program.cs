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
}

app.UseCors("SignalR");

app.MapHub<PunishmentHub>("/hub/punishment");
app.MapControllers();

app.Run();
