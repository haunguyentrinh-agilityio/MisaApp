---

description: "Task list for 002-cicd-azure-deploy"
---

# Tasks: CI/CD Pipeline with Branch-Based Deployment to Azure

**Input**: Design documents from `specs/002-cicd-azure-deploy/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: Required by constitution Principle II:
- the new endpoint gets an xUnit integration test (`ApiFactory`)
- the new post-deploy check gets a Playwright `@smoke` test
- the existing E2E suite keeps running, now against Azure SQL.

Acceptance scenarios that are GitHub or Azure platform behavior are covered by quickstart validation
runs. This is the justified exception in plan.md Complexity Tracking. See the coverage table at the
end.

**Organization**: Tasks are grouped by user story. **US2 comes before US1** even though both are P1,
because the deploy pipeline (US1) reuses the PR checks workflow (`ci.yml`) as its quality gate
(FR-002).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1–US5)
- Paths are repository-relative.

## Path Conventions

- Backend: `backend/src/MisaApp.Api/`, tests in `backend/tests/MisaApp.Api.Tests/`
- Frontend: `frontend/`, E2E in `frontend/e2e/`
- Infrastructure: `infra/` (Terraform roots `infra/shared`, `infra/environment`; scripts in `infra/scripts`)
- Workflows: `.github/workflows/`

## Design corrections found while generating tasks

Phase 1 fixes these in the design docs before any code depends on them:

1. **Key Vault names exceed Azure's 24-character limit.** For example, `kv-misaapp-production-abc123` is
   28 characters and `kv-misaapp-nonprod-abc123` is 25. Fix: use short environment codes
   `dev`/`stg`/`prd`/`np`, giving `kv-misaapp-<code>-<suffix>` (21 characters or fewer). Every other
   resource name fits its limit:
   - container app and job names: 32 maximum
   - storage account: 24 maximum
   - registry: 50 maximum
2. **First-ever CI run has no nonprod SQL server.** The PR `e2e` check needs `sql-misaapp-nonprod-<suffix>`, but
   `infra/shared` was only going to be applied by the develop deploy, which itself waits for checks to
   pass. Fix: `bootstrap.sh` applies `infra/shared` once at the end. After that, the develop deploy
   keeps it up to date.
3. **First deploy of an environment can't run migrations.** The migrate job and the SQL database don't
   exist until Terraform creates them. Fix: when there is no previous `image_tag` output, the deploy job:
   1. does a targeted apply of the migrate job and its dependencies
   2. runs the migration
   3. re-plans and applies (the saved plan is stale after the targeted apply).
4. **Rollback dispatch must run on the environment's branch.** GitHub Environment deployment-branch
   rules only accept `develop`/`stag`/`main`, and the plan identity's federated subject is the branch
   ref. Fix: run `gh workflow run deploy.yml --ref <branch>`. The `verify-tag` job rejects a
   mismatched ref with a clear message.
5. **`checks` depends on `build` in `deploy.yml`.** The `e2e` check needs the pushed images, and a
   reusable-workflow call can't be split per job. Fix: `checks` runs after `build`, not in parallel with
   it.
6. **Azure SQL server names are global DNS names** (`<name>.database.windows.net`), found during
   implementation. Unlike the registry, Key Vault and state storage, the SQL servers had no suffix.
   Fix: `sql-misaapp-nonprod-<suffix>` and `sql-misaapp-<env>-<suffix>`; scripts take the suffix from
   `NAME_SUFFIX` or `--suffix`.
7. **Stage and production deploys can't grant AcrPull on the shared registry**, found during
   implementation. `infra/environment` assigns AcrPull on `crmisaapp<suffix>` (in `rg-misaapp-shared`)
   to its API and migrator identities, but those deploy identities only had rights on their own
   resource group. Fix in `bootstrap.sh`: every deploy identity gets Reader on `rg-misaapp-shared`
   (registry data source), and after the first shared apply the stage and production deploy
   identities get Role Based Access Control Administrator on the registry, conditioned to AcrPull.
   Develop already has the conditioned role on the whole shared resource group.

Other implementation deviations (Phase 2):

- **Providers**: `azurerm ~> 5.9` (latest at implementation, not 4.x) plus `azapi ~> 2.13` for
  free-offer databases (research.md R4). Both roots set `resource_provider_registrations = "none"`
  because deploy identities have no subscription-level rights; `bootstrap.sh` registers the resource
  providers once.
- **Key Vault Secrets Officer** is not assigned in `infra/shared` (T024): assigning it to
  `client_config.current` would swap it between the admin (first apply) and the develop deploy
  identity on every apply, and refresh would fail with 403 in between. `bootstrap.sh` grants it on
  `rg-misaapp-shared` to both, and the develop deploy identity's conditioned RBAC Administrator role no
  longer needs Secrets Officer in its allowed list.
- **`AZURE_CI_PRINCIPAL_ID`** repository variable added (T020) for `ci_principal_id` (T051).
- **Key Vault network ACL** stays `Allow` (GitHub-hosted runners have no fixed IPs; access is gated by
  RBAC). trivy AZU-0013 is suppressed with an inline justification.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Correct the design docs and create the empty infrastructure skeleton.

- [X] T001 Apply design corrections 1, 4 and 5 (above) to the design docs:
  - **Key Vault names** become `kv-misaapp-dev-<suffix>`, `kv-misaapp-stg-<suffix>`,
    `kv-misaapp-prd-<suffix>` and `kv-misaapp-np-<suffix>`. Update
    `specs/002-cicd-azure-deploy/contracts/infrastructure.md`, `data-model.md`, `research.md` (R10)
    and `quickstart.md` §0.
  - **Rollback command** in `quickstart.md` §7 becomes
    `gh workflow run deploy.yml --ref develop -f environment=develop …`.
  - **Job graph** in `contracts/pipeline.md` becomes `build ─► checks ─► plan ─► deploy`.
- [X] T002 Add Terraform ignores to `.gitignore` under a `# Terraform` heading: `.terraform/`,
  `*.tfplan`, `tfplan*`, `*.tfstate`, `*.tfstate.*`, `crash.log`. `.terraform.lock.hcl` stays
  committed.
- [X] T003 [P] Create `infra/.tflint.hcl`:
  - `plugin "terraform" { preset = "recommended" }`
  - `plugin "azurerm"` with a pinned `version` and
    `source = "github.com/terraform-linters/tflint-ruleset-azurerm"`.
- [X] T004 [P] Create `infra/shared/versions.tf` and `infra/environment/versions.tf`:
  - `required_version = "~> 1.<minor>.0"`, using the latest stable Terraform 1.x
  - `azurerm ~> 4.<minor>` and `random ~> 3.<minor>`, using the latest at implementation time.

  Generate the committed `.terraform.lock.hcl` in both roots with
  `terraform providers lock -platform=linux_amd64 -platform=windows_amd64`.
- [X] T005 [P] Create the backend and provider files for both roots:
  - `infra/shared/backend.tf` and `infra/environment/backend.tf`: a partial
    `backend "azurerm" { use_oidc = true, use_azuread_auth = true }`. Storage account, container and
    key are passed with `-backend-config`, as described in `contracts/infrastructure.md`.
  - `infra/shared/providers.tf` and `infra/environment/providers.tf`:
    `provider "azurerm" { features {} use_oidc = true storage_use_azuread = true }`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Make the app deployable (version endpoint, nginx template, image build args, migrator
image), move compose to Azure SQL, and do the one-time Azure and GitHub bootstrap, including the
shared registry and nonprod SQL that every story needs.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### App: version endpoint (FR-006, `contracts/version-api.openapi.yaml`)

- [X] T006 [P] Write failing integration tests in
  `backend/tests/MisaApp.Api.Tests/Features/Version/VersionEndpointsTests.cs` (class fixture
  `ApiFactory`, `TestContext.Current.CancellationToken`):
  - `GetVersion_default_config_returns_dev_and_local`: expects 200 and JSON with exactly two
    properties, `commit: "dev"` and `environment: "local"`.
  - `GetVersion_configured_values_are_returned`: uses
    `factory.WithWebHostBuilder(b => { b.UseSetting("App:Commit", "<40-hex sha>"); b.UseSetting("App:Environment", "stage"); })`
    and expects those values back.
