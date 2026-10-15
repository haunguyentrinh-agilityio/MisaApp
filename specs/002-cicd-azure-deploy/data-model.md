# Data Model: CI/CD Pipeline with Branch-Based Deployment to Azure

**Feature**: [spec.md](spec.md) | **Research**: [research.md](research.md)

**No application database changes.** There is no new EF entity or migration. The "data" in this
feature is deployment configuration and the records GitHub and Azure keep about releases. This file
pins down their shape, naming, and state transitions.

## Environment

One per deployable stage. Defined by a `tfvars` file plus a GitHub Environment.

| Attribute | develop | stage | production |
| --- | --- | --- | --- |
| Source branch | `develop` | `stag` | `main` |
| GitHub Environment | `develop` | `stage` | `production` |
| Required reviewers | none | designated approvers | designated approvers |
| Resource group | `rg-misaapp-develop` | `rg-misaapp-stage` | `rg-misaapp-production` |
| Public URL | `ca-misaapp-develop-web` FQDN | `ca-misaapp-stage-web` FQDN | `ca-misaapp-production-web` FQDN |
| Database | `sql-misaapp-develop-<suffix>` / `sqldb-misaapp` | `sql-misaapp-stage-<suffix>` / `sqldb-misaapp` | `sql-misaapp-production-<suffix>` / `sqldb-misaapp` |
| SQL SKU | `GP_S_Gen5_1` serverless, auto-pause | `GP_S_Gen5_1` serverless, auto-pause | `S0` |
| Replicas (web/api) | min 0 / max 2 | min 0 / max 2 | min 1 / max 5 |
| `gemini_enabled` | false (echo) | false (echo) | true |
| Terraform state | `tfstate-develop/environment.tfstate` | `tfstate-stage/…` | `tfstate-production/…` |

**Validation rules**
- `name` ∈ {`develop`, `stage`, `production`}; names of Azure resources derive from it (no free-form
  names in tfvars except the global-uniqueness `suffix`).
- An environment's identities have no role on any other environment's resource group (FR-016).
- `gemini_enabled = true` requires secret `gemini-api-key` to exist in the environment Key Vault.
  The deploy preflight checks this.

## Shared resources

Not an environment. Applied by the develop deploy job from `infra/shared`.

| Resource | Name | Purpose |
| --- | --- | --- |
| Container registry | `crmisaapp<suffix>` (Standard) | All release artifacts; purge task keeps 30 newest tags or < 90 days |
| SQL server | `sql-misaapp-nonprod-<suffix>` (Entra + SQL auth) | Developer databases `sqldb-misaapp-dev-<alias>` and ephemeral CI databases `sqldb-misaapp-ci-<run>-<attempt>` |
| Key Vault | `kv-misaapp-np-<suffix>` | `sql-admin-password` for the nonprod server |
| Variable `developers` | list of lower-case aliases | One free-offer serverless database per alias |

## Release artifact

One immutable container image per deployable component per commit.

| Field | Value |
| --- | --- |
| Repository | `misaapp-api`, `misaapp-web`, `misaapp-migrator` |
| Tag | full 40-char commit SHA (no `latest`, no mutable tags) |
| Labels | `org.opencontainers.image.revision=<sha>`, `org.opencontainers.image.source=<repo URL>` |
| Baked config | API: `App__Commit=<sha>` |

**Rules**: a tag is written once (re-running a build for the same SHA overwrites it with identical
content). A deploy or rollback must reference a tag that exists in the registry; the workflow checks
this before planning.

## Pipeline run

A GitHub Actions workflow run.

| Field | Source |
| --- | --- |
| Trigger | `pull_request` / `push` / `workflow_dispatch` / `schedule` |
| Commit | `github.sha` |
| Checks | `backend`, `frontend`, `e2e`, `infra`, `secrets` (names are the required status checks; see [contracts/pipeline.md](contracts/pipeline.md)) |
| Result | per-job conclusion + run summary (plan output, deployed URL, commit) |

## Deployment

A GitHub Deployment record, created automatically by a job that targets an environment.

| Field | Source |
| --- | --- |
| Environment | GitHub Environment name |
| Commit / ref | run SHA (or `image_tag` input for rollback) |
| Actor | user who merged, approved, or dispatched |
| Trigger | `merge` / `redeploy` / `rollback` (written into the run name) |
| Status | see state machine |
| Environment URL | public web URL (job `environment.url`) |

**State machine**

```text
queued ──► checks_running ──(any check fails)──► failed
              │
              ▼
          planning ──(plan error / missing secret)──► failed
              │
              ▼
   awaiting_approval* ──(rejected)──► rejected
              │      └─(30 days, no decision)──► expired
              │      └─(newer commit on branch)─► superseded
              ▼
          migrating ──(job execution Failed)──► failed         (old version keeps serving)
              │
              ▼
          applying ──(revision never ready)──► failed          (old revision keeps serving)
              │
              ▼
        verifying ──(smoke fails)──► rolling_back ──► failed   (previous image_tag re-applied)
              │
              ▼
           succeeded
```
\* develop skips `awaiting_approval`. Rollback/redeploy runs skip `checks_running` and `migrating`.

## Approval

Recorded by GitHub on the deployment's environment protection rule.

| Field | Value |
| --- | --- |
| Environment | `stage` or `production` |
| Run / commit | the pending run |
| Reviewer | must be in the environment's required-reviewer list; others can't approve |
| Decision | approved / rejected (expired = no decision within 30 days) |
| Timestamp, comment | from GitHub |

## Infrastructure definition

| Root | State | Applied by | Inputs |
| --- | --- | --- | --- |
| `infra/bootstrap/bootstrap.sh` | none (idempotent CLI) | admin, once | subscription, location, suffix, GitHub repo, approvers |
| `infra/shared` | `tfstate-shared/shared.tfstate` | develop deploy job | `location`, `suffix`, `developers` |
| `infra/environment` | `tfstate-<env>/environment.tfstate` | `<env>` deploy job | `<env>.tfvars` + `image_tag` |

Full inputs and outputs: [contracts/infrastructure.md](contracts/infrastructure.md).

## Identities

| Identity | Kind | Used by | Rights (summary) |
| --- | --- | --- | --- |
| `id-misaapp-gh-ci` | GitHub OIDC | `ci.yml` E2E | nonprod SQL: create/drop DBs, firewall; nonprod Key Vault read; AcrPull |
| `id-misaapp-gh-build` | GitHub OIDC | `build` job | AcrPush |
| `id-misaapp-gh-plan-<env>` | GitHub OIDC | `plan` job | read-only on env + shared; state read |
| `id-misaapp-gh-deploy-<env>` | GitHub OIDC | `deploy` job | Contributor on env resource group (+ limited role assignment); state write |
| `id-misaapp-<env>-api` | Managed (Azure) | API container | AcrPull, Key Vault Secrets User, DB reader/writer |
| `id-misaapp-<env>-migrator` | Managed (Azure) | migrate job | AcrPull, SQL server Entra admin |
