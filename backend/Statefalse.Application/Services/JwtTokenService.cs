using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;

namespace Statefalse.Application;

/// <summary>
/// Configuration for issued session JWTs.
/// </summary>
public sealed class JwtOptions
{
    public string Secret { get; set; } = "";
    public string Issuer { get; set; } = "statefalse";
    public string Audience { get; set; } = "statefalse-native";
    public int ExpiryHours { get; set; } = 720; // 30 days
}

/// <summary>
/// Issues short-lived session JWTs for authenticated GitHub users.
/// Stateless: no server-side session store, revocation happens at expiry.
/// </summary>
public class JwtTokenService
{
    private readonly JwtOptions _options;

    public JwtTokenService(IOptions<JwtOptions> options)
    {
        _options = options.Value;
    }

    public string GenerateToken(long gitHubId, string username, string? avatarUrl)
    {
        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, gitHubId.ToString()),
            new(JwtRegisteredClaimNames.UniqueName, username)
        };
        if (!string.IsNullOrEmpty(avatarUrl))
            claims.Add(new Claim("avatar", avatarUrl));

        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_options.Secret));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var token = new JwtSecurityToken(
            issuer: _options.Issuer,
            audience: _options.Audience,
            claims: claims,
            expires: DateTime.UtcNow.AddHours(_options.ExpiryHours),
            signingCredentials: creds);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
