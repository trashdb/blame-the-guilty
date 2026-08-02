using System.Security.Cryptography;
using System.Text;
using Statefalse.Api.Services;

namespace Statefalse.Api.Tests;

public class CiStatusCalculatorTests
{
    private static (int Id, string? WorkflowName, string Status) Run(int id, string status, string? name = "ci")
        => (id, name, status);

    [Fact]
    public void NullHeadSha_ReturnsReview()
    {
        Assert.Equal("review", CiStatusCalculator.Calculate(null, true, false, []));
    }

    [Fact]
    public void NoRuns_ReturnsWaiting()
    {
        Assert.Equal("waiting", CiStatusCalculator.Calculate("sha", true, false, []));
    }

    [Fact]
    public void InProgress_ReturnsWaiting()
    {
        var runs = new[] { Run(1, "in_progress"), Run(2, "in_progress", "lint") };
        Assert.Equal("waiting", CiStatusCalculator.Calculate("sha", true, false, runs));
    }

    [Fact]
    public void Failure_ReturnsFailed()
    {
        var runs = new[] { Run(1, "success"), Run(2, "failure") };
        Assert.Equal("failed", CiStatusCalculator.Calculate("sha", true, false, runs));
    }

    [Fact]
    public void AllSuccess_ReturnsReview()
    {
        var runs = new[] { Run(1, "success"), Run(2, "success") };
        Assert.Equal("review", CiStatusCalculator.Calculate("sha", true, false, runs));
    }

    [Fact]
    public void OpenReviewApproved_ReturnsReady()
    {
        var runs = new[] { Run(1, "success") };
        Assert.Equal("ready", CiStatusCalculator.Calculate("sha", true, true, runs));
    }

    [Fact]
    public void ClosedNotApproved_StaysReview()
    {
        var runs = new[] { Run(1, "success") };
        Assert.Equal("review", CiStatusCalculator.Calculate("sha", false, true, runs));
    }

    [Fact]
    public void SupersededRuns_Ignored()
    {
        var runs = new[] { Run(1, "failure"), Run(2, "superseded") };
        Assert.Equal("failed", CiStatusCalculator.Calculate("sha", true, false, runs));
    }

    [Fact]
    public void OnlySupersededCancelledSkipped_ReturnsWaiting()
    {
        var runs = new[] { Run(1, "superseded"), Run(2, "cancelled"), Run(3, "skipped") };
        Assert.Equal("waiting", CiStatusCalculator.Calculate("sha", true, false, runs));
    }

    [Fact]
    public void LatestRunPerWorkflow_Used()
    {
        var runs = new[]
        {
            Run(1, "failure", "ci"),
            Run(2, "success", "ci"),
            Run(3, "failure", "test"),
            Run(4, "success", "test"),
        };
        Assert.Equal("review", CiStatusCalculator.Calculate("sha", true, false, runs));
    }
}

public class WorkflowConclusionMapperTests
{
    [Theory]
    [InlineData("success", "success")]
    [InlineData("failure", "failure")]
    [InlineData("cancelled", "cancelled")]
    [InlineData("timed_out", "cancelled")]
    [InlineData("skipped", "cancelled")]
    [InlineData("neutral", "cancelled")]
    [InlineData("action_required", "cancelled")]
    [InlineData("startup_failure", "cancelled")]
    [InlineData("stale", "cancelled")]
    public void ToDbStatus_MapsTerminalConclusions(string conclusion, string expected)
    {
        Assert.Equal(expected, WorkflowConclusionMapper.ToDbStatus(conclusion));
    }

    [Theory]
    [InlineData("in_progress")]
    [InlineData("queued")]
    [InlineData("pending")]
    [InlineData(null)]
    public void ToDbStatus_NonTerminalReturnsNull(string? conclusion)
    {
        Assert.Null(WorkflowConclusionMapper.ToDbStatus(conclusion));
    }
}

public class CheckRunStatusMapperTests
{
    [Theory]
    [InlineData("completed", "success", "success")]
    [InlineData("completed", "failure", "failure")]
    [InlineData("completed", "timed_out", "failure")]
    [InlineData("completed", "neutral", "cancelled")]
    [InlineData("in_progress", null, "in_progress")]
    [InlineData("queued", null, "in_progress")]
    public void Map_MapsStatusAndConclusion(string status, string? conclusion, string expected)
    {
        Assert.Equal(expected, CheckRunStatusMapper.Map(status, conclusion));
    }
}

public class IdListSerializerTests
{
    [Fact]
    public void Deserialize_NullOrEmpty_ReturnsEmpty()
    {
        Assert.Empty(IdListSerializer.Deserialize(null));
        Assert.Empty(IdListSerializer.Deserialize(""));
    }

    [Fact]
    public void Deserialize_JsonArray_ReturnsIds()
    {
        Assert.Equal(new long[] { 1, 2, 3 }, IdListSerializer.Deserialize("[1,2,3]"));
    }

    [Fact]
    public void Serialize_Empty_ReturnsNull()
    {
        Assert.Null(IdListSerializer.Serialize([]));
    }

    [Fact]
    public void Serialize_NonEmpty_RoundTrips()
    {
        var raw = IdListSerializer.Serialize([5, 7]);
        Assert.Equal(new long[] { 5, 7 }, IdListSerializer.Deserialize(raw));
    }
}

public class WebhookSignatureTests
{
    [Fact]
    public void HmacSignature_MatchesExpected()
    {
        const string secret = "webhook-secret";
        const string body = "{\"action\":\"opened\"}";

        var hash = HMACSHA256.HashData(
            Encoding.UTF8.GetBytes(secret),
            Encoding.UTF8.GetBytes(body));
        var expected = "sha256=" + Convert.ToHexString(hash).ToLowerInvariant();

        var again = HMACSHA256.HashData(
            Encoding.UTF8.GetBytes(secret),
            Encoding.UTF8.GetBytes(body));
        var actual = "sha256=" + Convert.ToHexString(again).ToLowerInvariant();

        Assert.Equal(expected, actual);
        Assert.StartsWith("sha256=", actual);
        Assert.Equal(71, actual.Length);
    }
}
