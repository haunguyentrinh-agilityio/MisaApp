# Contract: Infrastructure (Terraform roots + runtime configuration)

Research: R1–R5, R9, R10. Names use `<env>` ∈ {develop, stage, production} and a global `suffix`
(lower-case alphanumeric, ≤ 6 chars) for globally unique names.

## `infra/environment` (one state per environment)

Init: `terraform init -backend-config="storage_account_name=$TFSTATE_ACCOUNT" -backend-config="container_name=tfstate-<env>" -backend-config="key=environment.tfstate"` (Azure AD auth, `use_oidc = true`).

### Variables

| Name | Type | Required | Notes |
| --- | --- | --- | --- |
| `environment` | string | yes | validation: develop/stage/production |
| `location` | string | yes | e.g. `southeastasia` |
| `suffix` | string | yes | global-uniqueness suffix |
| `image_tag` | string | yes | 40-char SHA; validation regex `^[0-9a-f]{40}$` |
| `acr_name` | string | yes | shared registry (data source) |
| `sql_sku` | string | yes | `GP_S_Gen5_1`, `S0`, … |
| `sql_auto_pause_minutes` | number | no | `-1` disables; only for serverless |
| `sql_use_free_offer` | bool | no | default false |
| `web_min_replicas` / `web_max_replicas` | number | yes | |
| `api_min_replicas` / `api_max_replicas` | number | yes | |
| `gemini_enabled` | bool | yes | maps Key Vault secret `gemini-api-key` → `Gemini__ApiKey` when true |
| `gemini_model` | string | no | default `gemini-3.8-flash` |
| `log_retention_days` | number | no | default 30 |

### Outputs

| Name | Used by |
| --- | --- |
| `web_url` | GitHub `environment.url`, smoke test `BASE_URL` |
| `image_tag` | rollback capture (previous tag) |
| `migrate_job_name`, `resource_group_name` | migrate step |
| `key_vault_name` | preflight |

### Resources (all in `rg-misaapp-<env>`, created by bootstrap)

`log-misaapp-<env>`, `cae-misaapp-<env>`, `ca-misaapp-<env>-web`, `ca-misaapp-<env>-api`,
`caj-misaapp-<env>-migrate`, `id-misaapp-<env>-api`, `id-misaapp-<env>-migrator`,
`sql-misaapp-<env>-<suffix>` (Entra-only, admin = migrator identity, TLS 1.2, `prevent_destroy`),
`sqldb-misaapp` (`prevent_destroy`), `kv-misaapp-<code>-<suffix>` with `<code>` = `dev` | `stg` |
`prd` (Key Vault names are limited to 24 characters; RBAC, purge protection), role
assignments (AcrPull ×2, Key Vault Secrets User → api identity).

## `infra/shared`

| Variable | Type | Notes |
| --- | --- | --- |
| `location`, `suffix` | string | |
| `developers` | list(string) | aliases → `sqldb-misaapp-dev-<alias>` |
| `ci_principal_id` | string | CI identity object ID, for role assignments it needs on the nonprod server |

Resources: `crmisaapp<suffix>` (Standard, admin user disabled, `prevent_destroy`) + daily purge task;
`sql-misaapp-nonprod-<suffix>` (Entra + SQL auth, `prevent_destroy`); developer databases;
`kv-misaapp-np-<suffix>` with `sql-admin-password` (`random_password`, 32 chars, no `;'"`);
firewall rule "Allow Azure services" **not** set (developers/CI add their own IP rules).

Outputs: `acr_login_server`, `nonprod_sql_fqdn`, `nonprod_key_vault_name`.

## Runtime configuration contract

### API container (`misaapp-api`)

| Env var | Azure value | Compose value |
| --- | --- | --- |
| `ASPNETCORE_ENVIRONMENT` | `Production` | `${ASPNETCORE_ENVIRONMENT:-Development}` |
| `ConnectionStrings__Default` | `Server=tcp:sql-misaapp-<env>-<suffix>.database.windows.net,1433;Database=sqldb-misaapp;Authentication=Active Directory Managed Identity;User Id=<api client id>;Encrypt=True` | `${SQL_CONNECTION_STRING}` (SQL auth to `sql-misaapp-nonprod-<suffix>`) |
| `Database__MigrateOnStartup` | `false` | `true` |
| `Gemini__ApiKey` | Key Vault ref (only if `gemini_enabled`) | `${GEMINI_API_KEY:-}` |
| `Gemini__Model` | `var.gemini_model` | `${GEMINI_MODEL:-gemini-3.8-flash}` |
| `App__Commit` | baked in image | baked in image (`dev` unless built with `SOURCE_COMMIT`) |
| `App__Environment` | `<env>` | `local` |

Probes: startup + readiness `GET /api/health` (port 8080), liveness `GET /api/health` (failure
threshold 5). Ingress: internal, target port 8080, `allow_insecure_connections = true`.

### Web container (`misaapp-web`)

| Env var | Azure value | Compose value |
| --- | --- | --- |
| `API_UPSTREAM` | `http://ca-misaapp-<env>-api.internal.<environment domain>` (the API's ingress FQDN; nginx doesn't apply resolv.conf search domains) | `http://backend:8080` |
| `NGINX_ENTRYPOINT_LOCAL_RESOLVERS` | `1` | `1` |

Ingress: external, target port 80, HTTPS only. Readiness `GET /`.

### Migrate job (`misaapp-migrator`)

| Env var | Value |
| --- | --- |
| `SQL_SERVER`, `SQL_DATABASE` | env server FQDN, `sqldb-misaapp` |
| `MIGRATOR_CLIENT_ID` | migrator identity client ID (authenticates as Entra admin) |
| `APP_IDENTITY_NAME`, `APP_CLIENT_ID` | API identity; the script creates/grants its DB user (SID from client ID) |

Exit code 0 = schema at latest migration and API user present; non-zero = failed (no app rollout).
Trigger: manual; replica timeout 600 s; retry limit 0.

## Local `.env` contract (replaces `MSSQL_SA_PASSWORD`, `SQL_PORT`)

```dotenv
# Azure SQL dev database (sql-misaapp-nonprod-<suffix> / sqldb-misaapp-dev-<alias>); see docs/deployment.md
SQL_CONNECTION_STRING=Server=tcp:sql-misaapp-nonprod-<suffix>.database.windows.net,1433;Database=sqldb-misaapp-dev-<alias>;User Id=<admin>;Password=<from Key Vault>;Encrypt=True
GEMINI_API_KEY=
GEMINI_MODEL=gemini-3.8-flash
WEB_PORT=3000
API_PORT=8080
```