- [X] T007 [P] Create `backend/src/MisaApp.Api/Features/Version/VersionContracts.cs`:
  - `public sealed record VersionResponse(string Commit, string Environment);`
  - `public sealed class AppInfoOptions { public const string SectionName = "App"; public string Commit { get; set; } = "dev"; public string Environment { get; set; } = "local"; }`
- [X] T008 Create the endpoint and its registration:
  - `backend/src/MisaApp.Api/Features/Version/VersionServiceCollectionExtensions.cs`:
    `AddVersion(this IServiceCollection, IConfiguration)` binds `AppInfoOptions` to section `App`.
  - `backend/src/MisaApp.Api/Features/Version/VersionEndpoints.cs`: `MapVersionEndpoints()` maps
    `GET /api/version`, returning `TypedResults.Ok(new VersionResponse(...))` from
    `IOptions<AppInfoOptions>`. Blank values fall back to `"dev"`/`"local"`, because the contract
    requires `minLength: 1`.

  Depends on T007.
- [X] T009 Register the feature:
  - In `backend/src/MisaApp.Api/Program.cs`, call `builder.Services.AddVersion(builder.Configuration)`
    and `app.MapVersionEndpoints()` next to the Chat registrations.
  - Add `"App": { "Commit": "dev", "Environment": "local" }` to
    `backend/src/MisaApp.Api/appsettings.json`.
  - Run `dotnet test` in `backend/`; T006 must now pass.
- [X] T010 [P] Check the resolved SqlClient version (R12, to verify): run
  `dotnet list backend/src/MisaApp.Api package --include-transitive` and look at
  `Microsoft.Data.SqlClient`.
  - If it is 7.x or later, add `Microsoft.Data.SqlClient.Extensions.Azure` (latest stable) to
    `backend/src/MisaApp.Api/MisaApp.Api.csproj` so `Authentication=Active Directory Managed Identity`
    works.
  - Record the outcome in `specs/002-cicd-azure-deploy/research.md` R12.

### Containers: nginx template, commit stamping, migrator image

- [X] T011 [P] Move `frontend/nginx.conf` to `frontend/nginx/default.conf.template` with `git mv`.
  Then change it:
  - `resolver ${NGINX_LOCAL_RESOLVERS} valid=10s ipv6=off;` replaces `127.0.0.11`.
  - `set $api ${API_UPSTREAM};`
  - `proxy_set_header Host $proxy_host;` and add `proxy_set_header X-Forwarded-Host $host;`.
  - Keep the other locations, headers and timeouts unchanged (R2).
- [X] T012 Update the runtime stage of `frontend/Dockerfile`:
  - `COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template` replaces the
    `nginx.conf` copy.
  - `ENV API_UPSTREAM=http://backend:8080 NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1`
  - `ARG SOURCE_COMMIT=dev` and `LABEL org.opencontainers.image.revision=$SOURCE_COMMIT`.

  Depends on T011.
- [X] T013 [P] Create `backend/deploy/migrate.sh` (`#!/usr/bin/env bash`, `set -euo pipefail`,
  LF line endings, executable):
  1. Require `SQL_SERVER`, `SQL_DATABASE`, `MIGRATOR_CLIENT_ID`, `APP_IDENTITY_NAME` and
     `APP_CLIENT_ID`. If any is missing, fail with a message that names the missing variable.
  2. Run idempotent T-SQL through
     `sqlcmd -S "$SQL_SERVER" -d "$SQL_DATABASE" --authentication-method ActiveDirectoryManagedIdentity -U "$MIGRATOR_CLIENT_ID" -b`
     (flags to verify, R5). The T-SQL:
     - computes `DECLARE @sid varbinary(16) = CAST(CAST('<APP_CLIENT_ID>' AS uniqueidentifier) AS varbinary(16));`
     - if `sys.database_principals` has no row for the name, runs
       `CREATE USER [<APP_IDENTITY_NAME>] WITH SID = <sid>, TYPE = E` through dynamic SQL using
       `CONVERT(varchar(34), @sid, 1)`
     - runs `ALTER ROLE db_datareader ADD MEMBER [...]` and `ALTER ROLE db_datawriter ADD MEMBER [...]`.
  3. Run `./efbundle --connection "Server=tcp:$SQL_SERVER,1433;Database=$SQL_DATABASE;Authentication=Active Directory Managed Identity;User Id=$MIGRATOR_CLIENT_ID;Encrypt=True"`.
  4. Echo progress lines only. Never print the connection string or environment dumps.

  Add a `.gitattributes` rule `*.sh text eol=lf` if one isn't already present.
- [X] T014 Update `backend/Dockerfile`:
  - **Build stage:** copy `dotnet-tools.json`, run `dotnet tool restore`, then
    `dotnet ef migrations bundle --project src/MisaApp.Api --self-contained -r linux-x64 -o /out/efbundle`
    in a new `bundle` stage based on `build`.
  - **New `migrator` stage**, placed before `runtime` so `runtime` stays the last stage:
    - `FROM mcr.microsoft.com/dotnet/runtime-deps:10.0 AS migrator`
    - install a pinned `go-sqlcmd` release, checking the tarball against its `sha256`
    - copy `/out/efbundle` and `deploy/migrate.sh`
    - `USER $APP_UID`, `ENTRYPOINT ["/app/migrate.sh"]`.
  - **Runtime stage:** `ARG SOURCE_COMMIT=dev`, `ENV App__Commit=$SOURCE_COMMIT`, and
    `LABEL org.opencontainers.image.revision=$SOURCE_COMMIT`.

  Depends on T013. Verify with `docker build --target migrator backend` and
  `docker build --build-arg SOURCE_COMMIT=abc backend`.

### Compose moves to Azure SQL (constitution v2.0.0, Principle V)

- [X] T015 Update `compose.yaml`:
  - Remove the `sqlserver` service, the `sqlserver-data` volume and backend's `depends_on: sqlserver`.
  - Set backend
    `ConnectionStrings__Default: ${SQL_CONNECTION_STRING:?Set SQL_CONNECTION_STRING in .env (see docs/deployment.md)}`.
  - Keep `Database__MigrateOnStartup: "true"`.
  - Add `build.args.SOURCE_COMMIT: ${SOURCE_COMMIT:-dev}` to backend and frontend.
  - Update the header comment.

  `compose.dev.yaml` needs no change.
- [X] T016 [P] Update `.env.example`:
  - Remove `MSSQL_SA_PASSWORD` and `SQL_PORT`.
  - Add the `SQL_CONNECTION_STRING` line with the placeholders from the "Local `.env` contract" in
    `contracts/infrastructure.md`. Placeholders only, no real values.
  - Keep `GEMINI_API_KEY`, `GEMINI_MODEL`, `WEB_PORT` and `API_PORT`.
- [X] T017 [P] In `frontend/e2e/global-setup.ts`, change the doc comment "SQL Server" to "Azure SQL"
  and keep the 180 s wait, which covers serverless auto-pause resume (R4). In
  `backend/tests/MisaApp.Api.Tests/ApiFactory.cs`, change "SQL Server-specific behaviour" to "Azure
  SQL-specific behaviour".

### One-time bootstrap and shared infrastructure (FR-020c)

- [X] T018 Create `infra/bootstrap/bootstrap.sh`, part 1, Azure foundation:
  - **Script basics:** bash, `set -euo pipefail`, idempotent.
  - **Arguments:** `--subscription`, `--location`, `--suffix` (validate `^[a-z0-9]{1,6}$`),
    `--repo <owner>/<repo>`, `--approvers <user>[,<user>]`.
  - **Prerequisites:** check that `az`, `gh`, `jq` and `terraform` are installed and logged in.
  - **Resource groups:** `rg-misaapp-shared`, `rg-misaapp-develop`, `rg-misaapp-stage`,
    `rg-misaapp-production`.
  - **State storage account** `stmisaapptf<suffix>`:
    - StorageV2, TLS 1.2, public blob access off, shared key access off
    - blob versioning, plus blob and container soft delete for 30 days
    - containers `tfstate-shared`, `tfstate-develop`, `tfstate-stage` and `tfstate-production`
    - `CanNotDelete` lock.
  - **Output:** print a summary of what was created or already existed.
