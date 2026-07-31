#!/bin/bash
# Smoke test the Workamajig API with the credentials in .env.
# Usage: bash scripts/smoke.sh
set -euo pipefail
cd "$(dirname "$0")/.."

set -a; source .env; set +a

auth=(-H "APIAccessToken: $WMJ_COMPANY_TOKEN" -H "UserToken: $WMJ_USER_TOKEN")
base="$WMJ_URL/api/beta1"

call() {
  local label=$1 path=$2
  local status body
  body=$(curl -s -w '\n%{http_code}' "${auth[@]}" "$base/$path")
  status=${body##*$'\n'}
  body=${body%$'\n'*}
  if [[ $status != 200 ]]; then
    echo "✗ $label → HTTP $status: $(echo "$body" | head -c 200)"
    if [[ $body == *"not enabled"* ]]; then
      echo "  → Ask your Workamajig admin to enable API access for your user."
    fi
    return 1
  fi
  echo "✓ $label → $(echo "$body" | head -c 120)…"
}

call "services"          "services"
call "projects"          "projects"
call "employee lookup"   "employees/search?email=${WMJ_EMAIL:?Add WMJ_EMAIL=you@yourcompany.com to .env}"

# First live time entry — run deliberately, then verify it appears on your
# timesheet in Workamajig before trusting the app's submit path:
#
# curl -s "${auth[@]}" -H "Content-Type: application/json" -X POST "$base/time" \
#   -d '[{"userID":"you@example.com","hours":"0.25","projectNumber":"<PROJ NUM>","taskID":"1","serviceCode":"<CODE>","workDate":"'"$(date +%-m/%-d/%Y)"'","comments":"API test","overtime":"0"}]'

echo "Smoke test passed."
