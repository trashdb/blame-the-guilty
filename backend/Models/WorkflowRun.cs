using System.ComponentModel.DataAnnotations;

namespace BlameTheGuilty.Api.Models;

public class WorkflowRun
{
    [Key]
    public int Id { get; set; }

    public long RunId { get; set; }

    public long GitHubId { get; set; }

    [MaxLength(200)]
    public string? WorkflowName { get; set; }

    [Required]
    [MaxLength(200)]
    public string Repo { get; set; } = string.Empty;

    [Required]
    [MaxLength(100)]
    public string Actor { get; set; } = string.Empty;

    public string? HtmlUrl { get; set; }

    [Required]
    [MaxLength(20)]
    public string Status { get; set; } = "in_progress";

    public DateTime StartedAt { get; set; }
}
