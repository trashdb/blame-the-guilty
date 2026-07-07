using System.ComponentModel.DataAnnotations;

namespace BlameTheGuilty.Api.Models;

public class PullRequestEvent
{
    [Key]
    public int Id { get; set; }

    public long PrNumber { get; set; }

    [MaxLength(300)]
    public string Title { get; set; } = string.Empty;

    [MaxLength(100)]
    public string AuthorLogin { get; set; } = string.Empty;

    public long? AuthorGitHubId { get; set; }

    [Required]
    [MaxLength(200)]
    public string RepoFullName { get; set; } = string.Empty;

    [MaxLength(200)]
    public string? HeadBranch { get; set; }

    [MaxLength(200)]
    public string? BaseBranch { get; set; }

    public string? PrUrl { get; set; }

    [Required]
    [MaxLength(30)]
    public string Status { get; set; } = string.Empty;

    [MaxLength(50)]
    public string? Conclusion { get; set; }

    [MaxLength(500)]
    public string? ExtraInfo { get; set; }

    public DateTime OccurredAt { get; set; } = DateTime.UtcNow;

    public bool WasNotified { get; set; }
}
