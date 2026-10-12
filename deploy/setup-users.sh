#!/usr/bin/env bash

set -euo pipefail

ADMIN_USER="${ADMIN_USER:-alibi}"
DEPLOY_USER="${DEPLOY_USER:-deploy}"
DEPLOY_GROUP="${DEPLOY_GROUP:-deployers}"
AUDITOR_USER="${AUDITOR_USER:-auditor}"
ROLE="${1:-}"

[[ $EUID -eq 0 ]] || { echo "run as root (use sudo)" >&2; exit 1; }

ensure_group() {
    local group=$1
    if getent group "$group" >/dev/null; then
        echo "skip group $group (already exists)"
    else 
        groupadd "$group"
        echo "created group $group"
    fi
}

ensure_user() {
    local user=$1 group=$2 comment=$3
    if id "$user" &>/dev/null; then
        echo "skip user $user (already exists)"
    else
        useradd --create-home --shell /bin/bash --gid "$group" --comment "$comment" "$user"
        echo "created user $user (primary group $group)"
    fi
}

ensure_service_user() {
    local user=$1
    if id "$user" &>/dev/null; then
        echo "skip service user $user (already exists)"
    else
        useradd --system --user-group --no-create-home --shell /usr/sbin/nologin "$user"
        echo "creatd service user $user"
    fi
}

add_to_group() {
    local user=$1 group=$2 current
    if ! id "$user" &>/dev/null; then
        echo "user $user does not exist" >&2
        return 1
    fi

    if ! getent group "$group" &>/dev/null; then
        echo "group $group does not exist" >&2
        return 1
    fi

    current=" $(id -nG "$user") " || return 1

    if [[ $current == *" $group "* ]]; then
        echo "skip user $user already in group $group"
    else
        usermod -aG "$group" "$user"
        echo "user $user added to group $group"
    fi
}

report() {
    local u
    echo
    echo "== Accounts =="
    for u in "$@"; do
        if id "$u" &>/dev/null; then
            printf '%-12s groups: %-40s password: %-3s shell: %s\n' \
                "$u" \
                "$(id -nG "$u")" \
                "$(passwd -S "$u" | awk '{print $2}')" \
                "$(getent passwd "$u" | cut -d: -f7)"
        else
            printf '%-12s MISSING (created by its package or by another script)' "$u"
        fi
    done
}

setup_common() {
    ensure_group admins
    ensure_group auditors

    ensure_user "$ADMIN_USER" admins "Administrator"
    ensure_user "$AUDITOR_USER" auditors "Read-only auditor"

    add_to_group "$AUDITOR_USER" adm
    add_to_group "$AUDITOR_USER" systemd-journal
}

setup_app() { 
    setup_common

    ensure_group "$DEPLOY_GROUP"
    ensure_user "$DEPLOY_USER" "$DEPLOY_GROUP" "Automation bot (CI deploy)"

    ensure_service_user tsis1linux
    report "$ADMIN_USER" "$DEPLOY_USER" "$AUDITOR_USER" tsis1linux www-data
}

setup_db() {
    id postgres &>/dev/null || { echo "postgres user not found; install PostgreSQL first" >&2; exit 1; }
    setup_common
    
    report "$ADMIN_USER" "$AUDITOR_USER" postgres
}

case $ROLE in
    app) setup_app ;;
    db) setup_db ;;
    *)
        echo "Usage $0 {app|db}" >&2
        exit 1
        ;;
esac
