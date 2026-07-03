using System.ComponentModel.DataAnnotations;

namespace BlameTheGuilty.Api.Models;

public class PunishmentEvent
{
    [Key]
    public int Id { get; set; }

    public long RunId { get; set; }

    [Required]
    [MaxLength(100)]
    public string CulpritLogin { get; set; } = string.Empty;

    public long? CulpritGitHubId { get; set; }

    [Required]
    [MaxLength(200)]
    public string RepoFullName { get; set; } = string.Empty;

    [MaxLength(200)]
    public string? WorkflowName { get; set; }

    public string? WorkflowUrl { get; set; }

    public DateTime OccurredAt { get; set; } = DateTime.UtcNow;

    public bool WasNotified { get; set; }
}
