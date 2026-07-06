using System.ComponentModel.DataAnnotations;

namespace BlameTheGuilty.Api.Models;

public class PrComment
{
    [Key]
    public int Id { get; set; }

    public long PrNumber { get; set; }

    [Required]
    [MaxLength(100)]
    public string AuthorLogin { get; set; } = string.Empty;

    public long? AuthorGitHubId { get; set; }

    [Required]
    [MaxLength(200)]
    public string RepoFullName { get; set; } = string.Empty;

    public string? PrUrl { get; set; }

    public string? CommentBody { get; set; }

    public DateTime OccurredAt { get; set; } = DateTime.UtcNow;

    public bool WasNotified { get; set; }
}
