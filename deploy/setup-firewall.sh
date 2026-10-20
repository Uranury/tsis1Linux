#!/usr/bin/env bash
# Usage: sudo bash setup-firewall.sh app|db     apply and arm a 3-minute auto-rollback
#        sudo bash setup-firewall.sh confirm    make it permanent after testing a fresh login
set -euo pipefail

APP_IP=10.0.0.70
TABLE=tsis1linux
CONF_DIR=/etc/nftables.d
CONF=$CONF_DIR/$TABLE.nft
TIMER=tsis1linux-fw-rollback
tmp=""
trap '[[ -z $tmp ]] || rm -f "$tmp"' EXIT

die() {
	local msg=${1:-"unknown error"}
	echo "error: $msg" >&2
	exit 1
}

# Prints only the lines that differ between roles.
rules_for_role() {
	local role=${1:-}
	case "$role" in
	app)
		echo "tcp dport 22 accept"
		echo "tcp dport 80 accept" # add 443 here when TLS is set up
		;;
	db)
		echo "ip saddr $APP_IP tcp dport { 22, 5432 } accept"
		;;
	*)
		die "unknown role: $role"
		;;
	esac
}

# Prints the whole ruleset: fixed skeleton plus the role's lines.
render() {
	local role=$1
	cat << EOF
table inet $TABLE
delete table inet $TABLE
table inet $TABLE {
	chain input {
		type filter hook input priority 0; policy drop;
		ct state established,related accept
		ct state invalid drop
		iifname "lo" accept
		ip protocol icmp accept
		ip6 nexthdr icmpv6 accept
$(rules_for_role "$role")
	}
}
EOF
}

# Parses the file without loading it.
validate() {
	local file=$1 error
	if ! error=$(nft -c -f "$file" 2>&1); then
		die "nft check failed: $error"
	fi
}

# Puts the file where nftables.service reads it at boot (not enabled yet).
install_conf() {
	local file=$1
	[[ -f /etc/nftables.conf ]] || die "/etc/nftables.conf is missing"
	install -d -m 755 "$CONF_DIR"
	install -m 644 "$file" "$CONF"
	if ! grep -q 'nftables.d' /etc/nftables.conf; then
		echo "include \"$CONF_DIR/*.nft\"" >> /etc/nftables.conf
	fi
}

# If we lock ourselves out, deleting our table reopens the machine in 3 minutes.
arm_rollback() {
	systemctl stop "$TIMER.timer" 2> /dev/null || true
	systemctl reset-failed "$TIMER.service" 2> /dev/null || true
	systemd-run --quiet --unit="$TIMER" --on-active=3m \
		"$(command -v nft)" delete table inet "$TABLE"
}

# Runtime only: the saved rules stay on disk as the reboot fallback until confirm.
flush_iptables() {
	local ipt
	for ipt in iptables ip6tables; do
		command -v "$ipt" > /dev/null || continue
		"$ipt" -P INPUT ACCEPT
		"$ipt" -F INPUT
	done
}

apply() {
	nft -f "$CONF"
}

# Only after a fresh login worked: cancel the timer and make the change survive reboots.
confirm() {
	if ! systemctl is-active --quiet "$TIMER.timer"; then
		die "no rollback timer is armed (it may have fired); check: nft list tables"
	fi
	systemctl stop "$TIMER.timer"
	systemctl disable netfilter-persistent > /dev/null 2>&1 || true
	systemctl enable nftables > /dev/null 2>&1
	echo "rollback cancelled; the firewall is permanent and enabled at boot"
}

main() {
	local role=${1:-}
	[[ $EUID -eq 0 ]] || die "run as root (use sudo)"
	command -v nft > /dev/null || die "nft is not installed"

	case "$role" in
	confirm)
		confirm
		return
		;;
	app | db) ;;
	*)
		die "usage: $0 app|db|confirm"
		;;
	esac

	tmp=$(mktemp) || die "failed to create a temp file"
	render "$role" > "$tmp"
	validate "$tmp"
	install_conf "$tmp"
	arm_rollback
	flush_iptables
	apply

	echo
	nft list table inet "$TABLE"
	echo
	systemctl list-timers "$TIMER.timer" --no-pager || true
	echo
	echo "Open a NEW ssh session now. If it works: sudo bash $0 confirm"
	echo "Otherwise the rules are removed automatically in 3 minutes."
}

main "$@"
