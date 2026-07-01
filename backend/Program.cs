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
}

app.UseCors("SignalR");

app.MapHub<PunishmentHub>("/hub/punishment");
app.MapControllers();

app.Run();
