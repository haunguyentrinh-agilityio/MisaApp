using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.Extensions.Options;

namespace MisaApp.Api.Features.Version;

public static class VersionEndpoints
{
    public static IEndpointRouteBuilder MapVersionEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapGet("/api/version", GetVersion).WithTags("Version").WithName("GetVersion");
        return app;
    }

    // Blank settings fall back to the defaults: the contract requires non-empty strings.
    private static Ok<VersionResponse> GetVersion(IOptions<AppInfoOptions> options) =>
        TypedResults.Ok(new VersionResponse(
            string.IsNullOrWhiteSpace(options.Value.Commit) ? "dev" : options.Value.Commit,
            string.IsNullOrWhiteSpace(options.Value.Environment) ? "local" : options.Value.Environment));
}
