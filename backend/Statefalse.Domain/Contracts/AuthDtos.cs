namespace Statefalse.Domain.Contracts;

public sealed record UserProfileDto(long Id, string Username, string? AvatarUrl, bool HasPat);

public sealed record TokenDto(string Token);

public sealed record PatRequest
{
    public string? PatToken { get; set; }
}