- [X] T019 Extend `infra/bootstrap/bootstrap.sh`, part 2, identities. Create the user-assigned
  identities, federated credentials (issuer `https://token.actions.githubusercontent.com`) and role
  assignments from research.md R7 and the data-model "Identities" table. Each identity lives in
  `rg-misaapp-shared`:
  - **`id-misaapp-gh-ci`**
    - Subjects: `repo:<repo>:pull_request` and `repo:<repo>:ref:refs/heads/{develop,stag,main}`.
  - **`id-misaapp-gh-build`**
    - Subjects: `ref:refs/heads/{develop,stag,main}`.
    - Roles: AcrPush on `rg-misaapp-shared`.
  - **`id-misaapp-gh-plan-<env>`**
    - Subjects: `ref:refs/heads/<branch>`.
    - Roles: Reader on `rg-misaapp-<env>` and `rg-misaapp-shared`; Storage Blob Data Reader on
      container `tfstate-<env>`.
    - Custom role "MisaApp Container Apps Secret Reader" with
      `Microsoft.App/containerApps/listSecrets/action` and `Microsoft.App/jobs/listSecrets/action`
      (R7, to verify: drop it if `terraform plan` works without it).
  - **`id-misaapp-gh-deploy-<env>`**
    - Subjects: `environment:<env>`.
    - Roles: Contributor on `rg-misaapp-<env>`; Storage Blob Data Contributor on `tfstate-<env>`.
    - Role Based Access Control Administrator on `rg-misaapp-<env>`. Its ABAC condition limits it to
      the AcrPull (`7f951dda-4ed3-4680-a7ca-43fe172d538d`) and Key Vault Secrets User
      (`4633458b-17de-408a-b874-0445c86b69e6`) role definitions.
    - **Develop only:** Contributor on `rg-misaapp-shared` and Storage Blob Data Contributor on
      `tfstate-shared`. Also Role Based Access Control Administrator on `rg-misaapp-shared`,
      conditioned to AcrPull, Key Vault Secrets User, Key Vault Secrets Officer, SQL DB Contributor
      and SQL Server Contributor.
- [X] T020 Extend `infra/bootstrap/bootstrap.sh`, part 3, GitHub settings via `gh api`, all
  idempotent:
  - **Branches:** check that `develop`, `stag` and `main` exist. If one is missing, fail and name it.
  - **Environments:**
    - `develop`: deployment branch policy `develop`.
    - `stage`: branch policy `stag`; required reviewers = approvers.
    - `production`: branch policy `main`; required reviewers = approvers.
  - **Repository variables:** `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_CI_CLIENT_ID`,
    `AZURE_BUILD_CLIENT_ID`, `AZURE_PLAN_CLIENT_ID_DEVELOP`/`_STAGE`/`_PRODUCTION`, `ACR_NAME`,
    `TFSTATE_ACCOUNT`, `AZURE_LOCATION` and `NAME_SUFFIX`.
  - **Environment variable:** `AZURE_DEPLOY_CLIENT_ID` in each environment.
  - **Rulesets** on `develop`, `stag` and `main`:
    - pull requests required
    - required status checks `backend`, `frontend`, `e2e`, `infra` and `secrets`
    - force-push and deletion blocked
    - repository-admin bypass.
  - **Security:** enable secret scanning and push protection.
  - **No GitHub secrets are created.**
- [X] T021 [P] Create the shared root's inputs and outputs (`contracts/infrastructure.md` "infra/shared"):
  - `infra/shared/variables.tf`:
    - `location` (string)
    - `suffix` (string, validation `^[a-z0-9]{1,6}$`)
    - `developers` (list(string), default `[]`, each validated `^[a-z0-9]{2,12}$`)
    - `ci_principal_id` (string).
  - `infra/shared/outputs.tf`: `acr_login_server`, `nonprod_sql_fqdn`, `nonprod_key_vault_name`.
  - `infra/shared/terraform.tfvars`: `location` and an empty `developers` list. No secrets. The
    suffix and CI principal come from `-var`.
- [X] T022 [P] Create `infra/shared/registry.tf`:
  - `azurerm_container_registry` named `crmisaapp${var.suffix}` in `rg-misaapp-shared` (data source):
    Standard SKU, `admin_enabled = false`, `lifecycle { prevent_destroy = true }`.
  - AcrPull role assignment for `var.ci_principal_id`.
- [X] T023 [P] Create `infra/shared/sql_nonprod.tf`:
  - **Admin password:** `random_password` with `length = 32` and
    `override_special = "!#%*+-=?@^_"` (no `;'"`).
  - **Server `sql-misaapp-nonprod-<suffix>`:** version 12.0, `minimum_tls_version = "1.2"`, administrator
    login `misaappadmin` using that password, public network access on, **no** "Allow Azure services"
    rule, `prevent_destroy`.
  - **Developer databases:** `for_each = toset(var.developers)` creates `sqldb-misaapp-dev-<alias>`:
    - sku `GP_S_Gen5_1`, `auto_pause_delay_in_minutes = 60`, `min_capacity = 0.5`
    - free offer (R4, to verify): use azurerm properties if they exist. Otherwise add `azapi` to
      `versions.tf` and use `azapi_update_resource` setting `properties.useFreeLimit = true` and
      `freeLimitExhaustionBehavior = "AutoPause"`.
    - no `prevent_destroy`, so removing an alias removes its database.
  - **CI roles:** SQL DB Contributor and SQL Server Contributor on the server for `var.ci_principal_id`.
- [X] T024 [P] Create `infra/shared/keyvault.tf`:
  - Key Vault `kv-misaapp-np-${var.suffix}`: RBAC mode, purge protection, soft delete 7 days.
  - Key Vault Secrets Officer for `data.azurerm_client_config.current.object_id`, so the secret write
    succeeds.
  - Secret `sql-admin-password` set from `random_password`, with `depends_on` that role assignment.
  - Key Vault Secrets User for `var.ci_principal_id`.
- [X] T025 Extend `infra/bootstrap/bootstrap.sh`, part 4 (design correction 2): with the admin's
  credentials, run `terraform init` against `tfstate-shared/shared.tfstate`, then
  `terraform apply -var suffix=… -var ci_principal_id=<id-misaapp-gh-ci principal>` for
  `infra/shared`. Print the outputs. Depends on T019, T021–T024.
- [X] T026 [P] Create `infra/scripts/allow-my-ip.sh`:
  - Arguments: `--alias <alias>` and optional `--resource-group` (default `rg-misaapp-shared`).
  - Get the public IP from `curl -fsS https://api.ipify.org`.
  - Create or update firewall rule `dev-<alias>` on `sql-misaapp-nonprod-<suffix>`.
  - Print the connection-string template, without the password, pointing to `docs/deployment.md`.
- [ ] T027 Validate both foundations. Run each of these and confirm it passes:
  - `terraform fmt -check -recursive infra`
  - `terraform -chdir=infra/shared init -backend=false` then `validate`
  - `tflint --chdir=infra/shared --config=../.tflint.hcl`
  - `shellcheck infra/bootstrap/bootstrap.sh infra/scripts/*.sh backend/deploy/migrate.sh`.

  Then run quickstart §0 (bootstrap) as a subscription Owner and confirm that re-running it changes
  nothing.

**Checkpoint**: `dotnet test` passes, the images build, and bootstrap is done. The shared registry,
nonprod SQL and nonprod Key Vault exist. After an admin adds a developer alias by hand,
`docker compose up -d --build` works against that developer's Azure SQL database (quickstart §1).

---

## Phase 3: User Story 2 - Pull requests are validated before merge (Priority: P1)

**Goal**: Every PR to `develop`, `stag` or `main` runs five checks: `backend`, `frontend`, `e2e`,
`infra` and `secrets`. Each reports separately with a log link and none touches any environment.

**Independent Test**: Quickstart §2. A PR with a deliberately failing backend test shows `backend`
red, the other checks report on their own, merge is blocked, and the Azure activity log shows only
`ci-*` database create and delete.

