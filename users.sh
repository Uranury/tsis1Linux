#!/usr/bin/bash

set -euo pipefail

ADMIN_USER="${ADMIN_USER:-alibi}"
BOT_USER="${BOT_USER:-deploy}"
AUDITOR_USER="${AUDITOR_USER:-auditor}"
ROLE="${1:-}"

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
    if id "$user" >/dev/null; then
        echo "skip user $user (already exists)"
    else
        useradd --create-home --shell /bin/bash --gid "$group" --comment "$comment" "$user"
        echo "created user $user (primary group $group)"
    fi
}

ensure_service() {
    local user=$1
    if id "$user" >/dev/null; then
        echo "skip service user $user (already exists)"
    else
        useradd --system --user-group --no-create-home --shell /usr/sbin/nologin "$user"
        echo "creatd service user $user"
    fi
}

add_to_group() {
    local user=$1 group=$2 current
    if ! id "$user" >/dev/null; then
        echo "user $user does not exist"
        return 1
    fi
    if ! getent group "$group" >/dev/null; then
        echo "group $group does not exist"
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
