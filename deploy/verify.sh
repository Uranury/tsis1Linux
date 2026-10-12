#!/usr/bin/env bash
# Checks that users, sudo rules, file access, SSH settings and services match the
# tsis1Linux role table. Prints PASS or FAIL per check; exits 1 if any check fails.
#
# Usage: sudo ./verify.sh app   # on mainapp
#        sudo ./verify.sh db    # on main-db
#
# Run it after setup, and again after a reboot (the second run is the proof
# that the service and the SSH settings survive one).
#
# There is deliberately no `set -e`: checks are supposed to fail sometimes, and
# the script must carry on and report all of them. -u and pipefail stay on.
set -uo pipefail

APP=tsis1linux
ADMIN_USER="${ADMIN_USER:-alibi}"
DEPLOY_USER="${DEPLOY_USER:-deploy}"
AUDITOR_USER="${AUDITOR_USER:-auditor}"
ROLE="${1:-}"

[[ $EUID -eq 0 ]] || { echo "run as root (use sudo)" >&2; exit 1; }
[[ $ROLE == app || $ROLE == db ]] || { echo "usage: $0 app|db" >&2; exit 1; }

PASS=0
FAIL=0
# Not ((PASS++)): that expression evaluates to 0 the first time, which counts
# as a failure status in bash and is a classic source of surprises.
ok()  { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$1"; }

# as <user> <command...>   run a command as another user (we are root)
as() { runuser -u "$1" -- "${@:2}"; }

# check  <description> <command...>   passes if the command succeeds
# refuse <description> <command...>   passes if the command FAILS
check()  { local d=$1; shift; if "$@" &>/dev/null; then ok "$d"; else bad "$d"; fi; }
refuse() { local d=$1; shift; if "$@" &>/dev/null; then bad "$d"; else ok "$d"; fi; }

# can_read <yes|no> <user> <path> <description>
# Uses `test -r`, so no file contents (secrets!) are ever printed. A missing
# path FAILS: otherwise "cannot read" would pass for the wrong reason.
can_read() {
    local want=$1 user=$2 path=$3 desc=$4 got=no
    if [[ ! -e $path ]]; then
        bad "$desc ($path is missing, so this test proves nothing)"
        return
    fi
    if as "$user" test -r "$path"; then got=yes; fi
    if [[ $got == "$want" ]]; then ok "$desc"; else bad "$desc"; fi
}

# can_write <yes|no> <user> <path> <description>
can_write() {
    local want=$1 user=$2 path=$3 desc=$4 got=no
    if [[ ! -e $path ]]; then
        bad "$desc ($path is missing, so this test proves nothing)"
        return
    fi
    if as "$user" test -w "$path"; then got=yes; fi
    if [[ $got == "$want" ]]; then ok "$desc"; else bad "$desc"; fi
}

# stat_is <path> <"mode owner:group"> <description>
stat_is() {
    if [[ -e $1 && $(stat -c '%a %U:%G' "$1") == "$2" ]]; then ok "$3"; else bad "$3"; fi
}

in_group()   { [[ " $(id -nG "$1" 2>/dev/null) " == *" $2 "* ]]; }
has_nologin() { [[ $(getent passwd "$1" | cut -d: -f7) == */nologin ]]; }
user_absent() { ! id "$1" &>/dev/null; }
# Capture first, grep second. `sshd -T | grep -q` is flaky under pipefail: grep
# exits at the first match, sshd gets SIGPIPE while still writing, and the
# pipeline reports failure even though the line was found.
sshd_has() {
    local out
    out=$(sshd -T 2>/dev/null) || return 1
    grep -qix "$1" <<<"$out"
}
sudo_ok()    { local u=$1; shift; as "$u" sudo -n -l "$@"; }   # -l <cmd>: asks, does not run

# ---------------------------------------------------------------------------
echo "== $(hostname) ($ROLE), up since $(uptime -s), checked $(date '+%F %T') =="

users_and_sudo() {
    echo
    echo "== Groups and users =="
    check "group admins exists"   getent group admins
    check "group auditors exists" getent group auditors
    check "$ADMIN_USER is in admins"       in_group "$ADMIN_USER" admins
    check "$AUDITOR_USER is in auditors"   in_group "$AUDITOR_USER" auditors
    check "$AUDITOR_USER is in adm (logs)" in_group "$AUDITOR_USER" adm
    check "$AUDITOR_USER is in systemd-journal" in_group "$AUDITOR_USER" systemd-journal

    echo
    echo "== Sudo =="
    check  "$ADMIN_USER has full sudo"               sudo_ok "$ADMIN_USER" /usr/bin/whoami
    refuse "$AUDITOR_USER has no sudo at all"        as "$AUDITOR_USER" sudo -n -l
}

ssh_settings() {
    echo
    echo "== SSH =="
    check "password login is disabled" sshd_has "passwordauthentication no"
    check "root login is disabled"     sshd_has "permitrootlogin no"
}

verify_app() {
    users_and_sudo
    check "group deployers exists"                 getent group deployers
    check "$DEPLOY_USER is in deployers"           in_group "$DEPLOY_USER" deployers
    check "$APP service account has nologin shell" has_nologin "$APP"
    check  "$DEPLOY_USER may restart $APP.service" sudo_ok "$DEPLOY_USER" /usr/bin/systemctl restart "$APP.service"
    refuse "$DEPLOY_USER may NOT stop $APP.service"      sudo_ok "$DEPLOY_USER" /usr/bin/systemctl stop "$APP.service"
    refuse "$DEPLOY_USER may NOT restart nginx"          sudo_ok "$DEPLOY_USER" /usr/bin/systemctl restart nginx.service
    refuse "$DEPLOY_USER may NOT run arbitrary commands" sudo_ok "$DEPLOY_USER" /usr/bin/whoami

    echo
    echo "== File access =="
    can_read  yes "$AUDITOR_USER" /etc/sudoers.d/10-admins    "auditor can read sudo rules (ACL)"
    can_read  yes "$AUDITOR_USER" /var/log/nginx/access.log   "auditor can read nginx logs (adm)"
    can_read  no  "$AUDITOR_USER" "/etc/$APP/$APP.env"        "auditor can NOT read the secrets file"
    can_write no  "$AUDITOR_USER" /etc/nginx/nginx.conf       "auditor can NOT modify nginx config"
    can_write yes "$DEPLOY_USER"  "/opt/$APP/releases"        "$DEPLOY_USER can write releases"
    can_write no  "$APP"          "/opt/$APP/releases"        "$APP service cannot modify its own binaries"
    can_read  no  "$APP"          "/etc/$APP/$APP.env"        "$APP process cannot read the secrets file"
    stat_is "/etc/$APP/$APP.env" "600 root:root"             "secrets file is 600 root:root"
    stat_is "/opt/$APP/releases" "755 $DEPLOY_USER:deployers" "releases dir is owned by $DEPLOY_USER"

    ssh_settings
    stat_is "/home/$DEPLOY_USER/.ssh" "700 $DEPLOY_USER:deployers" "$DEPLOY_USER .ssh directory is 700"
    stat_is "/home/$DEPLOY_USER/.ssh/authorized_keys" "600 $DEPLOY_USER:deployers" "$DEPLOY_USER authorized_keys is 600"

    echo
    echo "== Services (boot persistence) =="
    check "nginx is enabled at boot"      systemctl is-enabled nginx
    check "nginx is running"              systemctl is-active nginx
    check "$APP is enabled at boot"       systemctl is-enabled "$APP"
    check "$APP is running"               systemctl is-active "$APP"
    check "$APP answers /healthz"         curl -fsS --max-time 5 http://127.0.0.1:8080/healthz
}

verify_db() {
    users_and_sudo
    check "no automation bot on this machine" user_absent "$DEPLOY_USER"

    echo
    echo "== File access =="
    can_read yes "$AUDITOR_USER" /etc/postgresql/16/main/pg_hba.conf          "auditor can read pg_hba.conf (ACL)"
    can_read yes "$AUDITOR_USER" /var/log/postgresql/postgresql-16-main.log   "auditor can read PostgreSQL logs (adm)"
    can_read no  "$AUDITOR_USER" "/var/backups/$APP"                          "auditor can NOT read the backups"
    can_read no  "$AUDITOR_USER" /var/lib/postgresql/16/main                  "auditor can NOT read the data directory"
    stat_is "/var/backups/$APP" "700 postgres:postgres"                       "backup directory is 700 postgres"

    ssh_settings

    echo
    echo "== Services (boot persistence) =="
    check "postgresql is enabled at boot" systemctl is-enabled postgresql
    check "postgresql is running"         systemctl is-active postgresql
    check "cron is enabled at boot"       systemctl is-enabled cron
    check "backup script is executable"   test -x "/usr/local/bin/$APP-backup.sh"
}

case $ROLE in
    app) verify_app ;;
    db)  verify_db ;;
esac

echo
echo "== $PASS passed, $FAIL failed =="
[[ $FAIL -eq 0 ]]