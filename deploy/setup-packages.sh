#!/usr/bin/env bash
# Usage: sudo bash setup-packages.sh          (mainapp only: main-db has no internet)
# Installs: jq, netcat-openbsd (default repo), postgresql-client from PGDG (added repo),
#           hurl (release tarball, checksum-verified, not managed by apt).
# Override the pinned hurl release with: sudo -E HURL_VERSION=... HURL_SHA256=... bash setup-packages.sh
set -euo pipefail

PG_CLIENT=${PG_CLIENT:-17}
HURL_VERSION=${HURL_VERSION:-8.0.1}
HURL_SHA256=${HURL_SHA256:-bc4732df4754748e9bf296aa3832ec019f798afb399f1279b72ed37b6e04525c}
HURL_URL="https://github.com/Orange-OpenSource/hurl/releases/download/$HURL_VERSION/hurl-$HURL_VERSION-aarch64-unknown-linux-gnu.tar.gz"

KEYRING=/etc/apt/keyrings/pgdg.asc
PGDG_LIST=/etc/apt/sources.list.d/pgdg.list
tmp=""
trap '[[ -z $tmp ]] || rm -rf "$tmp"' EXIT

die() {
	local msg=${1:-"unknown error"}
	echo "error: $msg" >&2
	exit 1
}

apt_install() {
	DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

# 1. Default repository: already trusted, nothing to configure.
install_default() {
	apt-get update -qq
	apt_install jq netcat-openbsd curl ca-certificates libxml2
}

# 2. Added repository: register the key and the source, then install from it.
add_pgdg() {
	install -d -m 755 /etc/apt/keyrings
	if [[ ! -f $KEYRING ]]; then
		curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc -o "$KEYRING" \
			|| die "could not download the PGDG key"
		chmod 644 "$KEYRING"
	fi
	if [[ ! -f $PGDG_LIST ]]; then
		echo "deb [signed-by=$KEYRING] https://apt.postgresql.org/pub/repos/apt noble-pgdg main" > "$PGDG_LIST"
	fi
	apt-get update -qq
	echo "--- candidate source ---"
	apt-cache policy "postgresql-client-$PG_CLIENT" | sed -n '1,6p'
	apt_install "postgresql-client-$PG_CLIENT"
}

# 3. Outside apt: download, verify, copy. Nothing tracks or updates this afterwards.
install_hurl() {
	local have="" bin
	if command -v hurl > /dev/null; then
		have=$(hurl --version 2>&1 || true)
	fi
	if [[ $have == *"$HURL_VERSION"* ]]; then
		echo "skip hurl $HURL_VERSION (already installed)"
		return
	fi
	tmp=$(mktemp -d) || die "failed to create a temp dir"
	curl -fsSL "$HURL_URL" -o "$tmp/hurl.tar.gz" || die "download failed: $HURL_URL"
	echo "$HURL_SHA256  $tmp/hurl.tar.gz" | sha256sum -c - || die "checksum mismatch"
	tar -xzf "$tmp/hurl.tar.gz" -C "$tmp"
	bin=$(find "$tmp" -type f -name hurl -print -quit)
	[[ -n $bin ]] || die "no hurl binary inside the tarball"
	install -m 755 -o root -g root "$bin" /usr/local/bin/hurl
}

report() {
	local out
	echo
	echo "== Installed =="
	jq --version
	dpkg-query -W -f='netcat-openbsd ${Version}\n' netcat-openbsd
	psql --version
	out=$(hurl --version 2>&1) \
		|| die "hurl does not run (try: ldd /usr/local/bin/hurl | grep 'not found')"
	echo "${out%%$'\n'*}"
	echo "hurl is at: $(command -v hurl)"
}

main() {
	[[ $EUID -eq 0 ]] || die "run as root (use sudo)"
	[[ $(dpkg --print-architecture) == arm64 ]] || die "this script expects arm64"
	install_default
	add_pgdg
	install_hurl
	report
}

main "$@"
