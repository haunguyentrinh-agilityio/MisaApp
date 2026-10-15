# Deployment

How MisaApp gets from a merged pull request to Azure, and how to operate it. Design and contracts:
[specs/002-cicd-azure-deploy](../specs/002-cicd-azure-deploy/spec.md). Validation scenarios:
[quickstart.md](../specs/002-cicd-azure-deploy/quickstart.md).

## Branches and environments

| Branch    | Environment  | Approval            | Azure resource group     |
| --------- | ------------ | ------------------- | ------------------------ |
| `develop` | `develop`    | none                | `rg-misaapp-develop`     |
| `stag`    | `stage`      | required reviewers  | `rg-misaapp-stage`       |
| `main`    | `production` | required reviewers  | `rg-misaapp-production`  |

Work flows `feature branch → PR → develop → PR → stag → PR → main`. All three branches are protected by
rulesets: a pull request and the five checks (`backend`, `frontend`, `infra`, `secrets`, `e2e`) are
required, and force-push and deletion are blocked. To promote, open a PR from `develop` to `stag` (or
from `stag` to `main`) and merge it.

## What a deploy does

`.github/workflows/deploy.yml` runs on every push to those branches:

1. **resolve**: maps the branch to one environment. Every later name and identity comes from it.
2. **build**: builds `misaapp-api`, `misaapp-web` and `misaapp-migrator` once, tagged with the full
   commit SHA, and pushes them to the shared registry `crmisaapp<suffix>`.
3. **checks**: runs `ci.yml` again, with E2E against those exact images.
4. **plan**: a read-only identity runs `terraform plan`. The plan appears in the run summary under
   "Planned changes for <env>".
5. **deploy** (GitHub Environment, so approvals and history apply):
   1. Stops with "Superseded by <sha>" if the branch has moved on since this run started.
   2. Checks the Terraform state is reachable. On `develop` it also applies `infra/shared`.
   3. Records the commit currently deployed (the rollback target).
   4. On the first deployment only, creates the database and migrate job first.
   5. Checks the Gemini secret exists when `gemini_enabled = true` (the name only; the value is
      never read).
   6. Runs the migrate job with the new migrator image. If it fails, nothing else changes.
   7. Applies exactly the approved plan. Container Apps starts the new revision and moves traffic
      once it passes its readiness probe.
   8. Runs the `@smoke` Playwright tests against the live URL and checks `/api/version` reports this
      commit.
   9. If the smoke test fails, re-applies the previous commit's images and fails the run, so GitHub
      notifies the team.

Deploys to one environment are queued, never run in parallel, and never cancelled halfway.

## Approving a stage or production deploy

The run waits on **Review deployments**. Before approving, open the run summary and read the
`plan` job's "Planned changes" section. Approving applies exactly that plan. Usually the plan is just
an image tag change on the two apps and the migrate job.

- **Approve**: the deploy proceeds as above.
- **Reject**: nothing is deployed; GitHub records who rejected it.
- If another deploy changed the environment after the plan was made, `deploy` fails with "state
  changed since approved plan". Use **Re-run all jobs** to plan and approve again.
- If you approve an old run after a newer commit landed, it ends as "Superseded" and deploys nothing.

## Rollback and redeploy

Put an environment back on any earlier commit whose images are still in the registry (images are
kept 90 days, and the 30 newest always stay):

```bash
gh workflow run deploy.yml --ref develop -f environment=develop -f image_tag=<full sha> -f reason="why"
gh workflow run deploy.yml --ref stag    -f environment=stage      -f image_tag=<full sha> -f reason="why"
gh workflow run deploy.yml --ref main    -f environment=production -f image_tag=<full sha> -f reason="why"
```

- Run it from the environment's branch; any other `--ref` fails in `resolve`.
- `verify-tag` fails with "Image tag <sha> not found in registry" if any of the three images is gone.
- Stage and production still need approval. The environment history shows the actor and reason.
- A rollback doesn't run migrations and doesn't revert the schema (see the rule below).
- Redeploying the current tag is safe and changes nothing.

Find earlier SHAs in the environment's deployment history on GitHub, or with
`git log --first-parent <branch>`.

## Database migrations: backward compatibility rule

The migrate job runs **before** the new revision starts, while the old revision keeps serving, and a
rollback keeps the new schema. So every migration must work with the previous release's code:

- **Expand, then contract.** Add nullable columns or new tables first; remove or rename columns in a
  later release, after no deployed code uses them.
- No column renames or type changes in one step; add the new column, backfill, switch the code, then
  drop the old one later.
- Don't add a `NOT NULL` column without a default.

`/db-migration` checks this. Never edit an applied migration.

## Secrets

Secrets live only in Azure Key Vault; GitHub has none (workflows use OIDC).

