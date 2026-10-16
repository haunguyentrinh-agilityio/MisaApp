using System.Text.Json;
using System.Text.Json.Serialization;
using MisaApp.Api.Features.Chat;
using MisaApp.Api.Features.Version;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenApi();
builder.Services.AddProblemDetails();
builder.Services.AddValidation();
builder.Services.ConfigureHttpJsonOptions(options =>
    // Strings only: a numeric role such as 5 would otherwise bind to an undefined ChatRole.
    options.SerializerOptions.Converters.Add(
        new JsonStringEnumConverter(JsonNamingPolicy.CamelCase, allowIntegerValues: false)));

builder.Services.AddHealthChecks();
builder.Services.AddChat(builder.Configuration);
builder.Services.AddVersion(builder.Configuration);

var app = builder.Build();

if (app.Services.GetRequiredService<IChatModel>() is EchoChatModel)
{
    app.Logger.LogWarning("Gemini:ApiKey is not configured; chat replies will be echoed back.");
}

app.UseExceptionHandler();
app.UseStatusCodePages();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.MapHealthChecks("/api/health");
app.MapChatEndpoints();
app.MapVersionEndpoints();

app.Run();

public partial class Program;
