#!/usr/bin/env bash
# Creates the JJ-Pipelines Jenkins view and its pipeline jobs via the Jenkins REST API.
# See README.md for setup and usage.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
VIEW_NAME="JJ-Pipelines"
BRANCH="master"

JOBS=(
  "sample-java-app-build:Jenkinsfile"
  "sample-java-app-ecr:Jenkinsfile.ecr"
  "sample-java-app-deploy-app:Jenkinsfile.deploy-app"
  "sample-java-app-ecs:Jenkinsfile.ecs"
  "sample-java-app-eks:Jenkinsfile.eks"
)

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found. Copy .env.example to .env and fill in values." >&2
  exit 1
fi
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

for var in JENKINS_URL JENKINS_USER JENKINS_API_TOKEN; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: required var $var is not set in $ENV_FILE" >&2
    exit 1
  fi
done
JENKINS_URL="${JENKINS_URL%/}"

GIT_URL="$(git -C "$SCRIPT_DIR/.." remote get-url origin)" || {
  echo "ERROR: could not determine origin URL via 'git remote get-url origin'" >&2
  exit 1
}

TMP_FILES=()
cleanup() {
  local f
  for f in "${TMP_FILES[@]:-}"; do
    if [[ -n "$f" && -f "$f" ]]; then
      rm -f "$f"
    fi
  done
  return 0
}
trap cleanup EXIT

new_tmp() {
  local f
  f="$(mktemp)"
  TMP_FILES+=("$f")
  echo "$f"
}

# jenkins_curl <curl args...>
# Sets HTTP_STATUS and HTTP_BODY. Does not raise on non-2xx (caller must check).
jenkins_curl() {
  local body_file
  body_file="$(new_tmp)"
  HTTP_STATUS="$(curl -s -o "$body_file" -w '%{http_code}' -u "${JENKINS_USER}:${JENKINS_API_TOKEN}" "$@" || echo "000")"
  HTTP_BODY="$(cat "$body_file")"
}

# --- Crumb (CSRF) handling: best-effort ---
CRUMB_ARGS=()
jenkins_curl "${JENKINS_URL}/crumbIssuer/api/json"
if [[ "$HTTP_STATUS" == "000" ]]; then
  echo "ERROR: cannot reach $JENKINS_URL (connection failed). Check JENKINS_URL and network access." >&2
  exit 1
elif [[ "$HTTP_STATUS" == "200" ]] && echo "$HTTP_BODY" | grep -q crumbRequestField; then
  crumb_field="$(sed -n 's/.*"crumbRequestField":"\([^"]*\)".*/\1/p' <<<"$HTTP_BODY")"
  crumb_value="$(sed -n 's/.*"crumb":"\([^"]*\)".*/\1/p' <<<"$HTTP_BODY")"
  if [[ -n "$crumb_field" && -n "$crumb_value" ]]; then
    CRUMB_ARGS=(-H "${crumb_field}: ${crumb_value}")
  fi
else
  echo "INFO: crumbIssuer unavailable or CSRF protection disabled; proceeding without a crumb." >&2
fi

# --- Idempotent view creation ---
jenkins_curl "${JENKINS_URL}/view/${VIEW_NAME}/api/json"
if [[ "$HTTP_STATUS" == "200" ]]; then
  echo "View ${VIEW_NAME} already exists, skipping create."
else
  jenkins_curl -X POST "${CRUMB_ARGS[@]}" -H "Content-Type: application/xml" \
    --data-binary "@${TEMPLATES_DIR}/view-JJ-Pipelines.xml" \
    "${JENKINS_URL}/createView?name=${VIEW_NAME}"
  if [[ ! "$HTTP_STATUS" =~ ^2 ]]; then
    echo "ERROR creating view ${VIEW_NAME}: HTTP $HTTP_STATUS: $HTTP_BODY" >&2
    exit 1
  fi
  echo "Created view ${VIEW_NAME}."
fi

# --- Jobs: create-or-update, then add to view ---
CREATED_URLS=()
for entry in "${JOBS[@]}"; do
  job_name="${entry%%:*}"
  script_path="${entry#*:}"

  rendered="$(new_tmp)"
  sed -e "s#__GIT_URL__#${GIT_URL}#g" \
      -e "s#__BRANCH__#${BRANCH}#g" \
      -e "s#__SCRIPT_PATH__#${script_path}#g" \
      "${TEMPLATES_DIR}/job-pipeline.xml.tpl" > "$rendered"

  jenkins_curl "${JENKINS_URL}/job/${job_name}/api/json"
  if [[ "$HTTP_STATUS" == "200" ]]; then
    echo "Job ${job_name} exists, updating config (scriptPath=${script_path})..."
    jenkins_curl -X POST "${CRUMB_ARGS[@]}" -H "Content-Type: application/xml" \
      --data-binary "@${rendered}" "${JENKINS_URL}/job/${job_name}/config.xml"
  else
    echo "Creating job ${job_name} (scriptPath=${script_path})..."
    jenkins_curl -X POST "${CRUMB_ARGS[@]}" -H "Content-Type: application/xml" \
      --data-binary "@${rendered}" "${JENKINS_URL}/createItem?name=${job_name}"
  fi
  if [[ ! "$HTTP_STATUS" =~ ^2 ]]; then
    echo "ERROR on job ${job_name}: HTTP $HTTP_STATUS: $HTTP_BODY" >&2
    exit 1
  fi

  jenkins_curl -X POST "${CRUMB_ARGS[@]}" "${JENKINS_URL}/view/${VIEW_NAME}/addJobToView?name=${job_name}"
  if [[ ! "$HTTP_STATUS" =~ ^2 ]]; then
    echo "ERROR adding ${job_name} to view ${VIEW_NAME}: HTTP $HTTP_STATUS: $HTTP_BODY" >&2
    exit 1
  fi

  CREATED_URLS+=("${JENKINS_URL}/job/${job_name}/")
done

echo
echo "Done. View: ${JENKINS_URL}/view/${VIEW_NAME}/"
for u in "${CREATED_URLS[@]}"; do
  echo "  - $u"
done
