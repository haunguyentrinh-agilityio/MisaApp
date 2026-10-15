# Research: CI/CD Pipeline with Branch-Based Deployment to Azure

**Feature**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md) | **Date**: 2026-10-14

Fixed by the user: GitHub Actions, Azure Container Apps, Azure SQL Database for every database
(the `sqlserver` container is removed from `compose.yaml`; local dev and CI also use Azure SQL),
Terraform for infrastructure. Stage and production need approval; develop does not.

---

## R1. Hosting: Azure Container Apps topology

- **Decision**: One Container Apps environment (Consumption) per app environment, each with:
  `ca-misaapp-<env>-web` (nginx + React build, **external** HTTPS ingress) and
  `ca-misaapp-<env>-api` (ASP.NET Core, **internal** ingress, target port 8080), plus a manual-trigger
  Container Apps Job `caj-misaapp-<env>-migrate`. **Single revision mode** for both apps.
- **Rationale**: Keeps the existing same-origin design (nginx proxies `/api/` to the API), so there's
  no CORS and no frontend change. The API isn't reachable from the internet. In single revision mode
  the platform only switches traffic once the new revision passes its readiness probe. A revision that
  never becomes ready leaves the old one serving, which covers FR-012 and FR-013 without managing
  traffic weights.
- **Alternatives considered**: Multiple revision mode with blue/green labels. It allows smoke-testing
  before cutover, but traffic weights fight with Terraform state and need two coordinated label sets
  (web and api); rejected for v1. App Service and AKS were rejected when the service was chosen.
- **Scaling**: develop/stage `min_replicas = 0` (cost), production `min_replicas = 1` for both apps
  (no cold start and no downtime during rollout).

## R2. nginx upstream inside Container Apps

- **Decision**: Turn `frontend/nginx.conf` into `frontend/nginx/default.conf.template`, which the
  official nginx image renders with `envsubst` at startup. Variables:
  - `API_UPSTREAM`: `http://backend:8080` in compose, `http://ca-misaapp-<env>-api` in Azure.
  - `NGINX_LOCAL_RESOLVERS`: filled in automatically from `/etc/resolv.conf` by the image's
    `15-local-resolvers.envsh` when `NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1`. Replaces the hard-coded `127.0.0.11`, which
    only works with Docker DNS.
  - `proxy_set_header Host $proxy_host;` and `X-Forwarded-Host $host;`.
- **Rationale**: Container Apps ingress (Envoy) routes by `Host`. Forwarding the public host to the
  internal app gives a 404, so the upstream host must be sent. The internal app sets
  `allow_insecure_connections = true` so plain HTTP inside the environment isn't redirected.
- **Alternatives considered**: Frontend calling the API's FQDN directly (needs CORS, public API);
  rejected.

## R3. Azure SQL layout and authentication