- [X] T028 [P] [US2] Create `infra/scripts/ci-database.sh`:
  - **`create <db-name> <rule-name>`:**
    - creates a Basic database on `sql-misaapp-nonprod-<suffix>`, tagged `createdUtc=<ISO-8601 UTC>`
    - creates a firewall rule for the runner IP from `api.ipify.org`
    - writes `db_name` to `$GITHUB_OUTPUT` when that variable is set.
  - **`drop <db-name> <rule-name>`:** deletes the database and the rule. It is idempotent and ignores
    "not found".
  - **`sweep --older-than-hours <n>`:** deletes these on `sql-misaapp-nonprod-<suffix>`:
    - `sqldb-misaapp-ci-*` databases whose `createdUtc` is older than n hours
    - `ci-*` firewall rules whose database no longer exists or is older than n hours.

  It never touches a non-`ci-` name.
- [X] T029 [US2] Create `.github/workflows/ci.yml`:
  - **Triggers:** `pull_request` to `develop`, `stag` and `main`, plus `workflow_call`.
  - **Permissions:** top-level `contents: read`.
  - **Concurrency:** `ci-${{ github.workflow }}-${{ github.event.pull_request.number || github.sha }}`
    with `cancel-in-progress: true` for PRs.
  - **Action pinning:** every third-party action is pinned to a full commit SHA with a `# vX.Y.Z`
    comment.
  - **Job `backend`:** `actions/setup-dotnet` with `global-json-file: backend/global.json`, then
    `dotnet build -c Release -warnaserror`, then `dotnet test -c Release --no-build`, working
    directory `backend/`.
  - **Job `frontend`:** `pnpm/action-setup` (reads `packageManager`), `actions/setup-node` with
    `node-version-file: frontend/.node-version` and pnpm cache, then
    `pnpm install --frozen-lockfile && pnpm lint && pnpm typecheck && pnpm test && pnpm build` in
    `frontend/`.
- [X] T030 [US2] Add two jobs to `.github/workflows/ci.yml`:
  - **Job `infra`:**
    - `hashicorp/setup-terraform` with the version pinned in T004
    - `terraform fmt -check -recursive infra`
    - `init -backend=false` and `validate` for both roots
    - `tflint --init` and `tflint`, both with `infra/.tflint.hcl`
    - `trivy config --severity HIGH,CRITICAL --exit-code 1 infra`, with a pinned version
    - `actionlint` with a pinned version.
  - **Job `secrets`:** checkout with `fetch-depth: 0`, then the pinned `gitleaks` CLI
    (`gitleaks git --redact --log-opts=<base>..HEAD` on PRs, full history otherwise). No
    license-gated action.
- [X] T031 [US2] Add job `e2e` to `.github/workflows/ci.yml`:
  - **Setup:**
    - `permissions: id-token: write, contents: read`, `timeout-minutes: 30`
    - skip with a `::notice::` when the PR comes from a fork
    - `azure/login` with `vars.AZURE_CI_CLIENT_ID`.
  - **Database:** `infra/scripts/ci-database.sh create sqldb-misaapp-ci-${{ github.run_id }}-${{ github.run_attempt }} ci-${{ github.run_id }}-${{ github.run_attempt }}`.
  - **Password:** read with `az keyvault secret show --vault-name kv-misaapp-np-${{ vars.NAME_SUFFIX }} --name sql-admin-password --query value -o tsv`.
    Run `echo "::add-mask::$pw"` before any other use, then export `SQL_CONNECTION_STRING` through
    `$GITHUB_ENV`.
  - **Run:** `docker compose up -d --build backend frontend`, then
    `docker compose --profile e2e run --rm --build playwright`. No `GEMINI_API_KEY`, so the echo model
    is used (FR-004).
  - **Always:**
    - upload `frontend/e2e/playwright-report` as an artifact
    - on failure, run `docker compose logs backend frontend`
    - run `ci-database.sh drop …`.
- [X] T032 [P] [US2] Create `.github/workflows/cleanup-ci-databases.yml`:
  - Triggers: `schedule: cron "17 * * * *"` and `workflow_dispatch`.
  - `permissions: id-token: write, contents: read`; concurrency group `cleanup-ci-databases`.
  - `azure/login` with the CI identity. Scheduled runs use ref `refs/heads/main`, which is covered by
    its federated subject.
  - Run `infra/scripts/ci-database.sh sweep --older-than-hours 2`.
- [ ] T033 [US2] Lint and validate the PR checks:
  1. Run `docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:<pinned>` and fix any findings.
  2. Push the branch and open a PR to `develop`.
  3. Run quickstart §2: a deliberately failing test turns `backend` red, the other checks report on
     their own, and after the fix all five pass and no `ci-*` database is left.

**Checkpoint**: PRs are gated by five required checks. No environment exists or changes yet.

---

## Phase 4: User Story 1 - Merging to `develop` ships to the develop environment (Priority: P1) 🎯 MVP

**Goal**: A merge to `develop` builds images once, runs every check against those images, plans,
migrates and applies, then smoke-tests and rolls back automatically on failure. No manual step.

**Independent Test**: Quickstart §3. After a merge, `https://<develop-url>/api/version` shows the
merge SHA and `environment: develop` within 20 minutes, `/api/health` is `Healthy`, and chat replies.

### Tests for User Story 1

- [X] T034 [P] [US1] Create `frontend/e2e/tests/smoke.spec.ts`. Every test is tagged
  `{ tag: '@smoke' }` and none sends a chat message:
  - **Page loads:** `getByRole('heading', { name: 'MisaApp' })` and
    `getByRole('region', { name: 'Chat' })` are visible.
  - **Health:** `GET /api/health` is 200 with text `Healthy`.
  - **Version:** `GET /api/version` is 200 with non-empty `commit` and `environment`. When
    `EXPECTED_COMMIT` is set, `commit === EXPECTED_COMMIT`. When `EXPECTED_ENVIRONMENT` is set,
    `environment === EXPECTED_ENVIRONMENT`.

  These tests also run in the full suite, where those variables are unset.
- [X] T035 [P] [US1] Update `frontend/e2e/playwright.config.ts`:
  - `const smoke = !!process.env.PW_SMOKE`
  - `grep: smoke ? /@smoke/ : undefined`
  - when `smoke` is set, only the `chromium` project runs.

  Retries and reporters stay unchanged.

### Infrastructure for User Story 1 (`infra/environment`, `contracts/infrastructure.md`)

- [X] T036 [P] [US1] Create `infra/environment/variables.tf` with every variable in the contract
  table. Validations:
  - `environment` ∈ {develop, stage, production}
  - `image_tag` matches `^[0-9a-f]{40}$`
  - `suffix` matches `^[a-z0-9]{1,6}$`
  - `sql_auto_pause_minutes` defaults to `-1`; `sql_use_free_offer` defaults to `false`;
    `gemini_model` defaults to `"gemini-3.8-flash"`; `log_retention_days` defaults to `30`.
- [X] T037 [P] [US1] Create `infra/environment/main.tf`. This is a new helper file that plan.md
  doesn't list; it keeps names in one place.
  - `locals`:
    - `env_code = { develop = "dev", stage = "stg", production = "prd" }[var.environment]`
    - the names `ca-misaapp-<env>-web`, `ca-misaapp-<env>-api`, `caj-misaapp-<env>-migrate`,
      `sql-misaapp-<env>-<suffix>`, `kv-misaapp-<env_code>-<suffix>`, `id-misaapp-<env>-api` and
      `id-misaapp-<env>-migrator`
    - common `tags` (`app = "misaapp"`, `environment`).
  - Data sources: `azurerm_resource_group` `rg-misaapp-<env>`, `azurerm_container_registry` (by
    `var.acr_name` in `rg-misaapp-shared`) and `azurerm_client_config`.
- [X] T038 [P] [US1] Create `infra/environment/outputs.tf`:
  - `web_url` (`"https://${...ingress[0].fqdn}"`)
  - `image_tag` (`var.image_tag`)
  - `migrate_job_name`, `resource_group_name`, `key_vault_name`
  - `sql_server_fqdn`.
- [X] T039 [P] [US1] Create `infra/environment/monitoring.tf`: `azurerm_log_analytics_workspace`
  `log-misaapp-<env>` with `retention_in_days = var.log_retention_days`.
