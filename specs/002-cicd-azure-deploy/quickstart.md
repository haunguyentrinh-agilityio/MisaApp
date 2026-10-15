# Quickstart: Validate the CI/CD Pipeline

Run these scenarios after `/speckit-implement` to show the feature works end to end. Contracts:
[pipeline.md](contracts/pipeline.md), [infrastructure.md](contracts/infrastructure.md),
[version-api.openapi.yaml](contracts/version-api.openapi.yaml). Operating guide (written during
implementation): `docs/deployment.md`.

## Prerequisites

- Azure subscription with Owner (bootstrap only) and the `az` CLI logged in.
- GitHub repository admin, `gh` CLI logged in.
- Terraform (version pinned in `infra/*/versions.tf`), Docker Desktop.
- On Windows Git Bash, export `PATHEXT`, `APPDATA`, `ProgramFiles` first (see memory note).

## 0. One-time bootstrap

```bash
infra/bootstrap/bootstrap.sh \
  --subscription <id> --location southeastasia --suffix <abc123> \
  --repo <owner>/<repo> --approvers <github-user>[,<github-user>]
# then set the production Gemini key (value never echoed):
az keyvault secret set --vault-name kv-misaapp-prd-<suffix> --name gemini-api-key --file <(read -rs k; printf %s "$k")
```

**Expect**:
- Resource groups `rg-misaapp-{shared,develop,stage,production}` and the state storage account exist.
- GitHub shows environments `develop`, `stage`, `production` (the last two with required reviewers),
  rulesets on `develop`/`stag`/`main`, repository variables, and **no secrets**.
- Re-running the script changes nothing (idempotent).

## 1. Local stack on Azure SQL

```bash
# add your alias to infra/shared developers list via PR → merged to develop → database created
infra/scripts/allow-my-ip.sh                       # firewall rule for your current IP
# put SQL_CONNECTION_STRING in .env (see contracts/infrastructure.md → Local .env)
docker compose up -d --build                       # http://localhost:3000
curl -s localhost:3000/api/version                 # {"commit":"dev","environment":"local"}
docker compose --profile e2e run --rm --build playwright
```

**Expect**: no `sqlserver` service; the app and the full Playwright suite pass against your Azure SQL
database. `dotnet test`, `pnpm lint && pnpm typecheck && pnpm test && pnpm build` still pass.

## 2. Pull request checks (US2)

1. Open a PR to `develop` with a deliberately failing backend test.
   - **Expect**: `backend` fails with a log link, the other checks report on their own, merge is
     blocked, and no environment is touched (Azure activity log shows only the `ci-*` database
     create/delete).
2. Fix the test.
   - **Expect**: all five checks pass and the ephemeral database is gone afterwards.

## 3. Develop deploys on merge (US1)

1. Merge the PR.
   - **Expect**: `deploy.yml` runs `build`, `checks`, `plan`, `deploy` with no approval prompt.
     Within 20 minutes (SC-001) the run summary shows the URL and commit.
2. Check the deployed version:
   ```bash
   curl -s https://<develop-url>/api/version   # commit == merge SHA, environment == develop
   curl -s https://<develop-url>/api/health    # Healthy
   ```
   Then send a chat message in the browser and get an (echo) reply.
3. Add a trivial EF migration in a PR and merge it.
   - **Expect**: the migrate job execution succeeds before the new revision is created; the
     `__EFMigrationsHistory` table in the develop database lists the migration.
4. Merge two PRs back to back.
   - **Expect**: the deploys run one after the other, and the environment ends on the newer commit.

## 4. Stage with approval (US3)

1. PR `develop` → `stag`, then merge.
   - **Expect**: the `deploy` job waits on "Review deployments", and the run summary shows the
     Terraform plan (image tag change). Stage still serves the old commit.
2. Reject it.
   - **Expect**: nothing is deployed, and GitHub records the rejection with your name.
3. Re-run and approve.
   - **Expect**: stage `/api/version` shows the new commit. Develop and production are unchanged.

## 5. Production with approval and zero downtime (US4)

1. While merging `stag` → `main`, run a request loop against production:
   ```bash
   while true; do curl -s -o /dev/null -w "%{http_code}\n" https://<prod-url>/api/health; sleep 0.5; done
   ```
2. Approve the deployment (a non-approver's account must not see an Approve button).
   - **Expect**: the loop prints only `200` during the rollout (SC-003), and production
     `/api/version` shows the new commit.
3. Approve while a newer commit is already on `main`.
   - **Expect**: the older run ends as "superseded" and deploys nothing.

## 6. Failure handling

| Scenario | How | Expect |
| --- | --- | --- |
| Migration fails | PR with a migration that violates a constraint, merge to develop | migrate job `Failed`, apply skipped, old version serving, run failed + email |
| Revision never healthy | Temporarily set a wrong DB name in develop tfvars | apply reports failed revision, old revision keeps serving |
| Smoke fails | Throwaway PR making `smoke.spec.ts` assert a missing heading, merge to develop | previous `image_tag` re-applied, run failed; revert the PR afterwards |
| Missing secret | Set `gemini_enabled = true` in develop tfvars without the secret | preflight fails naming `gemini-api-key`, value never printed |
| Stateful delete | PR that removes the SQL database resource | `plan` fails on `prevent_destroy` |

## 7. Rollback (US5)

```bash
gh workflow run deploy.yml --ref develop -f environment=develop -f image_tag=<earlier sha> -f reason="validate rollback"
```

Run it from the environment's branch (`--ref develop`, `stag`, or `main`): the environment's
deployment-branch rule and the plan identity's federated credential only accept that branch.

**Expect**:
- Finishes in under 10 minutes (SC-004) and `/api/version` shows the earlier commit.
- The GitHub `develop` environment history lists the rollback with your name.
- Stage and production are unchanged.
- An unknown tag fails at `verify-tag`.

## 8. Secrets hygiene (SC-006)

- `gitleaks` passes on the branch.
- Search the run logs for the SQL password and Gemini key: only `***` appears.
- `docker history` / `docker inspect` of the three images shows no secrets.
