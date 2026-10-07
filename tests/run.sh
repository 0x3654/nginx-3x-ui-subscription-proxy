#!/usr/bin/env bash
# Hermetic docker smoke tests for nginx-3x-ui-subscription-proxy.
# Builds the image, spins up a fake 3x-ui upstream (tests/upstream.py) and a
# proxy instance per case, then asserts on status/headers/body/logs.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
IMG=subproxy-under-test
NET=subproxy-test-net
UP=subproxy-test-upstream
TMP="$(mktemp -d)"

cleanup() {
  docker rm -f "$UP" $(docker ps -aq --filter label=subproxy-test=1) >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1"; }
assert_eq() { [ "$2" = "$3" ] && ok "$1" || bad "$1 — expected [$3], got [$2]"; }
assert_contains() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 — [$3] not found in [$2]" ;; esac; }
assert_absent() { case "$2" in *"$3"*) bad "$1 — [$3] should not be in [$2]" ;; *) ok "$1" ;; esac; }

echo "==> building image"
docker build -q -t "$IMG" -f "$DIR/../src/Dockerfile" "$DIR/.." >/dev/null

# VERIFY_UPSTREAM_TLS=on требует CA-бандл в образе — без него все https-апстримы
# падают с "unable to get local issuer certificate" (инцидент 2026-10-07)
docker run --rm --entrypoint sh "$IMG" -c 'test -s /etc/ssl/certs/ca-certificates.crt' \
  && echo "  ok: CA bundle present" || { echo "  FAIL: no CA bundle in image"; exit 1; }

echo "==> starting fake 3x-ui upstream"
docker network create "$NET" >/dev/null
docker run -d --rm --name "$UP" --net "$NET" -l subproxy-test=1 \
  -v "$DIR/upstream.py:/upstream.py:ro" \
  python:3.12-alpine python /upstream.py >/dev/null
sleep 1

# px <case> <port> "<SERVERS>" — start a proxy container and wait for nginx
px() {
  docker run -d --rm --name "subproxy-test-$1" --net "$NET" -l subproxy-test=1 \
    -p "127.0.0.1:$2:8080" \
    -e SERVERS="$3" -e SITE_HOST=test -e SITE_PORT=8080 -e SUB=sub -e TLS_MODE=off \
    "$IMG" >/dev/null
  for _ in $(seq 1 50); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://127.0.0.1:$2/" || true)" = "404" ] && return 0
    sleep 0.2
  done
  echo "proxy $1 failed to start"; docker logs "subproxy-test-$1"; exit 1
}
px_logs() { docker logs "subproxy-test-$1" 2>&1; }
px_stop() { docker rm -f "subproxy-test-$1" >/dev/null; }

# fetch <case> <port> <sub_id> — one request; sets hdr/body/status/elapsed
fetch() {
  local out
  out=$(curl -s -D "$TMP/h" -o "$TMP/b" -w '%{http_code} %{time_total}' "http://127.0.0.1:$2/sub/$3")
  status=${out%% *}; elapsed=${out##* }
  hdr=$(cat "$TMP/h"); body=$(cat "$TMP/b")
}
hget() { printf '%s' "$hdr" | tr -d '\r' | grep -i "^$1:" | head -1 | cut -d' ' -f2-; }

echo
echo "== case 1: both servers healthy (merge + aggregate headers)"
px both 9001 "http://$UP:8080/s/ok1/ http://$UP:8080/s/ok2/"
fetch both 9001 testuser
assert_eq "status" "$status" "200"
assert_eq "merged body" "$(printf '%s' "$body" | base64 -d)" "$(printf 'vless://ok1-testuser\nvless://ok2-testuser\n')"
assert_eq "userinfo aggregated" "$(hget Subscription-Userinfo)" "upload=150; download=350; total=1073741824; expire=1900000000"
assert_eq "announce passed through" "$(hget Announce)" "base64:$(printf 'Объявление' | base64)"
assert_eq "profile title" "$(hget Profile-Title)" "$(printf 'Тест' | base64)"
assert_eq "update interval" "$(hget Profile-Update-Interval)" "24"
px_stop both

echo "== case 2: unknown sub on old 3x-ui (400)"
px m400 9002 "http://$UP:8080/s/missb/ http://$UP:8080/s/ok1/"
fetch m400 9002 testuser
assert_eq "status" "$status" "200"
assert_eq "survivor config only" "$(printf '%s' "$body" | base64 -d)" "$(printf 'vless://ok1-testuser\n')"
assert_contains "warn in logs" "$(px_logs m400)" "No such client"
assert_absent "no announce header" "$hdr" "announce"
px_stop m400

echo "== case 3: unknown sub on new 3x-ui (404)"
px m404 9003 "http://$UP:8080/s/missn/ http://$UP:8080/s/ok1/"
fetch m404 9003 testuser
assert_eq "status" "$status" "200"
assert_eq "survivor config only" "$(printf '%s' "$body" | base64 -d)" "$(printf 'vless://ok1-testuser\n')"
assert_contains "warn in logs" "$(px_logs m404)" "No such client"
px_stop m404

echo "== case 4: hanging upstream must not stall the client"
px hang 9004 "http://$UP:8080/s/ok1/ http://$UP:8080/s/hang/"
fetch hang 9004 testuser
assert_eq "status" "$status" "200"
assert_eq "survivor config only" "$(printf '%s' "$body" | base64 -d)" "$(printf 'vless://ok1-testuser\n')"
assert_contains "timeout logged" "$(px_logs hang)" "timeout"
fast=$(awk -v t="$elapsed" 'BEGIN { print (t < 5) ? "yes" : "no" }')
assert_eq "responded in <5s (took ${elapsed}s)" "$fast" "yes"
px_stop hang

echo "== case 5: upstream 500 — warn, serve the rest"
px e500 9005 "http://$UP:8080/s/err/ http://$UP:8080/s/ok1/"
fetch e500 9005 testuser
assert_eq "status" "$status" "200"
assert_eq "survivor config only" "$(printf '%s' "$body" | base64 -d)" "$(printf 'vless://ok1-testuser\n')"
assert_contains "unexpected status logged" "$(px_logs e500)" "Unexpected status 500"
px_stop e500

echo "== case 6: no working upstream — 502"
px dead 9006 "http://$UP:8080/s/hang/ http://$UP:8080/s/err/"
fetch dead 9006 testuser
assert_eq "status" "$status" "502"
assert_contains "error body" "$body" "No configs available"
fast=$(awk -v t="$elapsed" 'BEGIN { print (t < 8) ? "yes" : "no" }')
assert_eq "failed fast (took ${elapsed}s)" "$fast" "yes"
px_stop dead

echo "== case 7: parallel fetch — hangers must overlap, not add up"
px par 9007 "http://$UP:8080/s/hang/ http://$UP:8080/s/ok1/ http://$UP:8080/s/hang/"
fetch par 9007 testuser
assert_eq "status" "$status" "200"
assert_eq "survivor config only" "$(printf '%s' "$body" | base64 -d)" "$(printf 'vless://ok1-testuser\n')"
par=$(awk -v t="$elapsed" 'BEGIN { print (t < 3.5) ? "yes" : "no" }')
assert_eq "two 2s-hangers finished within 3.5s (took ${elapsed}s — sequential would be >4s)" "$par" "yes"
px_stop par

echo "== case 8: healthz endpoint"
px hz 9008 "http://$UP:8080/s/ok1/"
hz=$(curl -s "http://127.0.0.1:9008/healthz")
assert_eq "healthz body" "$hz" "ok"
px_stop hz

echo
echo "== result: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
