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

# ---- bundle: EF Core migrations bundle + go-sqlcmd for the migrator image ----
FROM build AS bundle
ARG SQLCMD_VERSION=v1.10.0
ARG SQLCMD_SHA256=92516d98c63d99b0994de5b61350c91f6915f9b76f139a59039fbcb225c2e987
COPY dotnet-tools.json ./
RUN dotnet tool restore
# The bundle is self-contained for linux-x64, so it needs a RID-specific restore.
RUN dotnet restore src/MisaApp.Api -r linux-x64
RUN dotnet ef migrations bundle --project src/MisaApp.Api --configuration Release \
        --self-contained -r linux-x64 -o /out/efbundle
RUN apt-get update && apt-get install -y --no-install-recommends bzip2 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /tmp/sqlcmd.tar.bz2 \
        "https://github.com/microsoft/go-sqlcmd/releases/download/${SQLCMD_VERSION}/sqlcmd-linux-amd64.tar.bz2" \
    && echo "${SQLCMD_SHA256}  /tmp/sqlcmd.tar.bz2" | sha256sum -c - \
    && tar -xjf /tmp/sqlcmd.tar.bz2 -C /out sqlcmd

# ---- migrator: runs deploy/migrate.sh as a Container Apps Job ----
FROM mcr.microsoft.com/dotnet/runtime-deps:10.0 AS migrator
WORKDIR /app
COPY --from=bundle /out/sqlcmd /usr/local/bin/sqlcmd
COPY --from=bundle /out/efbundle ./efbundle
COPY --chmod=755 deploy/migrate.sh ./migrate.sh
USER $APP_UID
ENTRYPOINT ["/app/migrate.sh"]

# ---- runtime ----
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
ARG SOURCE_COMMIT=dev
LABEL org.opencontainers.image.revision=$SOURCE_COMMIT
ENV App__Commit=$SOURCE_COMMIT
WORKDIR /app
COPY --from=build /app .
USER $APP_UID
EXPOSE 8080
ENTRYPOINT ["dotnet", "MisaApp.Api.dll"]
