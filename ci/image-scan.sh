#!/usr/bin/env bash
# Trivy container-image scan. Invoked from the 'Container Image Scan' stage,
# right after 'Build Docker Image', in Jenkinsfile.ecr / Jenkinsfile.ecs /
# Jenkinsfile.eks.
#
# Required env:
#   IMAGE_REF - docker image ref to scan (e.g. sonarqube-java-demo:123)
# Optional env:
#   OUTPUT_DIR - where to write the report (default: security-reports)

set -uo pipefail  # no -e: trivy exits non-zero when it finds vulnerabilities; that's not a script failure

: "${IMAGE_REF:?IMAGE_REF is required}"

OUTPUT_DIR="${OUTPUT_DIR:-security-reports}"
mkdir -p "${OUTPUT_DIR}"

echo "==> Trivy (container image scan) for ${IMAGE_REF}"
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD/${OUTPUT_DIR}:/reports" \
  aquasec/trivy:latest image --format json --severity CRITICAL,HIGH,MEDIUM \
  -o "/reports/trivy-report.json" "${IMAGE_REF}"

echo "Image scan report written to ${OUTPUT_DIR}/trivy-report.json"
exit 0
