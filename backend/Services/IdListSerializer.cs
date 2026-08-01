using System.Text.Json;

namespace Statefalse.Api.Services;

public static class IdListSerializer
{
    public static long[] Deserialize(string? raw) =>
        raw is { Length: > 0 } && JsonSerializer.Deserialize<long[]>(raw) is { } arr ? arr : [];

    public static string? Serialize(long[] ids) =>
        ids.Length > 0 ? JsonSerializer.Serialize(ids) : null;
}
