# Implementation Plan: CI/CD Pipeline with Branch-Based Deployment to Azure

**Branch**: `002-cicd-azure-deploy` | **Date**: 2026-10-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/002-cicd-azure-deploy/spec.md`, plus planning input:
Azure Container Apps, Azure SQL Database everywhere (remove the local `sqlserver` container),
Terraform.

## Summary

Add three GitHub Actions workflows:
- `ci.yml` checks every pull request: backend, frontend, E2E on an ephemeral Azure SQL database,
  infrastructure lint, and secret scan.
- `deploy.yml` releases on merge: `develop` → develop, `stag` → stage, `main` → production.
- `cleanup-ci-databases.yml` removes leftover CI databases.

**How a release works**:
1. Each merge builds three images tagged with the commit SHA (`misaapp-api`, `misaapp-web`,
   `misaapp-migrator`) and pushes them to a shared Azure Container Registry.
2. The full E2E suite runs against those exact images.
3. Terraform plans the change. Stage and production then wait for a GitHub Environment approval.
4. A Container Apps Job applies EF migrations.
5. The saved plan is applied, rolling out a new single-mode Container Apps revision. Traffic switches
   only once the revision is healthy.
6. A Playwright `@smoke` run verifies the deploy. If it fails, the previous image tag is re-applied.

**Infrastructure** is Terraform, in two roots (`infra/shared`, `infra/environment` with one tfvars
file per environment), plus a one-time bootstrap script. Azure SQL uses Entra-only managed-identity
auth in deployed environments. Developers and CI use per-developer and per-run databases on a nonprod
server. GitHub stores no secrets (OIDC only).

**App changes** are small:
- a new `GET /api/version` endpoint
- an nginx config template so the proxy works in Container Apps
- a `migrator` Dockerfile stage
- `sqlserver` removed from compose.

## Technical Context

**Language/Version**: .NET 10 (C# latest) backend; TypeScript 6 / Node 24 frontend; HCL (Terraform 1.x
latest stable, pinned); Bash for scripts; GitHub Actions YAML

**Primary Dependencies**:
- GitHub Actions: `actions/checkout`, `actions/setup-dotnet`, `actions/setup-node`,
  `pnpm/action-setup`, `azure/login` (OIDC), `docker/setup-buildx-action`,
  `docker/build-push-action`, `hashicorp/setup-terraform`. Third-party actions are pinned to a commit
  SHA.
- Terraform providers: `azurerm` 4.x, `random`, `azapi` (only if the free-offer properties need it).
- Database tooling: EF Core 10 migrations bundle, `go-sqlcmd`.
- Lint and scan: `tflint`, `trivy`, `actionlint`, `gitleaks`.

**Storage**: Azure SQL Database.
- One Entra-only server per environment.
- One shared nonprod server for per-developer and per-CI-run databases.
- Terraform state in an Azure Storage account (one container per root and environment).
- No application schema change.

**Testing**: xUnit v3 integration test for `/api/version` (`ApiFactory`); Playwright (`smoke.spec.ts`
`@smoke`, plus the existing suite against Azure SQL); `terraform validate`/`tflint`/`trivy` and
`actionlint` as CI checks. Pipeline behavior is validated by the [quickstart](quickstart.md)
scenarios.

**Target Platform**: Azure Container Apps (Consumption, Linux containers), Azure SQL Database, Azure
Container Registry, Azure Key Vault, GitHub-hosted `ubuntu-latest` runners.

**Project Type**: Web application (existing frontend + backend), plus infrastructure as code and
CI/CD.

**Performance Goals**:
- Merge to `develop` live in ≤ 20 min, in at least 90% of runs (SC-001).
- An approved stage or production release live in ≤ 15 min (SC-008).
- Rollback in ≤ 10 min (SC-004).

**Constraints**:
- Zero downtime for production rollouts (min 1 replica, readiness-gated single revision).
- No secrets in the repo, images, logs, or GitHub.
- Migrations must stay backward compatible with the running version.
- E2E tests don't use Gemini.

**Scale/Scope**: 3 environments, 2 apps + 1 job per environment, about 8 workflow jobs, 2 Terraform
roots. Small team (a few developers). Production starts at S0 SQL and 1–5 replicas.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle / rule | Status | Notes |
| --- | --- | --- |
| I. Feature-sliced code | ✅ Pass | `/api/version` lives in `Features/Version/` with `MapVersionEndpoints()` + `AddVersion()`. Infra and CI live in new top-level `infra/` and `.github/`. They are not app layers. |
| II. Tests ship with every change | ⚠️ Pass with exception | New endpoint → integration test; new user-visible check → Playwright `@smoke`; existing E2E keeps running. **Exception**: acceptance scenarios that are GitHub/Azure platform behavior can't be xUnit/RTL/Playwright tests. Examples: approval refused for a non-approver; a revision that never becomes ready. `tasks.md` maps them to quickstart validation runs instead. See Complexity Tracking. |
| III. Explicit API contract | ✅ Pass | `/api/version` is camelCase JSON, documented in `contracts/version-api.openapi.yaml`. The frontend doesn't call it, so no `*Api.ts` change. No breaking change. |
| IV. Model-agnostic AI | ✅ Pass | CI and E2E run without `GEMINI_API_KEY` (echo model). Smoke tests never call chat. Production key comes from Key Vault through config only. |
| V. Reproducible Docker environment on Azure SQL | ✅ Pass (constitution 2.0.0) | Principle V was redefined by `/speckit-constitution` (1.0.1 → 2.0.0): compose runs frontend, backend and Playwright; the database is Azure SQL in every environment, including local and CI. This plan matches it. |
| Security & Data: secrets | ✅ Pass | Key Vault + managed identity + OIDC. `.env` still git-ignored and still the local config path. `gitleaks` + push protection. |
| Security & Data: migrations | ✅ Pass | EF migrations unchanged. Applied by a deployment step (matches the existing note in `docs/architecture.md`). |
| Workflow & quality gates | ✅ Pass | DoD unchanged in substance. `/verify` still runs all three layers; E2E now needs `SQL_CONNECTION_STRING`. Commits and pushes only on request. |

**Gate result (pre-research)**: PASS with two justified exceptions (V, II partial). V was resolved by
constitution 2.0.0; II (partial) remains in Complexity Tracking. There are no
unresolved NEEDS CLARIFICATION items: the service choice and the local database strategy were
settled with the user before research.

**Re-check after Phase 1 design**: unchanged. The design adds no new app layers or patterns. The only
new deployable is the migrator image, which is a build stage of the existing backend project, not a
new project. Constitution amendment items for `/speckit-constitution`:
- **Principle V** — **applied** in 2.0.0: SQL Server is no longer a compose service; the database is
  Azure SQL; local development needs network access to Azure.
- **Toolchain pins** — **deferred**: add Terraform (`required_version` + lock file).
- **Workflow** — **deferred**: "deployment happens only through `deploy.yml`; Azure resources change
  only through Terraform." (Already stated in `CLAUDE.md` and `docs/deployment.md`.)
- **Security & Data** — **deferred**: "migrations must be backward compatible with the previous
  release." (Already stated in `backend/CLAUDE.md`, `/db-migration` and `docs/deployment.md`.)

The three deferred items are candidates for a MINOR amendment (2.1.0).

Originally suggested as 1.1.0; `/speckit-constitution` applied it as 2.0.0 (MAJOR, because Principle V
was redefined).

## Project Structure

### Documentation (this feature)

```text
specs/002-cicd-azure-deploy/
├── plan.md              # This file
├── research.md          # Phase 0: decisions R1–R12
├── data-model.md        # Phase 1: environments, artifacts, deployments, identities
├── quickstart.md        # Phase 1: validation scenarios
├── contracts/
│   ├── version-api.openapi.yaml   # GET /api/version
│   ├── pipeline.md                # workflows, checks, inputs, GitHub settings
│   └── infrastructure.md          # Terraform variables/outputs, runtime env vars, .env
├── checklists/requirements.md
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
.github/
└── workflows/
    ├── ci.yml                       # NEW: PR checks + reusable (backend, frontend, e2e, infra, secrets)
    ├── deploy.yml                   # NEW: push develop/stag/main + workflow_dispatch rollback
    └── cleanup-ci-databases.yml     # NEW: hourly sweep of ephemeral CI databases

