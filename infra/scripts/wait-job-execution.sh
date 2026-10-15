#!/usr/bin/env bash
# Waits for one Container Apps job execution (the migrate job) to finish.
#
#   infra/scripts/wait-job-execution.sh <resource-group> <job-name> <execution-name> [timeout-seconds=900]
#
# Exit 0 when the execution succeeded; 1 when it failed, was stopped or timed out.
set -euo pipefail
export MSYS_NO_PATHCONV=1

if (($# < 3 || $# > 4)); then
  sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi
RESOURCE_GROUP=$1 JOB=$2 EXECUTION=$3 TIMEOUT=${4:-900}
[[ "$TIMEOUT" =~ ^[0-9]+$ ]] || { echo "timeout-seconds must be a whole number" >&2; exit 2; }

logs_hint() {
  cat >&2 <<EOF
Job logs (Log Analytics workspace log-misaapp-*, in $RESOURCE_GROUP):
  ContainerAppConsoleLogs_CL
  | where ContainerJobName_s == "$JOB" and ContainerGroupName_s startswith "$EXECUTION"
  | project TimeGenerated, Log_s
  | order by TimeGenerated asc
EOF
}

deadline=$((SECONDS + TIMEOUT))
status=""
while ((SECONDS < deadline)); do
  status=$(az containerapp job execution show -g "$RESOURCE_GROUP" -n "$JOB" \
    --job-execution-name "$EXECUTION" --query properties.status -o tsv 2>/dev/null || true)
  case "$status" in
    Succeeded)
      echo "Execution $EXECUTION of $JOB succeeded."
      exit 0
      ;;
    Failed | Stopped | Degraded)
      echo "::error::Execution $EXECUTION of $JOB ended with status $status." >&2
      logs_hint
      exit 1
      ;;
  esac
  echo "Execution $EXECUTION: ${status:-pending}..."
  sleep 10
done

echo "::error::Execution $EXECUTION of $JOB did not finish within ${TIMEOUT}s (last status: ${status:-unknown})." >&2
logs_hint
exit 1
