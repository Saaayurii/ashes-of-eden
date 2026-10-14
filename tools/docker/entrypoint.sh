#!/usr/bin/env bash
# Entry point for the build image. Usage:
#   entrypoint validate            validate data + localization
#   entrypoint test [smoke|K/N]    headless tests (all, the smoke runs, or one share of the rest)
#   entrypoint game-test           validate + play any game on the engine (a game pack's CI)
#   entrypoint net-test [mode...]  two-process crossplay stand (default: all four)
#   entrypoint server [--flags]    dedicated headless host for two browsers
#   entrypoint relay [--flags]     the relay rooms by code go through (docs/RELAY.md)
#   entrypoint build [preset...]   export presets (default: all desktop + web)
#   entrypoint build-debug Android debug-signed export (test APKs)
#   entrypoint godot <args...>     raw godot command
set -euo pipefail

cd /project

import() {
    # Generates .import files and compiled translations without opening the editor.
    godot --headless --import --quit >/dev/null 2>&1 || true
}

# Every Godot test, in the order `test` runs them (`test K/N` deals the rest
# out round-robin; the smoke tests stay together under `test smoke`).
TESTS=(
    "--headless -s scripts/tools/game_smoke_test.gd"
    "--headless -s scripts/tools/smoke_test.gd"
    "--headless -s scripts/tools/parry_test.gd"
    "--headless -s scripts/tools/gift_test.gd"
    "--headless -s scripts/tools/hero_data_test.gd"
    "--headless -s scripts/tools/combat_data_test.gd"
    "--headless -s scripts/tools/data_roots_test.gd"
    "--headless -s scripts/tools/traversal_moves_test.gd"
    "--headless -s scripts/tools/alignment_test.gd"
    "--headless -s scripts/tools/layers_test.gd"
    "--headless -s scripts/tools/exits_test.gd"
    "--headless -s scripts/tools/seal_phase_test.gd"
    "--headless -s scripts/tools/rest_items_test.gd"
    "--headless -s scripts/tools/skins_test.gd"
    "--headless -s scripts/tools/projectile_fx_test.gd"
    "--headless -s scripts/tools/projectile_motion_test.gd"
    "--headless -s scripts/tools/volley_test.gd"
    "--headless -s scripts/tools/action_fx_test.gd"
    "--headless -s scripts/tools/enemy_attack_frame_test.gd"
    "--headless --fixed-fps 60 -s scripts/tools/enemy_spacing_test.gd"
    "--headless -s scripts/tools/unscathed_test.gd"
    "--headless -s scripts/tools/practice_test.gd"
    "--headless -s scripts/tools/studio_live_test.gd"
    "--headless -s scripts/tools/studio_waves_test.gd"
    "--headless -s scripts/tools/studio_player_actions_test.gd"
    "--headless --fixed-fps 60 -s scripts/tools/techniques_test.gd"
    "--headless --fixed-fps 60 -s scripts/tools/weapon_test.gd"
    "--headless -s scripts/tools/fork_test.gd"
    "--headless -s scripts/tools/kept_flags_test.gd"
    "--headless -s scripts/tools/night_order_test.gd"
    "--headless --fixed-fps 60 -s scripts/tools/faction_test.gd"
    "--headless -s scripts/tools/move_hints_test.gd"
    "--headless -s scripts/tools/achievements_test.gd"
    "--headless -s scripts/tools/habit_test.gd"
    "--headless -s scripts/tools/resonance_test.gd"
    "--headless -s scripts/tools/map_test.gd"
    "--headless -s scripts/tools/vials_test.gd"
    "--headless -s scripts/tools/accessibility_test.gd"
    "--headless -s scripts/tools/relics_test.gd"
    "--headless -s scripts/tools/auto_attack_test.gd"
    "--headless -s scripts/tools/daily_test.gd"
    "--headless -s scripts/tools/chronicle_test.gd"
    "--headless -s scripts/tools/curse_test.gd"
    "--headless -s scripts/tools/slain_test.gd"
    "--headless -s scripts/tools/omen_test.gd"
    "--headless -s scripts/tools/pad_prompt_test.gd"
    "--headless -s scripts/tools/last_fall_test.gd"
    "--headless -s scripts/tools/endings_test.gd"
    "--headless -s scripts/tools/skill_test.gd"
    "--headless -s scripts/tools/refuse_test.gd"
    "--headless -s scripts/tools/store_test.gd"
    "--headless -s scripts/tools/boss_time_test.gd"
    "--headless -s scripts/tools/carried_test.gd"
    "--headless -s scripts/tools/numbers_test.gd"
    "--headless -s scripts/tools/elite_cache_test.gd"
    "--headless -s scripts/tools/blood_altar_test.gd"
    "--headless -s scripts/tools/affix_test.gd"
    "--headless -s scripts/tools/save_test.gd"
    "--headless -s scripts/tools/secret_test.gd"
    "--headless -s scripts/tools/room_jump_test.gd"
    "--headless -s scripts/tools/relay_test.gd"
    "--headless -s scripts/tools/telemetry_test.gd"
)

case "${1:-validate}" in
    validate)
        import
        godot --headless -s scripts/tools/validate_data.gd
        ;;
    game-test)
        import
        godot --headless -s scripts/tools/validate_data.gd
        godot --headless -s scripts/tools/game_smoke_test.gd
        ;;
    test)
        # test            every test, one after another
        # test smoke      only the two that play a whole night (the long ones)
        # test K/N        the K-th of N shares of the rest, for CI's parallel jobs
        shift
        import
        part="${1:-all}"
        k=0; n=0
        case "$part" in
            */*) k="${part%/*}"; n="${part#*/}" ;;
        esac
        i=0
        for t in "${TESTS[@]}"; do
            smoke=0
            case "$t" in *smoke_test.gd) smoke=1 ;; esac
            run=0
            if [ "$part" = all ]; then run=1
            elif [ "$part" = smoke ]; then [ $smoke -eq 1 ] && run=1
            elif [ $smoke -eq 0 ]; then
                [ $(( i % n + 1 )) -eq "$k" ] && run=1
                i=$(( i + 1 ))
            fi
            if [ $run -eq 1 ]; then
                echo "==> $t"
                # word splitting is wanted: a line may carry flags before -s
                # shellcheck disable=SC2086
                godot $t
            fi
        done
        ;;
    net-test)
        shift
        import
        modes=("$@")
        [ ${#modes[@]} -eq 0 ] && modes=(coop pvp coop-dedicated pvp-dedicated coop-relay pvp-relay coop-rejoin)
        for mode in "${modes[@]}"; do
            GODOT=godot tools/net_test.sh "$mode"
        done
        ;;
    server)
        shift
        import
        exec godot --headless -- --server "$@"
        ;;
    relay)
        shift
        import
        exec godot --headless -- --relay "$@"
        ;;
    build|build-debug)
        # build-debug signs with the image's debug keystore: what a test APK
        # needs. A store release needs your own keystore (see docs/RELEASE.md).
        mode="--export-release"
        [ "$1" = "build-debug" ] && mode="--export-debug"
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
            godot --headless "$mode" "$preset" "$out"
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
