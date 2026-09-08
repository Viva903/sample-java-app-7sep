#!/usr/bin/env bash
# Secret and dependency (SCA) scan of the source tree. Invoked from the
# 'Security Scan' stage, right after 'Sonar Scan', in every Jenkinsfile*.
# For container image scanning see ci/image-scan.sh (invoked separately,
# after the Docker image is built).
#
# Dependency scanning uses `trivy fs` rather than OWASP Dependency-Check:
# without an NVD API key, Dependency-Check's first run downloads the full
# ~387k-record NVD feed and can take 20-60+ minutes (blowing the pipeline's
# 30-minute timeout); Trivy ships its own prebuilt vulnerability DB, so a
# scan completes in well under a minute with no API key needed.
#
# Optional env:
#   OUTPUT_DIR - where to write reports (default: security-reports)

set -uo pipefail  # no -e: scanners exit non-zero when they find something; that's not a script failure

OUTPUT_DIR="${OUTPUT_DIR:-security-reports}"
mkdir -p "${OUTPUT_DIR}"

echo "==> Gitleaks (secret scan)"
docker run --rm -v "$PWD:/repo" zricethezav/gitleaks:latest \
  detect --source=/repo --no-git -f json -r "/repo/${OUTPUT_DIR}/gitleaks-report.json" -v

echo "==> Trivy filesystem scan (dependency/SCA)"
docker run --rm -v "$PWD:/repo" -w /repo \
  aquasec/trivy:latest fs --format json --severity CRITICAL,HIGH,MEDIUM \
  -o "/repo/${OUTPUT_DIR}/trivy-fs-report.json" .

echo "Security scan reports written to ${OUTPUT_DIR}/:"
ls -la "${OUTPUT_DIR}/" || true
exit 0
