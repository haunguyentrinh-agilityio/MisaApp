# Contract: Pipeline (GitHub Actions + GitHub settings)

What the workflows promise to developers, reviewers, and approvers. Research: R6–R8, R11.

## Workflows

### `ci.yml` (quality checks)

| | |
| --- | --- |
| Triggers | `pull_request` → `develop`, `stag`, `main`; `workflow_call` |
| `workflow_call` inputs | `image_tag` (string, optional): when set, E2E pulls `misaapp-api`, `misaapp-web` with this tag from the registry instead of building |
| Permissions | `contents: read`, `id-token: write` (E2E only) |
| Side effects | creates and drops one ephemeral database on `sql-misaapp-nonprod-<suffix>`; **never** touches develop, stage, or production (US2-AS2) |

Jobs, which are also the **required status checks** on the protected branches (FR-023):

| Check name | Runs | Fails when |
| --- | --- | --- |
| `backend` | `dotnet test` in `backend/` | any test fails / build warning in Release |
| `frontend` | `pnpm lint`, `pnpm typecheck`, `pnpm test`, `pnpm build` (Node 24, pnpm from `packageManager`) | any step fails |
| `e2e` | ephemeral Azure SQL DB → `docker compose --profile e2e` (no `GEMINI_API_KEY`) → Playwright (Chromium, Firefox) | any test fails; report uploaded as artifact |
| `infra` | `terraform fmt -check`, `terraform validate` (both roots, `-backend=false`), `tflint`, `trivy config`, `actionlint` | formatting, validation, or high-severity misconfiguration |
| `secrets` | `gitleaks` on the diff/history | a secret is detected |

### `deploy.yml` (release)

| | |
| --- | --- |
| Triggers | `push` → `develop`, `stag`, `main`; `workflow_dispatch` |
| Branch → environment | `develop` → `develop`, `stag` → `stage`, `main` → `production` (no other mapping) |
| `workflow_dispatch` inputs | `environment` (choice: develop/stage/production, required); `image_tag` (string, required: commit SHA already in the registry); `reason` (string, required, shown in run name) |
| Run name | `Deploy <env> @ <short sha>` / `Rollback <env> → <short tag>: <reason>` |
| Concurrency | job `deploy`: group `deploy-<env>`, `cancel-in-progress: false` |

Job graph:

```text
push:     build ─► checks ─► plan ─► deploy[environment=<env>]  (approval gate for stage/production)
dispatch: verify-tag ─► plan ─► deploy[environment=<env>]
```

`checks` runs after `build` because its `e2e` job pulls the images `build` pushed. A dispatch must
run from the environment's branch (`gh workflow run deploy.yml --ref <branch> …`); `resolve` rejects
any other ref.

`deploy` steps, in order (any failure stops and fails the run):

1. **Superseded guard** (push only): exit "superseded" if `origin/<branch>` ≠ run SHA.
2. **Preflight**: `gemini-api-key` exists if `gemini_enabled`; Terraform state reachable.
3. `infra/shared` plan + apply (develop only).
4. **Capture** previous `image_tag` (Terraform output).
5. **Migrate** (push only): start `caj-misaapp-<env>-migrate` with `misaapp-migrator:<sha>`, wait,
   fail on `Failed`.
6. **Apply** the saved plan from the `plan` job.
7. **Smoke**: Playwright `@smoke` against the environment URL, `EXPECTED_COMMIT=<tag>`.
8. On smoke failure: re-apply with the previous `image_tag`, then fail.

Outputs written to the run summary: environment URL, deployed commit, previous commit, plan
summary, migration execution name.

### `cleanup-ci-databases.yml`

Hourly. Deletes `sqldb-misaapp-ci-*` databases and `ci-*` firewall rules on
`sql-misaapp-nonprod-<suffix>` older than 2 hours. Idempotent.

## GitHub repository configuration (applied by `infra/bootstrap/bootstrap.sh`)

| Setting | Value |
| --- | --- |
| Rulesets on `develop`, `stag`, `main` | require PR, require status checks `backend`, `frontend`, `e2e`, `infra`, `secrets`; block force-push and deletion; admins may bypass |
| Environment `develop` | deployment branches: `develop` |
| Environment `stage` | deployment branches: `stag`; required reviewers: approvers list |
| Environment `production` | deployment branches: `main`; required reviewers: approvers list |
| Repository variables | `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_CI_CLIENT_ID`, `AZURE_CI_PRINCIPAL_ID`, `AZURE_BUILD_CLIENT_ID`, `AZURE_PLAN_CLIENT_ID_DEVELOP`/`_STAGE`/`_PRODUCTION`, `ACR_NAME`, `TFSTATE_ACCOUNT`, `AZURE_LOCATION`, `NAME_SUFFIX` |
| Environment variables | `AZURE_DEPLOY_CLIENT_ID` (per environment) |
| Secrets | **none** (OIDC only) |
| Security | secret scanning + push protection on |

## Guarantees

- No job that lacks the `<env>` GitHub Environment can change that environment's resources.
- The plan an approver sees in the run summary is the plan that is applied.
- A run never deploys a commit whose `checks` job did not succeed in the same run (push), or an
  image tag missing from the registry (dispatch).
- Two `deploy` jobs never run at the same time for the same environment.