infra/                               # NEW
├── bootstrap/
│   └── bootstrap.sh                 # one-time: RGs, tfstate, OIDC identities, roles, GitHub envs/rulesets
├── shared/                          # Terraform root: ACR + purge task, nonprod SQL + dev DBs, nonprod KV
│   ├── versions.tf  providers.tf  backend.tf  variables.tf  outputs.tf
│   ├── registry.tf  sql_nonprod.tf  keyvault.tf
│   ├── terraform.tfvars             # developers list, location, suffix (no secrets)
│   └── .terraform.lock.hcl
├── environment/                     # Terraform root, one state per env
│   ├── versions.tf  providers.tf  backend.tf  variables.tf  outputs.tf
│   ├── monitoring.tf  identity.tf  sql.tf  keyvault.tf  container_apps.tf  migrate_job.tf
│   ├── develop.tfvars  stage.tfvars  production.tfvars
│   └── .terraform.lock.hcl
├── scripts/
│   ├── ci-database.sh               # create | drop | sweep ephemeral CI databases + firewall rules
│   ├── allow-my-ip.sh               # developer firewall rule on sql-misaapp-nonprod-<suffix>
│   └── wait-job-execution.sh        # poll migrate job execution
└── .tflint.hcl

backend/
├── Dockerfile                       # CHANGED: SOURCE_COMMIT build arg → App__Commit; NEW `migrator` stage
├── deploy/
│   └── migrate.sh                   # NEW: create API DB user (SID) + run efbundle
├── src/MisaApp.Api/
│   ├── Program.cs                   # CHANGED: AddVersion() / MapVersionEndpoints()
│   ├── appsettings.json             # CHANGED: "App": { "Commit": "dev", "Environment": "local" }
│   └── Features/Version/            # NEW
│       ├── VersionContracts.cs      # VersionResponse record + AppInfoOptions
│       ├── VersionEndpoints.cs      # GET /api/version
│       └── VersionServiceCollectionExtensions.cs
└── tests/MisaApp.Api.Tests/Features/Version/
    └── VersionEndpointsTests.cs     # NEW

