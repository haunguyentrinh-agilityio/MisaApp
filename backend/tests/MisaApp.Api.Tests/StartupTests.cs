using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using MisaApp.Api.Data;

namespace MisaApp.Api.Tests;

public sealed class StartupTests
{
    [Fact]
    public void Migrate_on_startup_refuses_to_create_a_missing_database()
    {
        var path = Path.Combine(Path.GetTempPath(), $"misaapp-missing-{Guid.NewGuid():N}.db");
        using var factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Testing");
            builder.UseSetting("Database:MigrateOnStartup", "true");
            builder.UseSetting("Gemini:ApiKey", "");
            builder.ConfigureServices(services =>
            {
                services.RemoveAll<DbContextOptions<AppDbContext>>();
                services.RemoveAll<IDbContextOptionsConfiguration<AppDbContext>>();
                services.AddDbContext<AppDbContext>(options => options.UseSqlite($"DataSource={path}"));
            });
        });

        var error = Assert.Throws<InvalidOperationException>(() => factory.CreateClient());

        Assert.Contains("does not exist", error.Message);
        Assert.False(File.Exists(path));
    }
}
