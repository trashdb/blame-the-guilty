using System.ComponentModel.DataAnnotations;

namespace BlameTheGuilty.Api.Models;

public class GitHubUser
{
    [Key]
    public int Id { get; set; }

    /// <summary>Numeric immutable ID from GitHub API (unique per user).</summary>
    public long GitHubId { get; set; }

    [Required]
    [MaxLength(100)]
    public string GitHubUsername { get; set; } = string.Empty;

    public string? SignalRConnectionId { get; set; }

    public bool IsOnline => SignalRConnectionId != null;

    public string? AccessToken { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public DateTime? LastLoginAt { get; set; }
}
