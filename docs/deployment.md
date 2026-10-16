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
2. **build**: builds `misaapp-api` and `misaapp-web` once, tagged with the full commit SHA, and pushes
   them to the shared registry `crmisaapp<suffix>`.
3. **checks**: runs `ci.yml` again, with E2E against those exact images.
4. **plan**: a read-only identity runs `terraform plan`. The plan appears in the run summary under
   "Planned changes for <env>".
5. **deploy** (GitHub Environment, so approvals and history apply):
   1. Stops with "Superseded by <sha>" if the branch has moved on since this run started.
   2. Checks the Terraform state is reachable. On `develop` it also applies `infra/shared`.
   3. Records the commit currently deployed (the rollback target).
   4. On the first deployment only, creates the Key Vault and the apps' role assignments first, so
      they have propagated before the apps start.
   5. Checks the Gemini secret exists when `gemini_enabled = true` (the name only; the value is
      never read).
   6. Applies exactly the approved plan. Container Apps starts the new revision and moves traffic
      once it passes its readiness probe.
   7. Runs the `@smoke` Playwright tests against the live URL and checks `/api/version` reports this
      commit.
   8. If the smoke test fails, re-applies the previous commit's images and fails the run, so GitHub
      notifies the team.

Deploys to one environment are queued, never run in parallel, and never cancelled halfway.

## Approving a stage or production deploy

The run waits on **Review deployments**. Before approving, open the run summary and read the
`plan` job's "Planned changes" section. Approving applies exactly that plan. Usually the plan is just
an image tag change on the two apps.

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
- `verify-tag` fails with "Image tag <sha> not found in registry" if the API or web image is gone.
- Stage and production still need approval. The environment history shows the actor and reason.
- See the limits below before rolling back past the database removal.
- Redeploying the current tag is safe and changes nothing.

Find earlier SHAs in the environment's deployment history on GitHub, or with
`git log --first-parent <branch>`.

## Rollback limits after the database removal

The app stopped using its database in [specs/003-remove-chat-database](../specs/003-remove-chat-database/spec.md),
which ships in three releases:

| Release | What changes | Rolling back to a commit from before Release A |
| ------- | ------------ | ---------------------------------------------- |
| A (code) | The app, CI and deploy no longer use the database. Azure SQL, its data, the migrator identity, and the API's SQL env vars stay. | Works: the old image finds its database, schema and connection string. It shows only conversations saved before A. |
| B (infra) | Deletes the SQL servers and databases (all stored conversations, no backup), the nonprod vault, CI database cleanup, and the migrator identity and images. | **Not possible**: the old image needs the database. Roll back only to commits from Release A onward. |
| C (providers) | Removes Terraform providers that only the database used. | No further change. |

Release B is merged only after Release A has been deployed and is healthy in develop, stage **and**
production; Release C only after B is applied everywhere.

### Release B and C runbook

1. Before merging B, review the destroy plans locally for `infra/shared` and each environment
   ([quickstart B1](../specs/003-remove-chat-database/quickstart.md#b1-before-merging-review-the-destroy-plans-locally)).
   Only the listed SQL, vault and migrator resources may be destroyed. Removing their resource
   blocks also removes their `prevent_destroy` guard, so this review is the safeguard.
2. Merge B to `develop`; it deploys like any change (the develop apply of `infra/shared` deletes the
   nonprod SQL server and vault). Promote to `stag` and `main` with the usual approvals, reading each
   plan.
3. After each environment applies B, run the checks in
   [quickstart B2](../specs/003-remove-chat-database/quickstart.md#b2-after-b-is-applied-in-each-environment).
4. Then open the Release C PR
   ([quickstart C](../specs/003-remove-chat-database/quickstart.md#release-c--remove-unused-terraform-providers-follow-up-pr)).

## Secrets

Secrets live only in Azure Key Vault; GitHub has none (workflows use OIDC).

| Vault                       | Secret               | Used by                               |
| --------------------------- | -------------------- | ------------------------------------- |
| `kv-misaapp-np-<suffix>`    | `sql-admin-password` | nothing (deleted in Release B)        |
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
federated credentials and roles, the GitHub environments, rulesets and variables, an empty Terraform
state for each environment (the plan identities can only read state), and the first `infra/shared`
apply. It is idempotent. Then set the production Gemini key as shown above and push to
`develop` to create the develop environment.

Federated credential subjects use the prefix GitHub reports for the repository
(`gh api repos/<owner>/<repo>/actions/oidc/customization/sub`). New repositories use immutable
subjects such as `repo:<owner>@<owner-id>/<repo>@<repo-id>:pull_request`. If `azure/login` fails with
`AADSTS700213: No matching federated identity record`, the subject format changed (for example after
a rename, transfer, or switching immutable subjects on or off): re-run the bootstrap to update the
credentials.

## Cost notes

| Service                 | SKU                                          | Notes |
| ----------------------- | -------------------------------------------- | ----- |
| Container Apps          | Consumption                                  | develop and stage scale to zero; production keeps one replica |
| Registry                | Standard                                     | Daily purge task `purge-old-images` |
| Azure SQL (until Release B) | serverless in develop/stage, Standard S0 in production | Unused by the app; deleted in Release B |

## Troubleshooting

| Symptom | Cause and fix |
| ------- | ------------- |
| Apply fails with a revision that never becomes ready | Check the API's console logs (startup errors, Key Vault access). Traffic stays on the previous revision. |
| `Key Vault secret gemini-api-key missing in …` | Set the secret as shown above, then re-run the job. |
| `Terraform state for <env> unreachable` | Check the state storage account and the deploy identity's role on `tfstate-<env>`. |
| `plan` fails with `failed to lock azure state` … `AuthorizationPermissionMismatch` | The environment's `environment.tfstate` doesn't exist yet, and the read-only plan identity can't create it. Re-run the bootstrap (it creates the empty state), then re-run the workflow. |
| `Superseded by <sha>` | Expected: a newer commit is on the branch. Approve the newer run instead. |
| `state changed since approved plan` | Another deploy finished first. Re-run all jobs and approve the new plan. |
| `Smoke failed: rolled back to <sha>` | Download the smoke report artifact; fix forward with a new PR. |
| `plan` fails on `prevent_destroy` | The change would delete a database, SQL server or Key Vault. Rework the change. |
| `Run this from branch …` | A manual deploy was started from the wrong `--ref`. |
