using Microsoft.EntityFrameworkCore;
using BlameTheGuilty.Api.Models;

namespace BlameTheGuilty.Api.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<GitHubUser> GitHubUsers => Set<GitHubUser>();
    public DbSet<PunishmentEvent> PunishmentEvents => Set<PunishmentEvent>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<GitHubUser>(entity =>
        {
            entity.HasIndex(u => u.GitHubUsername).IsUnique();
            entity.HasIndex(u => u.GitHubId).IsUnique();
        });

        modelBuilder.Entity<PunishmentEvent>(entity =>
        {
            entity.HasIndex(e => e.OccurredAt);
            entity.HasIndex(e => e.CulpritLogin);
        });
    }
}
