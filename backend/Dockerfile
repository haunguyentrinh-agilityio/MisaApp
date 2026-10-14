# syntax=docker/dockerfile:1

# ---- dev: hot reload via `dotnet watch` (used by compose.dev.yaml) ----
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS dev
WORKDIR /src
ENV DOTNET_USE_POLLING_FILE_WATCHER=true \
    DOTNET_WATCH_RESTART_ON_RUDE_EDIT=true \
    ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "watch", "--project", "src/MisaApp.Api", "run", "--no-launch-profile"]

# ---- build ----
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY global.json Directory.Build.props ./
COPY src/MisaApp.Api/MisaApp.Api.csproj src/MisaApp.Api/
RUN dotnet restore src/MisaApp.Api/MisaApp.Api.csproj
COPY src/ src/
RUN dotnet publish src/MisaApp.Api -c Release -o /app --no-restore

# ---- runtime ----
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app .
USER $APP_UID
EXPOSE 8080
ENTRYPOINT ["dotnet", "MisaApp.Api.dll"]
