namespace Statefalse.Api.Contracts;

public sealed record BranchDto(string Name);

public sealed record PrPreviewDto(
    string Template,
    List<string> Commits,
    string Summary,
    string SuggestedBody,
    string? SummaryError);

public sealed record CreatePrResultDto(long PrNumber, string Url, bool? Existing = null);

public sealed record UserDto(long GitHubId, string Login, string? AvatarUrl);

public sealed record InterpretRequest
{
    public string Query { get; init; } = "";
    public long GitHubId { get; init; }
    public string? ApiKey { get; init; }
    public string? AiProvider { get; init; }
    public string? Model { get; init; }
}

public sealed record InterpretResponse
{
    public string Action { get; init; } = "";
    public string? Message { get; init; }
    public Dictionary<string, string>? Params { get; init; }
}