- [X] T040 [P] [US1] Create `infra/environment/identity.tf`:
  - user-assigned identities `id-misaapp-<env>-api` and `id-misaapp-<env>-migrator`
  - an AcrPull role assignment for each on the shared registry.
- [X] T041 [P] [US1] Create `infra/environment/sql.tf`:
  - **Server `sql-misaapp-<env>-<suffix>`:**
    - `azuread_administrator` = the migrator identity (login name, object ID = principal ID, tenant)
      with `azuread_authentication_only = true`
    - `minimum_tls_version = "1.2"`
    - firewall rule `AllowAzureServices` (0.0.0.0–0.0.0.0), needed because Consumption Container Apps
      egress is not VNet-bound (plan risk table)
    - `prevent_destroy`.
  - **Database `sqldb-misaapp`:**
    - `sku_name = var.sql_sku`
    - when the SKU starts with `GP_S_`: `auto_pause_delay_in_minutes` and `min_capacity = 0.5`
    - free offer when `var.sql_use_free_offer`, using the same mechanism chosen in T023
    - `prevent_destroy`.
- [X] T042 [P] [US1] Create `infra/environment/keyvault.tf`:
  - Key Vault `kv-misaapp-<env_code>-<suffix>`: RBAC mode, purge protection, soft delete 30 days.
  - Key Vault Secrets User for the api identity.
  - Terraform never creates or reads the `gemini-api-key` value (R10).
- [X] T043 [US1] Create `infra/environment/container_apps.tf`. Depends on T037–T042.
  - **Environment:** `cae-misaapp-<env>` linked to Log Analytics.
  - **API app `ca-misaapp-<env>-api`:**
    - single revision mode
    - api identity, also used for the registry
    - image `${acr_login_server}/misaapp-api:${var.image_tag}`
    - env vars exactly as in the contract "API container" table:
      - `ASPNETCORE_ENVIRONMENT=Production`
      - `ConnectionStrings__Default` with `Authentication=Active Directory Managed Identity;User Id=<api client id>`
      - `Database__MigrateOnStartup=false`
      - `Gemini__Model`
      - `App__Environment=<env>`
    - when `var.gemini_enabled`, a dynamic Key Vault secret `gemini-api-key`
      (`key_vault_secret_id = "${vault_uri}secrets/gemini-api-key"`, identity = api) mapped to
      `Gemini__ApiKey`
    - ingress internal, target port 8080, `allow_insecure_connections = true`, 100% to the latest
      revision
    - startup and readiness probes on `/api/health` port 8080, liveness on `/api/health` with
      `failure_count_threshold = 5`
    - cpu 0.5, memory 1Gi
    - min and max replicas from variables.
  - **Web app `ca-misaapp-<env>-web`:**
    - image `misaapp-web:${var.image_tag}`
    - env `API_UPSTREAM = "http://ca-misaapp-<env>-api"` and `NGINX_ENTRYPOINT_LOCAL_RESOLVERS = "1"`
    - ingress external, target port 80, HTTPS only
    - readiness probe on `/`
    - min and max replicas from variables.
  - **Ordering:** both apps `depends_on` their AcrPull role assignments.
- [X] T044 [US1] Create `infra/environment/migrate_job.tf`: `azurerm_container_app_job`
  `caj-misaapp-<env>-migrate`:
  - manual trigger, `replica_timeout_in_seconds = 600`, `replica_retry_limit = 0`
  - migrator identity, also used for the registry
  - image `misaapp-migrator:${var.image_tag}`
  - env `SQL_SERVER`, `SQL_DATABASE = "sqldb-misaapp"`, `MIGRATOR_CLIENT_ID`, `APP_IDENTITY_NAME` and
    `APP_CLIENT_ID`
  - `depends_on` the AcrPull assignment and the SQL database.
- [X] T045 [US1] Create `infra/environment/develop.tfvars` with `environment = "develop"`,
  `location`, `sql_sku = "GP_S_Gen5_1"`, `sql_auto_pause_minutes = 60`, `sql_use_free_offer = false`,
  web and api replicas min 0 / max 2, and `gemini_enabled = false`. `suffix`, `acr_name` and
  `image_tag` come from `-var`.

  Then run `terraform fmt`, `init -backend=false`, `validate` and `tflint` on `infra/environment`.
- [X] T046 [P] [US1] Create `infra/scripts/wait-job-execution.sh`:
  - Arguments: `<resource-group> <job-name> <execution-name> [timeout-seconds=900]`.
  - Poll `az containerapp job execution show --query properties.status -o tsv` every 10 s.
  - Exit 0 on `Succeeded`.
  - Exit 1 on `Failed`, `Stopped` or `Degraded`, or on timeout, printing the status and the
    Log Analytics query that shows the job's logs.

### Pipeline for User Story 1

- [X] T047 [P] [US1] Create `compose.ci.yaml`, an overlay used by CI E2E with registry images:
  - `backend`: `build: !reset null`, `image: ${ACR_LOGIN_SERVER}/misaapp-api:${IMAGE_TAG}`
  - `frontend`: `build: !reset null`, `image: ${ACR_LOGIN_SERVER}/misaapp-web:${IMAGE_TAG}`
  - `playwright` still builds locally.
- [X] T048 [US1] Extend `.github/workflows/ci.yml` for deploy runs:
  - Add `workflow_call.inputs.image_tag` (string, default `''`).
  - In job `e2e`, when `inputs.image_tag != ''`:
    - `az acr login --name ${{ vars.ACR_NAME }}`
    - export `ACR_LOGIN_SERVER` and `IMAGE_TAG`
    - run `docker compose -f compose.yaml -f compose.ci.yaml up -d --pull always backend frontend`
      instead of `--build`.

  Depends on T031, T047.
- [X] T049 [US1] Create `.github/workflows/deploy.yml`, part 1:
  - **Trigger:** `on.push.branches` `develop`, `stag`, `main`.
  - **Run name:** `run-name: Deploy <env> @ <short sha>`.
  - **Job `resolve`:** maps the branch to `environment`, `tfvars` and the plan client ID variable
    (`develop→develop`, `stag→stage`, `main→production`, nothing else) and exposes them as outputs.
  - **Job `build`:**
    - `id-token: write`, `azure/login` with `AZURE_BUILD_CLIENT_ID`, `az acr login`
    - `docker/setup-buildx-action`
    - three `docker/build-push-action` steps:
      - `misaapp-api`: target `runtime`, context `backend`
      - `misaapp-migrator`: target `migrator`, context `backend`
      - `misaapp-web`: target `runtime`, context `frontend`
    - each step uses `build-args: SOURCE_COMMIT=${{ github.sha }}`, labels
      `org.opencontainers.image.revision` and `org.opencontainers.image.source`, tag
      `${ACR}.azurecr.io/<repo>:${{ github.sha }}`, and `cache-from`/`cache-to: type=gha` with one
      scope per image.
  - **Job `checks`:** `needs: build`, `uses: ./.github/workflows/ci.yml` with
    `image_tag: ${{ github.sha }}` and `permissions: id-token: write, contents: read`.

  Pin every action to a full commit SHA.
- [X] T050 [US1] Add job `plan` to `.github/workflows/deploy.yml`:
  - `needs: [resolve, build, checks]`; no `environment`.
  - `azure/login` with the plan identity.
  - `terraform init` with
    `-backend-config=storage_account_name=${{ vars.TFSTATE_ACCOUNT }} -backend-config=container_name=tfstate-<env> -backend-config=key=environment.tfstate`.
  - `terraform plan -lock=false -input=false -var-file=<env>.tfvars -var image_tag=<sha> -var suffix=${{ vars.NAME_SUFFIX }} -var acr_name=${{ vars.ACR_NAME }} -out=tfplan`.
  - Append `terraform show -no-color tfplan` to `$GITHUB_STEP_SUMMARY` inside a `<details>` block
    headed "Planned changes for <env> (approving deploys exactly this plan)" (FR-020a).
  - Upload `tfplan` as artifact `tfplan-<env>-<run_attempt>` with `retention-days: 7`.
