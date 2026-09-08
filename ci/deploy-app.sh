#!/usr/bin/env bash
# Deploy sonarqube-java-demo JAR onto the deploy-vm "app" EC2 instance (Amazon Linux 2023).
# Invoked via SSM RunShellScript from Jenkinsfile.deploy-app.
#
# Required env (set by the SSM command):
#   S3_BUCKET  - CI artefacts bucket
#   S3_PREFIX  - e.g. sample-java-app/<BUILD_NUMBER>
#   JAR_NAME   - e.g. sonarqube-java-demo-0.0.1-SNAPSHOT.jar
# Optional:
#   AWS_DEFAULT_REGION - defaults to us-east-1

set -euo pipefail

: "${S3_BUCKET:?S3_BUCKET is required}"
: "${S3_PREFIX:?S3_PREFIX is required}"
: "${JAR_NAME:?JAR_NAME is required}"

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

APP_DIR="/opt/sample-java-app"
APP_JAR="${APP_DIR}/app.jar"
SERVICE_NAME="sample-java-app"
SERVICE_UNIT="/etc/systemd/system/${SERVICE_NAME}.service"
JAVA_PKG="java-26-amazon-corretto-headless"
HEALTH_URL="http://127.0.0.1/users/echo?q=ok"

echo "==> Ensuring Java 26 (Amazon Corretto) is installed"
if ! command -v java >/dev/null 2>&1; then
  dnf install -y "${JAVA_PKG}"
fi
java -version

if ! command -v curl >/dev/null 2>&1; then
  dnf install -y curl-minimal || dnf install -y curl
fi

echo "==> Preparing ${APP_DIR}"
mkdir -p "${APP_DIR}"

echo "==> Downloading s3://${S3_BUCKET}/${S3_PREFIX}/${JAR_NAME}"
aws s3 cp "s3://${S3_BUCKET}/${S3_PREFIX}/${JAR_NAME}" "${APP_JAR}" --only-show-errors
chmod 644 "${APP_JAR}"

if [ ! -f "${SERVICE_UNIT}" ]; then
  echo "==> Writing systemd unit ${SERVICE_UNIT}"
  cat > "${SERVICE_UNIT}" <<EOF
[Unit]
Description=sonarqube-java-demo (sample-java-app)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}
ExecStart=/usr/bin/java -jar ${APP_JAR} --server.port=80
Restart=on-failure
RestartSec=5
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
EOF
fi

echo "==> Reloading and restarting ${SERVICE_NAME}"
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl restart "${SERVICE_NAME}"

echo "==> Waiting for health check ${HEALTH_URL}"
for i in $(seq 1 30); do
  if curl -sf "${HEALTH_URL}" >/dev/null; then
    echo "Health check OK (attempt ${i})"
    curl -sS "${HEALTH_URL}" || true
    echo
    systemctl --no-pager --full status "${SERVICE_NAME}" || true
    exit 0
  fi
  sleep 2
done

echo "Health check failed after ~60s"
systemctl --no-pager --full status "${SERVICE_NAME}" || true
journalctl -u "${SERVICE_NAME}" -n 50 --no-pager || true
exit 1
