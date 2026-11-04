#!/usr/bin/env bash
# Runs upload.sh against a local fake GoFile API: no network, no real uploads.
# Needs: bash, curl, jq, python3.   Usage: bash test/run.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$DIR")"
PORT="${MOCK_PORT:-8766}"
WORK="$(mktemp -d)"
MOCK_PID=""
cleanup() { [[ -n "$MOCK_PID" ]] && kill "$MOCK_PID" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

mkdir -p "$WORK/tmp"
head -c 20000 /dev/urandom > "$WORK/a.bin"
head -c 30000 /dev/urandom > "$WORK/b.bin"
head -c 5000 /dev/urandom > "$WORK/we;ird, \"name\".bin"

python3 "$DIR/mock_gofile.py" "$PORT" "$WORK/mock.jsonl" 2>"$WORK/mock.err" &
MOCK_PID=$!
for _ in $(seq 1 50); do curl -s "http://127.0.0.1:$PORT/" >/dev/null 2>&1 && break; sleep 0.1; done

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         rc=$RC out=[$OUT] err=[$ERR]"; }
check() { local desc="$1"; shift; if "$@"; then ok "$desc"; else bad "$desc"; fi; }
has()   { [[ "$1" == *"$2"* ]]; }
hasnt() { [[ "$1" != *"$2"* ]]; }
rc_is() { [[ "$RC" -eq "$1" ]]; }
posts() { wc -l < "$WORK/mock.jsonl" | tr -d ' '; }
field() { sed -n "${1}p" "$WORK/mock.jsonl" | jq -r ".$2 // \"-\""; }

# run MODE args... : runs upload.sh against the fake API; sets RC, OUT (stdout), ERR (stderr).
run() {
    local mode="$1"; shift
    : > "$WORK/mock.jsonl"; : > "$WORK/argv.log"
    PATH="$DIR/shim:$PATH" MOCK_PORT="$PORT" MOCK_MODE="$mode" ARGV_LOG="$WORK/argv.log" \
        TMPDIR="$WORK/tmp" GOFILE_RETRY_DELAY=0 bash "$ROOT/upload.sh" "$@" >"$WORK/out" 2>"$WORK/err"
    RC=$?
    OUT=$(<"$WORK/out"); ERR=$(<"$WORK/err")
}

echo "uploads"
run ok "$WORK/a.bin"
check "guest upload (default auto-fastest) prints the link" has "$OUT" "Download Link: https://gofile.io/d/abc123"
check "  ...and exits 0" rc_is 0
run ok -q "$WORK/a.bin"
check "-q prints only the link on stdout" test "$OUT" = "https://gofile.io/d/abc123"
run ok --first-server "$WORK/a.bin"
check "--first-server works" has "$OUT" "Using GoFile server: s1"
run ok -q --first-server "$WORK/we;ird, \"name\".bin"
check "file name with ; , and quotes is sent intact" has "$(field 1 filename)" 'we;ird, '

echo "token handling"
export GOFILE_TOKEN='sEcReT"tok\en'
run ok -q --first-server "$WORK/a.bin"
unset GOFILE_TOKEN
check "token (with quote/backslash) reaches the server as form field" test "$(field 1 token)" = 'sEcReT"tok\en'
check "token reaches the server as Bearer header" test "$(field 1 auth)" = 'Bearer sEcReT"tok\en'
check "token is NOT in curl's command-line arguments" hasnt "$(<"$WORK/argv.log")" "sEcReT"
run ok -q --first-server -t abc123 "$WORK/a.bin"
check "-t flag works" test "$(field 1 token)" = "abc123"

echo "errors and retries"
run bad4 --first-server -r 3 "$WORK/a.bin"
check "401: fails with exit 1" rc_is 1
check "401: shows GoFile's message" has "$ERR" "invalid token"
check "401: is not retried" test "$(posts)" = 1
run fail --first-server -r 2 "$WORK/a.bin"
check "500: fails after the retries" rc_is 1
check "500: tried exactly -r times" test "$(posts)" = 2
check "500: says so" has "$ERR" "failed after 2 attempt"
curl -s "http://127.0.0.1:$PORT/reset" >/dev/null
run flaky --first-server "$WORK/a.bin"
check "500 then success: second attempt succeeds" rc_is 0
check "500 then success: 2 POSTs" test "$(posts)" = 2
run html --first-server "$WORK/a.bin"
check "502 HTML body: fails with the HTTP status" has "$ERR" "HTTP 502"
run ok "$WORK/does-not-exist.bin"
check "missing file: exit 1 with message" has "$ERR" "does not exist"
run ok
check "no arguments: exit 1" rc_is 1

echo "multiple files / folders"
run ok -q -s --first-server "$WORK/a.bin" "$WORK/b.bin"
check "-s: one link printed" test "$OUT" = "https://gofile.io/d/abc123"
check "-s: two uploads" test "$(posts)" = 2
check "-s: second upload goes to the first one's folder" test "$(field 2 folderId)" = "pf1"
check "-s: second upload uses the guest token" test "$(field 2 token)" = "gtok"
run ok -q --first-server "$WORK/a.bin" "$WORK/b.bin"
check "no -s: two separate links" test "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 2
check "no -s: no folder id sent" test "$(field 2 folderId)" = "-"
run nofolder -q -s --first-server "$WORK/a.bin" "$WORK/b.bin"
check "-s without folder info in the response: warns, still uploads both" has "$ERR" "uploaded separately"
check "  ...and exits 0" rc_is 0
run ok -q --first-server --folder fld42 -t tk "$WORK/a.bin"
check "--folder sends the folder id" test "$(field 1 folderId)" = "fld42"

echo "checksum / misc options"
run ok -c --first-server "$WORK/a.bin"
check "-c: matching MD5 is verified" has "$OUT" "MD5 verified"
run badmd5 -c --first-server "$WORK/a.bin"
check "-c: mismatch fails" has "$ERR" "MD5 mismatch"
check "  ...with exit 1" rc_is 1
run ok --limit-rate 5M --first-server "$WORK/a.bin"
check "--limit-rate is passed to curl" has "$(<"$WORK/argv.log")" "--limit-rate"
run ok --limit-rate fast "$WORK/a.bin"
check "--limit-rate rejects junk" rc_is 1
run ok --version
check "--version" has "$OUT" "GoFile Upload Script v"
run ok --auto-fastest --first-server "$WORK/a.bin"
check "conflicting server flags are rejected" rc_is 1
run ok -q --choose-server "$WORK/a.bin"
check "-q with --choose-server is rejected" rc_is 1

echo "server selection"
run ok --list-servers
check "--list-servers prints the table and exits 0" has "$OUT" "SERVER"
check "  ...without uploading" test "$(posts)" = 0
export PROBE_FAIL=1
run ok "$WORK/a.bin"
unset PROBE_FAIL
check "all probes fail: warns and falls back to the first listed server" has "$ERR" "no server answered"
check "  ...and still uploads" rc_is 0

echo "signals"
: > "$WORK/mock.jsonl"
PATH="$DIR/shim:$PATH" MOCK_PORT="$PORT" MOCK_MODE=slow TMPDIR="$WORK/tmp" \
    bash "$ROOT/upload.sh" --first-server "$WORK/a.bin" >/dev/null 2>&1 &
UP=$!
sleep 1; kill -TERM "$UP" 2>/dev/null; wait "$UP" 2>/dev/null; RC=$?; OUT=""; ERR=""
check "SIGTERM exits 143, not 0" rc_is 143
check "temp files are cleaned up after SIGTERM" test -z "$(ls -A "$WORK/tmp")"

echo
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
