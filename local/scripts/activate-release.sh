#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 1 ]] || { echo "Usage: $0 <version>" >&2; exit 1; }

version="$1"
rel="/opt/tsis1linux/releases/$version"
cur=/opt/tsis1linux/current

ssh app-deploy "bash -s" -- "$rel" "$cur" <<'EOF'
set -euo pipefail
rel=$1; cur=$2

[[ -x $rel/tsis1linux ]] || { echo "no executable release at $rel" >&2; exit 1; }
sudo -n -l /usr/bin/systemctl restart tsis1linux.service >/dev/null \
|| { echo "deploy cannot restart the service" >&2; exit 1; }

prev=$(readlink "$cur" || true)
ln -sfn "$rel" "$cur"
sudo systemctl restart tsis1linux.service

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS http://127.0.0.1:8080/healthz >/dev/null 2>&1; then
    echo "healthy: now running $rel"
    exit 0
  fi
  sleep 1
done

echo "health check failed" >&2
if [[ -n $prev ]]; then
  ln -sfn "$prev" "$cur"
  sudo systemctl restart tsis1linux.service
  echo "rolled back to $prev" >&2
fi
exit 1
EOF
