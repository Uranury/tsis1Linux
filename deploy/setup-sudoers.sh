#!/usr/bin/env bash
# Installs the sudo rules from the tsis1Linux role table, one file per role.
# Safe to run repeatedly: each file is validated, then (re)installed.
#
# Usage: sudo ./setup-sudoers.sh app   # on mainapp
#        sudo ./setup-sudoers.sh db    # on main-db
#
# Run setup-users.sh first: the rules refer to groups that must already exist.
set -euo pipefail

APP=tsis1linux
ADMIN_GROUP="${ADMIN_GROUP:-admins}"
DEPLOY_GROUP="${DEPLOY_GROUP:-deployers}"
ROLE="${1:-}"

[[ $EUID -eq 0 ]] || { echo "run as root (use sudo)" >&2; exit 1; }
[[ $ROLE == app || $ROLE == db ]] || { echo "usage: $0 app|db" >&2; exit 1; }
command -v visudo &>/dev/null || { echo "visudo not found; install the sudo package" >&2; exit 1; }

require_group() {
    getent group "$1" >/dev/null || { echo "group $1 missing; run setup-users.sh first" >&2; exit 1; }
}

# install_sudoers <filename>   (rule text comes from stdin)
# Unlike write_if_missing in setup-fs.sh, this OVERWRITES: sudo rules are policy,
# and rerunning the script should enforce the policy, not preserve manual edits.
# The text is written to a temp file and checked with visudo BEFORE it goes
# into /etc/sudoers.d/. A syntax error in a live sudoers file can lock everyone
# out of sudo, so an invalid file must never reach that directory.
install_sudoers() {
    local name=$1 tmp
    tmp=$(mktemp)
    cat >"$tmp"
    if visudo -cf "$tmp" >/dev/null; then
        install -m 440 -o root -g root "$tmp" "/etc/sudoers.d/$name"
        rm -f "$tmp"
        echo "installed /etc/sudoers.d/$name"
    else
        rm -f "$tmp"
        echo "invalid sudoers rule for $name; nothing installed" >&2
        exit 1
    fi
}

# Both machines: administrators get everything.
# NOPASSWD because these accounts have no password (SSH key is the authentication).
setup_common() {
    require_group "$ADMIN_GROUP"

    install_sudoers 10-admins <<EOF
# Administrators: full sudo
%$ADMIN_GROUP ALL=(ALL:ALL) NOPASSWD: ALL
EOF
}

setup_app() {
    setup_common
    require_group "$DEPLOY_GROUP"

    # Exact command, exact arguments, no wildcards: the CI bot can restart
    # one service and nothing else.
    install_sudoers 20-deployers <<EOF
# Automation bot: restart the API, nothing else
%$DEPLOY_GROUP ALL=(root) NOPASSWD: /usr/bin/systemctl restart $APP.service
EOF
}

setup_db() {
    setup_common
}

case $ROLE in
    app) setup_app ;;
    db)  setup_db ;;
esac

echo
echo "Auditors get no sudo rule on purpose: they read logs through group membership."
echo "Check with: sudo -l -U <user>"