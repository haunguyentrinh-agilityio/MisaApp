#!/usr/bin/env bash
# One-time, idempotent Azure + GitHub bootstrap for MisaApp CI/CD (specs/002-cicd-azure-deploy).
# Run as a subscription Owner who is also a GitHub repository admin. Re-running changes nothing.
#
#   infra/bootstrap/bootstrap.sh --subscription <id> --location southeastasia --suffix <abc123> \
#     --repo <owner>/<repo> --approvers <github-user>[,<github-user>]
#
# Parts: 1 Azure foundation, 2 identities, 3 GitHub settings, 4 environment state and first apply
# of infra/shared.
# No secrets are created in GitHub; workflows authenticate with OIDC.
set -euo pipefail
export MSYS_NO_PATHCONV=1 # Git Bash: keep /subscriptions/... scopes intact
# Ignore a personal `az configure --defaults group=...`: az rejects it alongside --scope.
export AZURE_DEFAULTS_GROUP=""

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

usage() {
  sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

SUBSCRIPTION="" LOCATION="" SUFFIX="" REPO="" APPROVERS=""
while (($#)); do
  case "$1" in
    --subscription) SUBSCRIPTION="${2:-}"; shift 2 ;;
    --location) LOCATION="${2:-}"; shift 2 ;;
    --suffix) SUFFIX="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --approvers) APPROVERS="${2:-}"; shift 2 ;;
    -h | --help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

for arg in SUBSCRIPTION LOCATION SUFFIX REPO APPROVERS; do
  [[ -n "${!arg}" ]] || { echo "Missing --$(tr '[:upper:]' '[:lower:]' <<<"$arg")" >&2; usage; }
done
[[ "$SUFFIX" =~ ^[a-z0-9]{1,6}$ ]] || { echo "--suffix must match ^[a-z0-9]{1,6}\$" >&2; exit 2; }
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "--repo must be <owner>/<repo>" >&2; exit 2; }
((BASH_VERSINFO[0] >= 4)) || { echo "bash 4 or later is required" >&2; exit 2; }

ENVIRONMENTS=(develop stage production)
declare -A BRANCH=([develop]=develop [stage]=stag [production]=main)
SHARED_RG="rg-misaapp-shared"
TFSTATE_ACCOUNT="stmisaapptf${SUFFIX}"
ACR_NAME="crmisaapp${SUFFIX}"
OIDC_ISSUER="https://token.actions.githubusercontent.com"
SECRET_READER_ROLE="MisaApp Container Apps Secret Reader"

# Role definition IDs used in ABAC conditions (built-in roles, same in every tenant).
ROLE_ACR_PULL="7f951dda-4ed3-4680-a7ca-43fe172d538d"
ROLE_KV_SECRETS_USER="4633458b-17de-408a-b874-0445c86b69e6" # gitleaks:allow (public built-in role ID)

SUMMARY=()
record() { SUMMARY+=("$(printf '%-8s %s' "$1" "$2")"); printf '  %-8s %s\n' "$1" "$2"; }
section() { printf '\n== %s\n' "$*"; }

# Retries a command that can fail briefly while a new identity replicates (PrincipalNotFound).
retry() {
  local attempt=1
  until "$@"; do
    ((attempt >= 6)) && return 1
    echo "  retrying in 10 s ($attempt/5)..." >&2
    sleep 10
    attempt=$((attempt + 1))
  done
}

# ensure_role <principal-object-id> <principal-type> <role-name> <scope> [abac-condition]
# Prints "created" when it adds the assignment, so callers can wait for propagation.
ensure_role() {
  local principal=$1 type=$2 role=$3 scope=$4 condition=${5:-}
  local existing
  existing=$(az role assignment list --scope "$scope" --role "$role" \
    --query "length([?principalId=='$principal' && scope=='$scope'])" -o tsv)
  if [[ "$existing" != "0" ]]; then
    record exists "role '$role' on ${scope##*/}"
    return
  fi
  local args=(--assignee-object-id "$principal" --assignee-principal-type "$type" --role "$role" --scope "$scope" -o none)
  [[ -n "$condition" ]] && args+=(--condition "$condition" --condition-version 2.0)
  retry az role assignment create "${args[@]}"
  record created "role '$role' on ${scope##*/}"
}