- [X] T051 [US1] Add job `deploy` to `.github/workflows/deploy.yml`, part 1:
  - **Job settings:**
    - `needs: [resolve, plan]`
    - `environment: { name: <env>, url: ${{ steps.out.outputs.web_url }} }`
    - `concurrency: { group: deploy-<env>, cancel-in-progress: false }`
    - `azure/login` with `vars.AZURE_DEPLOY_CLIENT_ID`.
  - **Step 1, superseded guard** (push only):
    - if `git ls-remote origin refs/heads/<branch>` ≠ `github.sha`, write "Superseded by <sha>" to the
      summary and set `superseded=true`
    - every later step has `if: steps.guard.outputs.superseded != 'true'`.
  - **Step 2, preflight:** `terraform init` against `tfstate-<env>`. If init fails, the job fails with
    "Terraform state for <env> unreachable".
  - **Step 3, develop only:** `terraform -chdir=infra/shared init` (`tfstate-shared`, key
    `shared.tfstate`) then `apply -auto-approve -input=false -var suffix=… -var ci_principal_id=…`.
    `ci_principal_id` comes from the repository variable added by bootstrap; add it to T020 if it is
    missing.
  - **Step 4, capture:** `prev=$(terraform output -raw image_tag 2>/dev/null || true)`; write it to
    the step outputs and the summary.
- [X] T052 [US1] Add steps to job `deploy` in `.github/workflows/deploy.yml`, part 2:
  - **Step 5, first deploy** (design correction 3; only when `prev` is empty):
    1. `terraform apply -auto-approve -input=false -target=azurerm_container_app_job.migrate -target=azurerm_mssql_database.main` with the same `-var`s.
    2. Record "first deployment: re-planned after targeted apply" in the summary.
  - **Step 6, migrate** (push only):
    1. `exec=$(az containerapp job start -g rg-misaapp-<env> -n caj-misaapp-<env>-migrate --image ${ACR}.azurecr.io/misaapp-migrator:<sha> --query name -o tsv)`
    2. `infra/scripts/wait-job-execution.sh rg-misaapp-<env> caj-misaapp-<env>-migrate "$exec"`
    3. on failure, stop the job; the old version keeps serving.
  - **Step 7, apply:**
    - download the `tfplan-<env>-<run_attempt>` artifact
    - run `terraform apply -input=false tfplan`
    - on a first deploy, run a fresh `terraform plan -out=tfplan` and apply that instead.
- [X] T053 [US1] Add steps to job `deploy` in `.github/workflows/deploy.yml`, part 3:
  - **Step 8, outputs** (`id: out`): read `terraform output -raw web_url`.
  - **Step 9, smoke:**
    - `docker build -t misaapp-e2e frontend/e2e`
    - `docker run --rm -e BASE_URL=<web_url> -e PW_SMOKE=1 -e EXPECTED_COMMIT=<tag> -e EXPECTED_ENVIRONMENT=<env> misaapp-e2e`
    - upload the report on failure.
  - **Step 10, automatic rollback** (`if: failure() && steps.smoke.outcome == 'failure' && prev != ''`):
    - run `terraform apply -auto-approve -input=false -var-file=<env>.tfvars -var image_tag=<prev> …`
    - write "Smoke failed: rolled back to <prev>" to the summary
    - the job stays failed, so GitHub notifies the team (FR-022).
  - **Step 11, summary:** environment URL, deployed commit, previous commit, migration execution name,
    trigger.
- [ ] T054 [US1] Validate locally:
  - `actionlint`, plus `terraform validate` and `tflint` for `infra/environment`
  - `docker compose up -d --build` against your dev database, then
    `curl -s localhost:3000/api/version` must return `{"commit":"dev","environment":"local"}`
  - `docker compose --profile e2e run --rm --build playwright` passes the full suite, including
    `smoke.spec.ts`
  - `PW_SMOKE=1` runs only the `@smoke` tests (quickstart §1).
- [ ] T055 [US1] Run quickstart §3 on the real develop environment:
  1. Merge the PR. The deploy succeeds within 20 minutes with no prompt, and `/api/version` matches
     the merge SHA.
  2. Merge a trivial EF migration through `/db-migration`. The migrate job succeeds before the new
     revision starts.
  3. Merge two PRs back to back. The deploys run one after the other, and develop ends on the newer
     commit.

**Checkpoint**: The MVP is complete. Develop deploys itself on every merge, behind the PR gate from US2.

---

## Phase 5: User Story 3 - Merging to `stag` ships to the stage environment (Priority: P2)

**Goal**: A merge to `stag` waits for a designated approver, then deploys exactly the plan the
approver saw, with stage's own database, configuration and secrets.

**Independent Test**: Quickstart §4. A pending release leaves stage unchanged. A rejection deploys
nothing and records the reviewer. An approval deploys the commit while develop and production stay
unchanged.

- [X] T056 [P] [US3] Create `infra/environment/stage.tfvars` with `environment = "stage"`,
  `sql_sku = "GP_S_Gen5_1"`, `sql_auto_pause_minutes = 60`, `sql_use_free_offer = false`, web and
  api replicas min 0 / max 2, and `gemini_enabled = false`.
- [X] T057 [US3] Check that every resource name and identity in `.github/workflows/deploy.yml` comes
  from the resolved environment:
  - plan client ID variable, `tfstate-<env>`, `<env>.tfvars`
  - `rg-misaapp-<env>`, `caj-misaapp-<env>-migrate`
  - the deploy identity is environment-scoped through `vars.AZURE_DEPLOY_CLIENT_ID`.

  A `stag` run must not reference any develop or production name (FR-008, FR-016). Add a `resolve`
  step that fails on an unknown branch.
- [ ] T058 [US3] Run quickstart §4 on stage:
  1. Merge `develop` → `stag`. The run waits on "Review deployments" with the plan in the summary.
  2. Reject it. Nothing is deployed and the rejection is recorded with the reviewer's name.
  3. Re-run and approve. Stage `/api/version` shows the new commit, and develop and production are
     unchanged.

**Checkpoint**: Develop deploys automatically and stage deploys after approval.

---

## Phase 6: User Story 4 - Merging to `main` ships to production (Priority: P2)

**Goal**: Production deploys after approval with zero downtime, using a real Gemini key from Key
Vault. A failed post-deploy check returns traffic to the previous version.

**Independent Test**: Quickstart §5. A `curl` loop prints only `200` during an approved rollout, and
`/api/version` shows the new commit. A non-approver can't approve. An approval of an outdated run
deploys nothing ("superseded").

- [X] T059 [P] [US4] Create `infra/environment/production.tfvars` with
  `environment = "production"`, `sql_sku = "S0"`, `sql_auto_pause_minutes = -1`,
  `sql_use_free_offer = false`, web and api replicas min 1 / max 5, and `gemini_enabled = true`.
- [X] T060 [US4] Add a Gemini secret preflight to job `deploy` in `.github/workflows/deploy.yml`,
  after step 2. When `<env>.tfvars` sets `gemini_enabled = true` (read with
  `grep -Eq '^\s*gemini_enabled\s*=\s*true' infra/environment/<env>.tfvars`), run
  `az keyvault secret show --vault-name kv-misaapp-<env_code>-${{ vars.NAME_SUFFIX }} --name gemini-api-key --query id -o tsv >/dev/null`.
  - If the secret is missing, fail with
    `::error::Key Vault secret gemini-api-key missing in kv-misaapp-<code>-<suffix>`. Never print the
    value.
  - When `gemini_enabled = false`, skip the check: the echo fallback is allowed (spec edge case).
- [X] T061 [US4] Add rollout settings to `infra/environment/container_apps.tf` for zero downtime
  (FR-013):
  - `termination_grace_period_seconds = 30` on both app templates
  - readiness probe `initial_delay = 5`, `interval_seconds = 5`, `failure_count_threshold = 3`
  - startup probe tolerating up to about 120 s, for SQL cold starts.

  Confirm in the plan output that both apps stay in `Single` revision mode.
- [ ] T062 [US4] As an admin, set the production Gemini key, without echoing it, using quickstart §0
  (`kv-misaapp-prd-<suffix>`). Then run quickstart §5:
  1. Run the `curl` loop during an approved `stag` → `main` rollout. It must print only `200`.
  2. Check that a non-approver account has no Approve button.
  3. Approve an older pending run after a newer commit has landed. It must end as "superseded".

