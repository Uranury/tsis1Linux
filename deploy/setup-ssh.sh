#!/usr/bin/env bash
# SSH setup for tsis1Linux, in two steps. Do them in this order:
#
#   sudo ./setup-ssh.sh key <user> <public-key-file>   # authorize a key for a user
#   sudo ./setup-ssh.sh harden                         # key-only login, limited groups
#
# Generate key pairs on YOUR LAPTOP, never on a server:
#   ssh-keygen -t ed25519 -f ~/.ssh/tsis1-deploy -C "tsis1linux deploy bot"
# Copy only the .pub file to the server. The private key never leaves your laptop
# (or, for the bot, goes into the CI secret store).
#
# Before running "harden": log in as each new user from a SECOND terminal and
# keep your current session open. If something is wrong, that session is how
# you fix it.
set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-deploy}"
ADMIN_USER="${ADMIN_USER:-alibi}"
# Extra group allowed to log in. "ubuntu" stays until the new accounts are proven;
# then rerun harden with EXTRA_GROUPS="" to drop it. (${VAR-default} without a
# colon keeps an explicitly empty value empty, which is what we need here.)
EXTRA_GROUPS="${EXTRA_GROUPS-ubuntu}"
DROPIN=/etc/ssh/sshd_config.d/10-tsis1linux.conf

usage() {
    echo "usage: $0 key <user> <public-key-file>" >&2
    echo "       $0 harden" >&2
    exit 1
}

[[ $EUID -eq 0 ]] || { echo "run as root (use sudo)" >&2; exit 1; }

# add_key <user> <public-key-file>
add_key() {
    local user=$1 file=$2 home group ak blob line options=""

    id "$user" &>/dev/null || { echo "user $user does not exist; run setup-users.sh first" >&2; exit 1; }
    [[ -f $file ]] || { echo "key file $file not found" >&2; exit 1; }

    # Refuse a private key: it must never be copied to a server.
    if grep -q 'PRIVATE KEY' "$file"; then
        echo "$file looks like a PRIVATE key; give me the .pub file" >&2
        exit 1
    fi
    ssh-keygen -l -f "$file" &>/dev/null || { echo "$file is not a valid public key" >&2; exit 1; }

    home=$(getent passwd "$user" | cut -d: -f6)
    group=$(id -gn "$user")
    ak="$home/.ssh/authorized_keys"

    # Service accounts have no home directory and must never get an SSH key.
    [[ -d $home ]] || { echo "$user has no home directory ($home); refusing to authorize a key" >&2; exit 1; }

    # sshd ignores keys if these permissions are too open.
    install -d -m 700 -o "$user" -g "$group" "$home/.ssh"
    if [[ ! -e $ak ]]; then
        (umask 077; : >"$ak")
        chown "$user:$group" "$ak"
    fi

    # Skip if this key is already authorized (compare the key material itself).
    blob=$(awk '{print $2}' "$file")
    if grep -qF "$blob" "$ak"; then
        echo "skip     key already authorized for $user"
        return
    fi

    # The bot's key may not forward ports, agents or X11. "pty" is added back
    # so you can still open an interactive session to demonstrate the login.
    if [[ $user == "$DEPLOY_USER" ]]; then
        options="restrict,pty "
    fi

    line=$(head -n 1 "$file")
    printf '%s%s\n' "$options" "$line" >>"$ak"
    echo "added    key for $user ($(ssh-keygen -l -f "$file" | awk '{print $2}'))"
}

harden() {
    local groups="" g admin_home

    # Refuse to switch to key-only login unless the admin account has a key.
    admin_home=$(getent passwd "$ADMIN_USER" | cut -d: -f6) || true
    if [[ ! -s ${admin_home:-/nonexistent}/.ssh/authorized_keys ]]; then
        echo "no key installed for $ADMIN_USER; run '$0 key $ADMIN_USER <file>' first" >&2
        exit 1
    fi

    # Only list groups that exist on this machine (deployers is absent on main-db).
    for g in admins deployers auditors $EXTRA_GROUPS; do
        if getent group "$g" &>/dev/null; then
            groups+="$g "
        fi
    done

    # Keep a copy so a bad config can be rolled back. A .bak file is not loaded:
    # sshd only includes *.conf from this directory.
    if [[ -e $DROPIN ]]; then
        cp -p "$DROPIN" "$DROPIN.bak"
    fi

    # File name starts with 10- because sshd uses the FIRST value it reads for a
    # setting, and files are read in order. This must sort before 50-cloud-init.conf.
    install -m 644 -o root -g root /dev/stdin "$DROPIN" <<EOF
# Managed by setup-ssh.sh
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
AllowGroups ${groups% }
EOF
    echo "wrote    $DROPIN"

    # Test the whole configuration BEFORE reloading. A broken config that is
    # reloaded can leave you unable to open new sessions.
    if sshd -t; then
        systemctl reload ssh
        echo "reloaded ssh (existing sessions stay open)"
        rm -f "$DROPIN.bak"
    else
        echo "sshd config invalid; rolling back" >&2
        if [[ -e $DROPIN.bak ]]; then
            mv "$DROPIN.bak" "$DROPIN"
        else
            rm -f "$DROPIN"
        fi
        exit 1
    fi

    echo
    echo "== Effective settings =="
    sshd -T | grep -Ei '^(passwordauthentication|permitrootlogin|pubkeyauthentication|allowgroups) '
}

case ${1:-} in
    key)    [[ $# -eq 3 ]] || usage; add_key "$2" "$3" ;;
    harden) harden ;;
    *)      usage ;;
esac