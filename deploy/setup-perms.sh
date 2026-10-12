#!/usr/bin/env bash
# Gives the auditors group read access, through ACLs, to the few files it needs
# but cannot read by default. Everything else an auditor needs is already
# covered by group membership (adm, systemd-journal) or default permissions.
# Safe to run repeatedly: setfacl -m sets the same entry again.
#
# Usage: sudo ./setup-perms.sh app   # on mainapp
#        sudo ./setup-perms.sh db    # on main-db
#
# Run this AFTER setup-sudoers.sh. Reinstalling a file with `install` removes
# its ACL, so rerun this script whenever you rerun setup-sudoers.sh.
set -euo pipefail

AUDIT_GROUP="${AUDIT_GROUP:-auditors}"
ROLE="${1:-}"

[[ $EUID -eq 0 ]] || { echo "run as root (use sudo)" >&2; exit 1; }
[[ $ROLE == app || $ROLE == db ]] || { echo "usage: $0 app|db" >&2; exit 1; }
command -v setfacl &>/dev/null || { echo "setfacl not found; install the acl package" >&2; exit 1; }
getent group "$AUDIT_GROUP" &>/dev/null || { echo "group $AUDIT_GROUP missing; run setup-users.sh first" >&2; exit 1; }

# grant <permissions> <path>
# Adds one ACL entry for the audit group. Owner, group and mode are untouched.
# Directories need x so the group can walk into them.
grant() {
    local perm=$1 path=$2
    if [[ ! -e $path ]]; then
        echo "skip     $path (does not exist)"
        return
    fi
    setfacl -m "g:$AUDIT_GROUP:$perm" "$path"
    echo "granted  $AUDIT_GROUP $perm on $path"
}

# Both machines: an auditor reviewing privileges must be able to read sudo rules.
setup_common() {
    local f
    grant r /etc/sudoers
    grant rx /etc/sudoers.d
    for f in /etc/sudoers.d/*; do
        [[ -f $f ]] && grant r "$f"
    done
}

setup_app() {
    setup_common
}

# pg_hba.conf decides who may connect to the database, and is not world-readable.
setup_db() {
    setup_common
    grant rx /etc/postgresql/16/main
    grant r /etc/postgresql/16/main/pg_hba.conf
}

case $ROLE in
    app) setup_app ;;
    db)  setup_db ;;
esac

cat <<EOF

Deliberately NOT granted (verify.sh should prove these stay closed):
  /etc/tsis1linux/tsis1linux.env   JWT secret and database password
  /var/backups/tsis1linux          full database dumps
  /var/lib/postgresql              raw database files

Check with: getfacl /etc/sudoers.d/10-admins
EOF