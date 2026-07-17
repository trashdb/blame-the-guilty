using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace BlameTheGuilty.Api.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "CheckSuiteEvents",
                columns: table => new
                {
                    Id = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    CheckSuiteId = table.Column<long>(type: "INTEGER", nullable: false),
                    Conclusion = table.Column<string>(type: "TEXT", maxLength: 50, nullable: false),
                    HeadBranch = table.Column<string>(type: "TEXT", maxLength: 200, nullable: true),
                    HeadSha = table.Column<string>(type: "TEXT", maxLength: 40, nullable: true),
                    PrAuthorLogin = table.Column<string>(type: "TEXT", maxLength: 100, nullable: true),
                    PrAuthorGitHubId = table.Column<long>(type: "INTEGER", nullable: true),
                    PrNumber = table.Column<int>(type: "INTEGER", nullable: true),
                    RepoFullName = table.Column<string>(type: "TEXT", maxLength: 200, nullable: false),
                    OccurredAt = table.Column<DateTime>(type: "TEXT", nullable: false),
                    WasNotified = table.Column<bool>(type: "INTEGER", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_CheckSuiteEvents", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "GitHubUsers",
                columns: table => new
                {
                    Id = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    GitHubId = table.Column<long>(type: "INTEGER", nullable: false),
                    GitHubUsername = table.Column<string>(type: "TEXT", maxLength: 100, nullable: false),
                    AccessToken = table.Column<string>(type: "TEXT", nullable: true),
                    UserPatToken = table.Column<string>(type: "TEXT", nullable: true),
                    SignalRConnectionId = table.Column<string>(type: "TEXT", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "TEXT", nullable: false),
                    LastLoginAt = table.Column<DateTime>(type: "TEXT", nullable: true),
                    AvatarUrl = table.Column<string>(type: "TEXT", maxLength: 500, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_GitHubUsers", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "PullRequestEvents",
                columns: table => new
                {
                    Id = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    PrNumber = table.Column<long>(type: "INTEGER", nullable: false),
                    Title = table.Column<string>(type: "TEXT", maxLength: 300, nullable: false),
                    AuthorLogin = table.Column<string>(type: "TEXT", maxLength: 100, nullable: false),
                    AuthorGitHubId = table.Column<long>(type: "INTEGER", nullable: true),
                    RepoFullName = table.Column<string>(type: "TEXT", maxLength: 200, nullable: false),
                    HeadBranch = table.Column<string>(type: "TEXT", maxLength: 200, nullable: true),
                    BaseBranch = table.Column<string>(type: "TEXT", maxLength: 200, nullable: true),
                    PrUrl = table.Column<string>(type: "TEXT", nullable: true),
                    Status = table.Column<string>(type: "TEXT", maxLength: 30, nullable: false),
                    Conclusion = table.Column<string>(type: "TEXT", maxLength: 50, nullable: true),
                    Draft = table.Column<bool>(type: "INTEGER", nullable: false),
                    MergeableState = table.Column<string>(type: "TEXT", maxLength: 50, nullable: true),
                    ReviewApproved = table.Column<bool>(type: "INTEGER", nullable: false),
                    ApprovedBy = table.Column<string>(type: "TEXT", maxLength: 100, nullable: true),
                    LastCommentBy = table.Column<string>(type: "TEXT", maxLength: 100, nullable: true),
                    LastCommentBody = table.Column<string>(type: "TEXT", maxLength: 500, nullable: true),
                    LastCommentAt = table.Column<DateTime>(type: "TEXT", nullable: true),
                    LastCommentUrl = table.Column<string>(type: "TEXT", maxLength: 500, nullable: true),
                    LastReviewFilePath = table.Column<string>(type: "TEXT", maxLength: 500, nullable: true),
                    LastReviewLine = table.Column<int>(type: "INTEGER", nullable: true),
                    ExtraInfo = table.Column<string>(type: "TEXT", maxLength: 500, nullable: true),
                    HeadSha = table.Column<string>(type: "TEXT", maxLength: 40, nullable: true),
                    OccurredAt = table.Column<DateTime>(type: "TEXT", nullable: false),
                    WasNotified = table.Column<bool>(type: "INTEGER", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PullRequestEvents", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "PunishmentEvents",
                columns: table => new
                {
                    Id = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    RunId = table.Column<long>(type: "INTEGER", nullable: false),
                    CulpritLogin = table.Column<string>(type: "TEXT", maxLength: 100, nullable: false),
                    CulpritGitHubId = table.Column<long>(type: "INTEGER", nullable: true),
                    RepoFullName = table.Column<string>(type: "TEXT", maxLength: 200, nullable: false),
                    WorkflowName = table.Column<string>(type: "TEXT", maxLength: 200, nullable: true),
                    WorkflowUrl = table.Column<string>(type: "TEXT", nullable: true),
                    OccurredAt = table.Column<DateTime>(type: "TEXT", nullable: false),
                    WasNotified = table.Column<bool>(type: "INTEGER", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PunishmentEvents", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "WorkflowRuns",
                columns: table => new
                {
                    Id = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    RunId = table.Column<long>(type: "INTEGER", nullable: false),
                    GitHubId = table.Column<long>(type: "INTEGER", nullable: false),
                    WorkflowName = table.Column<string>(type: "TEXT", maxLength: 200, nullable: true),
                    Repo = table.Column<string>(type: "TEXT", maxLength: 200, nullable: false),
                    Actor = table.Column<string>(type: "TEXT", maxLength: 100, nullable: false),
                    HeadBranch = table.Column<string>(type: "TEXT", maxLength: 200, nullable: true),
                    Trigger = table.Column<string>(type: "TEXT", maxLength: 50, nullable: true),
                    HtmlUrl = table.Column<string>(type: "TEXT", nullable: true),
                    HeadSha = table.Column<string>(type: "TEXT", maxLength: 40, nullable: true),
                    Status = table.Column<string>(type: "TEXT", maxLength: 20, nullable: false),
                    StartedAt = table.Column<DateTime>(type: "TEXT", nullable: false),
                    TargetGitHubIds = table.Column<string>(type: "TEXT", nullable: true),
                    IsIgnored = table.Column<bool>(type: "INTEGER", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_WorkflowRuns", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_CheckSuiteEvents_Conclusion",
                table: "CheckSuiteEvents",
                column: "Conclusion");

            migrationBuilder.CreateIndex(
                name: "IX_CheckSuiteEvents_OccurredAt",
                table: "CheckSuiteEvents",
                column: "OccurredAt");

            migrationBuilder.CreateIndex(
                name: "IX_CheckSuiteEvents_PrAuthorLogin",
                table: "CheckSuiteEvents",
                column: "PrAuthorLogin");

            migrationBuilder.CreateIndex(
                name: "IX_GitHubUsers_GitHubId",
                table: "GitHubUsers",
                column: "GitHubId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_GitHubUsers_GitHubUsername",
                table: "GitHubUsers",
                column: "GitHubUsername",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_PunishmentEvents_CulpritLogin",
                table: "PunishmentEvents",
                column: "CulpritLogin");

            migrationBuilder.CreateIndex(
                name: "IX_PunishmentEvents_OccurredAt",
                table: "PunishmentEvents",
                column: "OccurredAt");

            migrationBuilder.CreateIndex(
                name: "IX_WorkflowRuns_GitHubId",
                table: "WorkflowRuns",
                column: "GitHubId");

            migrationBuilder.CreateIndex(
                name: "IX_WorkflowRuns_RunId",
                table: "WorkflowRuns",
                column: "RunId");

            migrationBuilder.CreateIndex(
                name: "IX_WorkflowRuns_Status",
                table: "WorkflowRuns",
                column: "Status");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "CheckSuiteEvents");

            migrationBuilder.DropTable(
                name: "GitHubUsers");

            migrationBuilder.DropTable(
                name: "PullRequestEvents");

            migrationBuilder.DropTable(
                name: "PunishmentEvents");

            migrationBuilder.DropTable(
                name: "WorkflowRuns");
        }
    }
}
