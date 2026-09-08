#!/usr/bin/env bash
# Secret and dependency (SCA) scan of the source tree. Invoked from the
# 'Security Scan' stage, right after 'Sonar Scan', in every Jenkinsfile*.
# For container image scanning see ci/image-scan.sh (invoked separately,
# after the Docker image is built).
#
# Optional env:
#   OUTPUT_DIR - where to write reports (default: security-reports)

set -uo pipefail  # no -e: scanners exit non-zero when they find something; that's not a script failure

OUTPUT_DIR="${OUTPUT_DIR:-security-reports}"
mkdir -p "${OUTPUT_DIR}"

echo "==> Gitleaks (secret scan)"
docker run --rm -v "$PWD:/repo" zricethezav/gitleaks:latest \
  detect --source=/repo --no-git -f json -r "/repo/${OUTPUT_DIR}/gitleaks-report.json" -v

echo "==> OWASP Dependency-Check (dependency/SCA scan)"
mvn -B -ntp org.owasp:dependency-check-maven:10.0.4:check \
  -Dformat=JSON \
  -DoutputDirectory="${OUTPUT_DIR}"

echo "Security scan reports written to ${OUTPUT_DIR}/:"
ls -la "${OUTPUT_DIR}/" || true
exit 0