- **Decision**:
  | Server | Databases | Auth | Who connects |
  | --- | --- | --- | --- |
  | `sql-misaapp-develop-<suffix>`, `-stage`, `-production` (one per env, in that env's resource group) | `sqldb-misaapp` | **Microsoft Entra only** | API via user-assigned managed identity (`db_datareader` + `db_datawriter`); migrate job via the migrator identity (server Entra admin) |
  | `sql-misaapp-nonprod-<suffix>` (shared resource group) | `sqldb-misaapp-dev-<alias>` per developer; `sqldb-misaapp-ci-<run>` per CI run (ephemeral) | Entra + SQL auth | Developers' Docker stack and CI's Docker stack via the SQL admin login (password in the nonprod Key Vault) |
- **Rationale**:
  - Deployed environments use no passwords at all (FR-017/018).
  - Separate servers per environment give hard isolation (FR-016) and let Terraform state and role
    assignments stay per environment.
  - The Docker stack can't use a developer's `az login` token from inside a container, so local and CI
    use SQL auth, but only on the nonprod server, which holds no real data.
- **Why per-developer and per-CI-run databases instead of one shared "local" and one shared "ci"
  database**: branches carry different migrations. With a shared database, the first branch to apply a
  migration breaks every other branch's stack and E2E run. Per-developer databases cost the same as a
  shared one under the free offer (below). Per-run CI databases also remove cross-run test
  interference.
- **Alternatives considered**: Docker-free Entra auth in compose (mounting the az CLI token cache,
  fragile on Windows); a shared local/ci database (schema clashes, as above); SQL container in CI only
  (explicitly declined by the user).

## R4. Azure SQL SKUs and cost

- **Decision** (per-environment `tfvars`, so it can change without code):
  | Database | SKU | Notes |
  | --- | --- | --- |
  | `dev-<alias>` | General Purpose serverless `GP_S_Gen5_1`, auto-pause 60 min, **free offer** | Up to 10 free databases per subscription |
  | `ci-<run>` | Basic (5 DTU, 2 GB) | Lives for about 15 min, billed hourly (fractions of a cent per run) |
  | develop, stage | `GP_S_Gen5_1`, auto-pause 60 min, free offer if capacity remains, else billed serverless | Resume takes about 1 min; covered by SqlClient retry plus the 180 s wait in E2E global setup |
  | production | Standard S0 (10 DTU), no auto-pause | Predictable, no cold start; scale up through `tfvars` |
- **To verify during implementation**: whether the pinned `azurerm` version exposes the free-offer
  properties (`useFreeLimit`, `freeLimitExhaustionBehavior`). If not, set them with
  `azapi_update_resource` on the database.
- **Verified during implementation**: `azurerm` 5.9 has no free-offer properties, and Microsoft's docs
  state that an existing database can't be converted to the free offer. `azapi_update_resource` would
  therefore fail. Free-offer databases are created with `azapi_resource`
  (`Microsoft.Sql/servers/databases@2023-08-01`, sku `GP_S_Gen5` capacity 1, `useFreeLimit = true`,
  `freeLimitExhaustionBehavior = "AutoPause"`, `autoPauseDelay = 60`, `minCapacity = 0.5`, max 32 GB).
  The body passed azapi's embedded schema validation. The environment root picks `azapi_resource` or
  `azurerm_mssql_database` with `count` on `sql_use_free_offer`; changing that flag replaces the
  database, so it is a create-time choice.

## R5. Database migrations as a deployment step (FR-011)

- **Decision**:
  - Build a **migrator image** from a new `migrator` stage in `backend/Dockerfile`: an EF Core
    migrations bundle (`dotnet ef migrations bundle --self-contained -r linux-x64`), `go-sqlcmd`, and
    an entrypoint script.
  - The script runs as the migrator managed identity (the server's Entra admin):
    1. Idempotently create the API identity's database user with
       `CREATE USER [...] WITH SID = <sid from client id>, TYPE = E` and grant reader and writer roles.
    2. Run the bundle.
  - The pipeline starts the job with `az containerapp job start --image <migrator:sha>`, polls the
    execution until it reaches `Succeeded` or `Failed`, and only then applies the new app images.
  - `Database__MigrateOnStartup` stays `false` in every Azure environment. Compose keeps `true`.
- **Rationale**:
  - The job runs inside Azure, so the runner never needs a SQL firewall hole for deployed
    environments.
  - The API identity gets no DDL rights.
  - Creating the user from its SID avoids giving the SQL server Microsoft Graph "Directory Readers"
    permission.
  - EF applies each migration in a transaction on SQL Server, so a failure leaves the schema at the
    last good migration and the old app keeps running.
- **Rule** (documented in `docs/deployment.md`): migrations must be **backward compatible with the
  version still running** (expand/contract), because the old revision serves traffic until the new
  one is ready, and a rollback doesn't revert the schema.
- **To verify**: `go-sqlcmd` flags for a user-assigned managed identity
  (`--authentication-method ActiveDirectoryManagedIdentity` plus the client ID as user name).
  **Verified during implementation**: go-sqlcmd v1.10.0 lists `ActiveDirectoryManagedIdentity` under
  `--authentication-method`; the go-mssqldb driver takes the user-assigned client ID as the user name.
  The tarball is checked against its release `sha256` in the `bundle` stage.
  Also found: the RID-specific restore the bundle needs runs NuGet audit, which failed on transitive
  `System.Security.Cryptography.Pkcs` 9.0.11 (CVE-2026-84008, CVE-2026-70162). The API project now
  references 10.0.13 directly.
- **Alternatives considered**: `MigrateOnStartup` in Azure (races between replicas, the API needs
  DDL); running `efbundle` from the GitHub runner (needs a firewall opening on prod SQL); SQL scripts
  via `dotnet ef migrations script --idempotent` (needs `sqlcmd` on the runner plus a firewall opening,
  same objection).

## R6. Build once, deploy what was tested (FR-005, FR-006, FR-007)

- **Decision**:
  - On every push to `develop`/`stag`/`main`, the `build` job builds three images and pushes them to
    the shared registry `crmisaapp<suffix>`, tagged with the full commit SHA:
    `misaapp-api`, `misaapp-web`, `misaapp-migrator`.
  - Each image gets build arg `SOURCE_COMMIT=<sha>`, baked into `App__Commit` (API) and the OCI label
    `org.opencontainers.image.revision`.
  - E2E in the deploy run then **pulls those exact images** (via `compose.ci.yaml`) instead of
    building again.
  - Terraform deploys images by digest-stable SHA tag.
  - A promotion merge (`develop` → `stag`) creates a new commit and therefore a new build. That
    satisfies "once per commit", and the commit tested in the `stag` run is the one deployed to stage.
- **Retention**: an ACR Task in `infra/shared` runs `acr purge` daily and keeps the newest 30 tags
  per repository and anything younger than 90 days. With three environments that is more than
  5 rollback targets each (FR-007).
- **Alternatives considered**: Re-tagging one image across environments (needs fast-forward-only
  promotion, which conflicts with PR merges); per-environment registries (more cost, no benefit at
  this scale).

## R7. Workflow structure, OIDC identities, approvals

- **Decision**: three workflows:
  - `ci.yml`: `pull_request` to `develop`/`stag`/`main`, plus `workflow_call`.
  - `deploy.yml`: `push` to the three branches, plus `workflow_dispatch` for redeploy and rollback.
  - `cleanup-ci-databases.yml`: hourly schedule.

  Jobs in `deploy.yml`:
  `build` → `checks` (calls `ci.yml` with `image_tag`; E2E pulls the images `build` pushed) → `plan` (no environment) →
  `deploy` (GitHub environment `develop` | `stage` | `production`).
- **Approvals (FR-009)**: GitHub Environments `stage` and `production` have **required reviewers**
  and deployment-branch rules (`stag` / `main` only). `develop` has a branch rule only. GitHub records
  every approval and rejection (who, when) and expires pending approvals after 30 days.
- **Showing planned changes to the approver (FR-020a)**: the `plan` job writes `terraform show` output
  to the run summary and uploads the binary plan as an artifact. The approved `deploy` job applies that
  saved plan, so the approver approves exactly what they saw.
- **Identities**: GitHub OIDC with federated credentials. There are **no Azure secrets in GitHub**;
  only client IDs, tenant ID, and subscription ID are stored, as variables.
  | Identity | Federated subject | Rights |
  | --- | --- | --- |
  | `id-misaapp-gh-ci` | `pull_request`, `ref:refs/heads/{develop,stag,main}` | SQL DB Contributor + SQL Server Contributor (firewall rules) on `sql-misaapp-nonprod-<suffix>`; Key Vault Secrets User on nonprod Key Vault; AcrPull |
  | `id-misaapp-gh-build` | `ref:refs/heads/{develop,stag,main}` | AcrPush |
  | `id-misaapp-gh-plan-<env>` | `ref:refs/heads/<branch>` | Reader on env and shared resource groups; custom role with `Microsoft.App/containerApps/listSecrets/action` if `azurerm` refresh needs it; Storage Blob Data Reader on the env state container (plan runs with `-lock=false`) |
  | `id-misaapp-gh-deploy-<env>` | `environment:<env>` | Contributor + Role Based Access Control Administrator (limited by condition to AcrPull, Key Vault Secrets User) on env resource group; Storage Blob Data Contributor on env state container. `develop` also gets Contributor on the shared and nonprod resources (applies `infra/shared`) |
- **Rationale**:
  - The deploy identity can only be used from a job that passed the environment's protection rules,
    so the approval can't be bypassed by another workflow.
  - The plan identity is read-only, so running it before approval is safe.
- **Superseded releases (FR-010)**:
  - `deploy` job concurrency is `deploy-<env>` with `cancel-in-progress: false`, so applies never run
    in parallel.
  - The first step of `deploy` checks `git ls-remote origin <branch>`. If the run's SHA is no longer
    the branch head, it exits as "superseded" before touching Azure. An approver who approves an old
    pending release therefore deploys nothing, and the newest run deploys the newest commit.
  - Manual rollbacks skip this check.
- **Alternatives considered**: Terraform plan in the PR (needs Azure credentials on PRs for all
  environments and goes stale by merge time); one identity for everything (no least privilege).

## R8. Rollback and post-deploy verification (FR-012, FR-014, SC-004)

- **Decision**:
  - Terraform takes `image_tag` as a variable.
  - **Deploy** = migrate job, then `terraform apply` of the saved plan, then a smoke test.
  - **Manual rollback / redeploy** = `workflow_dispatch` of `deploy.yml` with inputs
    `environment` and `image_tag`. It skips build, tests, and migrations, but still goes through plan
    and approval for stage and production, so it is audited the same way. It first checks the tag
    exists in the registry.
  - **Automatic rollback**: before applying, the deploy job reads the current `image_tag` from
    Terraform output. If the smoke test fails, it re-applies with that previous tag and fails the run,
    which notifies the team (FR-022).
- **Smoke test**: Playwright tests tagged `@smoke` (new `frontend/e2e/tests/smoke.spec.ts`) run
  against the environment's public URL. They check that the page loads, `/api/health` returns
  `Healthy`, and `/api/version` reports the expected commit. They make no chat call, so production
  never writes test data or uses Gemini quota. Full E2E has already passed against the same images
  before deployment.
- **Alternatives considered**: `az containerapp revision activate` of the old revision (state drifts
  from Terraform, old revisions get deprovisioned in single mode).

## R9. Terraform layout and state

- **Decision**:
  - `infra/bootstrap/bootstrap.sh`: idempotent az and gh CLI script, run once by an admin (FR-020c).
    It creates:
    - resource groups `rg-misaapp-{shared,develop,stage,production}`
    - state storage account `stmisaapptf<suffix>` (versioning + soft delete; one container per root:
      `tfstate-shared`, `tfstate-develop`, …)
    - the identities, federated credentials, and role assignments from R7
    - the GitHub environments, reviewers, variables, and branch rulesets.
  - `infra/shared/` (Terraform root): ACR + purge task, nonprod SQL server + per-developer databases
    (`developers` list variable), nonprod Key Vault with generated SQL admin password. Applied by the
    develop deploy job.
  - `infra/environment/` (Terraform root, one state per env via `-backend-config`, with
    `develop.tfvars`, `stage.tfvars`, `production.tfvars`):
    - Log Analytics
    - Container Apps environment, web and api apps, migrate job
    - user-assigned identities (`id-misaapp-<env>-api`, `id-misaapp-<env>-migrator`)
    - SQL server + database, Key Vault
    - role assignments.
  - Environments differ only in `tfvars` (SKUs, replicas, names, `gemini_enabled`).
  - `lifecycle { prevent_destroy = true }` on SQL servers, databases, ACR, and state storage
    (edge case: a plan that deletes a stateful resource fails).
- **Versions**: latest stable Terraform 1.x and `azurerm` at implementation time, pinned with
  `required_version`, `~>` constraints, and a committed `.terraform.lock.hcl`. `azapi` only if R4
  needs it. **Resolved during implementation**: Terraform `~> 1.16.0`; `azurerm` 5.x had shipped
  by then (5.9.0), so the pin is `~> 5.9` rather than 4.x; `random ~> 3.9`.
- **Quality gates on PRs**: `terraform fmt -check`, `terraform validate`, `tflint`, and
  `trivy config` (IaC misconfiguration). These need no Azure credentials.
- **Alternatives considered**: Terraform for bootstrap (chicken-and-egg with its own state backend and
  needs Graph permissions for federated credentials; a CLI script is simpler for a once-only step);
  Bicep (user chose Terraform); Terraform GitHub provider for environments (needs a GitHub admin token
  stored as a secret).

## R10. Secrets and configuration (FR-017, SC-006)

- **Decision**:
  - The Gemini API key lives only in the environment Key Vault (`kv-misaapp-<code>-<suffix>`, RBAC
    mode). An admin sets it once with `az keyvault secret set`. Terraform never holds the value.
  - Key Vault names are limited to 24 characters, so they use short codes: `dev`, `stg`, `prd` for
    the environments and `np` for nonprod (`kv-misaapp-prd-abc123` is 21 characters).
  - When `gemini_enabled = true` in tfvars (production; optional elsewhere), the API container app
    gets a Key Vault reference secret mapped to `Gemini__ApiKey`.
  - When `false`, no secret is mapped, and the app falls back to the echo model.
  - **Preflight**: before applying, the deploy job runs
    `az keyvault secret show --query id` (never the value). If the secret is missing it fails with
    "Key Vault secret gemini-api-key missing in kv-…".
  - The nonprod SQL admin password is generated by Terraform (`random_password`, no `;'"` characters)
    into the nonprod Key Vault.
  - CI reads it with `az keyvault secret show` and immediately masks it (`::add-mask::`).
  - Developers read it once into their `.env`.
- **Secret scanning**: `gitleaks` job in `ci.yml`. GitHub push protection is turned on in the
  repository settings (bootstrap).
- **Alternatives considered**: GitHub environment secrets for the Gemini key (passes the secret
  through the runner and Terraform state); rejected.

## R11. CI end-to-end tests against Azure SQL

- **Decision**: the `e2e` job in `ci.yml`:
  1. `azure/login` (CI identity).
  2. Create `sqldb-misaapp-ci-<run_id>-<attempt>` (Basic, tagged `createdUtc`) on the nonprod server.
  3. Add a firewall rule for the runner's public IP.
  4. Read and mask the SQL password.
  5. `docker compose --profile e2e up` with `SQL_CONNECTION_STRING` pointing at the new database
     (`MigrateOnStartup=true` creates the schema).
  6. Run Playwright.
  7. In an `always()` step, delete the database and firewall rule.

  `cleanup-ci-databases.yml` deletes any `ci-*` database and `ci-*` firewall rule older than 2 hours,
  covering runs that were cancelled or crashed.
- **Fork PRs**: there's no OIDC token for forks, so E2E is skipped with a notice. Unit, lint, and
  build checks still run. The repository is private, so this is expected to be rare.
- **Cost and time**: about 1–2 min to create the database, which fits the 20-minute target (SC-001).

## R12. App changes required

- **`GET /api/version`** (new `Features/Version/`): returns `{ commit, environment }` from the
  `App:Commit` and `App:Environment` settings. It lets anyone check which commit an environment runs
  (FR-006, SC-005) and is what the smoke test checks. Contract:
  [contracts/version-api.openapi.yaml](contracts/version-api.openapi.yaml).
- **SQL Server authentication**: no code change. Connection strings use
  `Authentication=Active Directory Managed Identity;User Id=<client-id>` in Azure and SQL auth
  elsewhere. **To verify**: if the resolved `Microsoft.Data.SqlClient` is 7.x, Entra auth moved to
  `Microsoft.Data.SqlClient.Extensions.Azure`, so add that package. 6.x includes it.
  **Verified during implementation**: EF Core SqlServer 10.0.13 resolves `Microsoft.Data.SqlClient`
  6.1.7 (with `Azure.Identity` 1.17.1), so no extra package is needed.
- **Health probes**: API readiness and startup probes on `/api/health` (includes the DB check);
  liveness on the same path with a longer threshold. Web readiness on `/`.
- `ASPNETCORE_ENVIRONMENT=Production` in all Azure environments (no OpenAPI, no developer exception
  page). `App__Environment` carries the display name.