**Checkpoint**: All three environments deploy from their branches, with approvals on stage and
production.

---

## Phase 7: User Story 5 - Roll back an environment to a previous version (Priority: P3)

**Goal**: A release owner can put one environment back on an earlier image tag in under 10 minutes,
without rebuilding and with the same audit trail (approval for stage and production).

**Independent Test**: Quickstart §7. `gh workflow run deploy.yml --ref develop -f environment=develop -f image_tag=<earlier sha> -f reason="validate rollback"`
makes develop serve the earlier commit and the environment history shows who did it. An unknown tag
fails at `verify-tag`.

- [X] T063 [P] [US5] Create `infra/shared/registry_purge.tf` (FR-007). It defines
  `azurerm_container_registry_task` `purge-old-images` on the shared registry:
  - Linux platform, daily timer `0 3 * * *`.
  - Encoded task running
    `acr purge --filter 'misaapp-api:.*' --filter 'misaapp-web:.*' --filter 'misaapp-migrator:.*' --ago 90d --keep 30 --untagged`.
    This keeps the 30 newest tags, plus anything younger than 90 days, in each repository.
- [X] T064 [US5] Add `workflow_dispatch` to `.github/workflows/deploy.yml`:
  - **Inputs:** `environment` (choice develop/stage/production, required), `image_tag` (string,
    required), `reason` (string, required).
  - **Run name:**
    `run-name: ${{ github.event_name == 'workflow_dispatch' && format('Rollback {0} → {1}: {2}', inputs.environment, inputs.image_tag, inputs.reason) || ... }}`.
  - **Job `resolve`:** on dispatch, takes the environment from the input. It fails with
    "Run this from branch <branch> (gh workflow run deploy.yml --ref <branch> …)" when `github.ref`
    isn't that environment's branch (design correction 4).
- [X] T065 [US5] Add job `verify-tag` to `.github/workflows/deploy.yml`, dispatch only:
  - Check `image_tag` matches `^[0-9a-f]{40}$`.
  - `azure/login` with the CI identity, which has AcrPull.
  - Run `az acr repository show --name ${{ vars.ACR_NAME }} --image misaapp-api:<tag>` and the same for
    `misaapp-web`. If either is missing, fail with "Image tag <tag> not found in registry".

  Make `build` and `checks` push-only. Make `plan` depend on
  `[resolve, build, checks, verify-tag]` with
  `if: always() && !cancelled() && !contains(needs.*.result, 'failure')`, and use
  `image_tag = inputs.image_tag || github.sha`. In job `deploy`, skip the superseded guard, first-deploy
  and migrate steps on dispatch (data-model state machine). If the smoke test fails on a rollback, the
  run fails without re-applying the previous tag.
- [ ] T066 [US5] Run quickstart §7 on develop:
  - Roll back to an earlier SHA. It finishes in under 10 minutes and `/api/version` shows the earlier
    commit.
  - The environment history shows the actor and reason.
  - Stage and production are unchanged.
  - An unknown tag fails at `verify-tag`.

  Also redeploy the current tag to confirm FR-015 (re-run with no side effects).

**Checkpoint**: All five user stories work and can be checked on their own.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Documentation (FR-024), consistency with constitution v2.0.0, failure-path validation,
and the definition of done.

