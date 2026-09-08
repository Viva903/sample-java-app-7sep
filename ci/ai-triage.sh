#!/usr/bin/env bash
# Ask Claude to triage this build's test-coverage and security-scan output
# into one prioritized markdown report. Invoked from the 'AI Review' stage
# in every Jenkinsfile*, after the Test and Security Scan (and, where
# applicable, Container Image Scan) stages have produced their reports.
#
# Required env:
#   ANTHROPIC_API_KEY - Anthropic API key (Jenkins credential ANTHROPIC_API_KEY)
# Optional env:
#   JACOCO_XML            - path to JaCoCo coverage XML
#                            (default target/site/jacoco/jacoco.xml)
#   SECURITY_REPORTS_DIR  - dir with gitleaks/dependency-check/trivy JSON
#                            (default security-reports)
#   OUTPUT_FILE            - markdown report path (default ai-review-report.md)
#   DIFF_RANGE              - git diff range for changed Java files
#                              (default HEAD~1..HEAD)

set -euo pipefail

: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY is required}"

JACOCO_XML="${JACOCO_XML:-target/site/jacoco/jacoco.xml}"
SECURITY_REPORTS_DIR="${SECURITY_REPORTS_DIR:-security-reports}"
OUTPUT_FILE="${OUTPUT_FILE:-ai-review-report.md}"
DIFF_RANGE="${DIFF_RANGE:-HEAD~1..HEAD}"

command -v jq >/dev/null 2>&1 || { echo "jq is required on the agent but was not found" >&2; exit 1; }

read_or_placeholder() {
  if [ -f "$1" ]; then cat "$1"; else echo "(not present - scanner found nothing, didn't run, or this stage was skipped)"; fi
}

DIFF_CONTENT="$(git diff "${DIFF_RANGE}" -- '*.java' 2>/dev/null || echo '(no diff available)')"
[ -n "${DIFF_CONTENT}" ] || DIFF_CONTENT="(no *.java changes in ${DIFF_RANGE})"
JACOCO_CONTENT="$(read_or_placeholder "${JACOCO_XML}")"
GITLEAKS_CONTENT="$(read_or_placeholder "${SECURITY_REPORTS_DIR}/gitleaks-report.json")"
TRIVY_FS_CONTENT="$(read_or_placeholder "${SECURITY_REPORTS_DIR}/trivy-fs-report.json")"
TRIVY_CONTENT="$(read_or_placeholder "${SECURITY_REPORTS_DIR}/trivy-report.json")"

PROMPT="$(cat <<PROMPT_EOF
You are reviewing Jenkins build ${BUILD_NUMBER:-unknown} of ${JOB_NAME:-sample-java-app} (git diff range ${DIFF_RANGE}).

Below are: the Java diff for this build, a JaCoCo coverage report, and three
raw security scanner reports (Gitleaks secrets, Trivy filesystem/dependency
scan, Trivy container image scan - any of these may say "(not present)" if
that scanner found nothing, didn't run, or this pipeline has no image-scan
stage).

Do three things and write the result as Markdown:

1. TEST GAPS: cross-reference the diff against the JaCoCo report. List
   changed/new methods with no coverage, ranked by risk (methods with side
   effects, external I/O, or that look like they could throw/NPE first).
   Suggest (don't write) a JUnit 5 test for the top 2-3.
2. SECURITY TRIAGE: read the three scanner reports. Judge real risk - is the
   affected code/dependency/package actually reachable and exploitable in
   how this app uses it - not just raw severity. Group findings into "must
   fix", "worth tracking", and "noise", each with a one-line reason.
3. VERDICT: one line - PASS, PASS WITH FINDINGS, or BLOCKER - plus why,
   based on parts 1 and 2. Reserve BLOCKER for a real, reachable secret leak
   or a critical/exploitable vulnerability - not general lack of coverage.

--- DIFF (${DIFF_RANGE}, *.java) ---
${DIFF_CONTENT}

--- JACOCO COVERAGE (${JACOCO_XML}) ---
${JACOCO_CONTENT}

--- GITLEAKS REPORT ---
${GITLEAKS_CONTENT}

--- TRIVY FILESYSTEM/DEPENDENCY SCAN REPORT ---
${TRIVY_FS_CONTENT}

--- TRIVY IMAGE SCAN REPORT ---
${TRIVY_CONTENT}
PROMPT_EOF
)"

REQUEST_BODY="$(jq -n --arg prompt "${PROMPT}" '{
  model: "claude-opus-5",
  max_tokens: 16000,
  messages: [{role: "user", content: $prompt}]
}')"

RESPONSE="$(curl -sS https://api.anthropic.com/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${ANTHROPIC_API_KEY}" \
  -H "anthropic-version: 2023-06-01" \
  -d "${REQUEST_BODY}")"

if ! echo "${RESPONSE}" | jq -e '.content' >/dev/null 2>&1; then
  echo "Claude API call failed or returned no content:" >&2
  echo "${RESPONSE}" >&2
  printf '# AI Review\n\nClaude API call failed - see Jenkins console log for the raw response.\n' > "${OUTPUT_FILE}"
  exit 0
fi

echo "${RESPONSE}" | jq -r '.content[] | select(.type == "text") | .text' > "${OUTPUT_FILE}"

echo "===== AI Review Report ====="
cat "${OUTPUT_FILE}"
echo "============================="
