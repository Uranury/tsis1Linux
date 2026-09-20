#!/usr/bin/env bash
# Creates the directory layout, service user and sample files for tsis1Linux.
# Safe to run repeatedly: existing files are never overwritten.
#
# Usage: sudo ./setup-fs.sh app    # on the app instance (nginx + API)
#        sudo ./setup-fs.sh db     # on the db instance (PostgreSQL)
#
# Optional: DEPLOY_USER=<user> sudo -E ./setup-fs.sh app
#           (the account CI/you use to upload releases; defaults to ubuntu)
set -euo pipefail

APP=tsis1linux
DEPLOY_USER="${DEPLOY_USER:-ubuntu}"
ROLE="${1:-}"

[[ $EUID -eq 0 ]] || { echo "run as root (use sudo)" >&2; exit 1; }
[[ $ROLE == app || $ROLE == db ]] || { echo "usage: $0 app|db" >&2; exit 1; }

# Create a file from stdin only if it does not exist yet.
# Permissions are applied at creation time, so secrets are never briefly world-readable.
write_if_missing() {
  local path=$1 owner=$2 group=$3 mode=$4
  if [[ -e $path ]]; then
    echo "skip     $path (already exists)"
    cat >/dev/null
  else
    install -m "$mode" -o "$owner" -g "$group" /dev/stdin "$path"
    echo "created  $path"
  fi
}

setup_app() {
  # Unprivileged account the API runs as: no login shell, no home directory.
  if ! id "$APP" &>/dev/null; then
    useradd --system --user-group --no-create-home --shell /usr/sbin/nologin "$APP"
    echo "created  system user $APP"
  fi

  # Binaries: one directory per release, "current" symlink points at the live one.
  install -d -m 755 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/opt/$APP" "/opt/$APP/releases"

  # Configuration: systemd reads the env file as root, so root-only is enough.
  install -d -m 750 -o root -g root "/etc/$APP"

  write_if_missing "/etc/$APP/$APP.env" root root 600 <<'EOF'
# Loaded by systemd via EnvironmentFile. The app does not read .env files itself.
PORT=8080
DATABASE_URL=postgres://appuser:CHANGE_ME@10.0.0.113:5432/appdb?sslmode=require
JWT_SECRET=CHANGE_ME
ACCESS_TOKEN_TTL=15m
REFRESH_TOKEN_TTL=168h
EOF

  write_if_missing "/etc/systemd/system/$APP.service" root root 644 <<'EOF'
[Unit]
Description=tsis1Linux todo API
After=network-online.target
Wants=network-online.target

[Service]
User=tsis1linux
Group=tsis1linux
EnvironmentFile=/etc/tsis1linux/tsis1linux.env
ExecStart=/opt/tsis1linux/current/tsis1linux
Restart=on-failure
RestartSec=2
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload

  if [[ -d /etc/nginx/sites-available ]]; then
    write_if_missing "/etc/nginx/sites-available/$APP" root root 644 <<'EOF'
server {
    listen 80;
    server_name _;   # replace with your domain when you set up TLS

    location / {
        proxy_pass http://127.0.0.1:8080;   # must match the port the API listens on
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
  else
    echo "note     nginx not installed; install it and re-run to get the sample site config"
  fi

  cat <<EOF

Next steps (app):
  1. Edit /etc/$APP/$APP.env and replace the CHANGE_ME values.
  2. Upload a build to /opt/$APP/releases/<version>/$APP and chmod 755 it.
  3. ln -sfn /opt/$APP/releases/<version> /opt/$APP/current
  4. systemctl enable --now $APP
EOF
}

setup_db() {
  id postgres &>/dev/null || { echo "postgres user not found; install PostgreSQL first" >&2; exit 1; }

  # Backups: only the postgres user may read dumps.
  install -d -m 700 -o postgres -g postgres "/var/backups/$APP"

  write_if_missing "/usr/local/bin/$APP-backup.sh" root root 755 <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
DIR=/var/backups/tsis1linux
pg_dump --format=custom --file="$DIR/appdb-$(date +%F).dump" appdb
find "$DIR" -name 'appdb-*.dump' -mtime +7 -delete
EOF

  write_if_missing "/etc/cron.d/$APP-backup" root root 644 <<EOF
# minute hour day month weekday user command
0 3 * * * postgres /usr/local/bin/$APP-backup.sh
EOF

  command -v cron &>/dev/null || echo "warning  cron is not installed; the nightly backup will not run"

  echo
  echo "Data lives in /var/lib/postgresql/16/main and config in /etc/postgresql/16/main (managed by the package)."
}

case $ROLE in
  app) setup_app ;;
  db)  setup_db ;;
esac
