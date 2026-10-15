#!/usr/bin/env bash
# Entrypoint of the migrator image (Container Apps Job caj-misaapp-<env>-migrate).
# Runs as the migrator managed identity, which is the SQL server's Entra admin:
#   1. creates the API identity's database user (idempotent) with reader/writer roles,
#   2. applies EF Core migrations with the bundled efbundle.
# Prints progress lines only; never the connection string or the environment.
set -euo pipefail

for name in SQL_SERVER SQL_DATABASE MIGRATOR_CLIENT_ID APP_IDENTITY_NAME APP_CLIENT_ID; do
  if [[ -z "${!name:-}" ]]; then
    echo "migrate: required environment variable $name is not set" >&2
    exit 2
  fi
done

# The values are embedded in T-SQL below, so only accept the shapes Terraform produces.
guid='^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
if [[ ! "$APP_CLIENT_ID" =~ $guid ]]; then
  echo "migrate: APP_CLIENT_ID is not a GUID" >&2
  exit 2
fi
if [[ ! "$APP_IDENTITY_NAME" =~ ^[A-Za-z0-9_-]{1,128}$ ]]; then
  echo "migrate: APP_IDENTITY_NAME contains unsupported characters" >&2
  exit 2
fi

cd "$(dirname "$0")"

echo "migrate: ensuring database user [$APP_IDENTITY_NAME] in $SQL_DATABASE"
# A managed identity's SID is its client ID, so the user can be created without the SQL server
# needing Microsoft Graph "Directory Readers" permission.
sqlcmd -S "$SQL_SERVER" -d "$SQL_DATABASE" \
  --authentication-method ActiveDirectoryManagedIdentity -U "$MIGRATOR_CLIENT_ID" -b -Q "
SET NOCOUNT ON;
DECLARE @name sysname = N'$APP_IDENTITY_NAME';
DECLARE @sid varbinary(16) = CAST(CAST('$APP_CLIENT_ID' AS uniqueidentifier) AS varbinary(16));
DECLARE @sql nvarchar(max);
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @name)
BEGIN
    SET @sql = N'CREATE USER ' + QUOTENAME(@name) + N' WITH SID = ' + CONVERT(varchar(34), @sid, 1) + N', TYPE = E;';
    EXEC (@sql);
    PRINT 'migrate: created user';
END
SET @sql = N'ALTER ROLE db_datareader ADD MEMBER ' + QUOTENAME(@name) + N'; '
         + N'ALTER ROLE db_datawriter ADD MEMBER ' + QUOTENAME(@name) + N';';
EXEC (@sql);
"

echo "migrate: applying EF Core migrations"
./efbundle --connection "Server=tcp:$SQL_SERVER,1433;Database=$SQL_DATABASE;Authentication=Active Directory Managed Identity;User Id=$MIGRATOR_CLIENT_ID;Encrypt=True"

echo "migrate: done"
