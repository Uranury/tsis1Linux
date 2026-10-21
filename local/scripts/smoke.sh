#!/usr/bin/env bash
# Usage: local/scripts/smoke.sh <mainapp-public-ip>
# Runs from the laptop, against the public address only.
# Needs: curl, jq, nc, ssh.
set -uo pipefail   # no -e on purpose: keep going after a failed check

[[ $# -eq 1 ]] || { echo "Usage: $0 <mainapp-public-ip>" >&2; exit 1; }
HOST=$1
BASE="http://$HOST"
passed=0
failed=0

pass() { echo "PASS  $1"; passed=$((passed + 1)); }
fail() { echo "FAIL  $1"; failed=$((failed + 1)); }

# check "description" command args...   -> passes if the command exits 0
check() {
	local desc=$1
	shift
	if "$@" > /dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

# check_closed "description" port   -> passes if nothing answers within 3 seconds
check_closed() {
	local desc=$1 port=$2
	if nc -z -w3 "$HOST" "$port" > /dev/null 2>&1; then fail "$desc"; else pass "$desc"; fi
}

# api METHOD PATH [JSON] [TOKEN]  -> prints "<status> <body>" on one line
api() {
	local method=$1 path=$2 data=${3:-} token=${4:-}
	local args=(-sS --max-time 10 -X "$method" -w ' %{http_code}' "$BASE$path")
	[[ -n $data ]] && args+=(-H 'Content-Type: application/json' -d "$data")
	[[ -n $token ]] && args+=(-H "Authorization: Bearer $token")
	curl "${args[@]}" 2>&1
}
status_of() { echo "${1##* }"; }
body_of()   { echo "${1% *}"; }

echo "== Open ports (should answer) =="
check "port 22 (ssh) is open" nc -z -w3 "$HOST" 22
check "port 80 (nginx) is open" nc -z -w3 "$HOST" 80

echo
echo "== Closed ports (should NOT answer) =="
check_closed "port 443 is closed (no TLS yet)" 443
check_closed "port 8080 is closed (API is loopback only)" 8080
check_closed "port 5432 is closed (database is private)" 5432

echo
echo "== SSH refuses passwords =="
out=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o PubkeyAuthentication=no \
	-o PreferredAuthentications=password -o StrictHostKeyChecking=accept-new \
	"nobody@$HOST" true 2>&1 || true)
if [[ $out == *"Permission denied"* ]]; then
	pass "password login is refused"
else
	fail "password login was not refused: $out"
fi

echo
echo "== API flow through nginx =="

email="smoke-$(date +%s)-$RANDOM@example.com"
user="smoke-$RANDOM"
pw="Smoke-$RANDOM-test"

r=$(api GET /healthz)
[[ $(status_of "$r") == 200 ]] && pass "GET /healthz" || fail "GET /healthz ($r)"

r=$(api POST /auth/register "{\"username\":\"$user\",\"email\":\"$email\",\"password\":\"$pw\"}")
[[ $(status_of "$r") =~ ^2 ]] && pass "register" || fail "register ($r)"

r=$(api POST /auth/login "{\"email\":\"$email\",\"password\":\"$pw\"}")
body=$(body_of "$r")
access=$(jq -r '.access_token // empty' <<< "$body" 2> /dev/null)
refresh=$(jq -r '.refresh_token // empty' <<< "$body" 2> /dev/null)
if [[ -n $access && -n $refresh ]]; then pass "login returns both tokens"; else fail "login ($r)"; fi

r=$(api GET /tasks "" "")
[[ $(status_of "$r") == 401 ]] && pass "GET /tasks without a token is 401" || fail "unauthenticated /tasks ($r)"

r=$(api POST /tasks '{"title":"smoke test task"}' "$access")
[[ $(status_of "$r") =~ ^2 ]] && pass "create task" || fail "create task ($r)"

r=$(api GET /tasks "" "$access")
if [[ $(status_of "$r") == 200 && $(body_of "$r") == *"smoke test task"* ]]; then
	pass "list tasks shows the new task"
else
	fail "list tasks ($r)"
fi

if [[ -z $refresh ]]; then
	fail "logout (skipped: no refresh token from login)"
	fail "revoked refresh token (skipped: no refresh token from login)"
else
	r=$(api POST /auth/logout "{\"refresh_token\":\"$refresh\"}")
	[[ $(status_of "$r") =~ ^2 ]] && pass "logout" || fail "logout ($r)"

	r=$(api POST /auth/refresh "{\"refresh_token\":\"$refresh\"}")
	[[ $(status_of "$r") == 401 ]] && pass "revoked refresh token is rejected (401)" || fail "refresh after logout ($r)"
fi

echo
echo "== $passed passed, $failed failed =="
[[ $failed -eq 0 ]]