frontend/
├── Dockerfile                       # CHANGED: copy template to /etc/nginx/templates/
├── nginx/default.conf.template      # MOVED from nginx.conf: ${API_UPSTREAM}, ${NGINX_LOCAL_RESOLVERS}, Host $proxy_host
└── e2e/
    ├── playwright.config.ts         # CHANGED: grep/grepInvert for @smoke via env
    └── tests/smoke.spec.ts          # NEW: page loads, /api/health Healthy, /api/version commit matches

compose.yaml                         # CHANGED: drop sqlserver + volume; backend uses SQL_CONNECTION_STRING
compose.ci.yaml                      # NEW: overlay using registry images ${ACR}/misaapp-*:${IMAGE_TAG}
.env.example                         # CHANGED: SQL_CONNECTION_STRING replaces MSSQL_SA_PASSWORD/SQL_PORT
.gitignore                           # CHANGED: .terraform/, *.tfplan, *.tfstate*

docs/
├── deployment.md                    # NEW: branch flow, promote, approve, rollback, secrets, bootstrap, migration rules
├── architecture.md                  # CHANGED: Azure topology, Azure SQL, version endpoint
└── backlog.md                       # CHANGED: CI pipeline + deployment items → in progress/done
README.md, CLAUDE.md, backend/CLAUDE.md, frontend/CLAUDE.md   # CHANGED: no sqlserver; Azure SQL; deploy commands
.claude/skills/{daily-start,db-migration,verify}/SKILL.md     # CHANGED: drop sqlserver references; migration compat rule
.specify/memory/constitution.md      # AMENDED via /speckit-constitution (Principle V etc.)
```

**Structure Decision**: Keep the existing web-app layout (`backend/`, `frontend/`) and add the new
top-level `infra/` (Terraform + scripts) and `.github/workflows/`. App code changes follow the
feature-folder rule (`Features/Version/`). Two Terraform roots, not modules: the three environments
share one root, and `tfvars` plus a per-environment state key separate them. The registry and nonprod
SQL are shared, so they have their own root.

## Implementation phases (input for `/speckit-tasks`)

1. **Foundation**:
   - constitution amendment
   - `/api/version` + test
   - nginx template
   - Dockerfile `SOURCE_COMMIT` + `migrator` stage + `migrate.sh`
   - remove `sqlserver` from compose, `.env.example`
   - `smoke.spec.ts`
2. **Infrastructure**: `bootstrap.sh`, `infra/shared`, `infra/environment` + tfvars, scripts,
   `.tflint.hcl`.
3. **US2, PR checks**: `ci.yml` (five checks, ephemeral DB), `cleanup-ci-databases.yml`.
4. **US1, develop deploy**: `deploy.yml` (build → checks → plan → deploy: guard, preflight, shared
   apply, migrate, apply, smoke, auto-rollback), `compose.ci.yaml`.
5. **US3/US4, stage and production**: environment protection, approvers, production `tfvars`, Gemini
   secret preflight. These are mostly configuration on top of phase 4.
6. **US5, rollback**: `workflow_dispatch` path + `verify-tag`.
7. **Docs and validation**: `docs/deployment.md`, other docs, skills, backlog; run the
   [quickstart](quickstart.md) scenarios.

## Risks and follow-ups

| Risk | Mitigation |
| --- | --- |
| `azurerm` plan refresh needs `listSecrets` (plan identity is read-only) | Custom role with `Microsoft.App/containerApps/listSecrets/action` for plan identities (R7) |
| Free-offer DB properties missing in `azurerm` | `azapi_update_resource` (R4) |
| `Microsoft.Data.SqlClient` 7.x moved Entra auth out | Add `Microsoft.Data.SqlClient.Extensions.Azure` (R12) |
| Serverless auto-pause cold start in develop/stage | SqlClient retry, 180 s E2E health wait; production uses S0 without auto-pause |
| SQL servers allow public network access (Entra-only auth, IP rules) | Acceptable for v1; backlog item: VNet-integrated Container Apps + private endpoints |
| Local dev now needs internet + Azure access; offline dev is gone | Documented as a constitution amendment; accepted by the user |
| Shared nonprod SQL admin login used by developers and CI | Nonprod holds no real data; backlog: per-developer contained users |

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
| --- | --- | --- |
| Principle II (partial): some acceptance scenarios (approval gating, revision health, supersede, rollback) are verified by quickstart runs, not xUnit/RTL/Playwright | They're behaviors of GitHub Environments and Azure Container Apps, which only exist in a real pipeline run | Simulating GitHub/Azure in unit tests would test mocks, not the guarantees; the smoke test does automate the post-deploy checks |
| Third deployable image (`misaapp-migrator`) and a Container Apps Job | FR-011: migrations as an explicit step before traffic, run inside Azure without opening prod SQL to runners | Migrate-on-startup races between replicas and needs DDL rights for the API; running from the runner needs a prod firewall hole |
