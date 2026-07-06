using System.ComponentModel.DataAnnotations;

namespace BlameTheGuilty.Api.Models;

public class CheckSuiteEvent
{
    [Key]
    public int Id { get; set; }

    public long CheckSuiteId { get; set; }

    [Required]
    [MaxLength(50)]
    public string Conclusion { get; set; } = string.Empty;

    [MaxLength(200)]
    public string? HeadBranch { get; set; }

    [MaxLength(40)]
    public string? HeadSha { get; set; }

    [MaxLength(100)]
    public string? PrAuthorLogin { get; set; }

    public long? PrAuthorGitHubId { get; set; }

    public int? PrNumber { get; set; }

    [Required]
    [MaxLength(200)]
    public string RepoFullName { get; set; } = string.Empty;

    public DateTime OccurredAt { get; set; } = DateTime.UtcNow;

    public bool WasNotified { get; set; }
}
