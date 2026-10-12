#!/usr/bin/env bash
# Enables the API at boot and starts it now. Run on mainapp only.
#
# Usage: sudo ./enable-service.sh
#
# Prerequisites (the script checks them and tells you what is missing):
#   - setup-fs.sh has been run (creates the unit file and the env file)
#   - a release is uploaded to /opt/tsis1linux/releases/<version>/
#   - /opt/tsis1linux/current points at that release
#   - /etc/tsis1linux/tsis1linux.env has real values, not CHANGE_ME
set -euo pipefail

APP=tsis1linux
BIN="/opt/$APP/current/$APP"
ENV_FILE="/etc/$APP/$APP.env"

[[ $EUID -eq 0 ]] || { echo "run as root (use sudo)" >&2; exit 1; }
[[ -x $BIN ]] || { echo "no executable at $BIN; upload a release and point the current symlink at it" >&2; exit 1; }
[[ -f $ENV_FILE ]] || { echo "$ENV_FILE missing; run setup-fs.sh app first" >&2; exit 1; }
if grep -q CHANGE_ME "$ENV_FILE"; then
    echo "$ENV_FILE still contains CHANGE_ME placeholders; edit it first" >&2
    exit 1
fi

# Use the port the service is configured with, 8080 if none is set.
port=$(grep -E '^PORT=' "$ENV_FILE" | cut -d= -f2 || true)
URL="http://127.0.0.1:${port:-8080}/healthz"

systemctl daemon-reload
# enable = start at every boot, --now = also start right now.
systemctl enable --now "$APP"

# The API runs migrations against the remote database on startup, so it may
# need a few seconds before it answers.
healthy=0
for i in $(seq 1 15); do
    if curl -fsS --max-time 2 "$URL" &>/dev/null; then
        healthy=1
        echo "healthy after ${i}s: $URL"
        break
    fi
    sleep 1
done

if [[ $healthy -eq 0 ]]; then
    echo "service did not become healthy within 15s; last log lines:" >&2
    journalctl -u "$APP" -n 20 --no-pager >&2 || true
    exit 1
fi

echo
echo "enabled at boot: $(systemctl is-enabled "$APP")"
systemctl status "$APP" --no-pager | head -n 8