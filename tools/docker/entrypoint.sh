#!/usr/bin/env bash
# Entry point for the build image. Usage:
#   entrypoint validate            validate data + localization
#   entrypoint test                headless end-to-end smoke test of the game loop
#   entrypoint net-test [mode...]  two-process crossplay stand (default: all four)
#   entrypoint server [--flags]    dedicated headless host for two browsers
#   entrypoint build [preset...]   export presets (default: all desktop + web)
#   entrypoint godot <args...>     raw godot command
set -euo pipefail

cd /project

import() {
    # Generates .import files and compiled translations without opening the editor.
    godot --headless --import --quit >/dev/null 2>&1 || true
}

case "${1:-validate}" in
    validate)
        import
        godot --headless -s scripts/tools/validate_data.gd
        ;;
    test)
        import
        godot --headless -s scripts/tools/smoke_test.gd
        godot --headless -s scripts/tools/parry_test.gd
        godot --headless -s scripts/tools/gift_test.gd
        ;;
    net-test)
        shift
        import
        modes=("$@")
        [ ${#modes[@]} -eq 0 ] && modes=(coop pvp coop-dedicated pvp-dedicated)
        for mode in "${modes[@]}"; do
            GODOT=godot tools/net_test.sh "$mode"
        done
        ;;
    server)
        shift
        import
        exec godot --headless -- --server "$@"
        ;;
    build)
        shift
        presets=("$@")
        [ ${#presets[@]} -eq 0 ] && presets=("Windows Desktop" "Linux" "macOS" "Web")
        import
        for preset in "${presets[@]}"; do
            out=$(awk -v p="$preset" '
                $0 ~ "^name=\"" p "\"$" {found=1}
                found && /^export_path=/ {gsub(/export_path=|"/, ""); print; exit}' export_presets.cfg)
            [ -n "$out" ] || { echo "unknown preset: $preset" >&2; exit 1; }
            mkdir -p "$(dirname "$out")"
            echo "==> $preset -> $out"
            godot --headless --export-release "$preset" "$out"
        done
        ;;
    godot)
        shift
        exec godot "$@"
        ;;
    *)
        exec "$@"
        ;;
esac
