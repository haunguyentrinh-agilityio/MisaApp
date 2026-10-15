namespace MisaApp.Api.Features.Version;

public sealed record VersionResponse(string Commit, string Environment);

public sealed class AppInfoOptions
{
    public const string SectionName = "App";

    /// <summary>Git commit SHA baked into the image (build arg SOURCE_COMMIT → App__Commit).</summary>
    public string Commit { get; set; } = "dev";

    /// <summary>Deployment name: develop, stage, production in Azure; local otherwise.</summary>
    public string Environment { get; set; } = "local";
}
