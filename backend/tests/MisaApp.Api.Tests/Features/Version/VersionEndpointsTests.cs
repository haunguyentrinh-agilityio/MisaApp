using System.Net;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;

namespace MisaApp.Api.Tests.Features.Version;

public sealed class VersionEndpointsTests(ApiFactory factory) : IClassFixture<ApiFactory>
{
    [Fact]
    public async Task GetVersion_default_config_returns_dev_and_local()
    {
        var response = await factory.CreateClient()
            .GetAsync("/api/version", TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var json = JsonDocument.Parse(
            await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken));
        Assert.Equal(["commit", "environment"], json.RootElement.EnumerateObject().Select(p => p.Name));
        Assert.Equal("dev", json.RootElement.GetProperty("commit").GetString());
        Assert.Equal("local", json.RootElement.GetProperty("environment").GetString());
    }

    [Fact]
    public async Task GetVersion_configured_values_are_returned()
    {
        const string commit = "3f9c2d0e8b1a4c5d6e7f8091a2b3c4d5e6f70812";
        var client = factory.WithWebHostBuilder(builder =>
        {
            builder.UseSetting("App:Commit", commit);
            builder.UseSetting("App:Environment", "stage");
        }).CreateClient();

        var response = await client.GetAsync("/api/version", TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var json = JsonDocument.Parse(
            await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken));
        Assert.Equal(commit, json.RootElement.GetProperty("commit").GetString());
        Assert.Equal("stage", json.RootElement.GetProperty("environment").GetString());
    }
}
