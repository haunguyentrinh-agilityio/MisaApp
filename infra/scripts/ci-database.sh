#!/usr/bin/env bash
# Ephemeral E2E databases on the nonprod SQL server (sql-misaapp-nonprod-<suffix>).
#
#   infra/scripts/ci-database.sh [--suffix <suffix>] create <db-name> <rule-name>
#   infra/scripts/ci-database.sh [--suffix <suffix>] drop <db-name> <rule-name>
#   infra/scripts/ci-database.sh [--suffix <suffix>] sweep --older-than-hours <n>
#
# The suffix defaults to $NAME_SUFFIX. Only names starting with sqldb-misaapp-ci- (databases) and
# ci- (firewall rules) are ever created or deleted.
set -euo pipefail
export MSYS_NO_PATHCONV=1

RESOURCE_GROUP="rg-misaapp-shared"
DB_PREFIX="sqldb-misaapp-ci-"
RULE_PREFIX="ci-"

usage() {
  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

SUFFIX="${NAME_SUFFIX:-}"
if [[ "${1:-}" == "--suffix" ]]; then
  SUFFIX="${2:-}"
  shift 2
fi
[[ "$SUFFIX" =~ ^[a-z0-9]{1,6}$ ]] || { echo "Set --suffix or NAME_SUFFIX (^[a-z0-9]{1,6}\$)" >&2; exit 2; }
SERVER="sql-misaapp-nonprod-$SUFFIX"

check_names() {
  local db=$1 rule=$2
  [[ "$db" =~ ^${DB_PREFIX}[a-z0-9-]{1,90}$ ]] || { echo "Database name must start with $DB_PREFIX: $db" >&2; exit 2; }
  [[ "$rule" =~ ^${RULE_PREFIX}[A-Za-z0-9_-]{1,100}$ ]] || { echo "Rule name must start with $RULE_PREFIX: $rule" >&2; exit 2; }
}

db_exists() { az sql db show -g "$RESOURCE_GROUP" -s "$SERVER" -n "$1" -o none 2>/dev/null; }
rule_exists() { az sql server firewall-rule show -g "$RESOURCE_GROUP" -s "$SERVER" -n "$1" -o none 2>/dev/null; }

drop_db() {
  if db_exists "$1"; then
    az sql db delete -g "$RESOURCE_GROUP" -s "$SERVER" -n "$1" --yes -o none
    echo "Deleted database $1."
  fi
}

drop_rule() {
  if rule_exists "$1"; then
    az sql server firewall-rule delete -g "$RESOURCE_GROUP" -s "$SERVER" -n "$1" -o none
    echo "Deleted firewall rule $1."
  fi
}

cmd_create() {
  local db=$1 rule=$2 ip
  check_names "$db" "$rule"
  ip=$(curl -fsS https://api.ipify.org)
  [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "Could not determine the runner's public IPv4 address" >&2; exit 1; }

  # Database first: sweep deletes ci- rules that have no database, so a rule never exists alone.
  if db_exists "$db"; then
    echo "Database $db already exists."
  else
    az sql db create -g "$RESOURCE_GROUP" -s "$SERVER" -n "$db" \
      --edition Basic --backup-storage-redundancy Local \
      --tags "createdUtc=$(date -u +%Y-%m-%dT%H:%M:%SZ)" -o none
    echo "Created database $db on $SERVER."
  fi
  az sql server firewall-rule create -g "$RESOURCE_GROUP" -s "$SERVER" -n "$rule" \
    --start-ip-address "$ip" --end-ip-address "$ip" -o none
  echo "Firewall rule $rule allows $ip."

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "db_name=$db" >>"$GITHUB_OUTPUT"
  fi
}

cmd_drop() {
  local db=$1 rule=$2
  check_names "$db" "$rule"
  drop_db "$db"
  drop_rule "$rule"
}

cmd_sweep() {
  local hours=$1 cutoff name created rule
  [[ "$hours" =~ ^[0-9]+$ ]] || { echo "--older-than-hours must be a whole number" >&2; exit 2; }
  cutoff=$(date -u -d "-$hours hours" +%s)

  # createdUtc is set by `create`; creationDate covers a database that lost its tag.
  while IFS=$'\t' read -r name created; do
    [[ -n "$name" ]] || continue
    if [[ $(date -u -d "$created" +%s) -lt $cutoff ]]; then
      drop_db "$name"
    fi
  done < <(az sql db list -g "$RESOURCE_GROUP" -s "$SERVER" \
    --query "[?starts_with(name, '$DB_PREFIX')].[name, tags.createdUtc || creationDate]" -o tsv)

  # A rule ci-<id> belongs to database sqldb-misaapp-ci-<id>; remove rules whose database is gone.
  while read -r rule; do
    [[ -n "$rule" ]] || continue
    if ! db_exists "sqldb-misaapp-$rule"; then
      drop_rule "$rule"
    fi
  done < <(az sql server firewall-rule list -g "$RESOURCE_GROUP" -s "$SERVER" \
    --query "[?starts_with(name, '$RULE_PREFIX')].name" -o tsv)
  echo "Sweep of $SERVER done (older than $hours h)."
}

command -v az >/dev/null || { echo "az is not installed" >&2; exit 1; }
case "${1:-}" in
  create) (($# == 3)) || usage; cmd_create "$2" "$3" ;;
  drop) (($# == 3)) || usage; cmd_drop "$2" "$3" ;;
  sweep) [[ $# == 3 && "$2" == "--older-than-hours" ]] || usage; cmd_sweep "$3" ;;
  *) usage ;;
esac
