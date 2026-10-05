#!/usr/bin/env bash
# Crossplay stand: real scenes, real WebSocket transport, separate processes.
#
#   tools/net_test.sh coop            host + guest
#   tools/net_test.sh pvp             host + guest, duel
#   tools/net_test.sh coop-dedicated  headless referee + two guests
#   tools/net_test.sh pvp-dedicated
#   tools/net_test.sh coop-relay      relay + host + guest joining by code
#   tools/net_test.sh pvp-relay
#
# Fails when any side prints a FAIL line or never prints a verdict.
set -uo pipefail

want="${1:-coop}"
godot="${2:-${GODOT:-godot}}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
port="${NET_TEST_PORT:-8911}"
out="$(mktemp -d)"
trap '[ -n "${NET_TEST_KEEP:-}" ] || rm -rf "$out"' EXIT

mode="${want%-dedicated}"
mode="${mode%-relay}"
extra=()
case "$want" in
    *-dedicated) roles=(referee guest guest2) ;;
    *-relay)
        # The relay on $port; the host's own server one above it, which the
        # guest never touches: it comes in by code, through the relay.
        roles=(relay host guest)
        extra=("--relay-url=ws://127.0.0.1:$port" "--relay-code=ACE234")
        ;;
    *) roles=(host guest) ;;
esac

pids=()
for role in "${roles[@]}"; do
    role_port="$port"
    [ "$role" = "host" ] && [ ${#extra[@]} -gt 0 ] && role_port=$((port + 1))
    "$godot" --headless --path "$root" -s scripts/tools/net_test.gd -- \
        "--role=$role" "--mode=$mode" "--port=$role_port" "${extra[@]}" >"$out/$role.log" 2>&1 &
    pids+=($!)
done

# Nobody should need more than two minutes; kill the lot if one wedges.
( sleep 180; kill -9 "${pids[@]}" 2>/dev/null ) &
watchdog=$!

fail=0
for pid in "${pids[@]}"; do
    wait "$pid" || fail=1
done
kill "$watchdog" 2>/dev/null

for role in "${roles[@]}"; do
    echo "===== $role ====="
    grep -E '^( +(ok|FAIL) |NET TEST |SCRIPT ERROR|ERROR:)' "$out/$role.log" || cat "$out/$role.log"
    # A parse error makes Godot exit 0 without ever running, so demand a verdict.
    grep -q "^NET TEST PASSED" "$out/$role.log" || fail=1
done

if [ "$fail" -ne 0 ]; then
    echo "NET TEST FAILED ($want)"
    exit 1
fi
echo "NET TEST PASSED ($want)"
