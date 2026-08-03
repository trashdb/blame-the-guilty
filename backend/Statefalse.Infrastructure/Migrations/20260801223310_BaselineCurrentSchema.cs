using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Statefalse.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class BaselineCurrentSchema : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateIndex(
                name: "IX_PullRequestEvents_AuthorLogin",
                table: "PullRequestEvents",
                column: "AuthorLogin");

            migrationBuilder.CreateIndex(
                name: "IX_PullRequestEvents_PrNumber",
                table: "PullRequestEvents",
                column: "PrNumber");

            migrationBuilder.CreateIndex(
                name: "IX_PullRequestEvents_Status",
                table: "PullRequestEvents",
                column: "Status");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_PullRequestEvents_AuthorLogin",
                table: "PullRequestEvents");

            migrationBuilder.DropIndex(
                name: "IX_PullRequestEvents_PrNumber",
                table: "PullRequestEvents");

            migrationBuilder.DropIndex(
                name: "IX_PullRequestEvents_Status",
                table: "PullRequestEvents");
        }
    }
}
