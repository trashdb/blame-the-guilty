using System.ComponentModel.DataAnnotations;

namespace BlameTheGuilty.Api.Models;

public class GitHubUser
{
    [Key]
    public int Id { get; set; }

    public long GitHubId { get; set; }

    [Required]
    [MaxLength(100)]
    public string GitHubUsername { get; set; } = string.Empty;

    public string? AccessToken { get; set; }

    public string? SignalRConnectionId { get; set; }

    public bool IsOnline => SignalRConnectionId != null;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public DateTime? LastLoginAt { get; set; }

    [MaxLength(500)]
    public string? AvatarUrl { get; set; }
}