# ABAC condition: the holder may only add/remove assignments of the given role definition IDs.
rbac_condition() {
  local ids
  ids=$(printf '%s, ' "$@")
  ids=${ids%, }
  printf "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {%s})) AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {%s}))" "$ids" "$ids"
}

# ---------------------------------------------------------------------------------------------
section "Prerequisites"
for tool in az gh jq terraform; do
  command -v "$tool" >/dev/null || { echo "$tool is not installed" >&2; exit 1; }
done
az account show -o none 2>/dev/null || { echo "Run 'az login' first" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Run 'gh auth login' first" >&2; exit 1; }
az account set --subscription "$SUBSCRIPTION"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
gh api "repos/$REPO" --jq .full_name >/dev/null || { echo "GitHub repository $REPO not found or not accessible" >&2; exit 1; }
# The OIDC subject prefix GitHub presents: repo:<owner>/<repo>, or repo:<owner>@<id>/<repo>@<id> when
# the repository uses immutable subjects (the default for new repositories).
oidc_sub=$(gh api "repos/$REPO/actions/oidc/customization/sub")
[[ "$(jq -r .use_default <<<"$oidc_sub")" == "true" ]] || {
  echo "$REPO customizes its OIDC subject claim keys; the federated credentials below assume the default" >&2
  exit 1
}
SUBJECT_PREFIX=$(jq -r --arg d "repo:$REPO" '.sub_claim_prefix // $d' <<<"$oidc_sub")
echo "  subscription $SUBSCRIPTION_ID, tenant $TENANT_ID, repo $REPO"
echo "  OIDC subject prefix $SUBJECT_PREFIX"

# ---------------------------------------------------------------------------------------------
section "Part 1: Azure foundation"

# Deploy identities only hold resource-group roles, so Terraform's providers run with
# resource_provider_registrations = "none"; register what the roots use once, here.
for namespace in Microsoft.App Microsoft.OperationalInsights Microsoft.KeyVault \
  Microsoft.ContainerRegistry Microsoft.ManagedIdentity Microsoft.Storage; do
  if [[ "$(az provider show -n "$namespace" --query registrationState -o tsv)" == "Registered" ]]; then
    record exists "provider $namespace"
  else
    az provider register -n "$namespace" --wait -o none
    record created "provider $namespace"
  fi
done

for rg in "$SHARED_RG" rg-misaapp-develop rg-misaapp-stage rg-misaapp-production; do
  exists=$(az group exists -n "$rg")
  if [[ "${exists,,}" == "true" ]]; then
    record exists "resource group $rg"
  else
    az group create -n "$rg" -l "$LOCATION" --tags app=misaapp -o none
    record created "resource group $rg"
  fi
done

storage_flags=(--min-tls-version TLS1_2 --allow-blob-public-access false --allow-shared-key-access false --https-only true)
if az storage account show -n "$TFSTATE_ACCOUNT" -g "$SHARED_RG" -o none 2>/dev/null; then
  az storage account update -n "$TFSTATE_ACCOUNT" -g "$SHARED_RG" "${storage_flags[@]}" -o none
  record exists "storage account $TFSTATE_ACCOUNT (settings enforced)"
else
  az storage account create -n "$TFSTATE_ACCOUNT" -g "$SHARED_RG" -l "$LOCATION" \
    --kind StorageV2 --sku Standard_LRS --tags app=misaapp "${storage_flags[@]}" -o none
  record created "storage account $TFSTATE_ACCOUNT"
fi
TFSTATE_ID=$(az storage account show -n "$TFSTATE_ACCOUNT" -g "$SHARED_RG" --query id -o tsv)
az storage account blob-service-properties update --account-name "$TFSTATE_ACCOUNT" -g "$SHARED_RG" \
  --enable-versioning true \
  --enable-delete-retention true --delete-retention-days 30 \
  --enable-container-delete-retention true --container-delete-retention-days 30 -o none
record ensured "blob versioning + 30-day soft delete on $TFSTATE_ACCOUNT"

for container in tfstate-shared tfstate-develop tfstate-stage tfstate-production; do
  # container-rm goes through ARM, so it works with shared-key access disabled and no data role.
  exists=$(az storage container-rm exists --storage-account "$TFSTATE_ACCOUNT" -g "$SHARED_RG" -n "$container" -o tsv)
  if [[ "${exists,,}" == "true" ]]; then
    record exists "container $container"
  else
    az storage container-rm create --storage-account "$TFSTATE_ACCOUNT" -g "$SHARED_RG" -n "$container" -o none
    record created "container $container"
  fi
done
container_scope() { echo "$TFSTATE_ID/blobServices/default/containers/$1"; }

if [[ -n "$(az lock list -g "$SHARED_RG" --resource-name "$TFSTATE_ACCOUNT" --resource-type Microsoft.Storage/storageAccounts --query "[?level=='CanNotDelete'].name" -o tsv)" ]]; then
  record exists "CanNotDelete lock on $TFSTATE_ACCOUNT"
else
  az lock create -n lock-tfstate-nodelete --lock-type CanNotDelete -g "$SHARED_RG" \
    --resource-name "$TFSTATE_ACCOUNT" --resource-type Microsoft.Storage/storageAccounts -o none
  record created "CanNotDelete lock on $TFSTATE_ACCOUNT"
fi

# ---------------------------------------------------------------------------------------------
section "Part 2: identities, federated credentials, roles"

declare -A CLIENT_ID PRINCIPAL_ID
ensure_identity() {
  local name=$1
  if az identity show -n "$name" -g "$SHARED_RG" -o none 2>/dev/null; then
    record exists "identity $name"
  else
    az identity create -n "$name" -g "$SHARED_RG" -l "$LOCATION" --tags app=misaapp -o none
    record created "identity $name"
  fi
  CLIENT_ID[$name]=$(az identity show -n "$name" -g "$SHARED_RG" --query clientId -o tsv)
  PRINCIPAL_ID[$name]=$(az identity show -n "$name" -g "$SHARED_RG" --query principalId -o tsv)
}

# ensure_federation <identity> <credential-name> <subject-suffix>; subject = <SUBJECT_PREFIX>:<suffix>
ensure_federation() {
  local identity=$1 name=$2 subject="$SUBJECT_PREFIX:$3" current
  current=$(az identity federated-credential show --identity-name "$identity" -g "$SHARED_RG" -n "$name" \
    --query subject -o tsv 2>/dev/null || true)
  if [[ "$current" == "$subject" ]]; then
    record exists "federation $identity <- $subject"
    return
  fi
  # create is a PUT: it also corrects a credential whose subject has drifted.
  az identity federated-credential create --identity-name "$identity" -g "$SHARED_RG" -n "$name" \
    --issuer "$OIDC_ISSUER" --subject "$subject" --audiences api://AzureADTokenExchange -o none
  record created "federation $identity <- $subject"
}

rg_scope() { echo "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$1"; }
SHARED_SCOPE=$(rg_scope "$SHARED_RG")

# Custom role for the plan identities: azurerm reads Container App secrets during refresh (R7).
role_scopes=$(jq -cn --arg s "/subscriptions/$SUBSCRIPTION_ID" \
  '[$s + "/resourceGroups/rg-misaapp-develop", $s + "/resourceGroups/rg-misaapp-stage", $s + "/resourceGroups/rg-misaapp-production"]')
role_json=$(jq -cn --arg name "$SECRET_READER_ROLE" --argjson scopes "$role_scopes" '{
  Name: $name, IsCustom: true,
  Description: "Read Container App and Container Apps job secrets (Terraform plan refresh).",
  Actions: ["Microsoft.App/containerApps/listSecrets/action", "Microsoft.App/jobs/listSecrets/action"],
  NotActions: [], DataActions: [], NotDataActions: [], AssignableScopes: $scopes }')
existing_role=$(az role definition list --custom-role-only true -n "$SECRET_READER_ROLE" --scope "/subscriptions/$SUBSCRIPTION_ID" --query '[].id' -o tsv)
if [[ -n "$existing_role" ]]; then
  record exists "custom role '$SECRET_READER_ROLE'"
else
  az role definition create --role-definition "$role_json" -o none
  record created "custom role '$SECRET_READER_ROLE'"
fi

# Custom role for the develop deploy identity: Terraform reads the deletion details of the nonprod
# Key Vault when it destroys it. That action is checked at subscription scope, which no
# resource-group role grants.
DELETED_VAULT_READER_ROLE="MisaApp Deleted Key Vault Reader"
deleted_vault_role_json=$(jq -cn --arg name "$DELETED_VAULT_READER_ROLE" --arg s "/subscriptions/$SUBSCRIPTION_ID" '{
  Name: $name, IsCustom: true,
  Description: "Read soft-deleted Key Vault details (Terraform destroy of a purge-protected vault).",
  Actions: ["Microsoft.KeyVault/locations/deletedVaults/read"],
  NotActions: [], DataActions: [], NotDataActions: [], AssignableScopes: [$s] }')
existing_deleted_vault_role=$(az role definition list --custom-role-only true -n "$DELETED_VAULT_READER_ROLE" --scope "/subscriptions/$SUBSCRIPTION_ID" --query '[].id' -o tsv)
if [[ -n "$existing_deleted_vault_role" ]]; then
  record exists "custom role '$DELETED_VAULT_READER_ROLE'"
else
  az role definition create --role-definition "$deleted_vault_role_json" -o none
  record created "custom role '$DELETED_VAULT_READER_ROLE'"
fi

# CI: pull requests plus the checks that deploy.yml runs on each branch push (no environment).
ensure_identity id-misaapp-gh-ci
ensure_federation id-misaapp-gh-ci gh-pull-request pull_request
for env in "${ENVIRONMENTS[@]}"; do
  ensure_federation id-misaapp-gh-ci "gh-${BRANCH[$env]}" "ref:refs/heads/${BRANCH[$env]}"
done
# Its AcrPull role on the shared registry is assigned by infra/shared (part 4).

ensure_identity id-misaapp-gh-build
for env in "${ENVIRONMENTS[@]}"; do
  ensure_federation id-misaapp-gh-build "gh-${BRANCH[$env]}" "ref:refs/heads/${BRANCH[$env]}"
done
ensure_role "${PRINCIPAL_ID[id-misaapp-gh-build]}" ServicePrincipal AcrPush "$SHARED_SCOPE"

for env in "${ENVIRONMENTS[@]}"; do
  env_scope=$(rg_scope "rg-misaapp-$env")
  state_scope=$(container_scope "tfstate-$env")

  plan="id-misaapp-gh-plan-$env"
  ensure_identity "$plan"
  ensure_federation "$plan" "gh-${BRANCH[$env]}" "ref:refs/heads/${BRANCH[$env]}"
  ensure_role "${PRINCIPAL_ID[$plan]}" ServicePrincipal Reader "$env_scope"
  ensure_role "${PRINCIPAL_ID[$plan]}" ServicePrincipal Reader "$SHARED_SCOPE"
  ensure_role "${PRINCIPAL_ID[$plan]}" ServicePrincipal "Storage Blob Data Reader" "$state_scope"
  ensure_role "${PRINCIPAL_ID[$plan]}" ServicePrincipal "$SECRET_READER_ROLE" "$env_scope"
  # Key Vault Reader is metadata only (names, never values): Terraform refresh of the vault and the
  # deploy preflight that checks gemini-api-key exists.
  ensure_role "${PRINCIPAL_ID[$plan]}" ServicePrincipal "Key Vault Reader" "$env_scope"

  deploy="id-misaapp-gh-deploy-$env"
  ensure_identity "$deploy"
  ensure_federation "$deploy" "gh-environment-$env" "environment:$env"
  ensure_role "${PRINCIPAL_ID[$deploy]}" ServicePrincipal Contributor "$env_scope"
  ensure_role "${PRINCIPAL_ID[$deploy]}" ServicePrincipal "Key Vault Reader" "$env_scope"
  ensure_role "${PRINCIPAL_ID[$deploy]}" ServicePrincipal "Storage Blob Data Contributor" "$state_scope"
  ensure_role "${PRINCIPAL_ID[$deploy]}" ServicePrincipal "Role Based Access Control Administrator" "$env_scope" \
    "$(rbac_condition "$ROLE_ACR_PULL" "$ROLE_KV_SECRETS_USER")"
  # Design correction 7: infra/environment reads the shared registry and grants its identities AcrPull
  # on it; the registry-scoped grant is added in part 4, once infra/shared has created the registry.
  ensure_role "${PRINCIPAL_ID[$deploy]}" ServicePrincipal Reader "$SHARED_SCOPE"
done

# The develop deploy job also applies infra/shared.
dev_deploy="${PRINCIPAL_ID[id-misaapp-gh-deploy-develop]}"
ensure_role "$dev_deploy" ServicePrincipal Contributor "$SHARED_SCOPE"
ensure_role "$dev_deploy" ServicePrincipal "Storage Blob Data Contributor" "$(container_scope tfstate-shared)"
ensure_role "$dev_deploy" ServicePrincipal "Role Based Access Control Administrator" "$SHARED_SCOPE" \
  "$(rbac_condition "$ROLE_ACR_PULL" "$ROLE_KV_SECRETS_USER")"
ensure_role "$dev_deploy" ServicePrincipal "$DELETED_VAULT_READER_ROLE" "/subscriptions/$SUBSCRIPTION_ID"

# ---------------------------------------------------------------------------------------------
section "Part 3: GitHub settings ($REPO)"

missing=()
for env in "${ENVIRONMENTS[@]}"; do
  gh api "repos/$REPO/branches/${BRANCH[$env]}" --jq .name >/dev/null 2>&1 || missing+=("${BRANCH[$env]}")
done
if ((${#missing[@]})); then
  echo "Missing branch(es): ${missing[*]}. Create them from main and re-run." >&2
  exit 1
fi
record exists "branches develop, stag, main"

reviewers='[]'
IFS=',' read -ra approver_list <<<"$APPROVERS"
for login in "${approver_list[@]}"; do
  id=$(gh api "users/$login" --jq .id) || { echo "GitHub user $login not found" >&2; exit 1; }
  reviewers=$(jq -c --argjson id "$id" '. + [{type: "User", id: $id}]' <<<"$reviewers")
done

for env in "${ENVIRONMENTS[@]}"; do
  if [[ "$env" == develop ]]; then env_reviewers='[]'; else env_reviewers=$reviewers; fi
  jq -n --argjson reviewers "$env_reviewers" '{
      reviewers: $reviewers,
      deployment_branch_policy: {protected_branches: false, custom_branch_policies: true}
    }' | gh api -X PUT "repos/$REPO/environments/$env" --input - >/dev/null
  record ensured "environment $env (reviewers: $(jq length <<<"$env_reviewers"))"

  branch=${BRANCH[$env]}
  if gh api "repos/$REPO/environments/$env/deployment-branch-policies" \
    --jq ".branch_policies[] | select(.name == \"$branch\" and .type == \"branch\") | .id" | grep -q .; then
    record exists "environment $env branch policy $branch"
  else
    gh api -X POST "repos/$REPO/environments/$env/deployment-branch-policies" \
      -f name="$branch" -f type=branch >/dev/null
    record created "environment $env branch policy $branch"
  fi

  gh variable set AZURE_DEPLOY_CLIENT_ID --repo "$REPO" --env "$env" --body "${CLIENT_ID[id-misaapp-gh-deploy-$env]}"
  record ensured "environment $env variable AZURE_DEPLOY_CLIENT_ID"
done

declare -A REPO_VARS=(
  [AZURE_TENANT_ID]=$TENANT_ID
  [AZURE_SUBSCRIPTION_ID]=$SUBSCRIPTION_ID
  [AZURE_CI_CLIENT_ID]=${CLIENT_ID[id-misaapp-gh-ci]}
  [AZURE_CI_PRINCIPAL_ID]=${PRINCIPAL_ID[id-misaapp-gh-ci]}
  [AZURE_BUILD_CLIENT_ID]=${CLIENT_ID[id-misaapp-gh-build]}
  [AZURE_PLAN_CLIENT_ID_DEVELOP]=${CLIENT_ID[id-misaapp-gh-plan-develop]}
  [AZURE_PLAN_CLIENT_ID_STAGE]=${CLIENT_ID[id-misaapp-gh-plan-stage]}
  [AZURE_PLAN_CLIENT_ID_PRODUCTION]=${CLIENT_ID[id-misaapp-gh-plan-production]}
  [ACR_NAME]=$ACR_NAME
  [TFSTATE_ACCOUNT]=$TFSTATE_ACCOUNT
  [AZURE_LOCATION]=$LOCATION
  [NAME_SUFFIX]=$SUFFIX
)
for name in "${!REPO_VARS[@]}"; do
  gh variable set "$name" --repo "$REPO" --body "${REPO_VARS[$name]}"
done
record ensured "repository variables (${#REPO_VARS[@]})"

RULESET_NAME="misaapp-deploy-branches"
ruleset=$(jq -n --arg name "$RULESET_NAME" '{
  name: $name, target: "branch", enforcement: "active",
  conditions: {ref_name: {include: ["refs/heads/develop", "refs/heads/stag", "refs/heads/main"], exclude: []}},
  bypass_actors: [{actor_id: 5, actor_type: "RepositoryRole", bypass_mode: "always"}],
  rules: [
    {type: "deletion"},
    {type: "non_fast_forward"},
    {type: "pull_request", parameters: {
      required_approving_review_count: 0, dismiss_stale_reviews_on_push: false,
      require_code_owner_review: false, require_last_push_approval: false,
      required_review_thread_resolution: false}},
    {type: "required_status_checks", parameters: {
      strict_required_status_checks_policy: false,
      required_status_checks: [{context: "backend"}, {context: "frontend"}, {context: "e2e"},
                               {context: "infra"}, {context: "secrets"}]}}
  ]}')
ruleset_id=$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$RULESET_NAME\") | .id")
if [[ -n "$ruleset_id" ]]; then
  gh api -X PUT "repos/$REPO/rulesets/$ruleset_id" --input - <<<"$ruleset" >/dev/null
  record ensured "ruleset $RULESET_NAME"
else
  gh api -X POST "repos/$REPO/rulesets" --input - <<<"$ruleset" >/dev/null
  record created "ruleset $RULESET_NAME"
fi

jq -n '{security_and_analysis: {
    secret_scanning: {status: "enabled"},
    secret_scanning_push_protection: {status: "enabled"}}}' |
  gh api -X PATCH "repos/$REPO" --input - >/dev/null
