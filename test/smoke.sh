#!/usr/bin/env bash
# Runs the image the way the README describes (only NET_ADMIN, read-only root
# filesystem) against a fake LAPI with two bans and checks that both land in
# the nftables sets of the container's network namespace.
# Usage: test/smoke.sh <image>
set -euo pipefail

image=${1:?usage: $0 <image>}
root=$(cd "$(dirname "$0")/.." && pwd)
version=$(sed -n 's/^ARG VERSION=//p' "$root/Dockerfile")
helper=$(sed -n 's/^FROM --platform=[^ ]* \([^ ]*\) AS fetch$/\1/p' "$root/Dockerfile")
name=bouncer-smoke-$$
key=$(openssl rand -hex 16)
port=$((20000 + RANDOM % 20000))
lapi_pid=

cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  [ -z "$lapi_pid" ] || kill "$lapi_pid" 2>/dev/null || true
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  docker logs "$name" 2>&1 | tail -20 >&2 || true
  exit 1
}

# Version of the binary.
out=$(docker run --rm "$image" -version 2>&1) || fail "-version: $out"
grep -qF "$version" <<<"$out" || fail "expected $version, got: $out"
echo "ok: version $version"

# Without a configuration it must not start.
if out=$(docker run --rm "$image" 2>&1); then fail "starts without a configuration"; fi
grep -qF "unable to read config file" <<<"$out" || fail "unexpected error without a configuration: $out"
echo "ok: refuses to start without a configuration"

python3 -I "$root/test/fake-lapi.py" "$port" "$key" &
lapi_pid=$!
for _ in $(seq 1 20); do
  kill -0 "$lapi_pid" 2>/dev/null || fail "fake LAPI exited"
  (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && break
  sleep 0.5
done

docker run -d --name "$name" \
  --cap-drop ALL --cap-add NET_ADMIN \
  --read-only --security-opt no-new-privileges \
  --add-host lapi:host-gateway \
  -e API_URL="http://lapi:$port/" -e API_KEY="$key" \
  -v "$root/example/crowdsec-firewall-bouncer.yaml:/config/crowdsec-firewall-bouncer.yaml:ro" \
  "$image" >/dev/null

# nft from the alpine image of the build, in the bouncer's network namespace.
docker run --rm --network "container:$name" --cap-drop ALL --cap-add NET_ADMIN "$helper" sh -euc '
  apk add -q --no-cache nftables >/dev/null
  # Sets are named after the origin of the decision (cscli in the fake LAPI).
  for _ in $(seq 1 30); do
    if nft list set ip crowdsec crowdsec-blacklists-cscli 2>/dev/null | grep -qF 192.0.2.1 &&
       nft list set ip6 crowdsec6 crowdsec6-blacklists-cscli 2>/dev/null | grep -qF 2001:db8::1; then
      check() {
        nft list chain "$1" "$2" "$3" > /tmp/chain
        grep -qE "type filter hook input priority" /tmp/chain &&
          grep -qE "^[[:space:]]*$4 saddr @$5 .*drop$" /tmp/chain ||
          { echo "no input hook or drop rule for @$5:"; cat /tmp/chain; exit 1; }
      }
      check ip crowdsec crowdsec-chain-input ip crowdsec-blacklists-cscli
      check ip6 crowdsec6 crowdsec6-chain-input ip6 crowdsec6-blacklists-cscli
      exit 0
    fi
    sleep 1
  done
  echo "bans not in the sets:"; nft list ruleset; exit 1
' || fail "nftables"
echo "ok: both bans in the nftables sets, input chains drop them"

[ "$(docker inspect -f '{{.State.Running}}' "$name")" = true ] || fail "bouncer exited"
echo "smoke test passed"