| Vault                       | Secret               | Used by                               |
| --------------------------- | -------------------- | ------------------------------------- |
| `kv-misaapp-np-<suffix>`    | `sql-admin-password` | CI E2E, local development             |
| `kv-misaapp-<code>-<suffix>` | `gemini-api-key`    | the API app (`<code>`: `dev`, `stg`, `prd`) |

Add or rotate a secret without echoing it (needs Key Vault Secrets Officer on that vault):

```bash
az keyvault secret set --vault-name kv-misaapp-prd-<suffix> --name gemini-api-key \
  --file <(read -rs k; printf %s "$k")
```

Container Apps refreshes Key Vault references within 30 minutes; running replicas see the new value
after they restart (`az containerapp revision restart`) or on the next deploy. To use a
real Gemini key in develop or stage, set the secret, then set `gemini_enabled = true` in that
environment's tfvars through a PR.

## Bootstrap (once per subscription)

Run as a subscription Owner who is also a repository admin, with `az` and `gh` logged in:

```bash
infra/bootstrap/bootstrap.sh --subscription <id> --location southeastasia --suffix <abc123> \
  --repo <owner>/<repo> --approvers <github-user>[,<github-user>]
```

It creates the resource groups, the Terraform state storage, the managed identities with their
federated credentials and roles, the GitHub environments, rulesets and variables, and the first
`infra/shared` apply. It is idempotent. Then set the production Gemini key as shown above and push to
`develop` to create the develop environment.

Federated credential subjects use the prefix GitHub reports for the repository
(`gh api repos/<owner>/<repo>/actions/oidc/customization/sub`). New repositories use immutable
subjects such as `repo:<owner>@<owner-id>/<repo>@<repo-id>:pull_request`. If `azure/login` fails with
`AADSTS700213: No matching federated identity record`, the subject format changed (for example after
a rename, transfer, or switching immutable subjects on or off): re-run the bootstrap to update the
credentials.

## Local development on Azure SQL

There is no local SQL container. Each developer has a database on the shared nonprod server:

1. Add your alias (`^[a-z0-9]{2,12}$`) to `developers` in `infra/shared/terraform.tfvars` through a PR
   to `develop`. The deploy creates `sqldb-misaapp-dev-<alias>`.
2. Ask an admin for **Key Vault Secrets User** on `kv-misaapp-np-<suffix>`.
3. Open the firewall to your IP (re-run when your IP changes):
   `infra/scripts/allow-my-ip.sh --alias <alias> --suffix <suffix>`.
4. Copy `.env.example` to `.env` and fill in `SQL_CONNECTION_STRING`. Get the password with
   `az keyvault secret show --vault-name kv-misaapp-np-<suffix> --name sql-admin-password --query value -o tsv`
   and paste it into `.env` directly; don't put it in shell history or commit it.
5. `docker compose up -d --build`. The backend applies migrations to your database on startup.

For `dotnet run` outside Docker, set the same connection string with
`dotnet user-secrets set "ConnectionStrings:Default" "<connection string>" --project backend/src/MisaApp.Api`.

## Cost notes

| Database / service      | SKU                                         | Notes |
| ----------------------- | ------------------------------------------- | ----- |
| Developer databases     | serverless `GP_S_Gen5_1`, free offer        | Up to 10 free per subscription; auto-pause after 60 min |
| CI databases            | Basic                                        | Exist for about 15 minutes per run; an hourly sweep drops leftovers |
| develop, stage          | serverless `GP_S_Gen5_1`, auto-pause 60 min | First request after a pause waits about a minute |
| production              | Standard S0, always on                      | Scale up in `production.tfvars` |
| Container Apps          | Consumption                                  | develop and stage scale to zero; production keeps one replica |
| Registry                | Standard                                     | Daily purge task `purge-old-images` |

## Troubleshooting

| Symptom | Cause and fix |
| ------- | ------------- |
| `Migration <execution> failed` | Open Log Analytics `log-misaapp-<env>` and query `ContainerAppConsoleLogs_CL` for the execution name. Fix the migration in a new PR; the old version is still serving. |
| Apply fails with a revision that never becomes ready | Check the API's console logs (startup errors, database access). Traffic stays on the previous revision. |
| `Key Vault secret gemini-api-key missing in …` | Set the secret as shown above, then re-run the job. |
| `Terraform state for <env> unreachable` | Check the state storage account and the deploy identity's role on `tfstate-<env>`. |
| `Superseded by <sha>` | Expected: a newer commit is on the branch. Approve the newer run instead. |
| `state changed since approved plan` | Another deploy finished first. Re-run all jobs and approve the new plan. |
| `Smoke failed: rolled back to <sha>` | Download the smoke report artifact; fix forward with a new PR. |
| `plan` fails on `prevent_destroy` | The change would delete a database, SQL server or Key Vault. Rework the change. |
| `Run this from branch …` | A manual deploy was started from the wrong `--ref`. |