- [X] T067 [P] Create `docs/deployment.md`. It covers:
  - the branch flow `develop` → `stag` → `main` through PRs, and how to promote
  - what approvers see and how to approve or reject
  - rollback and redeploy (`gh workflow run deploy.yml --ref <branch> …`)
  - adding or rotating a secret (`az keyvault secret set`, never echoed)
  - the bootstrap steps (quickstart §0)
  - local development on Azure SQL: adding your alias to `infra/shared/terraform.tfvars`,
    `infra/scripts/allow-my-ip.sh`, filling `SQL_CONNECTION_STRING` in `.env`, and getting Key Vault
    Secrets User access on `kv-misaapp-np-<suffix>` from an admin
  - the **migration backward-compatibility rule** (expand/contract, because the old revision keeps
    serving and rollback doesn't revert the schema)
  - cost notes (R4) and troubleshooting (a failed migrate job, a revision that never becomes ready, a
    missing secret, a superseded run).
- [X] T068 [P] Update `docs/architecture.md`:
  - container diagram without `sqlserver`
  - Azure topology (Container Apps environment, web external, api internal, migrate job, Azure SQL,
    Key Vault, ACR)
  - configuration table (`ConnectionStrings:Default` from `SQL_CONNECTION_STRING` locally, managed
    identity in Azure; `App:Commit`, `App:Environment`)
  - `/api/version`
  - testing table (E2E now runs against Azure SQL).
- [X] T069 [P] Update `README.md`:
  - the stack table Database row becomes Azure SQL Database
  - setup uses `SQL_CONNECTION_STRING` in `.env`, linking `docs/deployment.md`
  - remove the `MSSQL_SA_PASSWORD`, `localhost,1433` and `docker compose up -d sqlserver` lines
  - add a CI/CD section linking `docs/deployment.md`.
- [X] T070 [P] Update the CLAUDE.md files so they match constitution v2.0.0:
  - **`CLAUDE.md`:**
    - the Database row becomes "Azure SQL Database (per-developer DB on `sql-misaapp-nonprod-<suffix>`)"
    - add an `Infra | Terraform, GitHub Actions | infra/, .github/workflows/` row
    - "Everything runs in Docker: `backend`, `frontend`, `playwright` (profile `e2e`); the database is
      Azure SQL"
    - the `dotnet run` note says "needs `ConnectionStrings:Default` via `dotnet user-secrets`"
    - add Terraform commands (`terraform -chdir=infra/environment validate`).
  - **`backend/CLAUDE.md`:** add the migration backward-compatibility rule and that migrations ship
    through the `migrator` image in Azure.
- [X] T071 [P] Update `.claude/skills/daily-start/SKILL.md`, `.claude/skills/db-migration/SKILL.md`
  and `.claude/skills/verify/SKILL.md`:
  - Remove the `sqlserver` references; the health check covers `backend` and `frontend` only.
  - `db-migration`: test against your Azure SQL dev database and apply the backward-compatibility
    rule.
  - `verify`: E2E needs `SQL_CONNECTION_STRING` in `.env`, and the step also runs `actionlint` plus
    `terraform validate` for both roots.
- [X] T072 [P] Update `specs/002-cicd-azure-deploy/plan.md`:
  - The Constitution Check row V becomes "✅ Pass (constitution 2.0.0)".
  - Remove the Principle V row from Complexity Tracking.
  - Mark the amendment list as applied (Principle V) or deferred (Terraform pin, deploy-only-via-
    `deploy.yml`, migration compatibility: candidates for a MINOR amendment).
- [X] T073 [P] Update `docs/backlog.md`:
  - Move "CI pipeline" and "Production deployment target and migration step" to Done with a link to
    `specs/002-cicd-azure-deploy/spec.md`.
  - Add to Later: "VNet-integrated Container Apps + SQL private endpoints" and "Per-developer contained
    users on nonprod SQL".
- [ ] T074 Run quickstart §6 failure handling on develop:
  - a failing migration
  - a revision that never becomes healthy
  - a failed smoke test with automatic rollback
  - a missing secret (temporarily set `gemini_enabled = true` in develop)
  - a stateful delete blocked by `prevent_destroy`.

  Revert every throwaway change afterwards.
- [ ] T075 Run quickstart §8 secrets hygiene:
  - `gitleaks` passes on the branch.
  - Run logs show only `***` for the SQL password.
  - `docker history` and `docker inspect` of `misaapp-api`, `misaapp-web` and `misaapp-migrator` show
    no secrets.
  - `git status` shows no `.env`, `*.tfstate` or `tfplan` file.
- [ ] T076 Run `/verify`. All four definition-of-done items must pass:
  1. `dotnet test`
  2. `pnpm lint && pnpm typecheck && pnpm test && pnpm build`
  3. the Playwright suite against the Docker stack on Azure SQL
  4. docs and backlog updated, no secrets or debug code in the diff.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies.
- **Foundational (Phase 2)**: depends on Setup. It **blocks every story**: images, compose on Azure
  SQL, bootstrap, and the shared registry and nonprod SQL.
- **US2 (Phase 3)**: depends on Foundational.
- **US1 (Phase 4)**: depends on Foundational **and US2**, because `deploy.yml` calls `ci.yml` as its
  quality gate (T048–T049).
- **US3 (Phase 5)** and **US4 (Phase 6)**: depend on US1, since they reuse its pipeline and Terraform
  root. They are independent of each other: different tfvars files, and T060 and T061 touch different
  files from T057.
- **US5 (Phase 7)**: depends on US1. It is independent of US3 and US4, but validating a rollback
  needs two develop deployments.
- **Polish (Phase 8)**: T067–T073 can start once US1 is done. T074–T076 need every story finished.

### User Story Dependencies

```text
Setup ─► Foundational ─► US2 ─► US1 (MVP) ─┬─► US3
                                           ├─► US4
                                           └─► US5
```

### Within Each Story

- Tests come before implementation: T006 before T007–T009, and T034–T035 before the smoke step in
  T053.
- Terraform variables, locals and identity come before resources, and resources before the tfvars
  validation (T045).
- Within each workflow file, tasks are sequential: `ci.yml` T029 → T030 → T031 → T048, and
  `deploy.yml` T049 → T050 → T051 → T052 → T053 → T060 → T064 → T065.
- Each story ends with its quickstart validation task.

### Parallel Opportunities

- **Setup:** T003, T004, T005.
- **Foundational:**
  - T006, T007, T010, T011, T013, T016 and T017 in parallel
  - then T021–T024 and T026 in parallel
  - `bootstrap.sh` T018 → T019 → T020 → T025 stays sequential (same file).
- **US2:** T028 and T032 in parallel with the `ci.yml` chain.
- **US1:** T034–T042, T046 and T047 in parallel. T043 and T044 come after the identity, SQL and
  Key Vault files.
- **US3, US4 and US5** can be split between people once US1 is merged: T056, T059 and T063 are
  parallel.
- **Polish:** T067–T073 are all different files.

---

## Parallel Example: User Story 1

```bash
# Tests and independent Terraform files together:
Task: "Create frontend/e2e/tests/smoke.spec.ts (@smoke: page, health, version)"
Task: "Update frontend/e2e/playwright.config.ts (PW_SMOKE → grep @smoke, chromium only)"
Task: "Create infra/environment/variables.tf"
Task: "Create infra/environment/main.tf (locals + data sources)"
Task: "Create infra/environment/outputs.tf"
Task: "Create infra/environment/monitoring.tf"
Task: "Create infra/environment/identity.tf"
Task: "Create infra/environment/sql.tf"
Task: "Create infra/environment/keyvault.tf"
Task: "Create infra/scripts/wait-job-execution.sh"
Task: "Create compose.ci.yaml"

# Then, sequentially: container_apps.tf → migrate_job.tf → develop.tfvars → deploy.yml (T049–T053)
```

---

## Implementation Strategy

### MVP first (US2 + US1)

1. **Phases 1–2.** Fix the design docs, ship `/api/version`, the nginx template and the migrator
   image, move compose to Azure SQL, and run bootstrap.
2. **Phase 3 (US2).** PRs are gated by the five checks. Turn on the required checks now.
3. **Phase 4 (US1).** Develop deploys on merge.
4. **Stop and validate:** run quickstart §1–§3.

### Incremental delivery

5. **US3.** Add `stage.tfvars` and validate approvals on stage.
6. **US4.** Add `production.tfvars`, the Gemini preflight and the zero-downtime settings, then run the
   first production release.
7. **US5.** Add the rollback dispatch and registry purge.
8. **Polish.** Docs, skills, failure-path validation, then `/verify`.

### Risks to watch while implementing

- The research items marked **"to verify"** have explicit tasks:
  - `azurerm` free-offer properties: T023
  - `go-sqlcmd` managed-identity flags: T013
  - SqlClient 7.x needing `Microsoft.Data.SqlClient.Extensions.Azure`: T010
  - plan identity `listSecrets`: T019 and T055.
- Required status checks can't be satisfied by the PR that introduces `ci.yml`. A repository admin
  merges it using the ruleset bypass, which is documented in `docs/deployment.md`.

---

## Acceptance scenario coverage (constitution Principle II)

| Scenario | Automated test | Quickstart run |
| --- | --- | --- |
| US1-AS1 merge → develop runs commit | `smoke.spec.ts` (`EXPECTED_COMMIT`) in deploy (T034, T053) | §3 (T055) |
| US1-AS2 failing check → nothing deployed | `checks` gate in `deploy.yml` (T049) | §2/§3 (T033, T055) |
| US1-AS3 app loads, health incl. DB, chat replies | `smoke.spec.ts`, `health.spec.ts`, `chat.spec.ts` (pre-deploy, same images) | §3 (T055) |
| US1-AS4 migration before traffic | migrate step (T052) | §3 step 2 (T055) |
| US2-AS1 per-check status on PR | the five `ci.yml` jobs (T029–T031) | §2 (T033) |
| US2-AS2 PR changes no environment | `ci.yml` uses only the nonprod CI identity (T031) | §2 (T033) |
| US2-AS3 failed check with log link | GitHub check runs | §2 (T033) |
| US3-AS1–AS3 approval gate, approve, reject | GitHub Environment `stage` (T020) | §4 (T058) |
| US3-AS4 stage's own DB, config, secrets | per-env identities and names (T019, T057) | §4 (T058) |
| US4-AS1–AS3 approval, recorded, non-approver refused | GitHub Environment `production` (T020) | §5 (T062) |
| US4-AS4 no downtime | readiness-gated single revision (T043, T061) | §5 curl loop (T062) |
| US4-AS5 failed health → previous version | smoke + automatic rollback (T053) | §6 (T074) |
| US5-AS1 rollback one environment | `workflow_dispatch` path (T064–T065) + smoke | §7 (T066) |
| US5-AS2 history shows who, when, version | GitHub deployment history + run name (T064) | §7 (T066) |
| `/api/version` contract | `VersionEndpointsTests` (T006) | §1 (T054) |

---

## Notes

- [P] = different files, no dependency on an incomplete task. [USx] = traceability to spec.md.
- Never read, print or commit `.env`. The SQL password is masked in CI before any other use.
- Commit only when a human asks. The constitution's Sync Impact Report comment should be removed
  before the constitution change is committed.
- Stop at each checkpoint and validate the story on its own.

## Implementation deviations (recorded during `/speckit-implement`)

- **Web identity**: the web app has its own user-assigned identity (AcrPull only), so nginx never gets
  a Key Vault token. T040 listed only api and migrator.
- **`image_tag` output** is derived from the API app's running image, not echoed from `var.image_tag`.
  It is absent until the apps exist, which is what first-deployment detection relies on.
- **Gemini preflight (T060)** lists secret names (`az keyvault secret list`) instead of
  `secret show`, so the deploy identity needs only **Key Vault Reader** (granted in bootstrap) and never
  reads the value. It runs after the first-deployment targeted apply, so the vault exists.
- **Stale plans**: `plan` records the state serial; `deploy` compares it before applying. develop
  re-plans and applies (noted in the summary); stage and production fail with "state changed since
  approved plan" so a human approves the new plan.
- **First-deployment targeted apply** also targets `azapi_resource.free_database` (free-offer databases).
- **Superseded guard** uses `gh api …/git/ref/heads/<branch>` instead of `git ls-remote` (checkout runs
  with `persist-credentials: false`).
- **`provenance: false`, `sbom: false`** on image builds, so the registry purge's `--untagged` can't
  delete manifests that a tagged index points to.
- **Run name** shows the full SHA (expressions can't take substrings).
- **`verify-tag`** also checks `misaapp-migrator`; **`plan`** requires `checks` (push) or `verify-tag`
  (dispatch) to succeed, which is stricter than `!contains(needs.*.result, 'failure')`.
- **Open follow-up**: `backend/src/MisaApp.Api/appsettings.Development.json` still contains the old
  `localhost,1433` `sa` connection string. It is overridden by user-secrets and compose, but it is dead
  configuration; removing it needs a check that `dotnet ef migrations add` still works without a
  connection string.
