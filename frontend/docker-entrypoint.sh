#!/bin/sh
# Regenerate the runtime config.js from environment variables so a single
# built image can target different backend URLs per environment.
set -e

CONFIG_FILE=/usr/share/nginx/html/config.js

HELLO_SERVICE_URL="${HELLO_SERVICE_URL:-http://localhost:3001}"
PROFILE_SERVICE_URL="${PROFILE_SERVICE_URL:-http://localhost:3002}"

cat > "$CONFIG_FILE" <<EOF
window.__APP_CONFIG__ = {
  HELLO_SERVICE_URL: "${HELLO_SERVICE_URL}",
  PROFILE_SERVICE_URL: "${PROFILE_SERVICE_URL}",
};
EOF

echo "[runtime-config] Wrote ${CONFIG_FILE}:"
cat "$CONFIG_FILE"