record ensured "secret scanning + push protection"

# ---------------------------------------------------------------------------------------------
section "Part 4: environment state and first apply of infra/shared (admin credentials)"

if [[ "$(az account show --query user.type -o tsv)" == "user" ]]; then
  ADMIN_ID=$(az ad signed-in-user show --query id -o tsv)
  ADMIN_TYPE=User
else
  ADMIN_ID=$(az ad sp show --id "$(az account show --query user.name -o tsv)" --query id -o tsv)
  ADMIN_TYPE=ServicePrincipal
fi
before=${#SUMMARY[@]}
for container in tfstate-shared tfstate-develop tfstate-stage tfstate-production; do
  ensure_role "$ADMIN_ID" "$ADMIN_TYPE" "Storage Blob Data Contributor" "$(container_scope "$container")"
done
if printf '%s\n' "${SUMMARY[@]:before}" | grep -q '^created'; then
  echo "  waiting 90 s for the new data-plane roles to propagate..."
  sleep 90
fi

# Local run: the providers' use_oidc finds no GitHub token and falls back to the Azure CLI login.
export ARM_SUBSCRIPTION_ID="$SUBSCRIPTION_ID" ARM_TENANT_ID="$TENANT_ID" ARM_USE_CLI=true
# Git Bash on Windows: terraform.exe can't resolve /d/... paths, so pass D:/... instead.
tf_path() { if command -v cygpath >/dev/null; then cygpath -m "$1"; else echo "$1"; fi; }

# The azurerm backend creates a missing state blob under a lease, which needs write access, but the
# plan identities only read state. Create each environment's empty state here so the first deploy's
# plan job finds it. A throwaway data dir leaves the developer's infra/environment/.terraform alone.
ENV_DIR=$(tf_path "$REPO_ROOT/infra/environment")
SEED_DATA_DIR=$(mktemp -d)
trap 'rm -rf "$SEED_DATA_DIR"' EXIT
for env in "${ENVIRONMENTS[@]}"; do
  exists=$(az storage blob exists --auth-mode login --account-name "$TFSTATE_ACCOUNT" \
    -c "tfstate-$env" -n environment.tfstate --query exists -o tsv)
  if [[ "${exists,,}" == "true" ]]; then
    record exists "state tfstate-$env/environment.tfstate"
    continue
  fi
  TF_DATA_DIR=$(tf_path "$SEED_DATA_DIR") terraform -chdir="$ENV_DIR" init -input=false -reconfigure \
    -backend-config="storage_account_name=$TFSTATE_ACCOUNT" \
    -backend-config="container_name=tfstate-$env" \
    -backend-config="key=environment.tfstate" >/dev/null
  record created "state tfstate-$env/environment.tfstate"
done

SHARED_DIR=$(tf_path "$REPO_ROOT/infra/shared")
terraform -chdir="$SHARED_DIR" init -input=false -reconfigure \
  -backend-config="storage_account_name=$TFSTATE_ACCOUNT" \
  -backend-config="container_name=tfstate-shared" \
  -backend-config="key=shared.tfstate"
# Interactive approval: review the plan before anything is created.
terraform -chdir="$SHARED_DIR" apply \
  -var "location=$LOCATION" -var "suffix=$SUFFIX" -var "ci_principal_id=${PRINCIPAL_ID[id-misaapp-gh-ci]}"
record ensured "infra/shared applied"

# Design correction 7: each environment's deploy identity grants its API identity AcrPull
# on the shared registry; allow exactly that role on exactly that resource.
ACR_ID=$(az acr show -n "$ACR_NAME" -g "$SHARED_RG" --query id -o tsv)
for env in stage production; do
  ensure_role "${PRINCIPAL_ID[id-misaapp-gh-deploy-$env]}" ServicePrincipal \
    "Role Based Access Control Administrator" "$ACR_ID" "$(rbac_condition "$ROLE_ACR_PULL")"
done
# develop already holds a conditioned RBAC Administrator role on the whole shared resource group.

section "infra/shared outputs"
terraform -chdir="$SHARED_DIR" output

section "Summary"
printf '  %s\n' "${SUMMARY[@]}"
cat <<EOF

Next:
  - Set the Gemini key for each environment that enables it, after its first deploy, e.g.
      az keyvault secret set --vault-name kv-misaapp-prd-$SUFFIX --name gemini-api-key --file <(read -rs k; printf %s "\$k")
EOF
