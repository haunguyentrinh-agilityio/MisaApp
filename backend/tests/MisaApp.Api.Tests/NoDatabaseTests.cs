using System.Net;

namespace MisaApp.Api.Tests;

/// <summary>The API has no database: chat content exists only in the visitor's browser.</summary>
public sealed class NoDatabaseTests(ApiFactory factory) : IClassFixture<ApiFactory>
{
    [Fact]
    public void Api_references_no_database_library()
    {
        var databaseAssemblies = typeof(Program).Assembly.GetReferencedAssemblies()
            .Select(assembly => assembly.Name ?? "")
            .Where(name => name.StartsWith("Microsoft.EntityFrameworkCore", StringComparison.Ordinal)
                || name.StartsWith("Microsoft.Data.SqlClient", StringComparison.Ordinal));

        Assert.Empty(databaseAssemblies);
    }

    [Fact]
    public async Task Health_is_healthy_without_database_configuration()
    {
        var response = await factory.CreateClient()
            .GetAsync("/api/health", TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("Healthy", await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken));
    }
}
