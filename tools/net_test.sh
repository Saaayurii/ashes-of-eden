#!/usr/bin/env bash
# Crossplay stand: real scenes, real WebSocket transport, separate processes.
#
#   tools/net_test.sh coop            host + guest
#   tools/net_test.sh pvp             host + guest, duel
#   tools/net_test.sh coop-dedicated  headless referee + two guests
#   tools/net_test.sh pvp-dedicated
#
# Fails when any side prints a FAIL line or never prints a verdict.
set -uo pipefail

want="${1:-coop}"
godot="${2:-${GODOT:-godot}}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
port="${NET_TEST_PORT:-8911}"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

mode="${want%-dedicated}"
if [ "$mode" = "$want" ]; then
    roles=(host guest)
else
    roles=(referee guest guest2)
fi

pids=()
for role in "${roles[@]}"; do
    "$godot" --headless --path "$root" -s scripts/tools/net_test.gd -- \
        "--role=$role" "--mode=$mode" "--port=$port" >"$out/$role.log" 2>&1 &
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
