# Quickstart: Validate Stateless Chat (Remove the Database)

Contract: [contracts/chat-api.md](contracts/chat-api.md). Release order and reasoning:
[research.md R7](research.md#r7-order-of-removal-in-azure-expandcontract-for-infrastructure).

## Release A — the app stops using the database (this branch)

### A1. No database anywhere in the code

```bash
git grep -nIiE "EntityFrameworkCore|SqlClient|AppDbContext|ConnectionStrings|MigrateOnStartup|SQL_CONNECTION_STRING|dotnet ef|misaapp-migrator" \
  -- backend frontend compose*.yaml .env.example .github README.md CLAUDE.md
```

Expected: no matches (Terraform in `infra/` still has SQL until Release B; see A5).

### A2. Backend

```bash
cd backend && dotnet test
```

Expected: all pass. Covers: reply with no history; history forwarded oldest-first and capped at
`MaxHistoryMessages - 1`; 400 for blank/oversized message, > 20 turns, blank/oversized turn, unknown
role; 502 on model failure; removed `GET` routes return 404; `/api/health` is 200.

### A3. Frontend

```bash
cd frontend && pnpm lint && pnpm typecheck && pnpm test && pnpm build
```

(Node < 24 locally: use the `node:24-alpine` container command from `CLAUDE.md`.)

Expected: all pass. Covers: send/reply; follow-up sends `history`; failed send restores the draft and
writes nothing; chat restored from storage without a network call; "New chat" clears screen and
storage; legacy `chat.conversationId` removed; unreadable storage discarded; storage errors don't
break chatting; storage capped at 100 messages; history capped at 20 turns × 8,000 characters;
non-string `reply` shown as an error.

### A4. Docker stack with no database settings

```bash
# .env needs no SQL_CONNECTION_STRING any more (GEMINI_API_KEY is optional).
docker compose up -d --build
curl -s http://localhost:3000/api/health          # → Healthy
docker compose --profile e2e run --rm --build playwright
```

Expected: Playwright passes: reply received; the second request's body carries two history turns;
reload keeps the chat; "New chat" clears it and a reload stays empty; a legacy stored conversation id
causes no error.

### A5. Infra and workflows

```bash
terraform -chdir=infra/environment init -backend=false && terraform -chdir=infra/environment validate
terraform -chdir=infra/shared init -backend=false && terraform -chdir=infra/shared validate
actionlint
```

Expected: valid. `deploy.yml` builds only `misaapp-api` and `misaapp-web`, has no migrate step, and
`ci.yml`'s e2e job creates no database and logs in to Azure only for registry images.

### A6. After merge, per environment (develop → stage → production)

- Deploy succeeds with no "Migrate database" step; the smoke test passes.
- `terraform plan` (deploy `plan` job) for each environment shows only: API/web image update,
  migrate job destroyed, migrator `acr_pull` role assignment destroyed. **No SQL resource changes.**
- In the app: chat, reload, "New chat" behave as in A4.

**Gate for Release B:** Release A is deployed and healthy in develop, stage, **and** production.

## Release B — delete database infrastructure (follow-up PR)

### B1. Before merging: review the destroy plans locally

```bash
# Shared root (applied with -auto-approve when B reaches develop)
terraform -chdir=infra/shared init -backend-config=... && terraform -chdir=infra/shared plan -var "ci_principal_id=<id>"
# Each environment root
terraform -chdir=infra/environment plan -var-file=develop.tfvars -var "image_tag=<current sha>"
```

Expected: only destroys of SQL servers/databases, the firewall rule, the migrator identity, the
nonprod Key Vault + `sql-admin-password`, CI SQL/Key Vault role assignments, and an in-place update of
the API container app (SQL env vars removed, startup probe shortened). Nothing else is destroyed.

### B2. After B is applied in each environment

```bash
az resource list --resource-type Microsoft.Sql/servers --query "[?contains(name,'misaapp')].name" -o tsv   # → empty once B is everywhere
az acr repository delete --name <acr> --repository misaapp-migrator --yes                               # one time, after B reaches develop
```

Expected: smoke test passes in each environment; no SQL server remains after production.

## Release C — remove unused Terraform providers (follow-up PR)

Prerequisite: Release B applied in all environments. Remove `azapi` (both roots) and `random`
(`infra/shared`) from `versions.tf`/`providers.tf` and the lock files, then:

```bash
terraform -chdir=infra/environment init -upgrade -backend=false && terraform -chdir=infra/environment validate
terraform -chdir=infra/shared init -upgrade -backend=false && terraform -chdir=infra/shared validate
```

Expected: valid; the deploy `plan` job shows no changes.
