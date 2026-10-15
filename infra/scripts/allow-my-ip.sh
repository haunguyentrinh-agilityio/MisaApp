#!/usr/bin/env bash
# Opens sql-misaapp-nonprod-<suffix> to your current public IP (firewall rule dev-<alias>), so the
# local Docker stack can reach your developer database. Re-run when your IP changes.
#
#   infra/scripts/allow-my-ip.sh --alias <alias> [--suffix <suffix>] [--resource-group <rg>]
#
# The suffix defaults to $NAME_SUFFIX (the repository variable set by bootstrap.sh).
set -euo pipefail
export MSYS_NO_PATHCONV=1

usage() {
  sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

ALIAS="" SUFFIX="${NAME_SUFFIX:-}" RESOURCE_GROUP="rg-misaapp-shared"
while (($#)); do
  case "$1" in
    --alias) ALIAS="${2:-}"; shift 2 ;;
    --suffix) SUFFIX="${2:-}"; shift 2 ;;
    --resource-group) RESOURCE_GROUP="${2:-}"; shift 2 ;;
    -h | --help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[[ "$ALIAS" =~ ^[a-z0-9]{2,12}$ ]] || { echo "--alias must match ^[a-z0-9]{2,12}\$" >&2; exit 2; }
[[ "$SUFFIX" =~ ^[a-z0-9]{1,6}$ ]] || { echo "Set --suffix or NAME_SUFFIX (^[a-z0-9]{1,6}\$)" >&2; exit 2; }
command -v az >/dev/null || { echo "az is not installed" >&2; exit 1; }
az account show -o none 2>/dev/null || { echo "Run 'az login' first" >&2; exit 1; }

SERVER="sql-misaapp-nonprod-$SUFFIX"
RULE="dev-$ALIAS"

IP=$(curl -fsS https://api.ipify.org)
[[ "$IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "Could not determine your public IPv4 address" >&2; exit 1; }

# create is a PUT, so it also moves an existing dev-<alias> rule to the new IP.
az sql server firewall-rule create -g "$RESOURCE_GROUP" -s "$SERVER" -n "$RULE" \
  --start-ip-address "$IP" --end-ip-address "$IP" -o none
echo "Firewall rule $RULE on $SERVER now allows $IP."

cat <<EOF

Put this in .env (password: Key Vault kv-misaapp-np-$SUFFIX, secret sql-admin-password;
see docs/deployment.md):

SQL_CONNECTION_STRING=Server=tcp:$SERVER.database.windows.net,1433;Database=sqldb-misaapp-dev-$ALIAS;User Id=misaappadmin;Password=<from Key Vault>;Encrypt=True
EOF
