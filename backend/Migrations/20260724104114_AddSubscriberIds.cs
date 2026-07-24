using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace BlameTheGuilty.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddSubscriberIds : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "SubscriberIds",
                table: "PullRequestEvents",
                type: "TEXT",
                maxLength: 1000,
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "SubscriberIds",
                table: "PullRequestEvents");
        }
    }
}
