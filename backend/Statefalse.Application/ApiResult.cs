namespace Statefalse.Application;

/// <summary>
/// HTTP-agnostic service result. Controllers map to <see cref="Microsoft.AspNetCore.Http.IResult"/>
/// / <see cref="Microsoft.AspNetCore.Mvc.IActionResult"/> via <c>From</c>.
/// </summary>
public sealed record ApiResult(int StatusCode, object? Value)
{
    public static ApiResult Ok(object? value = null) => new(StatusCodes.Status200OK, value);
    public static ApiResult Created(object? value = null) => new(StatusCodes.Status201Created, value);
    public static ApiResult NoContent() => new(StatusCodes.Status204NoContent, null);
    public static ApiResult BadRequest(object? value = null) => new(StatusCodes.Status400BadRequest, value);
    public static ApiResult Unauthorized(object? value = null) => new(StatusCodes.Status401Unauthorized, value);
    public static ApiResult Forbid(object? value = null) => new(StatusCodes.Status403Forbidden, value);
    public static ApiResult NotFound(object? value = null) => new(StatusCodes.Status404NotFound, value);
    public static ApiResult Error(int status, object? value) => new(status, value);

    public static ApiResult FromGitHubStatus(int status, object? value = null)
        => status <= 0 ? new(StatusCodes.Status502BadGateway, value ?? new { error = "GitHub API unreachable" }) : new(status, value);
}
